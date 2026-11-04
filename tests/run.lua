-- Tests for server/license.lua with plain Lua 5.4: FiveM's functions are stubbed, SunLicense's answers too.
--   lua tests/run.lua
local root = arg[0]:match('^(.*)/tests/run%.lua$') or '.'

local request, answer
local virtual = {}   -- files written by SaveResourceFile, or put there by a test (server/core.sealed)
function GetCurrentResourceName() return 'my-resource' end
function LoadResourceFile(_, name)   -- nil for a missing file, like FiveM
    if virtual[name] ~= nil then return virtual[name] ~= false and virtual[name] or nil end
    local f = io.open(root .. '/' .. name, 'rb')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end
function PerformHttpRequest(url, cb, method, body, headers)
    request = { url = url, method = method, body = body, headers = headers }
    cb(answer.status, answer.body)
end
dofile(root .. '/server/license.lua')

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if not ok then
        failures = failures + 1
        print('FAIL ' .. name .. ': ' .. tostring(err))
    end
end
local function eq(a, b) assert(a == b, ('expected %s, got %s'):format(tostring(b), tostring(a))) end
local function check(key, settings)
    local result
    License.check(settings or { url = 'https://api.example.test', apiKey = 'slk_test' }, key, 'server-1', function(r) result = r end)
    return result
end

test('valid: sends the key, the server id and the API key', function()
    answer = { status = 200, body = '{"valid":true,"code":"VALID"}' }
    local r = check(' AX8P-K7QX-M2PD-9HWT ')
    eq(r.state, 'VALID')
    assert(License.allowed(r))
    eq(request.url, 'https://api.example.test/api/v2/license/validate')
    eq(request.method, 'POST')
    eq(request.headers.Authorization, 'Bearer slk_test')
    assert(request.body:find('"license":"AX8P%-K7QX%-M2PD%-9HWT"'), request.body)
    assert(request.body:find('"host":"server%-1"'), request.body)
end)

for _, code in ipairs({ 'EXPIRED', 'REVOKED', 'SUSPENDED', 'TOO_MANY_MACHINES', 'NOT_FOUND', 'BLACKLISTED' }) do
    test('400 ' .. code .. ' is a rejection with its own message', function()
        answer = { status = 400, body = '{"valid":false,"status":400,"code":"' .. code .. '"}' }
        local r = check('AX8P-K7QX-M2PD-9HWT')
        eq(r.state, 'REJECTED')
        eq(r.code, code)
        assert(not r.message:find('not accepted'), r.message)
    end)
end

test('a 400 without a body is still a rejection', function()
    answer = { status = 400, body = nil }
    eq(check('AX8P-K7QX-M2PD-9HWT').state, 'REJECTED')
end)

test('no answer, 5xx, 429 and a refused API key are not a no', function()
    for _, status in ipairs({ 0, 500, 503, 429, 401, 403 }) do
        answer = { status = status, body = nil }
        eq(check('AX8P-K7QX-M2PD-9HWT').state, 'UNREACHABLE')
    end
end)

test('no key and no API key never call SunLicense', function()
    request = nil
    eq(check('  ').state, 'NOT_CONFIGURED')
    eq(check('AX8P-K7QX-M2PD-9HWT', { url = 'x', apiKey = '' }).state, 'UNREACHABLE')
    eq(request, nil)
end)

test('mask', function()
    eq(License.mask('AX8P-K7QX-M2PD-9HWT'), 'AX8P-XXXX-XXXX-XXXX')
    eq(License.mask('abcdefgh'), 'abcdXXXX')
    eq(License.mask(''), '(none)')
end)

