-- ==============================================================================
-- PREDICTOR EXACTO DE EVENTOS Y CLIMAS V5 (CICLO DE 6 NOCHES - 0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

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

local State = {
    CurrentDay = 0,
    PreviousDay = 0,
    DetectedMultiplier = 1,
    CycleStep = 1, -- Pasos del 1 al 6
    TodayEvent = "Normal",
    TomorrowPrediction = "Normal",
    WeatherTomorrow = "Despejado",
    Countdown = 0,
    IsNight = false,
    Season = "Summer",
    LastAlertTime = 0
}

-- ==============================================================================
-- 1. MOTOR DE CÁLCULO DEL CICLO DE 6 NOCHES
-- ==============================================================================

local function analyzeCycle()
    local ws = workspace
    local curDay = ws:GetAttribute("CurrentDay") or 0
    local isNight = ws:GetAttribute("Night")
    if isNight == nil then
        isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
    end

    local isBM = ws:GetAttribute("BloodMoon") == true
    local isRaid = ws:GetAttribute("BanditRaid") == true
    local season = tostring(ws:GetAttribute("Season") or "Summer")
    local countdown = math.floor(tonumber(ws:GetAttribute("Countdown") or 0) or 0)

    -- Detectar multiplicador real según el salto de días
    if State.PreviousDay == 0 then State.PreviousDay = curDay end
    if curDay > State.PreviousDay then
        local delta = curDay - State.PreviousDay
        if delta >= 1 and delta <= 20 then
            State.DetectedMultiplier = delta
        end
        State.PreviousDay = curDay
    end

    -- Sincronizar el paso del ciclo (1 al 6) con los eventos reales
    if isBM then
        if State.CycleStep ~= 1 and State.CycleStep ~= 4 then
            -- Si viene de Bandidos (paso 6), la Luna Roja es paso 1; de lo contrario es paso 4
            State.CycleStep = (State.CycleStep == 6 or State.CycleStep == 0) and 1 or 4
        end
    elseif isRaid then
        State.CycleStep = 6
    end

    -- Definición de los 6 pasos
    local CYCLE_NAMES = {
        [1] = "🔴 LUNA ROJA (Paso 1/6)",
        [2] = "🟢 Noche Normal (Paso 2/6)",
        [3] = "🟢 Noche Normal (Paso 3/6)",
        [4] = "🔴 LUNA ROJA (Paso 4/6)",
        [5] = "🟢 Noche Normal (Paso 5/6)",
        [6] = "🤠 INCURSIÓN DE BANDIDOS (Paso 6/6)"
    }

    local NEXT_NAMES = {
        [1] = "🟢 Mañana: Noche Normal",
        [2] = "🟢 Mañana: Noche Normal",
        [3] = "🚨 MAÑANA: 🔴 LUNA ROJA GARANTIZADA",
        [4] = "🟢 Mañana: Noche Normal",
        [5] = "🚨 MAÑANA: 🤠 BANDIDOS GARANTIZADOS",
        [6] = "🚨 MAÑANA: 🔴 LUNA ROJA GARANTIZADA"
    }

    local currentStep = State.CycleStep
    local nextStep = (currentStep % 6) + 1

    local todayText = CYCLE_NAMES[currentStep] or "Normal"
    local todayColor = isBM and Color3.fromRGB(255, 45, 55) or (isRaid and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(0, 255, 170))

    local tomorrowText = NEXT_NAMES[currentStep] or "Normal"
    local tomorrowColor = (nextStep == 1 or nextStep == 4) and Color3.fromRGB(255, 50, 60) or (nextStep == 6 and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(180, 200, 220))

    -- Predicción de clima matutino: tras Luna Roja siempre hay precipitación
    local weatherTomorrow = "☀️ Despejado"
    if currentStep == 1 or currentStep == 4 then
        if season == "Winter" then
            weatherTomorrow = "❄️ VENTISCA (Post-Luna Roja)"
        else
            weatherTomorrow = "🌧️ LLUVIA (Post-Luna Roja)"
        end
    end

    State.CurrentDay = curDay
    State.IsNight = isNight
    State.Countdown = countdown
    State.Season = season
    State.TodayEvent = todayText
    State.TomorrowPrediction = tomorrowText
    State.WeatherTomorrow = weatherTomorrow

    return todayText, todayColor, tomorrowText, tomorrowColor, weatherTomorrow, countdown, curDay, isNight, season, State.DetectedMultiplier, currentStep
end

-- Avanzar paso al cambiar la noche
workspace:GetAttributeChangedSignal("Night"):Connect(function()
    task.wait(0.5)
    local isNight = workspace:GetAttribute("Night")
    if isNight then
        -- Al caer la noche, avanzamos al siguiente paso si no fue forzado por evento
        local isBM = workspace:GetAttribute("BloodMoon") == true
        local isRaid = workspace:GetAttribute("BanditRaid") == true
        if not isBM and not isRaid then
            State.CycleStep = (State.CycleStep % 6) + 1
        end
    end
end)

-- ==============================================================================
-- 2. INTERFAZ GRÁFICA DEL PREDICTOR (ACRYLIC = FALSE)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EventPredictorV5Gui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 420)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -210)
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
TitleBar.Text = "  🔮 PREDICTOR EXACTO DE EVENTOS (CICLO 6 NOCHES)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel 1: Hoy
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
TodayTitle.Text = "CALCULANDO HOY..."
TodayTitle.TextColor3 = Color3.fromRGB(0, 255, 170)
TodayTitle.TextSize = 15
TodayTitle.Font = Enum.Font.GothamBold
TodayTitle.TextXAlignment = Enum.TextXAlignment.Left
TodayTitle.Parent = TodayCard

