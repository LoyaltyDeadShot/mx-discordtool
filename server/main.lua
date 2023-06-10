if config.guild == '' then Warn('Please set the guild id in the config.lua') end

local convar = GetConvar("mysql_connection_string", "")

---@param connectionString string The connection string to parse
---@return table The parsed uri
local function parseUri(connectionString)
    local uri = {}
    local str = connectionString:sub(9)
    local split = str:split('?')
    local uriStr = split[1]
    local paramsStr = split[2]
    local uriSplit = uriStr:split('@')
    local auth = uriSplit[1]
    local host = uriSplit[2]
    local authSplit = auth:split(':')
    local user = authSplit[1]
    local password = authSplit[2]
    local hostSplit = host:split('/')
    local hostSplit2 = hostSplit[1]:split(':')
    local hostName = hostSplit2[1]
    local port = hostSplit2[2]
    local database = hostSplit[2]
    uri.user = user
    uri.password = password
    uri.hostName = hostName
    uri.port = port
    uri.database = database
    if paramsStr then
        local paramsSplit = paramsStr:split('&')
        for _, param in ipairs(paramsSplit) do
            local paramSplit = param:split('=')
            local key = paramSplit[1]
            local value = paramSplit[2]
            uri[key] = value
        end
    end
    return uri
end

DATABASE_NAME = convar:match("database=(.-);")

if not DATABASE_NAME and convar:match("mysql://") then
    local uri = parseUri(convar)
    DATABASE_NAME = uri.database
end

if not DATABASE_NAME then
    error('Failed to get database name from mysql_connection_string convar. Please check your mysql_connection_string convar. You can reference here: https://overextended.dev/oxmysql/issues')
end

---@param enum number
---@return string | nil
local function getEnumName(enum)
    for k, v in pairs(TypeEnum) do
        if v == enum then return k end
    end
    return nil
end

local function getGuildId()
    return config.guild
end

exports('GetGuildId', getGuildId)

---@param enum number The enum to convert to function
---@param owner string The command sender (Discord Id) In the future we will use this for some things
---@vararg any The arguments to pass to the enum
local function enumToFunction(enum, owner, ...)
    if not enum then return error('enum is nil') end
    local enumName = getEnumName(enum)
    if not enumName then return error(('Failed to get enum name: %s'):format(enum)) end
    local funcName = _G[enumName]
    if not funcName then return error(('Failed to load enum: %s'):format(enumName)) end
    local data = funcName(...)
    return data
end

---@param owner string The command sender (Discord Id) In the future we will use this for some things
---@param guild string The guild id to get the data from
---@param type number The enum to convert to function
---@param data table
local function getRequestData(owner, guild, type, data)
    return enumToFunction(type, owner, data)
end

exports('GetRequestData', getRequestData)

---@param player string The player server id to get the identifier from
---@param identifierType string | table The type of the identifier to get (discord, steam, license, xbl, live, fivem)
---@return string | table | nil The identifier(s)
function GetPlayerIdentifierFromType(player, identifierType)
    local data
    local typeOf = type(identifierType)
    if typeOf == 'string' then identifierType = { identifierType } end
    if typeOf == 'table' then data = {} end
    for _, v in ipairs(identifierType) do
        local identifiers = GetPlayerIdentifiers(player)
        for _, identifier in ipairs(identifiers) do
            if identifier:find(v) then
                if typeOf == 'table' then
                    data[v] = identifier
                end
                if typeOf == 'string' and v == identifierType[1] then 
                    data = identifier
                end
                break
            end
        end
    end
    if type(data) == 'table' and not next(data) then return nil end
    return data
end

---@param player string The player server id to get the discord id from
---@return string | nil The discord id
function GetPlayerDiscordId(player)
    local discordId = nil
    local identifier = GetPlayerIdentifierFromType(player, 'discord')
    if identifier and type(identifier) == 'string' then
        discordId = identifier:gsub('discord:', '')
    end
    return discordId
end

