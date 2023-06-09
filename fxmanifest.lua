fx_version 'cerulean'
game 'gta5'
author 'MOXHA'
lua54 'yes'

name 'MX Discord Tool'
description 'A Tool for the Fivem Manager Bot'
version '1.1.3'
repository 'https://github.com/MOXHARTZ/mx-discordtool'
bot_invite 'https://discord.com/oauth2/authorize?client_id=1058429846805557330&scope=bot&permissions=1376805706816'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/config.lua',
    'server/modules/*.lua',
    'bridge/server.lua',
    'index.js',
    'server/enums.lua',
    'server/main.lua'
}

dependencies {
    '/server:5895',
    '/onesync',
    'oxmysql',
    'ox_lib',
    'yarn'
}