local TodayDetail = Instance.new("TextLabel")
TodayDetail.Size = UDim2.new(1, -20, 0, 44)
TodayDetail.Position = UDim2.new(0, 10, 0, 36)
TodayDetail.BackgroundTransparency = 1
TodayDetail.Text = "Día: 0 | Multiplicador: Calculando..."
TodayDetail.TextColor3 = Color3.fromRGB(180, 190, 205)
TodayDetail.TextSize = 10
TodayDetail.Font = Enum.Font.Code
TodayDetail.TextXAlignment = Enum.TextXAlignment.Left
TodayDetail.Parent = TodayCard

-- Panel 2: Predicción Mañana
local TomorrowCard = Instance.new("Frame")
TomorrowCard.Size = UDim2.new(1, -20, 0, 85)
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
TomorrowHeader.Text = "PREDICCIÓN PARA LA PRÓXIMA NOCHE Y MAÑANA:"
TomorrowHeader.TextColor3 = Color3.fromRGB(255, 215, 0)
TomorrowHeader.TextSize = 10
TomorrowHeader.Font = Enum.Font.GothamBold
TomorrowHeader.TextXAlignment = Enum.TextXAlignment.Left
TomorrowHeader.Parent = TomorrowCard

local TomorrowDesc = Instance.new("TextLabel")
TomorrowDesc.Size = UDim2.new(1, -20, 0, 48)
TomorrowDesc.Position = UDim2.new(0, 10, 0, 30)
TomorrowDesc.BackgroundTransparency = 1
TomorrowDesc.Text = "Calculando paso del ciclo..."
TomorrowDesc.TextColor3 = Color3.fromRGB(220, 220, 220)
TomorrowDesc.TextSize = 11
TomorrowDesc.Font = Enum.Font.Code
TomorrowDesc.TextXAlignment = Enum.TextXAlignment.Left
TomorrowDesc.Parent = TomorrowCard

-- Panel 3: Reloj Regresivo (Alerta 30s)
local ClockCard = Instance.new("Frame")
ClockCard.Size = UDim2.new(1, -20, 0, 75)
ClockCard.Position = UDim2.new(0, 10, 0, 228)
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
ClockInfo.Text = "Fase: Día\nHora Solar: 12.00\nAlerta: Inactiva"
ClockInfo.TextColor3 = Color3.fromRGB(180, 190, 205)
ClockInfo.TextSize = 10
ClockInfo.Font = Enum.Font.Code
ClockInfo.TextXAlignment = Enum.TextXAlignment.Left
ClockInfo.Parent = ClockCard

