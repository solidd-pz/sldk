script_name("MapKlad 1.0")
script_author("sldk")
script_version("1.0")

local imgui, ffi, vkeys = require 'mimgui', require 'ffi', require 'vkeys'
local inicfg = require 'inicfg'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local faicons = require('fAwesome6')

-- Пути к файлам
local dbPath = getWorkingDirectory() .. "\\config\\sqlkd.txt"
local settingsIniPath = "MapKlad_settings.ini"

-- Конфигурация по умолчанию для сохранения настроек (showIDs теперь false по кастому)
local iniConfig = inicfg.load({
    settings = {
        scriptActive = true,
        enable3DMarkers = true,
        antiWH = false,
        markerRenderDist = 117,
        markerRadius = 2.2,
        radiusOutside = 117,
        radiusCheck = 27,
        mapIcon = 56,
        enableNotifications = true,
        showSuccessActions = true,
        showInfoMessages = true,
        showErrorsWarnings = true,
        showIDs = false, -- Выключено по умолчанию
        normR = 1.0, normG = 1.0, normB = 1.0, normA = 1.0,
        chkR = 1.0, chkG = 0.2, chkB = 0.2, chkA = 1.0
    }
}, settingsIniPath)

local json_url = "https://raw.githubusercontent.com/solidd-pz/sldk/main/update.json"
local json_path = getWorkingDirectory() .. "\\config\\mapklad_update.json"

local function saveSettings()
    if iniConfig then
        inicfg.save(iniConfig, settingsIniPath)
    end
end

-- Хранилище данных
local database = {}

-- Переменные окна UI
local windowState = imgui.new.bool(false)
local currentTab = 1

local scriptActive = imgui.new.bool(iniConfig.settings.scriptActive)
local showIDs = iniConfig.settings.showIDs -- Считываем из конфига

-- Переменные для 3D Маркеров
local enable3DMarkers = imgui.new.bool(iniConfig.settings.enable3DMarkers)
local antiWH = imgui.new.bool(iniConfig.settings.antiWH)
local markerRenderDist = imgui.new.int(iniConfig.settings.markerRenderDist)
local markerRadius = imgui.new.float(iniConfig.settings.markerRadius)

-- Цвета точек
local normalColor = imgui.new.float[4](
    iniConfig.settings.normR, 
    iniConfig.settings.normG, 
    iniConfig.settings.normB, 
    iniConfig.settings.normA
)
local checkedColor = imgui.new.float[4](
    iniConfig.settings.chkR, 
    iniConfig.settings.chkG, 
    iniConfig.settings.chkB, 
    iniConfig.settings.chkA
)

local radiusOutside = imgui.new.int(iniConfig.settings.radiusOutside)
local radiusCheck = imgui.new.int(iniConfig.settings.radiusCheck)
local mapIcon = imgui.new.int(iniConfig.settings.mapIcon)

local enableNotifications = imgui.new.bool(iniConfig.settings.enableNotifications)
local showSuccessActions = imgui.new.bool(iniConfig.settings.showSuccessActions)
local showInfoMessages = imgui.new.bool(iniConfig.settings.showInfoMessages)
local showErrorsWarnings = imgui.new.bool(iniConfig.settings.showErrorsWarnings)

local myFont = renderCreateFont("Arial", 10, 5)

local mymark = {}
local checkpoint, cx, cy, cz = nil, 0, 0, 0

local tabs = {
    { name = "Настройки", icon = faicons('GEAR') },
    { name = "3D Маркеры", icon = faicons('LOCATION_DOT') },
    { name = "Уведомления", icon = faicons('BELL') },
    { name = "Информация", icon = faicons('CIRCLE_INFO') }
}

local tabState = {}
for i = 1, #tabs do
    tabState[i] = { anim = (i == 1 and 1.0 or 0.0), hover = 0.0 }
end

local toggleAnim = {}

local function Lerp(from, to, weight)
    return from + (to - from) * weight
end