---@param unknownId string The unknown id to get the player server id from (must be discord or identifier or source)
---@return string | nil The player server id
function GetPlayerFromUnknownId(unknownId)
    unknownId = unknownId:gsub('discord:', '')
    local players = GetPlayers()
    for _, player in ipairs(players) do
        if player == unknownId then return player end
        local identifier = Framework:GetIdentifier(player)
        if identifier == unknownId then return player end
        local playerDiscordId = GetPlayerDiscordId(player)
        if playerDiscordId == unknownId then return player end
    end
    return nil
end

-- https://stackoverflow.com/a/27028488/19627917
---@param o table The table to dump
---@return string The dumped table
function Dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. Dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

---@param source string The player server id to get the tokens from
---@return table | nil The tokens
function GetTokensFromPlayer(source)
    local data = {}
    local tokens = GetNumPlayerTokens(source)
    if not tokens or tokens < 0 then return nil end
    for i = 0, tokens - 1 do
        local token = GetPlayerToken(source, i)
        table.insert(data, token)
    end
    return data
end

---@param identifier string The identifier to set to base (important for using the multicharacter)
---@return string The identifier without the multicharacter code (ex: 1:123sd23 -> 123sd23)
function SetIdentifierToBase(identifier)
    local match = identifier:match('%d:%w+')
    if not match then return identifier end
    local split = match:split(':')
    if #split > 1 then
        identifier = split[2]
    end
    return identifier
end

--- @param data {identifier: string}
--- @return {banned: boolean, whitelisted: boolean, job: string, charinfo: table, accounts: table, group: string, identifier: string, inventory: table, status: 'online' | 'offline'}
function GetUserById(data)
    local resolve = Framework:GetUserData(data.identifier)
    return resolve
end

---@param data {discord: string, character: number} 
---@return table
function GetUserByDiscord(data)
    local source = GetPlayerFromUnknownId(data.discord)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        } 
    end
    local identifier = Framework:GetIdentifier(source)
    local resolve = Framework:GetUserData(identifier)
    return resolve
end

---@param identifier string The identifier to get the tokens from
---@param fivem string The fivem identifier
---@param license string The license identifier
---@param xbl string The xbl identifier
---@param live string The live identifier
---@param discord string The discord identifier
---@param tokens table The tokens
---@param duration number The duration of the ban
---@param reason string The reason of the ban
---@param bannedBy string Discord id of the admin who banned the user
local function banSql(identifier, fivem, license, xbl, live, discord, tokens, duration, reason, bannedBy)
    identifier = identifier or ''
    identifier = SetIdentifierToBase(identifier)
    fivem = fivem or ''
    license = license or ''
    xbl = xbl or ''
    live = live or ''
    discord = discord or ''
    tokens = tokens or {}
    duration = duration or os.time() + config.defaultBanDuration
    reason = reason or ''
    bannedBy = bannedBy or ''
    MySQL.insert.await('INSERT INTO mx_banlist (identifier, fivem, license, xbl, live, discord, tokens, duration, reason, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        identifier,
        fivem,
        license,
        xbl,
        live,
        discord,
        json.encode(tokens),
        duration,
        reason,
        bannedBy
    })
end

--- @param data {identifier: string} 
--- @return string | table The error code or success
function UnBan(data)
    local identifier = SetIdentifierToBase(data.identifier)
    local isBanned = CheckPlayerIsBanned(identifier)
    if not isBanned then return _T('unban.is_not_banned') end
    MySQL.execute.await('DELETE FROM mx_banlist WHERE identifier = ?', {
        identifier
    })
    return 'success'
end

---@param identifier string
function SetWhitelist(identifier)
    identifier = SetIdentifierToBase(identifier)
    MySQL.insert.await('INSERT INTO mx_whitelist (identifier) VALUES (?) ON DUPLICATE KEY UPDATE identifier = ?', {
        identifier,
        identifier
    })
end

---@param identifier string
function RemoveWhitelist(identifier)
    identifier = SetIdentifierToBase(identifier)
    MySQL.execute.await('DELETE FROM mx_whitelist WHERE identifier = ?', {
        identifier
    })