-- Selector manual de sincronización
local SyncContainer = Instance.new("Frame")
SyncContainer.Size = UDim2.new(1, -20, 0, 32)
SyncContainer.Position = UDim2.new(0, 10, 0, 310)
SyncContainer.BackgroundTransparency = 1
SyncContainer.Parent = MainFrame

local function createSyncBtn(name, stepNumber, posX, sizeX)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(sizeX, -4, 1, 0)
    btn.Position = UDim2.new(posX, 0, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 9
    btn.Font = Enum.Font.GothamBold
    btn.Parent = SyncContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        State.CycleStep = stepNumber
        btn.Text = "✅ " .. name
        task.wait(0.5)
        btn.Text = name
    end)
end

createSyncBtn("1: ROJA", 1, 0.00, 0.166)
createSyncBtn("2: NORM", 2, 0.166, 0.166)
createSyncBtn("3: NORM", 3, 0.333, 0.166)
createSyncBtn("4: ROJA", 4, 0.500, 0.166)
createSyncBtn("5: NORM", 5, 0.666, 0.166)
createSyncBtn("6: BAND", 6, 0.833, 0.166)

-- Botón Copiar Estado
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 350)
CopyBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyBtn.Text = "📋 COPIAR ESTADO ACTUAL DEL CICLO"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local text = string.format(
        "Día: %d | Multiplicador: x%d | Fase: %s\n" ..
        "Estado del Ciclo: %s (Paso %d/6)\n" ..
        "Predicción Próxima Noche: %s\n" ..
        "Clima Próximo Día: %s\n" ..
        "Countdown: %ds | Hora Solar: %.2f",
        State.CurrentDay, State.DetectedMultiplier, State.IsNight and "Noche" or "Día",
        State.TodayEvent, State.CycleStep,
        State.TomorrowPrediction,
        State.WeatherTomorrow,
        State.Countdown, Lighting.ClockTime
    )
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR ESTADO ACTUAL DEL CICLO"
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
FloatBtn.Text = "🔮\nCYCLE"
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
-- 3. BUCLE DE ACTUALIZACIÓN VISUAL (BAJO CONSUMO)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.5)
        local todayText, todayColor, tomorrowText, tomorrowColor, weatherTomorrow, countdown, curDay, isNight, season, mult, step = analyzeCycle()

        TodayTitle.Text = todayText
        TodayTitle.TextColor3 = todayColor
        TodayDetail.Text = string.format(
            "Día: %d  (Salto real: x%d) | Estación: %s\nFase: %s | Paso activo: %d/6",
            curDay, mult, season,
            isNight and "🌙 NOCHE" or "☀️ DÍA", step
        )

        TomorrowDesc.Text = string.format(
            "• Evento: %s\n• Clima de mañana: %s",
            tomorrowText, weatherTomorrow
        )

        local mins = math.floor(countdown / 60)
        local secs = math.floor(countdown % 60)
        ClockText.Text = string.format("%02d:%02d", mins, secs)

        -- Alerta a los 30 segundos
        if countdown > 0 and countdown <= 30 then
            ClockCard.BackgroundColor3 = Color3.fromRGB(80, 20, 25)
            ClockText.TextColor3 = Color3.fromRGB(255, 60, 70)
            ClockInfo.Text = string.format("⚠️ ¡FALTAN %d SEGUNDOS!\nPrepárate para la noche\nHora: %.2f", countdown, Lighting.ClockTime)

            if (tick() - State.LastAlertTime) > 40 then
                State.LastAlertTime = tick()
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
            ClockInfo.Text = string.format("Fase: %s\nHora Solar: %.2f\nAlerta: Inactiva", isNight and "Noche" or "Día", Lighting.ClockTime)
        end
    end
end)
