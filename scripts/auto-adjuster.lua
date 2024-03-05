local utils = require 'mp.utils'
local profiles = {}

local selected = {
    name = "undefined",
    profile,
}

local internal_opts = {
    savedata = "~~/data",
    executor = "~~/tools",
    similarity = 45,
    showMessages = true,
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

local removedProfile = {}
local hasProfile = false
local usingFolder = false
local original_top = mp.get_property_native("ontop")
local function get_system_volume()
    if (not internal_opts.externaltools) then return end
    local executor = mp.command_native({"expand-path", internal_opts.executor .. "/svcl.exe"})
    mp.set_property_native("ontop", true)
    local file = io.popen(executor .. ' /Stdout /GetPercent "DefaultRenderDevice"')
    local output = file:read('*all'):gsub("[\r\n]", "")
    file:close()
    mp.add_timeout(2, function()
        mp.set_property_native("ontop", original_top)
    end)
    return math.floor(output)
end

local function cleanupTitle(title)
    title = title:gsub("%d+", "")
    title = title:gsub("%b()", "")
    title = title:gsub("%b[]", "")
    title = title:gsub("%_", " ")
    title = title:gsub("^%s*(.-)%s*$", "%1")
    return title
end

local function osd_print(message, duration)
    if (not duration) then duration = 3 end 
    duration = duration * 1000
    if (internal_opts.showMessages) then 
        print(message)
        mp.command('show-text "' .. message .. '" ' .. duration)
    end
end

local function validatePath(path)
    local directory = path:match("(.+)/.+")
    if not directory then
        return
    end

    local file = io.open(directory, "r")
    if file then
        file:close()
        return path
    else
        local success, err = os.execute("mkdir \"" .. directory .. "\"")
        if not success then
            print("Error creating directory: " .. err)
            return mp.command_native({"expand-path", "~~"})
        end
        return path
    end
    return mp.command_native({"expand-path", "~~"})
end

local function json_format(tbl)
    local json_str = utils.format_json(tbl)
    local indent_char = "    "
    local indent_level = 0
    local in_string = false

    local function insert_whitespace()
        return "\n" .. string.rep(indent_char, indent_level)
    end

    local beautified_str = ""
    for i = 1, #json_str do
        local char = string.sub(json_str, i, i)

        if char == '"' then
            in_string = not in_string
        end

        if not in_string then
            if char == "{" or char == "[" then
                indent_level = indent_level + 1
                beautified_str = beautified_str .. char .. insert_whitespace()
            elseif char == "}" or char == "]" then
                indent_level = indent_level - 1
                beautified_str = beautified_str .. insert_whitespace() .. char
            elseif char == "," then
                beautified_str = beautified_str .. char .. insert_whitespace()
            else
                beautified_str = beautified_str .. char
            end
        else
            beautified_str = beautified_str .. char
        end
    end

    return beautified_str
end

local function getSearchMethod(searchType)
    local compareFrom
    if (not searchType) then searchType = "file" end
    if (usingFolder) then searchType = "folder" end
    searchType = searchType:lower()
    if (searchType == "file") then
        compareFrom = mp.get_property("filename/no-ext")
    elseif (searchType == "folder") then
        local dir, filename = utils.split_path(mp.get_property("path"))
        compareFrom = dir 
        compareFrom = compareFrom:gsub("\\", "\\\\\\")
        compareFrom = string.sub(compareFrom, 1, -2)
        local parts = {}
        for part in string.gmatch(compareFrom, "[^\\\\\\]+") do
            table.insert(parts, part)
        end
        compareFrom = parts[#parts]
    end
    return cleanupTitle(compareFrom)
end

local original_volume
local function set_system_volume(volume)
    if (not internal_opts.externaltools) then return end
    local executor = mp.command_native({"expand-path", internal_opts.executor .. "/svcl.exe"})
    os.execute(executor .. ' /SetVolume "DefaultRenderDevice" ' .. math.floor(volume))
end

--[[https://gist.github.com/Badgerati/3261142]]
local function calculateSimilarity(str1, str2)
    str1 = str1:gsub("%s", "")
    str2 = str2:gsub("%s", "")    
    
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

local function setProperties(config)
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
            if (prop == "ext_volume") then if (value ~= original_volume) then set_system_volume(value) end end
            if (prop == "folder") then usingFolder = value end
        elseif properties[prop] == "number" then
            mp.set_property_number(prop, value)
        elseif properties[prop] == "native" then
            mp.set_property_native(prop, value)
        end
    end
end

local function setProfile(searchType, context)
    if (not context) then context = "undefined" end
    if (not searchType) then searchType = "file" end
    local compareFrom = getSearchMethod(searchType)
    local maxSimilarity = 0
    local profileName
    for name, profile in pairs(profiles) do
        local sim = calculateSimilarity(compareFrom, name)
        if sim > maxSimilarity then
            maxSimilarity = sim
            selected.profile = profile
            selected.name = name
        end
    end
    if maxSimilarity >= internal_opts.similarity then 
        hasProfile = true
        original_volume = get_system_volume()
        setProperties(selected.profile)
        if (context == "reload") then
            osd_print("Profile reloaded successfully..")
            return;
        end
        osd_print("(Likeness: " .. maxSimilarity .. "%) Profile set to " .. selected.name)
    else
        if (searchType == "file") then
            setProfile("folder")
            return;
        end
        hasProfile = false
        osd_print("(Likeness: " .. maxSimilarity .. "%) No profile found")
    end
end

local function saveProfiles(context)
    if (not context) then context = "undefined" end
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local file = io.open(validatePath(filePath), "r")
    local existingData = {}
    
    if file then
        local jsonData = file:read("*all")
        existingData = utils.parse_json(jsonData)
        file:close()
    end
    
    for k, v in pairs(profiles) do
        existingData[k] = v
    end
    
    local saveData = json_format(existingData)
    file = io.open(validatePath(filePath), "w")
    
    if file then
        file:write(saveData)
        file:close()
        if (context == "redo") then
            osd_print("Profile remove undone") 
            return
        end
        osd_print("Profiles saved")
    else
        osd_print("Failed to save profiles")
    end
end

local function copyProfile()
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
    selected.profile = profiles[filename]
    selected.name = filename
    saveProfiles()
end

local function loadProfiles(context)
    if (not context) then context = "undefined" end
    local file = io.open(validatePath(mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})), "r")
    if file then
        local data = file:read("*all")
        profiles = utils.parse_json(data)
        file:close()

        setProfile("file", context)
    end
end

local function clearProfiles()
    osd_print("Cleared + backed up all profiles")
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local backupFilePath = filePath .. "_backup"
    os.rename(filePath, backupFilePath)
    profiles = {}
    setProperties()
end

local function undoProfile()
    local filename = selected.name
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local file = io.open(validatePath(filePath), "r")
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
    
    removedProfile = profiles[filename]
    profiles[filename] = nil
    local saveData = json_format(existingData)
    file = io.open(validatePath(filePath), "w")
    
    if file then
        file:write(saveData)
        file:close()
        osd_print("Current profile removed")
    else
        osd_print("Failed to remove profile")
    end
end

local function redoProfile()
    local filename = selected.name
    profiles[filename] = removedProfile
    saveProfiles("redo")
end

mp.register_event("file-loaded", function() loadProfiles() end)

mp.register_event("shutdown", function()
    if (hasProfile) then set_system_volume(original_volume) end
    mp.set_property_native("ontop", original_top)
end)

mp.add_forced_key_binding("ctrl+shift+c", "saveProfile", function() copyProfile() end)
mp.add_forced_key_binding("ctrl+shift+r", "reloadProfiles", function() loadProfiles("reload") end)
mp.add_forced_key_binding("ctrl+shift+l", "clearProfiles", function() clearProfiles() end)
mp.add_forced_key_binding("ctrl+shift+z", "undoProfile", function() undoProfile() end)
mp.add_forced_key_binding("ctrl+shift+y", "redoProfile", function() redoProfile() end)

mp.add_forced_key_binding("ctrl+shift+f", "toggleFolderMode", function()
    usingFolder = not usingFolder
    osd_print("Using folder setting = "..tostring(usingFolder))
end)