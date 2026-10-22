-- The license check, without FiveM's game code so it can be tested with plain Lua (tests/run.lua).
--
-- 1. Online: POST /api/v2/license/validate through the official SDK (lib/sunlicense.lua), with this
--    server's id as host, so each server takes one of the license's machine slots.
-- 2. A 400 is SunLicense saying no: REJECTED with its code.
-- 3. No answer (network, 5xx, 429, the resource's API key refused): UNREACHABLE, and main.lua decides
--    (ALLOW_WHEN_UNREACHABLE). Lua has no Ed25519 built in, so there is no offline license file here.

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

--- Checks licenseKey for this server and calls done(result) once SunLicense answers.
function License.check(settings, licenseKey, serverId, done)
    if licenseKey == nil or licenseKey:match('^%s*$') then
        return done({ state = 'NOT_CONFIGURED', message = 'No license key. Add  set my_resource_license "YOUR-KEY"  to server.cfg and restart the resource.' })
    end
    if settings.apiKey == nil or settings.apiKey == '' then
        return done({ state = 'UNREACHABLE', message = "This build has no SunLicense API key (SUNLICENSE_API_KEY when you ran scripts/package.sh); the license can't be checked." })
    end
    local client = SunLicense.new({ baseUrl = settings.url, token = settings.apiKey, timeout = 10 })
    client:validate(licenseKey:match('^%s*(.-)%s*$'), { host = serverId }, function(_, status, body)
        done(License.decide(status, body))
    end)
end

function License.allowed(result)
    return result.state == 'VALID'
end