local function updateConfigValues()
    if not iniConfig then return end
    iniConfig.settings.scriptActive = scriptActive[0]
    iniConfig.settings.enable3DMarkers = enable3DMarkers[0]
    iniConfig.settings.antiWH = antiWH[0]
    iniConfig.settings.markerRenderDist = markerRenderDist[0]
    iniConfig.settings.markerRadius = markerRadius[0]
    iniConfig.settings.radiusOutside = radiusOutside[0]
    iniConfig.settings.radiusCheck = radiusCheck[0]
    iniConfig.settings.mapIcon = mapIcon[0]
    iniConfig.settings.enableNotifications = enableNotifications[0]
    iniConfig.settings.showSuccessActions = showSuccessActions[0]
    iniConfig.settings.showInfoMessages = showInfoMessages[0]
    iniConfig.settings.showErrorsWarnings = showErrorsWarnings[0]
    iniConfig.settings.showIDs = showIDs
    
    iniConfig.settings.normR = normalColor[0]
    iniConfig.settings.normG = normalColor[1]
    iniConfig.settings.normB = normalColor[2]
    iniConfig.settings.normA = normalColor[3]
    iniConfig.settings.chkR = checkedColor[0]
    iniConfig.settings.chkG = checkedColor[1]
    iniConfig.settings.chkB = checkedColor[2]
    iniConfig.settings.chkA = checkedColor[3]

    saveSettings()
end

local notifications = {}
local MAX_NOTIFICATIONS = 5

function addNotification(title, text, duration)
    if not enableNotifications[0] then return end
    if #notifications >= MAX_NOTIFICATIONS then
        table.remove(notifications, 1)
    end
    table.insert(notifications, {
        title = title or "Уведомление",
        text = text or "",
        duration = duration or 3.5,
        startTime = os.clock(),
        alpha = 0.0
    })
end

-- Команды
local function cmd_add_circle()
    local status, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if status and x and y and z then
        local kneeHeightZ = z - 0.45
        local newID = getNextFreeID()
        table.insert(database, {
            id = newID, x = x, y = y, z = kneeHeightZ, radius = markerRadius[0],
            name = "Точка #" .. newID, state = true, isRed = false, leftTime = 0
        })
        saveDatabase()
        addNotification("MapKlad", string.format("Точка добавлена! ID: %d", newID), 3.0)
    end
end

local function cmd_del_circle(arg)
    local targetID = tonumber(arg)
    if not targetID then
        sampAddChatMessage("[MapKlad] Укажите ID. Пример: /dlc 3", 0xFF8C00)
        return
    end

    local foundIndex = nil
    for i, item in ipairs(database) do
        if item.id == targetID then foundIndex = i break end
    end

    if foundIndex then
        if mymark[foundIndex] and doesBlipExist(mymark[foundIndex]) then removeBlip(mymark[foundIndex]) end
        table.remove(database, foundIndex)
        saveDatabase()
        ClearAllBlips()
        addNotification("MapKlad", string.format("Точка %d удалена!", targetID), 3.0)
    else
        sampAddChatMessage(string.format("[MapKlad] Точка с ID %d не найдена.", targetID), 0xFF8C00)
    end
end

local function cmd_toggle_id()
    showIDs = not showIDs
    updateConfigValues() -- Сохраняем состояние в конфиг при изменении через команду
    addNotification("MapKlad", "Отображение ID: " .. (showIDs and "ВКЛ" or "ВЫКЛ"), 2.0)
end

local function cleanLabel(str)
    local clean = str:gsub("##.*", "")
    return tostring(clean)
end

function ToggleSwitchLeft(label, bool_val, isDisabled)
    local draw_list = imgui.GetWindowDrawList()
    local clean_text = cleanLabel(label)
    
    local switch_w = 34.0
    local switch_h = 16.0
    local radius = switch_h * 0.5

    local p = imgui.GetCursorScreenPos()
    local id = label
    
    if toggleAnim[id] == nil then
        toggleAnim[id] = bool_val[0] and 1.0 or 0.0
    end

    imgui.InvisibleButton(id, imgui.ImVec2(switch_w, switch_h))
    local clicked = not isDisabled and imgui.IsItemClicked()
    if clicked then
        bool_val[0] = not bool_val[0]
        updateConfigValues()
    end

    local target = bool_val[0] and 1.0 or 0.0
    toggleAnim[id] = Lerp(toggleAnim[id], target, 0.25)
    local anim_t = toggleAnim[id]

    local alphaMultiplier = isDisabled and 0.4 or 1.0

    local col_bg = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
        (0.25 + (0.95 - 0.25) * anim_t) * alphaMultiplier,
        (0.12 + (0.55 - 0.12) * anim_t) * alphaMultiplier,
        (0.05 + (0.05 - 0.05) * anim_t) * alphaMultiplier,
        1.0 * alphaMultiplier
    ))
    local col_circle = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.9, 0.9, 0.92, alphaMultiplier))

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + switch_w, p.y + switch_h), col_bg, radius)
    local circle_x = p.x + radius + anim_t * (switch_w - radius * 2.0)
    draw_list:AddCircleFilled(imgui.ImVec2(circle_x, p.y + radius), radius - 2.0, col_circle)

    imgui.SameLine()
    imgui.SetCursorPosY(imgui.GetCursorPosY() - 1)
    
    if isDisabled then
        imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 0.6), clean_text)
    else
        imgui.Text(clean_text)
    end

    return clicked
