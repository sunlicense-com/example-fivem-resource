-- The protected part of your resource: the features buyers pay for. scripts/package.sh seals this file
-- (`sunlicense seal`) into server/core.sealed for the build you sell, and leaves this plain copy out, so
-- it only runs after SunLicense confirms the license (core unlock). A copy with the license check cut
-- out has no key to open it.
--
-- Return a table with start(); it runs once, after a valid check (or one in the last 7 days when
-- SunLicense can't be reached). Register your events, commands and threads in it, not at the top level.

local Core = {}

function Core.start(resource)
    -- Your features. For example:
    -- RegisterCommand('hello', function(source) TriggerClientEvent('chat:addMessage', source, { args = { resource, 'Hello!' } }) end)
    print(('^2[%s] Running.^7'):format(resource))
end

return Core
