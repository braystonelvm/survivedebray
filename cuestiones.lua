-- ==============================================================================
-- PREDICTOR TEMPRANO DE CLIMAS, LUNA ROJA Y EVENTOS (BANNER + MATEMÁTICO)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

-- Eliminar desenfoque
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

local BLOOD_MOON_CYCLE = 27 -- Intervalo detectado: 164 - 137 = 27 días

local PredictionState = {
    MorningWarningText = "Ninguno",
    TodayEvent = "Normal",
    TomorrowPrediction = "Normal",
    DaysUntilBloodMoon = 0,
    NextBloodMoonDay = 191,
    Countdown = 0,
    CurrentDay = 0,
    Season = "Summer",
    IsNight = false,
    LastAlertTime = 0
}

-- ==============================================================================
-- 1. ESCÁNER DE ANUNCIOS EN PANTALLA (PLAYERGUI)
-- ==============================================================================

local function scanPlayerGuiForMorningWarnings()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return nil end

    for _, desc in ipairs(pg:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.TextTransparency < 0.5 then
            local txt = desc.Text:lower()
            if txt:find("luna de sangre") or txt:find("blood moon") or txt:find("saldrá esta noche") or txt:find("salva esta noche") then
                return "🔴 LUNA DE SANGRE ESTA NOCHE", desc.Text
            elseif txt:find("bandid") or txt:find("incursión") or txt:find("raid") then
                return "🤠 INCURSIÓN DE BANDIDOS ESTA NOCHE", desc.Text
            elseif txt:find("ventisca") or txt:find("blizzard") or txt:find("tormenta") then
                return "❄️ VENTISCA ESTA NOCHE", desc.Text
            end
        end
    end
    return nil, nil
end

-- ==============================================================================
-- 2. MOTOR MATEMÁTICO DE PREDICCIÓN (HOY Y MAÑANA)
-- ==============================================================================

local function calculatePredictions()
    local ws = workspace
    local currentDay = ws:GetAttribute("CurrentDay") or 0
    local lastBM = ws:GetAttribute("LastBloodMoonDay") or 137
    local isNight = ws:GetAttribute("Night")
    if isNight == nil then
        isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
    end

    local season = tostring(ws:GetAttribute("Season") or "Summer")
    local isRaining = ws:GetAttribute("Raining") == true
    local isBlizzard = ws:GetAttribute("Blizzard") == true
    local isBandit = ws:GetAttribute("BanditRaid") == true
    local isBloodMoonAttr = ws:GetAttribute("BloodMoon") == true

    local countdown = ws:GetAttribute("Countdown") or 0
    if type(countdown) ~= "number" then countdown = tonumber(countdown) or 0 end

    -- 1. Revisar si hay un aviso matutino en pantalla
    local guiEventTag, fullBannerText = scanPlayerGuiForMorningWarnings()

    -- 2. Determinar evento de hoy
    local todayEvent = "☀️ Día Normal / Noche Común de Zombies"
    local todayColor = Color3.fromRGB(0, 255, 170)

    if isBloodMoonAttr or guiEventTag == "🔴 LUNA DE SANGRE ESTA NOCHE" then
        todayEvent = "🔴 LUNA ROJA (BLOOD MOON)"
        todayColor = Color3.fromRGB(255, 45, 55)
    elseif isBandit or guiEventTag == "🤠 INCURSIÓN DE BANDIDOS ESTA NOCHE" then
        todayEvent = "🤠 INCURSIÓN DE BANDIDOS"
        todayColor = Color3.fromRGB(255, 170, 0)
    elseif isBlizzard or guiEventTag == "❄️ VENTISCA ESTA NOCHE" then
        todayEvent = "❄️ VENTISCA (BLIZZARD)"
        todayColor = Color3.fromRGB(100, 200, 255)
    elseif isRaining then
        todayEvent = "🌧️ DÍA LLUVIOSO"
        todayColor = Color3.fromRGB(120, 160, 220)
    end

    -- 3. Calcular matemáticamente cuándo cae la próxima Luna Roja
    local nextBMDay = lastBM
    while nextBMDay <= currentDay do
        nextBMDay = nextBMDay + BLOOD_MOON_CYCLE
    end

    local daysLeftBM = nextBMDay - currentDay

    -- 4. Predicción del día de mañana
    local tomorrowEvent = "Noche Común (Zombies)"
    local tomorrowColor = Color3.fromRGB(180, 200, 220)

    if daysLeftBM == 1 then
        tomorrowEvent = "⚠️ MAÑANA: LUNA ROJA GARANTIZADA"
        tomorrowColor = Color3.fromRGB(255, 50, 60)
    elseif daysLeftBM == 2 then
        tomorrowEvent = "En 2 días: Próxima Luna Roja"
        tomorrowColor = Color3.fromRGB(255, 150, 50)
    else
        tomorrowEvent = string.format("Normal (Faltan %d días para Luna Roja)", daysLeftBM)
    end

    PredictionState.CurrentDay = currentDay
    PredictionState.TodayEvent = todayEvent
    PredictionState.TomorrowPrediction = tomorrowEvent
    PredictionState.DaysUntilBloodMoon = daysLeftBM
    PredictionState.NextBloodMoonDay = nextBMDay
    PredictionState.Countdown = countdown
    PredictionState.Season = season
    PredictionState.IsNight = isNight
    PredictionState.MorningWarningText = fullBannerText or "Sin anuncios en pantalla"

    return todayEvent, todayColor, tomorrowEvent, tomorrowColor, daysLeftBM, nextBMDay, countdown, isNight, season
end

-- ==============================================================================
-- 3. INTERFAZ GRÁFICA DEL PREDICTOR (ACRYLIC = FALSE)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WeatherAndEventPredictorGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 410)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -205)
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
TitleBar.Text = "  🔮 PREDICTOR DE CLIMA, EVENTOS Y LUNA ROJA"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Tarjeta 1: Evento de Hoy
local TodayCard = Instance.new("Frame")
TodayCard.Size = UDim2.new(1, -20, 0, 80)
TodayCard.Position = UDim2.new(0, 10, 0, 44)
TodayCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
TodayCard.Parent = MainFrame