end

function initDatabaseFile()
    if not doesDirectoryExist(getWorkingDirectory() .. "\\config") then
        createDirectory(getWorkingDirectory() .. "\\config")
    end
    if not doesFileExist(dbPath) then
        local file = io.open(dbPath, "w")
        if file then file:close() end
    end
end

function saveDatabase()
    local file = io.open(dbPath, "w")
    if file then
        for _, item in ipairs(database) do
            file:write(string.format("ID: %d | X: %.3f | Y: %.3f | Z: %.3f | Радиус: %.1f\n", 
                item.id, item.x, item.y, item.z, item.radius or 2.2))
        end
        file:close()
    end
end

function loadDatabase()
    initDatabaseFile()
    local file = io.open(dbPath, "r")
    if file then
        database = {}
        for line in file:lines() do
            if not line:find("^//") and line:match("%S") then
                local x, y, z = line:match("X:%s*([%d%.%-]+).*Y:%s*([%d%.%-]+).*Z:%s*([%d%.%-]+)")
                if x and y and z then
                    local id = line:match("ID:%s*(%d+)")
                    local radius = line:match("Радиус:%s*([%d%.%-]+)") or line:match("Radius:%s*([%d%.%-]+)") or 2.2
                    local finalID = id and tonumber(id) or (#database + 1)

                    table.insert(database, {
                        id = finalID,
                        x = tonumber(x),
                        y = tonumber(y),
                        z = tonumber(z),
                        radius = tonumber(radius),
                        name = "Точка #" .. finalID,
                        state = true,
                        isRed = false,
                        leftTime = 0
                    })
                end
            end
        end
        file:close()
        table.sort(database, function(a, b) return a.id < b.id end)
    end
end

function getNextFreeID()
    if #database == 0 then return 1 end
    local maxID = 0
    for _, item in ipairs(database) do
        if item.id > maxID then maxID = item.id end
    end
    return maxID + 1
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    -- ВОТ ЭТУ СТРОЧКУ ДОБАВИТЬ:
    lua_thread.create(checkUpdate)

    loadDatabase()
	
    sampRegisterChatCommand("sldk", function() windowState[0] = not windowState[0] end)
    sampRegisterChatCommand("adc", cmd_add_circle)
    sampRegisterChatCommand("dlc", cmd_del_circle)
    sampRegisterChatCommand("cid", cmd_toggle_id)

    addNotification("MapKlad", "Скрипт загружен", 3.0)

    while true do
        wait(0)

        if wasKeyPressed(vkeys.VK_F2) and not sampIsChatInputActive() and not sampIsDialogActive() then
            windowState[0] = not windowState[0]
        end

        local px, py, pz = getCharCoordinates(PLAYER_PED)

        if checkpoint ~= nil and math.floor(getDistanceBetweenCoords3d(cx, cy, cz, px, py, pz)) <= 7 then 
            deleteCheckpoint(checkpoint) 
            addOneOffSound(0, 0, 0, 1057) 
            checkpoint = nil 
            addNotification("MapKlad", "Вы прибыли на место!", 3.0)
        end

        if scriptActive[0] and #database > 0 then
            local currentTime = os.clock()

            for i, item in ipairs(database) do
                local dist = getDistanceBetweenCoords3d(px, py, pz, item.x, item.y, item.z)

                if dist <= radiusOutside[0] and item.state then
                    if not mymark[i] then 
                        mymark[i] = addSpriteBlipForCoord(item.x, item.y, item.z, mapIcon[0]) 
                    end
                else
                    if mymark[i] and doesBlipExist(mymark[i]) then 
                        removeBlip(mymark[i]) 
                        mymark[i] = nil 
                    end
                end

                if enable3DMarkers[0] and dist <= markerRenderDist[0] then
                    if antiWH[0] then
                        local cx, cy, cz = getCharCoordinates(PLAYER_PED)
                        local hit, _, _, _, _ = processLineOfSight(cx, cy, cz + 0.5, item.x, item.y, item.z, true, true, false, true, false, false, false)
                        if hit then
                            goto continue_marker
                        end
                    end

                    if dist <= radiusCheck[0] then
                        if dist <= 2.5 then
                            item.isRed = true
                            item.leftTime = 0 
                        else
                            if item.isRed then
                                if item.leftTime == 0 then
                                    item.leftTime = currentTime
                                elseif currentTime - item.leftTime >= 3.0 then
                                    item.isRed = false
                                    item.leftTime = 0
                                end
                            end
                        end
                    end
                    
                    local r = math.floor(normalColor[0] * 255)
                    local g = math.floor(normalColor[1] * 255)
                    local b = math.floor(normalColor[2] * 255)
                    local a = math.floor(normalColor[3] * 255)
                    
                    if item.isRed then
                        r = math.floor(checkedColor[0] * 255)
                        g = math.floor(checkedColor[1] * 255)
                        b = math.floor(checkedColor[2] * 255)
                        a = math.floor(checkedColor[3] * 255)
                    end

                    local drawColor = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)

                    drawPerfectCircle(item.x, item.y, item.z, markerRadius[0], drawColor)
                    
                    if showIDs then
                        local tx, ty, tz = convert3DCoordsToScreen(item.x, item.y, item.z + 0.35)
                        if tx and ty and isPointOnScreen(item.x, item.y, item.z + 0.35, 0.0) then
                            renderFontDrawText(myFont, string.format("ID: %d", item.id), tx - 15, ty, drawColor)
                        end
                    end
                    ::continue_marker::
                end
            end
        else
            if next(mymark) ~= nil then
                ClearAllBlips()
            end
        end
    end
