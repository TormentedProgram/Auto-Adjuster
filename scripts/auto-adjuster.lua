local utils = require 'mp.utils'

local externaltools = true
local profiles = {}

local internal_opts = {
    savedata = "~~/script-opts",
    executor = "~~/scripts"
}

local properties = {
    saturation = "number",
    ext_volume = "special",
    volume = "native",
    brightness = "number",
    gamma = "number",
    contrast = "number",
    vf = "native"
}

local original_top = mp.get_property_native("ontop")
function get_system_volume()
    if (not externaltools) then return end
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

local original_volume = get_system_volume()
function set_system_volume(volume)
    if (not externaltools) then return end
    local executor = mp.command_native({"expand-path", internal_opts.executor .. "/svcl.exe"})
    os.execute(executor .. ' /SetVolume "Volume" ' .. volume)
end

local function calculateSimilarity(str1, str2)
    local words1 = {}
    local words2 = {}
    for word in str1:lower():gmatch("%a+") do
        table.insert(words1, word)
    end
    for word in str2:lower():gmatch("%a+") do
        table.insert(words2, word)
    end
    
    local intersection = 0
    for _, word1 in ipairs(words1) do
        for _, word2 in ipairs(words2) do
            if word1 == word2 then
                intersection = intersection + 1
                break
            end
        end
    end
    
    local similarity = intersection / math.max(#words1, #words2)
    
    return similarity
end

function setProfile()
    local filename = mp.get_property("filename/no-ext")
    local maxSimilarity = 0
    local bestMatch
    local profileName
    for name, profile in pairs(profiles) do
        local sim = calculateSimilarity(filename, name)
        if sim > maxSimilarity then
            maxSimilarity = sim
            bestMatch = profile
            profileName = name
        end
    end
    if maxSimilarity >= 0.25 then 
        setProperties(bestMatch)
        mp.osd_message("(Likeness:" .. maxSimilarity .. ") Profile set to " .. profileName)
    else
        mp.osd_message("(Likeness:" .. maxSimilarity .. ") No matching profile found")
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
                if (prop == "ext_volume") then config[prop] = set_system_volume(original_volume) end
            end
        end
    end
    for prop, value in pairs(config) do
        if properties[prop] == "special" then
            if (prop == "ext_volume") then set_system_volume(value) end
        elseif properties[prop] == "number" then
            mp.set_property_number(prop, value)
        elseif properties[prop] == "native" then
            mp.set_property_native(prop, value)
        end
    end
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
function copyProfile()
    local filename = mp.get_property("filename/no-ext")
    profiles[filename] = {}
    for prop, propType in pairs(properties) do
        if propType == "number" then
            profiles[filename][prop] = mp.get_property_number(prop)
        elseif propType == "native" then
            profiles[filename][prop] = mp.get_property_native(prop)
        elseif propType == "special" then
            profiles[filename][prop] = mp.get_property_number(prop)
            if (prop == "ext_volume") then profiles[filename][prop] = get_system_volume() end
        end
    end
    saveProfiles()
end

function loadProfiles()
    local file = io.open(mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"}), "r")
    if file then
        local data = file:read("*all")
        profiles = utils.parse_json(data)
        file:close()

        mp.add_timeout(1, function()
            setProfile()
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

loadProfiles()

mp.register_event("shutdown", function()
    set_system_volume(original_volume)
    mp.set_property_native("ontop", original_top)
end)

mp.add_forced_key_binding("n", "saveProfile", copyProfile)
mp.add_forced_key_binding("h", "reloadProfiles", loadProfiles)
mp.add_forced_key_binding("c", "clearProfiles", clearProfiles)