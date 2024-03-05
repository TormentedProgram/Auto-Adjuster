local utils = require 'mp.utils'
local allAnimes
local selectedAnime

local internal_opts = {
    similarity = 25,
    showMessages = true,
}

local function osd_print(message, duration)
    if (not duration) then duration = 3 end 
    duration = duration * 1000
    if (internal_opts.showMessages) then 
        print(message)
        mp.command('show-text "' .. message .. '" ' .. duration)
    end
end

local function fetchDB()
    local url = "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json"
    local command = "curl -s " .. url
    local handle = io.popen(command)
    local output = handle:read("*a")
    handle:close()
    return output
end

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
    
    for i = 0, len1, 1 do
        matrix[i] = {}
        matrix[i][0] = i
    end
    for j = 0, len2, 1 do
        matrix[0][j] = j
    end
    
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

    local maxLen = math.max(len1, len2)
    local distance = matrix[len1][len2]
    local similarity = math.floor((1 - distance / maxLen) * 100)
    
    return similarity
end

local function openPage()
    local anilistSource
    for _, source in ipairs(selectedAnime.sources) do
        if string.find(source, "anilist.co") then
            anilistSource = source
            break
        end
    end
    if anilistSource then
        osd_print("Opening anilist page!")
        local command = 'start "" "' .. anilistSource .. '"'
        os.execute(command)
    else
        osd_print("No anilist page found..")
    end
end    

local function cleanupTitle(title)
    title = title:gsub("%d+", "")
    title = title:gsub("%b()", "")
    title = title:gsub("%b[]", "")
    title = title:gsub("%_", " ")
    title = title:gsub("^%s*(.-)%s*$", "%1")
    return title
end

local function findShowBySimilarity(title)
    title = cleanupTitle(title)

    local maxSimilarity = 0
    local bestShow = nil

    for _, show in ipairs(allAnimes.data) do
        local similarity = calculateSimilarity(title, show.title)
        if similarity >= internal_opts.similarity and similarity > maxSimilarity then
            maxSimilarity = similarity
            bestShow = show
        else
            for _, synonym in ipairs(show.synonyms or {}) do
                similarity = calculateSimilarity(title, synonym)
                if similarity >= internal_opts.similarity and similarity > maxSimilarity then
                    maxSimilarity = similarity
                    bestShow = show
                    break
                end
            end
        end
    end

    if bestShow then
        return bestShow
    else
        bestShow = {}
        bestShow.title = "Undefined"
        return bestShow
    end
end


local function setupAnime()
    local data = fetchDB()
    allAnimes = utils.parse_json(data)
    mp.add_timeout(0.1, function()
        local videotitle = mp.get_property("filename/no-ext")
        selectedAnime = findShowBySimilarity(videotitle)
        osd_print("Anime Title Found: "..selectedAnime.title, 5)
    end)
end

setupAnime()

mp.add_forced_key_binding("ctrl+shift+p", "openPage", function() openPage() end)