end

---@param tokens1 table The first tokens
---@param tokens2 table The second tokens
---@return boolean If the tokens are the same
local function checkTokens(tokens1, tokens2)
    for _, token1 in ipairs(tokens1) do
        for _, token2 in ipairs(tokens2) do
            if token1 == token2 then return true end
        end
    end
    return false
end

---@param number number The number to check
---@param str string The string to add the suffix
local function suffixDate(number, str)
    if number > 1 then return str .. 's' end
    return str
end

---@param time number The time to format
---@return string The formatted time
local function formatDuration(time)
    local duration = time - os.time()
    local years = math.floor(duration / (60 * 60 * 24 * 365))
    duration = duration - (years * 60 * 60 * 24 * 365)
    local months = math.floor(duration / (60 * 60 * 24 * 30))
    duration = duration - (months * 60 * 60 * 24 * 30)
    local weeks = math.floor(duration / (60 * 60 * 24 * 7))
    duration = duration - (weeks * 60 * 60 * 24 * 7)
    local days = math.floor(duration / (60 * 60 * 24))
    duration = duration - (days * 60 * 60 * 24)
    local hours = math.floor(duration / (60 * 60))
    duration = duration - (hours * 60 * 60)
    local minutes = math.floor(duration / 60)
    duration = duration - (minutes * 60)
    local seconds = math.floor(duration)

    local yearStr = suffixDate(years, 'general.year')
    local monthStr = suffixDate(months, 'general.month')
    local weekStr = suffixDate(weeks, 'general.week')
    local dayStr = suffixDate(days, 'general.day')
    local hourStr = suffixDate(hours, 'general.hour')
    local minuteStr = suffixDate(minutes, 'general.minute')
    local secondStr = suffixDate(seconds, 'general.second')

    local data = {}
    if years > 0 then table.insert(data, years .. _T(yearStr)) end
    if months > 0 then table.insert(data, months .. _T(monthStr)) end
    if weeks > 0 then table.insert(data, weeks .. _T(weekStr)) end
    if days > 0 then table.insert(data, days .. _T(dayStr)) end
    if hours > 0 then table.insert(data, hours .. _T(hourStr)) end
    if minutes > 0 then table.insert(data, minutes .. _T(minuteStr)) end
    if seconds > 0 then table.insert(data, seconds .. _T(secondStr)) end
    return table.concat(data, ', ')
end

---@param identifier string The identifier to check
---@return boolean If the player is banned
function CheckPlayerIsBanned(identifier)
    identifier = SetIdentifierToBase(identifier)
    local banList = MySQL.prepare.await('SELECT id FROM mx_banlist WHERE identifier = ?', {
        identifier
    })
    return banList ~= nil
end

---@param identifiers {license: string, steam: string}
---@return boolean If the player is whitelisted
function CheckPlayerIsWhitelisted(identifiers)
    if identifiers.license then
        identifiers.license = SetIdentifierToBase(identifiers.license)
    end
    local whitelist = MySQL.prepare.await('SELECT identifier FROM mx_whitelist WHERE identifier = ? OR identifier = ?', {
        identifiers.license,
        identifiers.steam or '-1'
    })
    return whitelist ~= nil 
end