end

local function checkUpdate()
    downloadUrlToFile(json_url, json_path, function(id, status)
        if status == 6 then
            local file = io.open(json_path, "r")
            if file then
                local content = file:read("*a")
                file:close()
                os.remove(json_path)

                local latest_version = content:match('"latest"%s*:%s*"(.-)"')
                local download_url = content:match('"url"%s*:%s*"(.-)"')

                if latest_version and latest_version ~= thisScript().version then
                    sampAddChatMessage("[MapKlad] Найдено обновление, качаю...", 0xFF8C00)
                    downloadUrlToFile(download_url, thisScript().path, function(id3, status3)
                        if status3 == 6 then
                            sampAddChatMessage("[MapKlad] Обновлено! Перезапуск...", 0x00FF00)
                            thisScript():reload()
                        end
                    end)
                end
            end
        end
    end)
end

function drawPerfectCircle(x, y, z, radius, color)
    local points = 50
    local step = (2 * math.pi) / points
    for i = 0, points - 1 do
        local angle1 = i * step
        local angle2 = (i + 1) * step
        local x1 = x + (math.cos(angle1) * radius)
        local y1 = y + (math.sin(angle1) * radius)
        local x2 = x + (math.cos(angle2) * radius)
        local y2 = y + (math.sin(angle2) * radius)
        
        if isPointOnScreen(x1, y1, z, 0.0) and isPointOnScreen(x2, y2, z, 0.0) then
            local w1, h1 = convert3DCoordsToScreen(x1, y1, z)
            local w2, h2 = convert3DCoordsToScreen(x2, y2, z)
            if w1 and h1 and w2 and h2 and w1 > 0 and h1 > 0 and w2 > 0 and h2 > 0 then
                renderDrawLine(w1, h1, w2, h2, 3, color)
            end
        end
    end
end

function ClearAllBlips()
    for i, blip in pairs(mymark) do 
        if blip and doesBlipExist(blip) then 
            removeBlip(blip) 
        end 
    end
    mymark = {}
end

