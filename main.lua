local utils = require 'mp.utils'
local profiles = {}

local selected = {
    name = "undefined",
    profile,
}

local internal_opts = {
    savedata = "~~/script-opts/auto-adjuster",
    similarity = 60,
    showMessages = true,
}

local default_properties = {
    saturation = 0,
    folder = false,
    volume = 100,
    brightness = 0,
    gamma = 0,
    contrast = 0,
}

untoggledProperties = nil

local properties = {
    ["saturation"] = "number",
    ["folder"] = "special",
    ["ext_volume"] = "special",
    ["volume"] = "native",
    ["brightness"] = "number",
    ["gamma"] = "number",
    ["sub-scale"] = "number",
    ["sid"] = "number",
    ["contrast"] = "number",
    ["vf"] = "native",
    ["af"] = "native",
    ["glsl-shaders"] = "native",
    ["canSkip"] = "custom"
}

local keymap = {
    ["toggleProfile()"] = "ctrl+shift+t",
    ["copyProfile()"] = "ctrl+shift+c",
    ["loadProfiles('reload')"] = "ctrl+shift+r",
    ["clearProfiles()"] = "ctrl+shift+l",
    ["undoProfile()"] = "ctrl+shift+z",
    ["redoProfile()"] = "ctrl+shift+y"
}

local triggeredDeletionWarning = false
local triggeredUndoWarning = false

local removedProfile = {}
local hasProfile = false
local usingFolder = false

local original_top

function printTable(t, indent)
    indent = indent or 0
    local indentString = string.rep(" ", indent)
    
    if type(t) ~= "table" then
        print(indentString .. tostring(t))
        return
    end

    for key, value in pairs(t) do
        if type(value) == "table" then
            print(indentString .. tostring(key) .. ":")
            printTable(value, indent + 4)
        else
            print(indentString .. tostring(key) .. ": " .. tostring(value))
        end
    end
end

function osd_print(message, duration, indent, doPrint)
    if (not indent) then indent = 0 end 
    if (not doPrint) then doPrint = true end 
    if (not duration) then duration = 3 end 
    if type(message) == "table" then
        local indentString = string.rep(" ", indent)
        local tableString = ""

        for key, value in pairs(message) do
            if type(value) == "table" then
                tableString = tableString .. indentString .. tostring(key) .. ":\n" .. osd_print(value, duration, indent + 4, false)
            else
                tableString = tableString .. indentString .. tostring(key) .. ": " .. tostring(value) .. "\n"
            end
        end
        message = tableString
    end
    if doPrint then
        duration = duration * 1000
        if (internal_opts.showMessages) then 
            print(message)
            mp.command('show-text "' .. message .. '" ' .. duration)
        end
    else
        return message
    end
end

function runPythonAsync(callback, arg1, arg2)
    local script_dir = debug.getinfo(1).source:match("@?(.*/)")
    local script_name = debug.getinfo(1, "S").source:match(".*/([^/\\]+)%.lua$")
    local args = {"python", script_dir.."python/"..script_name..".py"}

    if arg1 then table.insert(args, tostring(arg1)) end
    if arg2 then table.insert(args, tostring(arg2)) end

    osd_print(args, 10)

    local table = {
        name = "subprocess",
        args = args,
        capture_stdout = true
    }
    mp.command_native_async(table, function(success, result, error)
        osd_print("Python script failed: " .. (result.stderr or "unknown error"), 10)
        if success and result.stdout then
            local python_vars = utils.parse_json(result.stdout)
            osd_print("GRAH "..result.stdout)
            if not python_vars or python_vars["nil"] then
                callback(nil)
            else
                callback(python_vars)
            end
        else
            osd_print("Python script failed: " .. (result.stderr or "unknown error"), 10)
            callback(nil)
        end
    end)
end

function runPythonSync(arg1,arg2)
    local script_dir = debug.getinfo(1).source:match("@?(.*/)")
    local script_name = debug.getinfo(1, "S").source:match(".*/([^/\\]+)%.lua$")
    local command = "python " .. script_dir.."python/"..script_name .. ".py"

    if arg1 then command = command .. " " .. tostring(arg1) end
    if arg2 then command = command .. " " .. tostring(arg2) end

    os.execute(command)