local function onPlayerConnecting(name, setKickReason, deferrals)
    local source = source
    deferrals.defer()
    Wait(0)
    deferrals.update(_T('connection.checking'))
    Wait(1000)
    local identifiers = GetPlayerIdentifierFromType(source, {
        'discord',
        'license',
        'xbl',
        'live',
        'fivem',
        'steam'
    })
    if not identifiers then 
        deferrals.done(_T('connection.can_not_get_identifiers'))
        return
    end

    deferrals.update(_T('connection.checking.ban'))

    Wait(1000)

    local tokens = GetTokensFromPlayer(source)
    if not tokens then 
        deferrals.done(_T('connection.can_not_get_tokens'))
        return
    end

    local banList = MySQL.query.await('SELECT * FROM mx_banlist')
    if not banList or #banList == 0 then goto skipBanCheck end

    Wait(0)

    for _, ban in ipairs(banList) do
        local banned = false
        if ban?.fivem == identifiers?.fivem then banned = true end
        if ban?.license == identifiers?.license then banned = true end
        if ban?.xbl == identifiers?.xbl then banned = true end
        if ban?.live == identifiers?.live then banned = true end
        if ban?.discord == identifiers?.discord then banned = true end
        if checkTokens(tokens, json.decode(ban.tokens)) then banned = true end
        if banned then
            if ban.duration < os.time() then
                MySQL.execute.await('DELETE FROM mx_banlist WHERE id = ?', {
                    ban.id
                })
                deferrals.done()
                return
            end
            local duration = formatDuration(ban.duration)
            local reason = _T('connection.banned', ban.reason, duration)
            deferrals.done(reason)
            return
        end
    end

    ::skipBanCheck::

    Wait(100)

    if not config.whitelist then return deferrals.done() end

    deferrals.update(_T('connection.checking.whitelist'), config.discordInviteLink)

    Wait(1000)
    
    -- Hmm i don't know how to i get rockstar license from the api, so i'm using the steam id for the whitelist.
    local whitelisted = CheckPlayerIsWhitelisted({
        license = identifiers?.license,
        steam = identifiers?.steam
    })

    if not whitelisted then
        deferrals.done(_T('connection.not_whitelisted'))
        return
    end

    Wait(0)

    deferrals.done()
end

AddEventHandler('playerConnecting', onPlayerConnecting)

-- ! Developer Note Framework:GetIdentifier function returns the citizenid for qbcore. So maybe we need to change it to steam or license or fivem or discord. 
---@param source string The player server id to get the framework identifier from
---@param reason string The reason of the ban
---@param duration number The duration of the ban
---@param bannedBy string The discord id of the admin who banned the user
local function ban(source, reason, duration, bannedBy)
    local frameworkIdentifier = Framework:GetIdentifier(source)
    if not frameworkIdentifier then return Warn('Failed to get framework identifier from source :' .. source) end
    local identifiers = GetPlayerIdentifierFromType(source, {
        'discord',
        'license',
        'xbl',
        'live',
        'fivem'
    })
    if not identifiers then return Warn(_T('error.failed_to_get_identifier', source)) end
    local tokens = GetTokensFromPlayer(source)
    if not tokens then return Warn('Failed to get tokens from source :' .. source) end
    banSql(frameworkIdentifier, identifiers?.fivem, identifiers?.license, identifiers?.xbl, identifiers?.live, identifiers.discord, tokens, duration, reason, bannedBy)
    DropPlayer(source, reason)
end

---@param data {identifier: string, reason: string, duration: string | number, bannedBy: string} The data to ban the user
---@return string | table The error code or success
function BanUser(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    local duration = tonumber(data.duration)
    if not duration then return 'Duration is not a number!' end
    duration = os.time() + duration * 60 * 60
    ban(source, data.reason, duration, data.bannedBy)
    return 'success'
end

local genders
function FormatGender(gender)
    if not genders then
        genders = {
            ['m'] = _T('user_info.male'),
            ['f'] = _T('user_info.female'),
            [0] = _T('user_info.male'),
            [1] = _T('user_info.female')
        }
    end
    gender = genders[gender]
    return gender or 'Unknown Gender' 
end

---@param data {identifier: string} The data to get the user from
---@return string | table The error code or success
function Screenshot(data)
    local resourceState = GetResourceState('screenshot-basic')
    if resourceState ~= 'started' then 
        local str = 'Screenshot property is working with screenshot-basic resource. If you want to use it, please install the screenshot-basic.'
        Warn(str)
        return str
    end
    if config.webhook == '' then
        local str = 'Webhook is empty, please set the webhook in the config.lua'
        Warn(str)
        return str
    end
    local discord = data.identifier
    local source = GetPlayerFromUnknownId(discord)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        } 
    end
    local screenshot = lib.callback.await('mx-discordtool:takeScreenshot', source, config.webhook)
    if screenshot == '' then return 'Failed to take screenshot. May be the webhook is not valid.' end
    return screenshot
