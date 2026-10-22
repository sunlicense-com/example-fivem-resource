-- A FiveM resource protected by SunLicense. See README.md.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'my-resource'
author 'You'
description 'A FiveM resource protected by SunLicense'
version '1.0.0'

-- lib/sunlicense.lua (the SDK) is loaded by server/license.lua, so it isn't listed here.
server_scripts {
    'settings.lua',
    'server/license.lua',
    'server/main.lua',
}