end


function cleanupTitle(title)
    title = title:gsub("%d+", "")
    title = title:gsub("%b()", "")
    title = title:gsub("%b[]", "")
    title = title:gsub("%_", " ")
    title = title:gsub("^%s*(.-)%s*$", "%1")
    return title
end

function validatePath(path)
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

function json_format(tbl)
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
--[[https://gist.github.com/Badgerati/3261142]]
function calculateSimilarity(str1, str2)
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

function setProperties(config)
    if not config then
        config = {}
        
        for prop, propType in pairs(properties) do
            if propType == "number" then
                config[prop] = 0
            elseif propType == "native" then
                config[prop] = ""
            elseif propType == "" then
                config[prop] = ""
            elseif propType == "special" then
                config[prop] = nil
                if (prop == "ext_volume") then config[prop] = original_volume end
                if (prop == "folder") then config[prop] = false end
            elseif propType == "custom" then
                config[prop] = nil
            end
        end
    end
    for prop, value in pairs(config) do
        if properties[prop] == "special" then
            if (prop == "ext_volume") then 
                if (value ~= original_volume) then 
                    runPythonAsync(function(python) 
                        --no
                    end, "setvolume", value)
                end 
            end
            if (prop == "folder") then usingFolder = value end
        elseif properties[prop] == "number" then
            mp.set_property_number(prop, value)
        elseif properties[prop] == "custom" then
            mp.set_property("user-data/Auto-Adjuster/" .. prop, value)
        elseif properties[prop] == "native" then
            mp.set_property_native(prop, value)
        elseif properties[prop] == "" then
            mp.set_property(prop, value)
        end
    end
end

function setProfile(searchType, context)
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
        setProperties(selected.profile)
        if (context == "reload") then
            osd_print("Profile reloaded successfully..")
            return;
        end
        osd_print("(Likeness: " .. maxSimilarity .. "%) Profile set to " .. selected.name, 2)
        profileActive = true
    else
        if (searchType == "file") then
            setProfile("folder")
            return;
        end
        hasProfile = false
        osd_print("(Likeness: " .. maxSimilarity .. "%) No profile found")
    end
end

function setupBinds()
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/keybinds.json"})
    local file = io.open(validatePath(filePath), "r")

    if file then
        local jsonData = file:read("*all")
        keymap = utils.parse_json(jsonData)
        file:close()
    else
        file = io.open(validatePath(filePath), "w")
        if file then
            local saveData = json_format(keymap)
            file:write(saveData)
            file:close()

            file = io.open(validatePath(filePath), "r")
            if file then
                local jsonData = file:read("*all")
                keymap = utils.parse_json(jsonData)
                file:close()
            end
        end
    end

    for func, keybind in pairs(keymap) do
        mp.add_forced_key_binding(keybind, func, function() load(func)() end)
    end

    local keys = {'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'}
    for idx, key in ipairs(keys) do
        local key_combination = "ctrl+shift+"..key
        local function_name = "toggleSpecialSettings("..key..")"
        mp.add_forced_key_binding(key_combination, function_name, function() 
            load("toggleSpecialSettings("..idx..")")() 
        end)
    end
end

function saveProfiles(context)
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

function copyProfile(context)
    if (not context) then context = "undefined" end
    local filename = getSearchMethod()
    profiles[filename] = {}
    for prop, propType in pairs(properties) do
        if propType == "number" then
            local value = mp.get_property_number(prop)
            if value ~= nil then
                local rounded_value = tonumber(string.format("%.2f", value))
                if rounded_value == math.floor(rounded_value * 10) / 10 then
                    rounded_value = tonumber(string.format("%.1f", rounded_value))
                end
                profiles[filename][prop] = rounded_value
            end
        elseif propType == "" then
            local value = mp.get_property(prop)
            if value ~= nil then
              profiles[filename][prop] = value
            end
        elseif propType == "native" then
            local value = mp.get_property_native(prop)
            if value ~= nil then
                if type(value) == "table" then
                    if #value > 0 then
                        profiles[filename][prop] = value
                    end
                else
                    profiles[filename][prop] = value
                end
            end
        elseif propType == "custom" then
            local value = mp.get_property("user-data/Auto-Adjuster/" .. prop)
            if value ~= nil then
                value = utils.parse_json(value)
            end
            if value ~= nil then
                profiles[filename][prop] = value
            end
        elseif propType == "special" then
            local value = mp.get_property_number(prop)
            if value ~= nil then
              profiles[filename][prop] = value
              if (prop == "ext_volume") then
                runPythonAsync(function(python)
                  if (python) then
                    profiles[filename][prop] = tonumber(python["Volume"])
                  end
                end, "getvolume")
              end
            end
            if (prop == "folder") then profiles[filename][prop] = usingFolder end
          end
        end
        
    if context == "undefined" then
        selected.profile = profiles[filename]
        selected.name = filename
        saveProfiles()
    elseif context == "return" then
        return profiles[filename]
    end
end

function loadProfiles(context)
    if (not context) then context = "undefined" end
    setupBinds()
    local file = io.open(validatePath(mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})), "r")
    if file then
        local data = file:read("*all")
        profiles = utils.parse_json(data)
        file:close()

        setProfile("file", context)
    end
