local utils = require 'mp.utils'
local profiles = {}

local internal_opts = {
    savedata = "~~/data",
    executor = "~~/tools",
    similarity = 35,
    externaltools = true
}

local properties = {
    saturation = "number",
    folder = "special",
    ext_volume = "special",
    volume = "native",
    brightness = "number",
    gamma = "number",
    contrast = "number",
    vf = "native"
}

local usingFolder = false
local original_top = mp.get_property_native("ontop")
function get_system_volume()
    if (not internal_opts.externaltools) then return end
    local executor = mp.command_native({"expand-path", internal_opts.executor .. "/svcl.exe"})
    mp.set_property_native("ontop", true)
    local file = io.popen(executor .. ' /Stdout /GetPercent "Volume"')
    local output = file:read('*all'):gsub("[\r\n]", "")
    file:close()
    mp.add_timeout(3, function()
        mp.set_property_native("ontop", original_top)
    end)
    return output
end

function getSearchMethod(searchType)
    local compareFrom
    if (not searchType) then searchType = "file" end
    if (usingFolder) then searchType = "folder" end
    searchType = searchType:lower()
    if (searchType == "file") then
        compareFrom = mp.get_property("filename/no-ext")
    elseif (searchType == "folder") then
        local dir, filename = utils.split_path(mp.get_property("path"))
        compareFrom = dir 
        local compareFrom = compareFrom:gsub([[\]], "\\")
        compareFrom = string.sub(compareFrom, 1, -2)
        local parts = {}
        for part in string.gmatch(compareFrom, "[^\\]+") do
            table.insert(parts, part)
        end
        compareFrom = parts[#parts]
    end
    return compareFrom
end

local original_volume = get_system_volume()
function set_system_volume(volume)
    if (not internal_opts.externaltools) then return end
    local executor = mp.command_native({"expand-path", internal_opts.executor .. "/svcl.exe"})
    os.execute(executor .. ' /SetVolume "Volume" ' .. volume)
end

--[[https://gist.github.com/Badgerati/3261142]]
local function calculateSimilarity(str1, str2)
    local len1 = string.len(str1)
    local len2 = string.len(str2)
    local matrix = {}
    local cost = 0
    
    -- quick cut-offs to save time
    if (len1 == 0) then
        return 0  -- When one string is empty, they are perfectly different
    elseif (len2 == 0) then
        return 0  -- When one string is empty, they are perfectly different
    elseif (str1 == str2) then
        return 100  -- When both strings are identical, they are perfectly similar
    end
    
    -- initialise the base matrix values
    for i = 0, len1, 1 do
        matrix[i] = {}
        matrix[i][0] = i
    end
    for j = 0, len2, 1 do
        matrix[0][j] = j
    end
    
    -- actual Levenshtein algorithm
    for i = 1, len1, 1 do
        for j = 1, len2, 1 do
            if (str1:byte(i) == str2:byte(j)) then
                cost = 0
            else
                cost = 1
            end
            
            matrix[i][j] = math.min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
        end
    end
    
    -- Calculate similarity as a value between 0 and 100
    local maxLen = math.max(len1, len2)
    local distance = matrix[len1][len2]
    local similarity = math.floor((1 - distance / maxLen) * 100)
    
    return similarity
end

function setProfile(searchType, context)
    if (not context) then context = "undefined" end
    if (not searchType) then searchType = "file" end
    local compareFrom = getSearchMethod(searchType)
    local maxSimilarity = 0
    local bestMatch
    local profileName
    for name, profile in pairs(profiles) do
        local sim = calculateSimilarity(compareFrom, name)
        if sim > maxSimilarity then
            maxSimilarity = sim
            bestMatch = profile
            profileName = name
        end
    end
    if maxSimilarity >= internal_opts.similarity then 
        setProperties(bestMatch)
        if (context == "reload") then
            mp.osd_message("Profile reloaded successfully..")
            return;
        end
        mp.osd_message("(Likeness: " .. maxSimilarity .. "%) Profile set to " .. profileName)
    else
        if (searchType == "file") then
            setProfile("folder")
            return;
        end
        mp.osd_message("(Likeness: " .. maxSimilarity .. "%) No profile found")
    end
end

function setProperties(config)
    if not config then
        config = {}
        for prop, propType in pairs(properties) do
            if propType == "number" then
                config[prop] = 0
            elseif propType == "native" then
                config[prop] = ""
            elseif propType == "special" then
                config[prop] = nil
                if (prop == "ext_volume") then config[prop] = original_volume end
                if (prop == "folder") then config[prop] = false end
            end
        end
    end
    for prop, value in pairs(config) do
        if properties[prop] == "special" then
            if (prop == "ext_volume") then set_system_volume(value) end
            if (prop == "folder") then usingFolder = value end
        elseif properties[prop] == "number" then
            mp.set_property_number(prop, value)
        elseif properties[prop] == "native" then
            mp.set_property_native(prop, value)
        end
    end
end

function copyProfile()
    local filename = getSearchMethod()
    profiles[filename] = {}
    for prop, propType in pairs(properties) do
        if propType == "number" then
            profiles[filename][prop] = mp.get_property_number(prop)
        elseif propType == "native" then
            profiles[filename][prop] = mp.get_property_native(prop)
        elseif propType == "special" then
            profiles[filename][prop] = mp.get_property_number(prop)
            if (prop == "ext_volume") then profiles[filename][prop] = get_system_volume() end
            if (prop == "folder") then profiles[filename][prop] = usingFolder end
        end
    end
    saveProfiles()
end

function loadProfiles(context)
    if (not context) then context = "undefined" end
    local file = io.open(mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"}), "r")
    if file then
        local data = file:read("*all")
        profiles = utils.parse_json(data)
        file:close()

        mp.add_timeout(1, function()
            setProfile("file", context)
        end)
    end
end

function clearProfiles()
    mp.osd_message("Cleared + backed up all profiles")
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local backupFilePath = filePath .. "_backup"
    os.rename(filePath, backupFilePath)
    profiles = {}
    setProperties()
end

function saveProfiles()
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local file = io.open(filePath, "r")
    local existingData = {}
    
    if file then
        local jsonData = file:read("*all")
        existingData = utils.parse_json(jsonData)
        file:close()
    end
    
    for k, v in pairs(profiles) do
        existingData[k] = v
    end
    
    local saveData = utils.format_json(existingData)
    file = io.open(filePath, "w")
    
    if file then
        file:write(saveData)
        file:close()
        mp.osd_message("Profiles saved")
    else
        mp.osd_message("Failed to save profiles")
    end
end

function undoProfile()
    local filename = getSearchMethod()
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local file = io.open(filePath, "r")
    local existingData = {}
    
    if file then
        local jsonData = file:read("*all")
        existingData = utils.parse_json(jsonData)
        file:close()
    end
    
    for k, v in pairs(profiles) do
        if (k == filename) then
            existingData[k] = nil
        end
    end
    
    local saveData = utils.format_json(existingData)
    file = io.open(filePath, "w")
    
    if file then
        file:write(saveData)
        file:close()
        mp.osd_message("Current profile removed")
    else
        mp.osd_message("Failed to remove profile")
    end
end

loadProfiles()

mp.register_event("shutdown", function()
    set_system_volume(original_volume)
    mp.set_property_native("ontop", original_top)
end)

mp.add_forced_key_binding("ctrl+shift+c", "saveProfile", function() copyProfile() end)
mp.add_forced_key_binding("ctrl+shift+r", "reloadProfiles", function() loadProfiles("reload") end)
mp.add_forced_key_binding("ctrl+shift+l", "clearProfiles", function() clearProfiles() end)
mp.add_forced_key_binding("ctrl+shift+z", "undoProfile", function() undoProfile() end)

mp.add_forced_key_binding("ctrl+shift+f", "toggleFolderMode", function()
    usingFolder = not usingFolder
    mp.osd_message("Using folder setting = "..tostring(usingFolder))
end)