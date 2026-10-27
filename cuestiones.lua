-- ==============================================================================
-- PREDICTOR DINÁMICO DE EVENTOS POR MULTIPLICADOR (ROUNDS & BANNER WATCHER)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

-- Eliminar cualquier filtro de desenfoque de la pantalla
pcall(function()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") then obj:Destroy() end
    end
end)

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local Config = {
    AutoDetectMultiplier = true,
    ManualMultiplier = 9,       -- Multiplicador por defecto si no lo lee
    StuckAlertTime = 30
}

local EventTracker = {
    CurrentDay = 0,
    ActiveMultiplier = 9,
    TodayEvent = "Normal",
    TomorrowPrediction = "Calculando...",
    MorningBannerDetected = nil,
    MorningBannerTime = 0,
    RoundsSinceBloodMoon = 0,
    RoundsUntilNextBloodMoon = 0,
    IsNight = false,
    Countdown = 0,
    LastDayRecorded = -1,
    LastAlertTime = 0
}

-- ==============================================================================
-- 1. DETECCIÓN AUTOMÁTICA DEL MULTIPLICADOR EN PANTALLA (x1, x9, x11)
-- ==============================================================================

local function detectGameMultiplier()
    if not Config.AutoDetectMultiplier then
        return Config.ManualMultiplier
    end

    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        for _, desc in ipairs(pg:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.TextTransparency < 0.5 then
                local txt = desc.Text
                -- Busca patrones como "x9", "x11", "x1"
                local multStr = txt:match("x(%d+)")
                if multStr then
                    local num = tonumber(multStr)
                    if num and num >= 1 and num <= 20 then
                        return num
                    end
                end
            end
        end
    end

    -- Respaldo: Atributo de dificultad del servidor
    local wsDiff = workspace:GetAttribute("PlayerDifficulty")
    if wsDiff and type(wsDiff) == "number" and wsDiff > 1 then
        return wsDiff
    end

    return Config.ManualMultiplier
end

-- ==============================================================================
-- 2. CENTINELA CONTINUO DE BANNERS MATUTINOS EN PLAYERGUI
-- ==============================================================================

local function checkMorningBanners()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return end

    for _, desc in ipairs(pg:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.TextTransparency < 0.5 then
            local rawText = desc.Text
            local lowerText = rawText:lower()

            if lowerText:find("luna de sangre") or lowerText:find("blood moon") or lowerText:find("saldrá esta noche") then
                EventTracker.MorningBannerDetected = "🔴 LUNA DE SANGRE ESTA NOCHE"
                EventTracker.MorningBannerTime = tick()
                break
            elseif lowerText:find("bandid") or lowerText:find("incursión") or lowerText:find("raid") then
                EventTracker.MorningBannerDetected = "🤠 INCURSIÓN DE BANDIDOS ESTA NOCHE"
                EventTracker.MorningBannerTime = tick()
                break
            elseif lowerText:find("ventisca") or lowerText:find("blizzard") or lowerText:find("tormenta") then
                EventTracker.MorningBannerDetected = "❄️ VENTISCA ESTA NOCHE"
                EventTracker.MorningBannerTime = tick()
                break
            end
        end
    end
end

-- Escuchar eventos instantáneos en la interfaz
task.spawn(function()
    local pg = lp:WaitForChild("PlayerGui", 10)
    if pg then
        pg.DescendantAdded:Connect(function(desc)
            if desc:IsA("TextLabel") then
                task.wait(0.05)
                local lowerText = desc.Text:lower()
                if lowerText:find("luna de sangre") or lowerText:find("blood moon") or lowerText:find("saldrá esta noche") then
                    EventTracker.MorningBannerDetected = "🔴 LUNA DE SANGRE ESTA NOCHE"
                    EventTracker.MorningBannerTime = tick()
                elseif lowerText:find("bandid") or lowerText:find("raid") then
                    EventTracker.MorningBannerDetected = "🤠 INCURSIÓN DE BANDIDOS ESTA NOCHE"
                    EventTracker.MorningBannerTime = tick()
                end
            end
        end)
    end
end)

-- ==============================================================================
-- 3. MOTOR DE PREDICCIÓN BASADO EN RONDAS REALES Y MULTIPLICADOR
-- ==============================================================================

local function updateEventPredictions()
    local ws = workspace
    local currentDay = ws:GetAttribute("CurrentDay") or 0
    local lastBMDay = ws:GetAttribute("LastBloodMoonDay") or currentDay
    local isNight = ws:GetAttribute("Night")
    if isNight == nil then
        isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
    end

    local mult = detectGameMultiplier()
    EventTracker.ActiveMultiplier = mult

    -- Si cambió el día, limpiar banners viejos que duren más de 180s
    if EventTracker.LastDayRecorded ~= currentDay then
        EventTracker.LastDayRecorded = currentDay
        if (tick() - EventTracker.MorningBannerTime) > 180 then
            EventTracker.MorningBannerDetected = nil
        end
    end

    checkMorningBanners()

    local isBloodMoonActive = ws:GetAttribute("BloodMoon") == true
    local isBanditActive = ws:GetAttribute("BanditRaid") == true
    local isBlizzard = ws:GetAttribute("Blizzard") == true
    local isRaining = ws:GetAttribute("Raining") == true
    local season = tostring(ws:GetAttribute("Season") or "N/A")

    local countdown = ws:GetAttribute("Countdown") or 0
    if type(countdown) ~= "number" then countdown = tonumber(countdown) or 0 end

    -- 1. Determinar el evento de hoy
    local todayLabel = "☀️ Día Normal / Noche de Zombies Común"
    local todayColor = Color3.fromRGB(0, 255, 170)

    if isBloodMoonActive or EventTracker.MorningBannerDetected == "🔴 LUNA DE SANGRE ESTA NOCHE" then
        todayLabel = "🔴 LUNA ROJA (BLOOD MOON)"
        todayColor = Color3.fromRGB(255, 45, 55)
    elseif isBanditActive or EventTracker.MorningBannerDetected == "🤠 INCURSIÓN DE BANDIDOS ESTA NOCHE" then
        todayLabel = "🤠 INCURSIÓN DE BANDIDOS"
        todayColor = Color3.fromRGB(255, 170, 0)
    elseif isBlizzard or EventTracker.MorningBannerDetected == "❄️ VENTISCA ESTA NOCHE" then
        todayLabel = "❄️ VENTISCA (BLIZZARD)"
        todayColor = Color3.fromRGB(100, 200, 255)
    elseif isRaining then
        todayLabel = "🌧️ LLUVIA"
        todayColor = Color3.fromRGB(120, 160, 220)
    end

    -- 2. Calcular cuántas noches/rondas reales han pasado desde la última Luna Roja
    local daysSinceBM = math.max(0, currentDay - lastBMDay)
    local roundsSinceBM = math.floor(daysSinceBM / math.max(1, mult))

    -- Intervalo de rondas según el multiplicador:
    -- Multiplicador x1  -> Cada 5 rondas
    -- Multiplicador x9  -> Cada 3 rondas (27 días de contador)
    -- Multiplicador x11 -> Cada 2 o 3 rondas alternadas
    local targetIntervalRounds = (mult >= 11 and 2) or ((mult >= 8) and 3) or 5
    local roundsUntilNext = math.max(0, targetIntervalRounds - roundsSinceBM)

    -- 3. Predicción para mañana
    local tomorrowLabel = "Noche Común (Zombies)"
    local tomorrowColor = Color3.fromRGB(180, 200, 220)

    if roundsUntilNext == 1 then
        tomorrowLabel = "⚠️ MAÑANA: LUNA ROJA ALTA PROBABILIDAD"
        tomorrowColor = Color3.fromRGB(255, 60, 70)
    elseif roundsUntilNext == 0 and not isBloodMoonActive and EventTracker.MorningBannerDetected ~= "🔴 LUNA DE SANGRE ESTA NOCHE" then
        tomorrowLabel = "🚨 MAÑANA: CICLO CUMPLIDO -> LUNA ROJA"
        tomorrowColor = Color3.fromRGB(255, 45, 55)
    elseif mult >= 11 and roundsSinceBM == 1 then
        tomorrowLabel = "Mañana: Probable Bandido o Noche Normal"
        tomorrowColor = Color3.fromRGB(255, 170, 40)
    else
        tomorrowLabel = string.format("Normal (Faltan ~%d noches para Luna Roja)", roundsUntilNext)
    end

    EventTracker.CurrentDay = currentDay
    EventTracker.TodayEvent = todayLabel
    EventTracker.TomorrowPrediction = tomorrowLabel
    EventTracker.RoundsSinceBloodMoon = roundsSinceBM
    EventTracker.RoundsUntilNextBloodMoon = roundsUntilNext
    EventTracker.Countdown = countdown
    EventTracker.IsNight = isNight

    return todayLabel, todayColor, tomorrowLabel, tomorrowColor, countdown, mult, roundsSinceBM, roundsUntilNext, season, currentDay, lastBMDay
end

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA (ACRYLIC = FALSE / SIN DESENFOQUE)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EventPredictorV4Gui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 490, 0, 420)
MainFrame.Position = UDim2.new(0.5, -245, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "  🔮 PREDICTOR DE EVENTOS POR MULTIPLICADOR DE RONDAS"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel 1: Evento de Hoy
local TodayCard = Instance.new("Frame")
TodayCard.Size = UDim2.new(1, -20, 0, 85)
TodayCard.Position = UDim2.new(0, 10, 0, 44)
TodayCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
TodayCard.Parent = MainFrame

local TodayCorner = Instance.new("UICorner")
TodayCorner.CornerRadius = UDim.new(0, 8)
TodayCorner.Parent = TodayCard

local TodayTitle = Instance.new("TextLabel")
TodayTitle.Size = UDim2.new(1, -20, 0, 30)
TodayTitle.Position = UDim2.new(0, 10, 0, 6)
TodayTitle.BackgroundTransparency = 1
TodayTitle.Text = "ANALIZANDO..."
TodayTitle.TextColor3 = Color3.fromRGB(0, 255, 170)
TodayTitle.TextSize = 15
TodayTitle.Font = Enum.Font.GothamBold
TodayTitle.TextXAlignment = Enum.TextXAlignment.Left
TodayTitle.Parent = TodayCard

local TodayDetail = Instance.new("TextLabel")
TodayDetail.Size = UDim2.new(1, -20, 0, 44)
TodayDetail.Position = UDim2.new(0, 10, 0, 36)
TodayDetail.BackgroundTransparency = 1
TodayDetail.Text = "Multiplicador: Detectando...\nAviso: Ninguno"
TodayDetail.TextColor3 = Color3.fromRGB(180, 190, 205)
TodayDetail.TextSize = 10
TodayDetail.Font = Enum.Font.Code
TodayDetail.TextXAlignment = Enum.TextXAlignment.Left
TodayDetail.Parent = TodayCard

-- Panel 2: Predicción de Mañana
local TomorrowCard = Instance.new("Frame")
TomorrowCard.Size = UDim2.new(1, -20, 0, 75)
TomorrowCard.Position = UDim2.new(0, 10, 0, 136)
TomorrowCard.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
TomorrowCard.Parent = MainFrame

local TomorrowCorner = Instance.new("UICorner")
TomorrowCorner.CornerRadius = UDim.new(0, 8)
TomorrowCorner.Parent = TomorrowCard

local TomorrowHeader = Instance.new("TextLabel")
TomorrowHeader.Size = UDim2.new(1, -20, 0, 24)
TomorrowHeader.Position = UDim2.new(0, 10, 0, 6)
TomorrowHeader.BackgroundTransparency = 1
TomorrowHeader.Text = "PREDICCIÓN PARA LA PRÓXIMA NOCHE:"
TomorrowHeader.TextColor3 = Color3.fromRGB(255, 215, 0)
TomorrowHeader.TextSize = 10
TomorrowHeader.Font = Enum.Font.GothamBold
TomorrowHeader.TextXAlignment = Enum.TextXAlignment.Left
TomorrowHeader.Parent = TomorrowCard

local TomorrowDesc = Instance.new("TextLabel")
TomorrowDesc.Size = UDim2.new(1, -20, 0, 40)
TomorrowDesc.Position = UDim2.new(0, 10, 0, 30)
TomorrowDesc.BackgroundTransparency = 1
TomorrowDesc.Text = "Calculando noches restantes..."
TomorrowDesc.TextColor3 = Color3.fromRGB(220, 220, 220)
TomorrowDesc.TextSize = 11
TomorrowDesc.Font = Enum.Font.Code
TomorrowDesc.TextXAlignment = Enum.TextXAlignment.Left
TomorrowDesc.Parent = TomorrowCard

-- Panel 3: Cronómetro Regresivo (Alerta 30s)
local ClockCard = Instance.new("Frame")
ClockCard.Size = UDim2.new(1, -20, 0, 75)
ClockCard.Position = UDim2.new(0, 10, 0, 218)
ClockCard.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
ClockCard.Parent = MainFrame

local ClockCorner = Instance.new("UICorner")
ClockCorner.CornerRadius = UDim.new(0, 8)
ClockCorner.Parent = ClockCard

local ClockText = Instance.new("TextLabel")
ClockText.Size = UDim2.new(0.45, 0, 1, 0)
ClockText.Position = UDim2.new(0, 10, 0, 0)
ClockText.BackgroundTransparency = 1
ClockText.Text = "00:00"
ClockText.TextColor3 = Color3.fromRGB(255, 255, 255)
ClockText.TextSize = 32
ClockText.Font = Enum.Font.GothamBold
ClockText.TextXAlignment = Enum.TextXAlignment.Left
ClockText.Parent = ClockCard

local ClockInfo = Instance.new("TextLabel")
ClockInfo.Size = UDim2.new(0.53, -10, 1, 0)
ClockInfo.Position = UDim2.new(0.47, 0, 0, 0)
ClockInfo.BackgroundTransparency = 1
ClockInfo.Text = "Fase: Día\nHora Solar: 12.00\nAlerta: Inactiva (>30s)"
ClockInfo.TextColor3 = Color3.fromRGB(180, 190, 205)
ClockInfo.TextSize = 10
ClockInfo.Font = Enum.Font.Code
ClockInfo.TextXAlignment = Enum.TextXAlignment.Left
ClockInfo.Parent = ClockCard

-- Selector Manual de Multiplicador por si se desea forzar
local MultContainer = Instance.new("Frame")
MultContainer.Size = UDim2.new(1, -20, 0, 34)
MultContainer.Position = UDim2.new(0, 10, 0, 300)
MultContainer.BackgroundTransparency = 1
MultContainer.Parent = MainFrame

local function createMultBtn(name, multValue, posX, sizeX)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(sizeX, -4, 1, 0)
    btn.Position = UDim2.new(posX, 0, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MultContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        if multValue == 0 then
            Config.AutoDetectMultiplier = true
            btn.Text = "AUTO (ON)"
        else
            Config.AutoDetectMultiplier = false
            Config.ManualMultiplier = multValue
            btn.Text = "✅ " .. name
        end
        task.wait(0.5)
        btn.Text = name
    end)
end

createMultBtn("AUTO", 0, 0.00, 0.25)
createMultBtn("Fijar x1", 1, 0.25, 0.25)
createMultBtn("Fijar x9", 9, 0.50, 0.25)
createMultBtn("Fijar x11", 11, 0.75, 0.25)

-- Botón Copiar Reporte
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 342)
CopyBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyBtn.Text = "📋 COPIAR DATOS DE TIEMPO Y MULTIPLICADOR"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local text = string.format(
        "Día Actual: %d | Multiplicador Activo: x%d\n" ..
        "Evento Hoy: %s\n" ..
        "Predicción Mañana: %s\n" ..
        "Noches Reales desde última Luna Roja: %d noches\n" ..
        "Noches Reales estimadas para la próxima: ~%d noches\n" ..
        "Aviso Capturado en Pantalla: %s\n" ..
        "Countdown: %.1fs | Hora Solar: %.2f",
        EventTracker.CurrentDay, EventTracker.ActiveMultiplier,
        EventTracker.TodayEvent,
        EventTracker.TomorrowPrediction,
        EventTracker.RoundsSinceBloodMoon,
        EventTracker.RoundsUntilNextBloodMoon,
        tostring(EventTracker.MorningBannerDetected or "Ninguno"),
        EventTracker.Countdown, Lighting.ClockTime
    )
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR DATOS DE TIEMPO Y MULTIPLICADOR"
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
FloatBtn.Text = "🔮\nEVENT"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==============================================================================
-- 5. BUCLE DE ACTUALIZACIÓN EN VIVO (CADA 0.25s)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.25)
        local todayEvent, todayColor, tomorrowEvent, tomorrowColor, countdown, mult, roundsSince, roundsUntil, season, curDay, lastBM = updateEventPredictions()

        TodayTitle.Text = todayEvent
        TodayTitle.TextColor3 = todayColor
        TodayDetail.Text = string.format(
            "Día: %d (x%d) | Fase: %s | Estación: %s\nAviso Capturado: %s",
            curDay, mult,
            EventTracker.IsNight and "🌙 NOCHE" or "☀️ DÍA",
            season,
            tostring(EventTracker.MorningBannerDetected or "Sin avisos especiales hoy")
        )

        TomorrowDesc.Text = string.format(
            "• %s\n• Noches transcurridas desde Luna Roja: %d | Próxima en: ~%d noche(s)",
            tomorrowEvent, roundsSince, roundsUntil
        )

        local mins = math.floor(countdown / 60)
        local secs = math.floor(countdown % 60)
        ClockText.Text = string.format("%02d:%02d", mins, secs)

        -- ALERTA A LOS 30 SEGUNDOS
        if countdown > 0 and countdown <= Config.StuckAlertTime then
            ClockCard.BackgroundColor3 = Color3.fromRGB(80, 20, 25)
            ClockText.TextColor3 = Color3.fromRGB(255, 60, 70)
            ClockInfo.Text = string.format("⚠️ ¡FALTAN %d SEGUNDOS!\nPrepárate para la noche\nHora Solar: %.2f", math.floor(countdown), Lighting.ClockTime)

            if (tick() - EventTracker.LastAlertTime) > 40 then
                EventTracker.LastAlertTime = tick()
                pcall(function()
                    local sound = Instance.new("Sound")
                    sound.SoundId = "rbxassetid://4590662766"
                    sound.Volume = 1.0
                    sound.Parent = workspace
                    sound:Play()
                    game:GetService("Debris"):AddItem(sound, 3)
                end)
            end
        else
            ClockCard.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
            ClockText.TextColor3 = Color3.fromRGB(255, 255, 255)
            ClockInfo.Text = string.format("Fase: %s\nHora Solar: %.2f\nAlerta: Inactiva (>30s)", EventTracker.IsNight and "Noche" or "Día", Lighting.ClockTime)
        end
    end
end)
