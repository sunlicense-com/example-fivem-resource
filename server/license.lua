-- The license check, without FiveM's game code so it can be tested with plain Lua (tests/run.lua).
--
-- 1. Online: POST /api/v2/license/validate through the official SDK (lib/sunlicense.lua), with this
--    server's id as host, so each server takes one of the license's machine slots.
-- 2. A 400 is SunLicense saying no: REJECTED with its code.
-- 3. No answer (network, 5xx, 429, the resource's API key refused): UNREACHABLE, and main.lua decides
--    (ALLOW_WHEN_UNREACHABLE). Lua has no Ed25519 built in, so there is no offline license file here.
-- 4. Core unlock: a valid answer carries the key that opens server/core.sealed (your features, sealed
--    by scripts/package.sh); the SDK keeps it for 7 days, bound to this server, for outages. A rejection
--    forgets it. License.core() opens the core and checks the resource's files against the digests
--    sealed with it (tamper reports, sent with the next check).

License = {}

local resource = GetCurrentResourceName()
local SunLicense = load(LoadResourceFile(resource, 'lib/sunlicense.lua'), '@lib/sunlicense.lua')()

--- What to tell the server owner for each SunLicense result code. Edit the wording freely.
local MESSAGES = {
    VALID = 'License is valid.',
    NOT_FOUND = "This license key doesn't exist. Check the license convar in server.cfg (no spaces), or download the resource again from the store you bought it on.",
    EXPIRED = 'This license has expired. Renew it where you bought the resource.',
    REVOKED = 'This license has been revoked. Contact the resource author if you think this is a mistake.',
    SUSPENDED = 'This license is suspended for now. Contact the resource author.',
    TOO_MANY_MACHINES = 'This license is already used on the maximum number of servers. Free a slot by removing the resource from another server, or ask the author to reset your servers.',
    BLACKLISTED = 'This server or network has been blocked by the resource author. Contact them for help.',
}

function License.message(code)
    if code == nil then return 'The license was not accepted.' end
    return MESSAGES[code] or ('The license was not accepted (' .. code .. ').')
end

--- "AX8P-XXXX-XXXX-XXXX": never print a whole key to a console others may read.
function License.mask(key)
    if key == nil or key:match('^%s*$') then return '(none)' end
    key = key:match('^%s*(.-)%s*$')
    local first, rest = key:match('^([^-]*)(.*)$')
    if rest == '' then
        return first:sub(1, 4) .. string.rep('X', math.max(0, #first - 4))
    end
    return first .. rest:gsub('[^-]', 'X')
end

--- The answer for one HTTP response: { state = VALID | REJECTED | UNREACHABLE, code, message }.
function License.decide(status, body)
    if type(status) == 'number' and status >= 200 and status < 300 then
        return { state = 'VALID', code = 'VALID', message = License.message('VALID') }
    end
    if status == 400 then
        local code = type(body) == 'string' and body:match('"code"%s*:%s*"([%w_]+)"') or nil
        return { state = 'REJECTED', code = code, message = License.message(code) }
    end
    if status == 401 or status == 403 then
        return { state = 'UNREACHABLE', message = ('SunLicense refused this build\'s API key (HTTP %d): the resource author needs to update it.'):format(status) }
    end
    if type(status) == 'number' and status > 0 then
        return { state = 'UNREACHABLE', message = ('SunLicense didn\'t answer (HTTP %d).'):format(status) }
    end
    return { state = 'UNREACHABLE', message = "SunLicense can't be reached." }
end

-- One client and protection per resource, so the unlock and the integrity result carry across checks.
local client, protection, clientFor

--- The SDK's protection for this resource (core unlock, integrity, the ownership notice).
function License.protection(settings, licenseKey, serverId)
    local key = licenseKey and licenseKey:match('^%s*(.-)%s*$') or nil
    local id = tostring(settings.url) .. '|' .. tostring(settings.apiKey)
    if not client or clientFor ~= id then
        client = SunLicense.new({ baseUrl = settings.url, token = settings.apiKey, timeout = 10 })
        protection = client:protection({ licenseKey = key, fingerprint = serverId, product = settings.product,
            owner = settings.owner, terms = settings.terms ~= '' and settings.terms or nil })
        clientFor = id
    end
    protection:license(key, serverId)
    return protection, client
end

--- One console line: product, owner and the masked key (never the full key, never the buyer's name).
function License.notice(settings, licenseKey, serverId)
    return License.protection(settings, licenseKey, serverId):notice()
end

--- The protected part (server/core.sealed, from server/core.lua): its table, or nil and why. Opens only
--- with the unlock from a valid check (or one cached in the last 7 days). Without core.sealed (while
--- developing, or a build made without SUNLICENSE_PRODUCT) it loads server/core.lua as it is.
function License.core()
    local sealed = LoadResourceFile(resource, 'server/core.sealed')
    local code, name = nil, '@server/core.lua'
    if sealed and not sealed:match('^%s*$') then
        if not protection then return nil, 'no license check yet' end
        local why
        code, why = protection:unseal(sealed)
        if not code then return nil, why end
        protection:integrity() -- this resource's files vs the digests sealed with the core
    else
        code = LoadResourceFile(resource, 'server/core.lua')
        if not code then return nil, 'server/core.lua and server/core.sealed are both missing' end
    end
    local chunk, err = load(code, name)
    if not chunk then return nil, err end
    local ok, core = pcall(chunk)
    if not ok then return nil, core end
    return type(core) == 'table' and core or {}
end

--- True when the core can open now: a valid check this run, or one cached in the last 7 days.
function License.unlocked()
    return protection ~= nil and protection:unlocked()
end

--- Checks licenseKey for this server and calls done(result) once SunLicense answers.
function License.check(settings, licenseKey, serverId, done)
    if licenseKey == nil or licenseKey:match('^%s*$') then
        return done({ state = 'NOT_CONFIGURED', message = 'No license key. Add  set my_resource_license "YOUR-KEY"  to server.cfg and restart the resource.' })
    end
    if settings.apiKey == nil or settings.apiKey == '' then
        return done({ state = 'UNREACHABLE', message = "This build has no SunLicense API key (SUNLICENSE_API_KEY when you ran scripts/package.sh); the license can't be checked." })
    end
    local _, c = License.protection(settings, licenseKey, serverId)
    c:validate(licenseKey:match('^%s*(.-)%s*$'), { host = serverId }, function(_, status, body)
        done(License.decide(status, body))
    end)
end

function License.allowed(result)
    return result.state == 'VALID'
end

--- Anonymous usage statistics for your product's Analytics tab (the SDK's built-in analytics): every
--- 30 minutes in the background, the server build, OS and your resource's version (fxmanifest.lua),
--- with the license and this server's id. Never affects the license check. enabled() is read before
--- each report; the convar sunlicense_analytics false turns it off for every SunLicense resource.
function License.analytics(settings, licenseKey, serverId, enabled)
    return SunLicense.analytics({
        baseUrl = settings.url, apiKey = settings.apiKey, fingerprint = serverId, enabled = enabled,
        licenseKey = licenseKey and licenseKey:match('^%s*(.-)%s*$') or nil,
    })
end
