-- Tests for server/license.lua with plain Lua 5.4: FiveM's functions are stubbed, SunLicense's answers too.
--   lua tests/run.lua
local root = arg[0]:match('^(.*)/tests/run%.lua$') or '.'

local request, answer
function GetCurrentResourceName() return 'my-resource' end
function LoadResourceFile(_, name)   -- nil for a missing file, like FiveM
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
local function start(convars)
    local log, stopped, files = {}, false, {}
    function GetConvar(name, default) return convars[name] or default end
    function SaveResourceFile(_, name, data) files[name] = data end
    function StopResource() stopped = true end
    function SetTimeout() end
    function CreateThread() end
    function RegisterCommand() end
    SunLicenseSettings = { url = 'https://api.example.test', apiKey = 'slk_test' }
    local realPrint = print
    print = function(line) log[#log + 1] = line end
    local ok, err = pcall(dofile, root .. '/server/main.lua')
    print = realPrint
    assert(ok, err)
    return table.concat(log, '\n'), stopped, files
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

print(('%d tests, %d failed'):format(count, failures))
os.exit(failures == 0 and 0 or 1)