function onScriptTerminate(script, quitGame)
    if script == thisScript() then 
        ClearAllBlips() 
        if checkpoint ~= nil then deleteCheckpoint(checkpoint) end 
    end
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    local iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges)

    local style = imgui.GetStyle()
    style.WindowRounding = 8.0
    style.FrameRounding = 6.0
    style.ChildRounding = 6.0
    style.PopupRounding = 8.0
    style.GrabRounding = 6.0
    style.WindowBorderSize = 1.0
    style.FrameBorderSize = 0.0
    style.PopupBorderSize = 1.0
    style.ScrollbarSize = 5.0
    style.ItemSpacing = imgui.ImVec2(8, 6)
    style.WindowPadding = imgui.ImVec2(10, 10)

    local colors = style.Colors
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.09, 0.08, 0.07, 0.92) 
    colors[imgui.Col.PopupBg] = imgui.ImVec4(0.09, 0.08, 0.07, 0.95)
    colors[imgui.Col.Border] = imgui.ImVec4(0.95, 0.55, 0.15, 0.35) 
    colors[imgui.Col.ChildBg] = imgui.ImVec4(0.0, 0.0, 0.0, 0.0) 
    
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.16, 0.13, 0.11, 0.80)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.22, 0.18, 0.14, 0.90)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.28, 0.23, 0.18, 1.00)

    colors[imgui.Col.ScrollbarBg] = imgui.ImVec4(0.0, 0.0, 0.0, 0.0)
    colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(0.0, 0.0, 0.0, 0.0)
    colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.95, 0.55, 0.15, 0.20)
    colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(0.95, 0.55, 0.15, 0.40)

    colors[imgui.Col.SliderGrab] = imgui.ImVec4(0.95, 0.55, 0.15, 1.00)
    colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(1.00, 0.65, 0.25, 1.00)

    colors[imgui.Col.NavHighlight] = imgui.ImVec4(0.0, 0.0, 0.0, 0.0)
    colors[imgui.Col.Header] = imgui.ImVec4(0.0, 0.0, 0.0, 0.0)
    colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.95, 0.55, 0.15, 0.15)
    colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.95, 0.55, 0.15, 0.30)

    colors[imgui.Col.Button] = imgui.ImVec4(0.16, 0.13, 0.11, 0.80)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.95, 0.55, 0.15, 0.30)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.95, 0.55, 0.15, 0.60)
    colors[imgui.Col.Separator] = imgui.ImVec4(0.95, 0.55, 0.15, 0.20)
end)

imgui.OnFrame(function() return #notifications > 0 end, function(playerEnv)
    playerEnv.HideCursor = true

    local displaySize = imgui.GetIO().DisplaySize
    local now = os.clock()
    local offsetY = 15.0

    for i = #notifications, 1, -1 do
        local toast = notifications[i]
        local elapsed = now - toast.startTime
        local remaining = toast.duration - elapsed

        if elapsed < 0.20 then toast.alpha = Lerp(toast.alpha, 1.0, 0.35)
        elseif remaining < 0.3 then toast.alpha = Lerp(toast.alpha, 0.0, 0.30)
        else toast.alpha = 1.0 end

        if remaining <= 0 and toast.alpha < 0.05 then
            table.remove(notifications, i)
        else
            local notifWidth = 250.0
            local titleSize = imgui.CalcTextSize(tostring(toast.title))
            local textSize = imgui.CalcTextSize(tostring(toast.text), nil, false, notifWidth - 30.0)
            
            local notifHeight = titleSize.y + textSize.y + 20.0
            local posX = displaySize.x - notifWidth - 15.0
            local posY = displaySize.y - notifHeight - offsetY

            imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(notifWidth, notifHeight), imgui.Cond.Always)
            
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, toast.alpha)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 6.0)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.0)

            local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + 
                         imgui.WindowFlags.NoMove + imgui.WindowFlags.NoInputs + 
                         imgui.WindowFlags.NoFocusOnAppearing

            if imgui.Begin("##ToastNotif_" .. tostring(i), nil, flags) then
                local dl = imgui.GetWindowDrawList()
                local p = imgui.GetWindowPos()
                local sz = imgui.GetWindowSize()

                dl:AddRectFilled(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x + 4, p.y + sz.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.95, 0.55, 0.15, toast.alpha)), 6.0)
                
                imgui.SetCursorPos(imgui.ImVec2(12, 6))
                imgui.TextColored(imgui.ImVec4(1.0, 0.65, 0.25, 1.0), faicons('BELL') .. " " .. tostring(toast.title))
                
                imgui.SetCursorPos(imgui.ImVec2(12, 8 + titleSize.y))
                imgui.PushTextWrapPos(notifWidth - 10.0)
                imgui.TextUnformatted(tostring(toast.text))
                imgui.PopTextWrapPos()

                imgui.End()
            end
            
            imgui.PopStyleVar(3)
            offsetY = offsetY + notifHeight + 8.0
        end
    end