local TodayCorner = Instance.new("UICorner")
TodayCorner.CornerRadius = UDim.new(0, 8)
TodayCorner.Parent = TodayCard

local TodayTitle = Instance.new("TextLabel")
TodayTitle.Size = UDim2.new(1, -20, 0, 28)
TodayTitle.Position = UDim2.new(0, 10, 0, 6)
TodayTitle.BackgroundTransparency = 1
TodayTitle.Text = "CALCULANDO HOY..."
TodayTitle.TextColor3 = Color3.fromRGB(0, 255, 170)
TodayTitle.TextSize = 15
TodayTitle.Font = Enum.Font.GothamBold
TodayTitle.TextXAlignment = Enum.TextXAlignment.Left
TodayTitle.Parent = TodayCard

local TodayDetail = Instance.new("TextLabel")
TodayDetail.Size = UDim2.new(1, -20, 0, 42)
TodayDetail.Position = UDim2.new(0, 10, 0, 34)
TodayDetail.BackgroundTransparency = 1
TodayDetail.Text = "Día: 0 | Fase: Día | Estación: Summer\nAviso: Escaneando banner matutino..."
TodayDetail.TextColor3 = Color3.fromRGB(180, 190, 205)
TodayDetail.TextSize = 10
TodayDetail.Font = Enum.Font.Code
TodayDetail.TextXAlignment = Enum.TextXAlignment.Left
TodayDetail.Parent = TodayCard

-- Tarjeta 2: Predicción del Día de Mañana
local TomorrowCard = Instance.new("Frame")
TomorrowCard.Size = UDim2.new(1, -20, 0, 75)
TomorrowCard.Position = UDim2.new(0, 10, 0, 130)
TomorrowCard.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
TomorrowCard.Parent = MainFrame

local TomorrowCorner = Instance.new("UICorner")
TomorrowCorner.CornerRadius = UDim.new(0, 8)
TomorrowCorner.Parent = TomorrowCard

local TomorrowTitle = Instance.new("TextLabel")
TomorrowTitle.Size = UDim2.new(1, -20, 0, 26)
TomorrowTitle.Position = UDim2.new(0, 10, 0, 6)
TomorrowTitle.BackgroundTransparency = 1
TomorrowTitle.Text = "PREDICCIÓN PARA MAÑANA:"
TomorrowTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
TomorrowTitle.TextSize = 11
TomorrowTitle.Font = Enum.Font.GothamBold
TomorrowTitle.TextXAlignment = Enum.TextXAlignment.Left
TomorrowTitle.Parent = TomorrowCard

local TomorrowDetail = Instance.new("TextLabel")
TomorrowDetail.Size = UDim2.new(1, -20, 0, 38)
TomorrowDetail.Position = UDim2.new(0, 10, 0, 32)
TomorrowDetail.BackgroundTransparency = 1
TomorrowDetail.Text = "Calculando ciclo..."
TomorrowDetail.TextColor3 = Color3.fromRGB(220, 220, 220)
TomorrowDetail.TextSize = 11
TomorrowDetail.Font = Enum.Font.Code
TomorrowDetail.TextXAlignment = Enum.TextXAlignment.Left
TomorrowDetail.Parent = TomorrowCard