end

---@param data {identifier:string, reason: string}
---@return string | table The error code or success
function KickUser(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    DropPlayer(source, data.reason)
    return 'success'
end

local wipeFetch = ([[
    SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_MAXIMUM_LENGTH
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = '%s' AND DATA_TYPE = 'varchar' AND COLUMN_NAME IN('identifier','owner','citizenid')
]]):format(DATABASE_NAME)

---@param identifier string The identifier to wipe
---@return string | table The error code or success
local function sqlWipe(identifier)
    local userIsExist = Framework:CheckUserIsExistInSql(identifier)
    if not userIsExist then 
        return {
            errorCode = 307 -- User is not in the database
        }
    end

    local result = MySQL.query.await(wipeFetch)
    for k,element in pairs(result) do
        local wipeExecute = ([[
            DELETE FROM %s WHERE %s = ?
        ]]):format(element.TABLE_NAME, element.COLUMN_NAME)
        MySQL.Sync.execute(wipeExecute:format(element.TABLE_NAME, element.COLUMN_NAME), {
            identifier
        })
    end
    return 'success'
end

---@param data {identifier: string }
---@return string | table The error code or success
function Wipe(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    local identifier
    if source then 
        identifier = Framework:GetIdentifier(source)
        if not identifier then return _T('error.failed_to_get_identifier', source) end
        DropPlayer(source, _T('wipe.drop.player.reason'))
    else    
        identifier = data.identifier
        local player = Framework:GetPlayerByIdentifier(identifier)
        if player then
            DropPlayer(player.source, _T('wipe.drop.player.reason'))
        end
    end
    
    return sqlWipe(identifier)
end

---@param data {identifier: string }
---@return string | table The error code or success
function Revive(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    return Framework:Revive(source)
end

---@param data {identifier: string }
---@return string | table The error code or success
function Kill(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    local src = tonumber(source)
    if not src then return 'Source is not a number!' end
    TriggerClientEvent('mx-discordtool:die', src)
    Framework:ShowNotification(src, _T('kill.notification'))
    return 'success'
end

---@param data {identifier: string, coords: {x: number, y: number, z: number} }
---@return string | table The error code or success
function SetCoords(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    local src = tonumber(source)
    if not src then return 'Source is not a number!' end
    local ped = GetPlayerPed(src)
    local coords = data.coords
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then return _T('set_coords.invalid') end
    SetEntityCoords(ped, x, y, z, true, false, false, false)
    Framework:ShowNotification(src, _T('set_coords.notification'))
    return 'success'
end

---@param data {identifier: string }
---@return string | table The error code or success
function ToggleWhitelist(data)
    if not config.whitelist then return _T('whitelist.disabled') end
    local frameworkIdentifier = Framework:SetIdentifier(data.identifier)
    if not frameworkIdentifier then return _T('error.failed_to_get_identifier', data.identifier) end
    data.identifier = frameworkIdentifier
    local whitelisted = CheckPlayerIsWhitelisted({
        license = data.identifier
    })
    if whitelisted then
        RemoveWhitelist(data.identifier)
    else
        SetWhitelist(data.identifier)
    end
    return _T('whitelist.response', whitelisted and '❌' or '✅')
end

---@param data {identifier: string, group: string }
---@return string | table The error code or success
function SetGroup(data)
    local group = data.group
    if not group then return 'Group is not a string!' end
    return Framework:SetGroup(data.identifier, group)
end

---@param data {identifier: string, job: string, grade: string }
---@return string | table The error code or success
function SetJob(data)
    local job = data.job
    local grade = tonumber(data.grade)
    if not job then return 'Job is not a string!' end
    if not grade then return _T('set_job.grade.invalid') end
    return Framework:SetJob(data.identifier, job, grade)
end

---@param data {identifier: string, amount: number, type: string, action: string} Action is (add_money, remove_money, set_money) and type is (bank, cash, black_money(only for esx))
---@return string | table The error code or success
function SetMoney(data)
    local amount = tonumber(data.amount)
    local type = data.type
    local action = data.action
    if not amount then return 'Amount is not a number!' end
    if not type then return 'Type is not a string!' end
    if not action then return 'Action is not a string!' end
    return Framework:SetMoney(data.identifier, amount, type, action)
end

---@param coords vector4 The coords to spawn the vehicle
---@param model string The model of the vehicle
---@return string Response string
---@return number | nil The entity of the vehicle
local function spawnVehicle(coords, model)
    -- CreateVehicleServerSetter is not working -_-
    local entity = CreateVehicle(model, coords.x, coords.y, coords.z + 1.0, coords.w, true, true)
    local finish = 10
    while not DoesEntityExist(entity) do
        Wait(100)
        finish = finish - 1
        if finish <= 0 then return 'Failed to spawn vehicle' end
    end
    return 'success', entity
end

---@param data {identifier: string, model: string} The data to give the vehicle
---@return string | table The error code or success
function GiveVehicle(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    local src = tonumber(source)
    if not src then return 'Source is not a number!' end
    local ped = GetPlayerPed(src)
    if not ped then return 'Ped is nil but how is the possible? :thinking:' end
    local entityCoords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local coords = vec4(entityCoords.x, entityCoords.y, entityCoords.z, heading)
    local model = data.model
    if not model then return 'Model is not a string!' end
    local existModel = lib.callback.await('mx-discordtool:isModelExist', src, model)
    if not existModel then return _T('give_vehicle.model.does_not_exists') end
    local response, entity = spawnVehicle(coords, model)
    if not entity then return response end
    TaskWarpPedIntoVehicle(ped, entity, -1)
    Framework:ShowNotification(src, _T('give_vehicle.notification'))
    return response
end

---@param data {identifier: string, item: string, amount: string}
---@return string | table The error code or success
function GiveItem(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    local item = data.item
    local amount = tonumber(data.amount)
    if not item then return 'Item is not a string!' end
    if not amount then return 'Amount is not a number!' end
    return Framework:GiveItem(source, item, amount)
end

---@param data {identifier: string, item: string, amount: string}
---@return string | table The error code or success
function RemoveItem(data)
    local source = GetPlayerFromUnknownId(data.identifier)
    if not source then 
        return {
            errorCode = 301 -- User is not in the server
        }
    end
    local item = data.item
    local amount = tonumber(data.amount)
    if not item then return 'Item is not a string!' end
    if not amount then return 'Amount is not a number!' end
    return Framework:RemoveItem(source, item, amount)
end

---@param data {firstName: string, lastName: string}
---@return string | table The error code or success
function GetUserByName(data)
    local firstName = data.firstName
    local lastName = data.lastName
    if not firstName then return 'First name is not a string!' end
    if not lastName then return 'Last name is not a string!' end
    local identifier = Framework:GetIdentifierByFirstnameAndLastname(firstName, lastName)
    if type(identifier) == 'table' then return identifier end
    local resolve = Framework:GetUserData(identifier)
    return resolve
end

---@param data {source: string | number}
---@return string | table The error code or success
function GetUserBySource(data)
    local src = tonumber(data.source)
    if not src then return 'Source is not a number!' end
    local identifier = Framework:GetIdentifier(src)
    if not identifier then return _T('error.failed_to_get_identifier', data.source) end
    local resolve = Framework:GetUserData(identifier)
    return resolve
end

---@param inventory table
---@return table
function FormatInventory(inventory)
    local result = {}
    if not inventory then return result end
    for _, item in ipairs(inventory) do
        table.insert(result, item)
    end
    return result
end

function GetBanList()
    local banList = MySQL.query.await('SELECT * FROM mx_banlist ORDER BY id ASC')
    if not banList or #banList == 0 then return nil end
    for _, ban in ipairs(banList) do
        local duration = formatDuration(ban.duration)
        ban.duration = duration
    end
    return banList
end