end

function clearProfiles()
    if not triggeredDeletionWarning then
        triggeredDeletionWarning = true
        osd_print("This will erase all profiles!, repeat keybind to proceed...", 3)
        return
    end

    osd_print("Cleared + backed up all profiles")
    local filePath = mp.command_native({"expand-path", internal_opts.savedata .. "/profiles.json"})
    local backupFilePath = filePath .. "_backup"
    os.rename(filePath, backupFilePath)
    profiles = {}
    triggeredDeletionWarning = false
    setProperties()
end

function undoProfile()
    if not triggeredUndoWarning then
        triggeredUndoWarning = true
        osd_print("This will undo the current profile!, repeat keybind to proceed...", 3)
        return
    end

    triggeredUndoWarning = false

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

function redoProfile()
    local filename = selected.name
    profiles[filename] = removedProfile
    saveProfiles("redo")
end

runPythonAsync(function(python)
    if (python) then
        original_volume = tonumber(python["Volume"])
    end
end, "getvolume")
original_top = mp.get_property_native("ontop")

mp.register_event("file-loaded", function() loadProfiles() end)

mp.register_event("shutdown", function() --not
    if (hasProfile) then 
        runPythonSync("setvolume", original_volume) 
    end
end)

profileActive = false
function toggleProfile()
    if hasProfile then
        if profileActive then
            osd_print("[VFX OFF]",1)
            untoggledProperties = copyProfile("return")
            setProperties()
            setProperties(default_properties)
            profileActive = false
        else
            osd_print("[VFX ON]",1)
            showMsgOriginal = internal_opts.showMessages
            internal_opts.showMessages = false
            if untoggledProperties ~= nil then
                setProperties(untoggledProperties)
            else
                loadProfiles("reload")
            end
            internal_opts.showMessages = showMsgOriginal
            profileActive = true
        end
    else
        osd_print("[NO VFX PROFILE FOUND]",3)
    end
end

function tobool(value)
    if value == nil then
        return false
    end
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "string" then
        return value == "true"
    end
    return false
end

function toggleSpecialSettings(num)
    if num == 1 then
        usingFolder = not usingFolder
        osd_print("[FOLDER-MODE: " .. tostring(usingFolder).. "]")
    elseif num == 2 then
        local current_value = mp.get_property("user-data/Auto-Adjuster/canSkip")

        real_value = false
        if current_value ~= nil then
            real_value = utils.parse_json(current_value)
        end

        local new_value = not tobool(real_value)
        mp.set_property("user-data/Auto-Adjuster/canSkip", tostring(new_value))

        osd_print("[SKIP-CHAPTERS: " .. tostring(new_value).. "]")
    end
end