end)

imgui.OnFrame(function() return windowState[0] end, function(playerEnv)
    playerEnv.HideCursor = false
    imgui.GetIO().MouseDrawCursor = false

    local displaySize = imgui.GetIO().DisplaySize
    local winSize = imgui.ImVec2(600, 380)
    imgui.SetNextWindowPos(imgui.ImVec2((displaySize.x - winSize.x) / 2, (displaySize.y - winSize.y) / 2), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(winSize, imgui.Cond.Always)
    
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse
    if imgui.Begin("##MapKladWindow", nil, flags) then
        imgui.TextColored(imgui.ImVec4(0.95, 0.55, 0.15, 1.00), faicons('MAP_LOCATION_DOT') .. " MapKlad 1.0")
        imgui.SameLine()
        imgui.TextDisabled("by sldk")

        imgui.SameLine(imgui.GetWindowWidth() - 30)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.55, 0.15, 0.20))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.95, 0.55, 0.15, 0.40))
        if imgui.Button(faicons('XMARK'), imgui.ImVec2(20, 20)) then windowState[0] = false end
        imgui.PopStyleColor(3)
        imgui.Spacing()

        imgui.BeginChild("LeftTabs", imgui.ImVec2(155, 0), false)
            local dl = imgui.GetWindowDrawList()
            for i, tabObj in ipairs(tabs) do
                local isActive = (currentTab == i)
                local st = tabState[i]

                local btnPos = imgui.GetCursorScreenPos()
                local btnWidth = imgui.GetContentRegionAvail().x
                local btnHeight = 28.0

                imgui.SetCursorScreenPos(btnPos)
                if imgui.InvisibleButton("##tab_btn_" .. i, imgui.ImVec2(btnWidth, btnHeight)) then
                    currentTab = i
                end

                local isHovered = imgui.IsItemHovered()
                st.hover = Lerp(st.hover, isHovered and 1.0 or 0.0, 0.25)
                st.anim = Lerp(st.anim, isActive and 1.0 or 0.0, 0.25)

                local bgAlpha = math.max(st.anim * 0.85, st.hover * 0.25)
                if bgAlpha > 0.01 then
                    local col_bg = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.95, 0.55, 0.15, bgAlpha))
                    dl:AddRectFilled(btnPos, imgui.ImVec2(btnPos.x + btnWidth, btnPos.y + btnHeight), col_bg, 6.0)
                end

                local col_text = imgui.ImVec4(
                    0.6 + (1.0 - 0.6) * math.max(st.anim, st.hover),
                    0.6 + (1.0 - 0.6) * math.max(st.anim, st.hover),
                    0.65 + (1.0 - 0.65) * math.max(st.anim, st.hover),
                    1.0
                )
                
                local labelFormatted = tabObj.icon .. "  " .. tabObj.name
                dl:AddText(imgui.ImVec2(btnPos.x + 10, btnPos.y + 6), imgui.ColorConvertFloat4ToU32(col_text), labelFormatted)

                imgui.SetCursorScreenPos(imgui.ImVec2(btnPos.x, btnPos.y + btnHeight + 3))
            end
        imgui.EndChild() 
        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.ScrollbarBg, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarGrab, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarGrabHovered, imgui.ImVec4(0.95, 0.55, 0.15, 0.20))
        imgui.PushStyleColor(imgui.Col.ScrollbarGrabActive, imgui.ImVec4(0.95, 0.55, 0.15, 0.40))

        imgui.BeginChild("ContentArea", imgui.ImVec2(0, 0), false, imgui.WindowFlags.AlwaysVerticalScrollbar)
            if currentTab == 1 then
                imgui.Text(faicons('GEAR') .. " Основные настройки") 
                imgui.Separator() 
                imgui.Spacing()
                
                if ToggleSwitchLeft("Включить скрипт##main", scriptActive, false) then
                    if not scriptActive[0] then ClearAllBlips() end
                end

                imgui.Spacing() 
                imgui.Text(faicons('MAP') .. " Карта и радиусы") 
                imgui.Separator() 
                imgui.Spacing()

                imgui.PushItemWidth(180) 
                if imgui.SliderInt("Радиус точек вне зоны", radiusOutside, 0, 500) then updateConfigValues() end
                if imgui.SliderInt("Радиус проверки точек", radiusCheck, 0, 100) then updateConfigValues() end
                if imgui.SliderInt("Иконка на карте (1-63)", mapIcon, 1, 63) then 
                    ClearAllBlips() 
                    updateConfigValues()
                end
                imgui.PopItemWidth()

            elseif currentTab == 2 then
                imgui.Text(faicons('LOCATION_DOT') .. " 3D Маркеры") 
                imgui.Separator() 
                imgui.Spacing()
                
                imgui.Text("Отображение и дистанция")
                imgui.Separator()
                ToggleSwitchLeft("Включить 3D маркеры##markers", enable3DMarkers, false)

                if enable3DMarkers[0] then
                    imgui.Spacing()
                    ToggleSwitchLeft("Проверка препятствий (Anti-WH)##antiwh", antiWH, false)

                    imgui.Spacing()
                    imgui.Text("Тип маркеров:")
                    imgui.TextColored(imgui.ImVec4(0.95, 0.55, 0.15, 1.00), "3D circles")

                    imgui.Spacing()
                    imgui.Text("Общие настройки маркеров:")
                    imgui.PushItemWidth(imgui.GetContentRegionAvail().x)
                    if imgui.SliderInt("##renderdist", markerRenderDist, 10, 300) then updateConfigValues() end
                    imgui.PopItemWidth()

                    imgui.Spacing()
                    imgui.Text("Настройки кастомных кругов:")
                    imgui.PushItemWidth(imgui.GetContentRegionAvail().x)
                    if imgui.SliderFloat("##markerradius", markerRadius, 0.5, 10.0, "%.1f") then updateConfigValues() end
                    imgui.PopItemWidth()

                    imgui.Spacing()
                    imgui.Text("Цвет обычной точки:")
                    if imgui.ColorEdit4("##normColor", normalColor, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.AlphaBar) then
                        updateConfigValues()
                    end

                    imgui.Spacing()
                    imgui.Text("Цвет проверенной точки:")
                    if imgui.ColorEdit4("##chkColor", checkedColor, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.AlphaBar) then
                        updateConfigValues()
                    end
                end

            elseif currentTab == 3 then
                imgui.Text(faicons('BELL') .. " Уведомления") 
                imgui.Separator() 
                imgui.Spacing()
                
                ToggleSwitchLeft("Включить уведомления##notif1", enableNotifications, false)
                imgui.Spacing()

                ToggleSwitchLeft("Успешные действия##notif2", showSuccessActions, true)
                ToggleSwitchLeft("Информационные сообщения##notif3", showInfoMessages, true)
                ToggleSwitchLeft("Ошибки и предупреждения##notif4", showErrorsWarnings, true)

                imgui.Spacing()
                if imgui.Button("Проверить длинный текст", imgui.ImVec2(180, 26)) then
                    addNotification("Тест", "Уведомление отрисовано ровно и компактно!", 4.0)
                end
            elseif currentTab == 4 then
                imgui.Text(faicons('CIRCLE_INFO') .. " Информация о скрипте")
                imgui.Separator()
                imgui.Spacing()
                imgui.Text("Название: MapKlad")
                imgui.Text("Версия: 1.0")
                imgui.Text("Автор: sldk")
                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(0.95, 0.55, 0.15, 1.00), "Управление скриптом:")
                imgui.Spacing()
                imgui.BulletText("Открыть/Закрыть меню: клавиша [F2] или команда /sldk")
                imgui.BulletText("Добавить точку: /adc")
                imgui.BulletText("Удалить точку: /dlc [ID]")
                imgui.BulletText("Включить/Выключить ID: /cid")
            end
        imgui.EndChild()
        imgui.PopStyleColor(4)

        imgui.End()
    end
end)