-- Tarjeta 3: Reloj Regresivo con Alerta (30s)
local ClockCard = Instance.new("Frame")
ClockCard.Size = UDim2.new(1, -20, 0, 80)
ClockCard.Position = UDim2.new(0, 10, 0, 212)
ClockCard.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
ClockCard.Parent = MainFrame

local ClockCorner = Instance.new("UICorner")
ClockCorner.CornerRadius = UDim.new(0, 8)
ClockCorner.Parent = ClockCard

local ClockNumber = Instance.new("TextLabel")
ClockNumber.Size = UDim2.new(0.46, 0, 1, 0)
ClockNumber.Position = UDim2.new(0, 10, 0, 0)
ClockNumber.BackgroundTransparency = 1
ClockNumber.Text = "00:00"
ClockNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
ClockNumber.TextSize = 32
ClockNumber.Font = Enum.Font.GothamBold
ClockNumber.TextXAlignment = Enum.TextXAlignment.Left
ClockNumber.Parent = ClockCard

local ClockDetail = Instance.new("TextLabel")
ClockDetail.Size = UDim2.new(0.52, -10, 1, 0)
ClockDetail.Position = UDim2.new(0.48, 0, 0, 0)
ClockDetail.BackgroundTransparency = 1
ClockDetail.Text = "Tiempo para Cambio\nHora Solar: 12.00\nAlerta: Inactiva"
ClockDetail.TextColor3 = Color3.fromRGB(180, 190, 205)
ClockDetail.TextSize = 10
ClockDetail.Font = Enum.Font.Code
ClockDetail.TextXAlignment = Enum.TextXAlignment.Left
ClockDetail.Parent = ClockCard

-- Botón Copiar Registro Completo
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 300)
CopyBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyBtn.Text = "📋 COPIAR DATOS DE TIEMPO Y EVENTOS"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local text = string.format(
        "Día Actual: %d | Evento Hoy: %s\nPredicción Mañana: %s\nDías para Luna Roja: %d (Día objetivo: %d)\nEstación: %s | Fase: %s | Countdown: %.1f\nAviso Banner Pantalla: %s",
        PredictionState.CurrentDay, PredictionState.TodayEvent,
        PredictionState.TomorrowPrediction,
        PredictionState.DaysUntilBloodMoon, PredictionState.NextBloodMoonDay,
        PredictionState.Season, PredictionState.IsNight and "Noche" or "Día",
        PredictionState.Countdown,
        PredictionState.MorningWarningText
    )
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡DATOS COPIADOS!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR DATOS DE TIEMPO Y EVENTOS"
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
-- 4. BUCLE DE ACTUALIZACIÓN EN VIVO (CADA 0.25s)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.25)
        local todayEvent, todayColor, tomorrowEvent, tomorrowColor, daysLeftBM, nextBMDay, countdown, isNight, season = calculatePredictions()

        TodayTitle.Text = todayEvent
        TodayTitle.TextColor3 = todayColor
        TodayDetail.Text = string.format(
            "Día: %d | Fase: %s | Estación: %s\nAviso Pantalla: %s",
            PredictionState.CurrentDay,
            isNight and "🌙 NOCHE" or "☀️ DÍA",
            season,
            PredictionState.MorningWarningText
        )

        TomorrowDetail.Text = string.format(
            "• %s\n• Próxima Luna Roja: Día %d (en %d días)",
            tomorrowEvent, nextBMDay, daysLeftBM
        )

        -- Actualización del cronómetro
        local mins = math.floor(countdown / 60)
        local secs = math.floor(countdown % 60)
        ClockNumber.Text = string.format("%02d:%02d", mins, secs)

        -- Alerta visual y sonora a los 30 segundos
        if countdown > 0 and countdown <= 30 then
            ClockCard.BackgroundColor3 = Color3.fromRGB(80, 20, 25)
            ClockNumber.TextColor3 = Color3.fromRGB(255, 60, 70)
            ClockDetail.Text = string.format("⚠️ ¡FALTAN %d SEGUNDOS!\nHora Solar: %.2f\nAlerta: Activa", math.floor(countdown), Lighting.ClockTime)

            if (tick() - PredictionState.LastAlertTime) > 40 then
                PredictionState.LastAlertTime = tick()
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
            ClockNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
            ClockDetail.Text = string.format("Tiempo para Cambio\nHora Solar: %.2f\nAlerta: Inactiva", Lighting.ClockTime)
        end
    end
end)