-- server/main.lua as FiveM runs it: start-up, stop on a rejection, start on a valid answer.
local function start(convars, keepFiles)
    local log, stopped, files, timers = {}, false, {}, {}
    if not keepFiles then virtual = {} end
    dofile(root .. '/server/license.lua') -- a fresh resource start: nothing unlocked in memory
    function GetConvar(name, default) return convars[name] or default end
    function GetResourceMetadata() return '1.0.0' end
    function SaveResourceFile(_, name, data) files[name] = data virtual[name] = data ~= '' and data or false end
    function StopResource() stopped = true end
    function SetTimeout(ms) timers[#timers + 1] = ms end
    function CreateThread() end
    function RegisterCommand() end
    SunLicenseSettings = { url = 'https://api.example.test', apiKey = 'slk_test', product = 'My Resource', owner = 'You', terms = '' }
    local realPrint = print
    print = function(line) log[#log + 1] = line end
    local ok, err = pcall(dofile, root .. '/server/main.lua')
    print = realPrint
    assert(ok, err)
    return table.concat(log, '\n'), stopped, files, timers
end

test('main: no key stops the resource', function()
    local log, stopped = start({})
    assert(stopped, log)
    assert(log:find('No license key'), log)
end)

test('main: a valid key starts the features and keeps a server id', function()
    answer = { status = 200, body = '{}' }
    local log, stopped, files = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' })
    assert(not stopped, log)
    assert(log:find('AX8P%-XXXX%-XXXX%-XXXX'), log)
    assert(log:find('Running'), log)
    assert(not log:find('K7QX'), 'the full key was printed')
    assert(files['.machine-id']:find('^fivem%-'), files['.machine-id'])
end)

test('main: a revoked key stops the resource', function()
    answer = { status = 400, body = '{"code":"REVOKED"}' }
    local log, stopped = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' })
    assert(stopped and not log:find('Running'), log)
end)

test('analytics: a report with the license, this server and the resource version; the convar turns it off', function()
    answer = { status = 204, body = '' }
    local convars = {}
    function GetConvar(name, default) return convars[name] or default end
    function GetResourceMetadata(_, key) return key == 'version' and '1.0.0' or nil end
    local on = function() return GetConvar('my_resource_analytics', 'true') ~= 'false' end
    local analytics = License.analytics({ url = 'https://api.example.test', apiKey = 'slk_test' }, ' AX8P-K7QX-M2PD-9HWT ', 'server-1', on)
    request = nil
    local status
    analytics:sendNow(function(s) status = s end)
    eq(status, 204)
    eq(request.url, 'https://api.example.test/api/v2/analytics/report')
    eq(request.headers.Authorization, 'Bearer slk_test')
    assert(request.body:find('"licenseKey":"AX8P%-K7QX%-M2PD%-9HWT"'), request.body)
    assert(request.body:find('"fingerprint":"server%-1"'), request.body)
    assert(request.body:find('"platform":"fivem"'), request.body)
    assert(request.body:find('"productVersion":"1.0.0"'), request.body)
    convars.my_resource_analytics = 'false'
    request = nil
    analytics:sendNow(function(s) status = s end)
    eq(status, 0)
    eq(request, nil)
    convars.my_resource_analytics, convars.sunlicense_analytics = nil, 'off'
    analytics:sendNow(function(s) status = s end)
    eq(status, 0)
end)

test('main: analytics reports in the background, first after 1 to 30 minutes; off with the convar', function()
    answer = { status = 200, body = '{}' }
    local log, stopped, _, timers = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' })
    assert(not stopped, log)
    eq(#timers, 1)
    assert(timers[1] >= 60 * 1000 and timers[1] <= 30 * 60 * 1000, tostring(timers[1]))
    request = nil
    local _, _, _, again = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT', my_resource_analytics = 'false' })
    eq(#again, 1) -- scheduled, but nothing is sent while the convar says false (checked before each report)
end)

-- Core unlock: the build you sell carries server/core.sealed instead of server/core.lua. These tests seal
-- the core here with a made-up product key, the way `sunlicense seal` does on SunLicense's servers.
local SDK = load(LoadResourceFile('my-resource', 'lib/sunlicense.lua'), '@lib/sunlicense.lua')()
local C = SDK.Crypto
local productKey = C.sha256('a product key for the tests')
local function seal(source, digests)
    local plain = SDK.Analytics.json({ v = 1, digests = digests or {}, data = C.toBase64(source) })
    local nonce = C.sha256(source):sub(1, 12)
    local ct, tag = C.gcmEncrypt(productKey, nonce, plain, 'SLS1')
    return 'SLS1.' .. C.toBase64(nonce .. ct .. tag, true)
end
local function sealedBuild()
    virtual = {}
    local core, manifest = LoadResourceFile('my-resource', 'server/core.lua'), LoadResourceFile('my-resource', 'fxmanifest.lua')
    virtual['server/core.lua'] = false -- package.sh leaves the plain core out
    virtual['server/core.sealed'] = seal(core, { ['fxmanifest.lua'] = SDK.Protection.digest(manifest) })
end
local VALID_WITH_UNLOCK = '{"valid":true,"status":200,"code":"VALID","unlock":"' .. C.toBase64(productKey) .. '"}'

test('main: prints the ownership notice with the masked key', function()
    answer = { status = 200, body = '{}' }
    local log = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' })
    assert(log:find('My Resource is licensed software by You%. License AX8P%-XXXX%-XXXX%-XXXX%.'), log)
end)

test('core unlock: the sealed core runs after a valid check, and its digests are checked', function()
    sealedBuild()
    answer = { status = 200, body = VALID_WITH_UNLOCK }
    local log, stopped, files = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(not stopped and log:find('Running'), log)
    local cached = false
    for name in pairs(files) do if name:find('^%.sunlicense%-unlock%-') then cached = true end end
    assert(cached, 'the unlock is cached in the resource for outages')
    -- the next check reports the result
    request = nil
    License.check(SunLicenseSettings, 'AX8P-K7QX-M2PD-9HWT', 'server-1', function() end)
    assert(request.body:find('"integrity":"OK"'), request.body)
end)

test('core unlock: a valid answer without the unlock leaves the core locked', function()
    sealedBuild()
    answer = { status = 200, body = '{"valid":true,"code":"VALID"}' }
    local log, stopped = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(not stopped and not log:find('Running'), log)
    assert(log:find('protected part could not start'), log)
end)

test('core unlock: no answer on the very first start waits; with an unlock from an earlier start it runs', function()
    sealedBuild()
    answer = { status = 0 }
    local log = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(not log:find('Running') and log:find('needs one valid license check first'), log)
    answer = { status = 200, body = VALID_WITH_UNLOCK }
    start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true) -- a valid check caches the unlock
    answer = { status = 503 }
    log = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true) -- restart during an outage
    assert(log:find('Running'), log)
end)

test('core unlock: a rejection forgets the unlock, so a later outage keeps the core locked', function()
    sealedBuild()
    answer = { status = 200, body = VALID_WITH_UNLOCK }
    start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    answer = { status = 400, body = '{"valid":false,"status":400,"code":"REVOKED"}' }
    local log, stopped = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(stopped, log)
    answer = { status = 0 }
    log = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(not log:find('Running'), log)
end)

test('tamper reports: a changed fxmanifest.lua is MODIFIED in the next check', function()
    sealedBuild()
    virtual['fxmanifest.lua'] = LoadResourceFile('my-resource', 'fxmanifest.lua') .. "\nserver_script 'evil.lua'\n"
    answer = { status = 200, body = VALID_WITH_UNLOCK }
    local log = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(log:find('Running'), log) -- the server keeps running: Sentinel decides, not the resource
    request = nil
    License.check(SunLicenseSettings, 'AX8P-K7QX-M2PD-9HWT', 'server-1', function() end)
    assert(request.body:find('"integrity":"MODIFIED"') and request.body:find('fxmanifest%.lua'), request.body)
end)

test('core unlock: data sealed for another product never runs', function()
    sealedBuild()
    answer = { status = 200, body = '{"valid":true,"code":"VALID","unlock":"' .. C.toBase64(C.sha256('another product')) .. '"}' }
    local log = start({ my_resource_license = 'AX8P-K7QX-M2PD-9HWT' }, true)
    assert(not log:find('Running') and log:find("wasn't sealed for this product"), log)
    virtual = {}
end)

print(('%d tests, %d failed'):format(count, failures))
os.exit(failures == 0 and 0 or 1)
