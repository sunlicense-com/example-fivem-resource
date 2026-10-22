-- Start-up, re-checks and your features. The license is checked when the resource starts and every
-- my_resource_recheck_hours; your features start only once it is valid (startFeatures).

--- When SunLicense can't be reached: keep running (true, the default: an outage on our side shouldn't
--- take your customers' servers down) or wait (false).
local ALLOW_WHEN_UNREACHABLE = true
--- How soon to try again after no answer.
local RETRY_MS = 10 * 60 * 1000

local resource = GetCurrentResourceName()
local licenseKey = GetConvar('my_resource_license', '')
local started = false
local retrying = false
local status = nil

--- A random id for this server, kept in the resource's folder, so restarts count as the same machine.
--- Copying the folder to another server copies the id too; the license's machine limit still applies.
local function serverId()
    local id = LoadResourceFile(resource, '.machine-id')
    if id and id ~= '' then return id end
    math.randomseed(os.time())
    id = ('fivem-%08x%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), os.time())
    SaveResourceFile(resource, '.machine-id', id, -1)
    return id
end
local machine = serverId()

--- Your resource's features: register events, commands and threads here, not at the top of a file.
local function startFeatures()
    print(('^2[%s] Running.^7'):format(resource))
end

local check

local function apply(result)
    status = result
    if result.state == 'VALID' then
        if not started then
            started = true
            print(('^2[%s] License %s: %s^7'):format(resource, License.mask(licenseKey), result.message))
            startFeatures()
        end
    elseif result.state == 'REJECTED' or result.state == 'NOT_CONFIGURED' then
        print(('^1[%s] License %s: %s^7'):format(resource, License.mask(licenseKey), result.message))
        print(('^1[%s] Stopping until this is fixed.^7'):format(resource))
        StopResource(resource)
    else
        print(('^3[%s] %s Trying again in 10 minutes.^7'):format(resource, result.message))
        if ALLOW_WHEN_UNREACHABLE and not started then
            started = true
            startFeatures()
        elseif not started then
            print(('^1[%s] Needs a license check to start; it will start once SunLicense answers.^7'):format(resource))
        end
        if not retrying then   -- one retry at a time
            retrying = true
            SetTimeout(RETRY_MS, function()
                retrying = false
                check()
            end)
        end
    end
end

check = function()
    License.check(SunLicenseSettings, licenseKey, machine, apply)
end

check()

local hours = tonumber(GetConvar('my_resource_recheck_hours', '6')) or 6
if hours > 0 then
    CreateThread(function()
        while true do
            Wait(hours * 60 * 60 * 1000)
            check()
        end
    end)
end

-- "my_resource_license" in the server console (or with ace permission command.my_resource_license):
-- shows the license status, masked.
RegisterCommand('my_resource_license', function(source)
    local s = status and (('%s: %s'):format(status.state, status.message)) or "The license hasn't been checked yet."
    local line = ('License %s (%s)'):format(License.mask(licenseKey), s)
    if source == 0 then print(line) else TriggerClientEvent('chat:addMessage', source, { args = { resource, line } }) end
end, true)
