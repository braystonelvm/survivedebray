-- ==============================================================================
-- MONITOR DIAGNÓSTICO DE TIEMPO, DÍAS Y EVENTOS (ALERTA 30 SEGUNDOS)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local DiagnosticData = {
    CurrentDay = 0,
    DayType = "Normal",
    TimeLeft = 0,
    ClockTime = 0,
    IsNight = false,
    Season = "Desconocida",
    LastAlertTriggered = 0,
    RawAttributes = {}
}

-- ==============================================================================
-- 1. DETECCIÓN Y CLASIFICACIÓN DEL EVENTO
-- ==============================================================================

local function analyzeDayAndEvent()
    local ws = workspace
    local day = ws:GetAttribute("CurrentDay") or ws:GetAttribute("Day") or 0
    local isNight = ws:GetAttribute("Night")
    if isNight == nil then
        -- En Roblox, la noche estándar suele estar entre 18.0 y 6.0
        isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
    end

    local isBloodMoon = ws:GetAttribute("BloodMoon") == true
    local isBanditRaid = ws:GetAttribute("BanditRaid") == true
    local isBlizzard = ws:GetAttribute("Blizzard") == true
    local isRaining = ws:GetAttribute("Raining") == true
    local season = tostring(ws:GetAttribute("Season") or "N/A")
    local lastBMDay = ws:GetAttribute("LastBloodMoonDay") or "N/A"

    -- Determinar el tipo de día / noche
    local dayType = "Día / Noche Normal (Zombies)"
    local tagColor = Color3.fromRGB(0, 255, 170)

    if isBloodMoon then
        dayType = "🔴 LUNA ROJA (BLOOD MOON)"
        tagColor = Color3.fromRGB(255, 40, 50)
    elseif isBanditRaid then
        dayType = "🤠 INCURSIÓN DE BANDIDOS (BANDIT RAID)"
        tagColor = Color3.fromRGB(255, 170, 0)
    elseif isBlizzard then
        dayType = "❄️ VENTISCA (BLIZZARD)"
        tagColor = Color3.fromRGB(100, 200, 255)
    elseif isRaining then
        dayType = "🌧️ LLUVIA (RAINING)"
        tagColor = Color3.fromRGB(120, 160, 220)
    end

    -- Lectura del contador de tiempo para que empiece la noche / termine la ronda
    local countdown = ws:GetAttribute("Countdown") or ws:GetAttribute("TimeLeft") or ws:GetAttribute("WaveTime") or 0
    if type(countdown) ~= "number" then
        countdown = tonumber(countdown) or 0
    end

    DiagnosticData.CurrentDay = day
    DiagnosticData.DayType = dayType
    DiagnosticData.TimeLeft = countdown
    DiagnosticData.ClockTime = Lighting.ClockTime
    DiagnosticData.IsNight = isNight
    DiagnosticData.Season = season

    return dayType, tagColor, countdown, day, isNight, season, lastBMDay
end

local function captureAllTimeAttributes()
    local lines = {
        "==================================================================",
        "          REPORTE DE ATRIBUTOS TEMPORALES DEL JUEGO               ",
        "==================================================================",
        string.format("Fecha y Hora Local: %s", os.date("%Y-%m-%d %X")),
        string.format("Lighting.ClockTime: %.2f | TimeOfDay: %s", Lighting.ClockTime, Lighting.TimeOfDay),
        "\n[ATRIBUTOS DE WORKSPACE RELACIONADOS AL TIEMPO Y EVENTOS]:"
    }

    for k, v in pairs(workspace:GetAttributes()) do
        local kn = tostring(k):lower()
        if kn:find("day") or kn:find("night") or kn:find("time") or kn:find("wave") 
           or kn:find("blood") or kn:find("raid") or kn:find("count") or kn:find("season")
           or kn:find("blizzard") or kn:find("rain") or kn:find("mobs") then
            table.insert(lines, string.format(" • Workspace.%s = %s (%s)", tostring(k), tostring(v), typeof(v)))
        end
    end

    table.insert(lines, "\n[TODOS LOS DEMÁS ATRIBUTOS]:")
    for k, v in pairs(workspace:GetAttributes()) do
        local kn = tostring(k):lower()
        if not (kn:find("day") or kn:find("night") or kn:find("time") or kn:find("wave") 
           or kn:find("blood") or kn:find("raid") or kn:find("count") or kn:find("season")
           or kn:find("blizzard") or kn:find("rain") or kn:find("mobs")) then
            table.insert(lines, string.format("   Workspace.%s = %s", tostring(k), tostring(v)))
        end
    end

    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 2. INTERFAZ GRÁFICA DEL MONITOR
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DayTimeDiagnosticGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 390)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -195)
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
TitleBar.Text = "  ⏰ ANALIZADOR DE DÍA, EVENTOS Y RELOJ REGRESIVO"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Tarjeta 1: Cartel Principal del Tipo de Día
local EventCard = Instance.new("Frame")
EventCard.Size = UDim2.new(1, -20, 0, 75)
EventCard.Position = UDim2.new(0, 10, 0, 44)
EventCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
EventCard.Parent = MainFrame

local EventCorner = Instance.new("UICorner")
EventCorner.CornerRadius = UDim.new(0, 8)
EventCorner.Parent = EventCard

local EventTitle = Instance.new("TextLabel")
EventTitle.Size = UDim2.new(1, -20, 0, 34)
EventTitle.Position = UDim2.new(0, 10, 0, 6)
EventTitle.BackgroundTransparency = 1
EventTitle.Text = "CARGANDO ESTADO..."
EventTitle.TextColor3 = Color3.fromRGB(0, 255, 170)
EventTitle.TextSize = 16
EventTitle.Font = Enum.Font.GothamBold
EventTitle.TextXAlignment = Enum.TextXAlignment.Left
EventTitle.Parent = EventCard

local EventSub = Instance.new("TextLabel")
EventSub.Size = UDim2.new(1, -20, 0, 26)
EventSub.Position = UDim2.new(0, 10, 0, 42)
EventSub.BackgroundTransparency = 1
EventSub.Text = "Día: 0 | Fase: Día | Estación: N/A"
EventSub.TextColor3 = Color3.fromRGB(180, 190, 205)
EventSub.TextSize = 10
EventSub.Font = Enum.Font.Code
EventSub.TextXAlignment = Enum.TextXAlignment.Left
EventSub.Parent = EventCard

-- Tarjeta 2: Reloj Regresivo con Alerta de 30 Segundos
local CountdownCard = Instance.new("Frame")
CountdownCard.Size = UDim2.new(1, -20, 0, 85)
CountdownCard.Position = UDim2.new(0, 10, 0, 126)
CountdownCard.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
CountdownCard.Parent = MainFrame

local CountdownCorner = Instance.new("UICorner")
CountdownCorner.CornerRadius = UDim.new(0, 8)
CountdownCorner.Parent = CountdownCard

local CountdownNumber = Instance.new("TextLabel")
CountdownNumber.Size = UDim2.new(0.48, 0, 1, 0)
CountdownNumber.Position = UDim2.new(0, 10, 0, 0)
CountdownNumber.BackgroundTransparency = 1
CountdownNumber.Text = "00:00"
CountdownNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
CountdownNumber.TextSize = 34
CountdownNumber.Font = Enum.Font.GothamBold
CountdownNumber.TextXAlignment = Enum.TextXAlignment.Left
CountdownNumber.Parent = CountdownCard

local CountdownDetail = Instance.new("TextLabel")
CountdownDetail.Size = UDim2.new(0.50, -10, 1, -12)
CountdownDetail.Position = UDim2.new(0.50, 0, 0, 6)
CountdownDetail.BackgroundTransparency = 1
CountdownDetail.Text = "Tiempo para Cambio:\nAlerta: Inactiva\nHora Solar: 00:00"
CountdownDetail.TextColor3 = Color3.fromRGB(190, 200, 215)
CountdownDetail.TextSize = 10
CountdownDetail.Font = Enum.Font.Code
CountdownDetail.TextXAlignment = Enum.TextXAlignment.Left
CountdownDetail.Parent = CountdownCard

-- Visor de Telemetría Detallada
local TelemetryBox = Instance.new("TextBox")
TelemetryBox.Size = UDim2.new(1, -20, 0, 115)
TelemetryBox.Position = UDim2.new(0, 10, 0, 218)
TelemetryBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
TelemetryBox.TextColor3 = Color3.fromRGB(220, 220, 220)
TelemetryBox.TextSize = 9
TelemetryBox.Font = Enum.Font.Code
TelemetryBox.TextXAlignment = Enum.TextXAlignment.Left
TelemetryBox.TextYAlignment = Enum.TextYAlignment.Top
TelemetryBox.ClearTextOnFocus = false
TelemetryBox.MultiLine = true
TelemetryBox.TextEditable = false
TelemetryBox.Text = "Monitoreando variables de Workspace..."
TelemetryBox.Parent = MainFrame

local TelemetryCorner = Instance.new("UICorner")
TelemetryCorner.CornerRadius = UDim.new(0, 6)
TelemetryCorner.Parent = TelemetryBox

-- Botones de Acción
local CopyReportBtn = Instance.new("TextButton")
CopyReportBtn.Size = UDim2.new(1, -20, 0, 36)
CopyReportBtn.Position = UDim2.new(0, 10, 0, 342)
CopyReportBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyReportBtn.Text = "📋 COPIAR TODOS LOS DATOS Y ATRIBUTOS TEMPORALES"
CopyReportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyReportBtn.TextSize = 10
CopyReportBtn.Font = Enum.Font.GothamBold
CopyReportBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyReportBtn

CopyReportBtn.MouseButton1Click:Connect(function()
    local text = captureAllTimeAttributes()
    if setclipboard then
        setclipboard(text)
    elseif toclipboard then
        toclipboard(text)
    end
    CopyReportBtn.Text = "✅ ¡DATOS COPIADOS AL PORTAPAPELES!"
    task.wait(1.5)
    CopyReportBtn.Text = "📋 COPIAR TODOS LOS DATOS Y ATRIBUTOS TEMPORALES"
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "⏰\nRELOJ"
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
-- 3. BUCLE DE ACTUALIZACIÓN Y DETECTOR DE 30 SEGUNDOS
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.25)
        local dayType, tagColor, countdown, day, isNight, season, lastBMDay = analyzeDayAndEvent()

        EventTitle.Text = dayType
        EventTitle.TextColor3 = tagColor
        EventSub.Text = string.format("Día Actual: %d | Fase: %s | Estación: %s | Última Luna Roja: Día %s", day, isNight and "🌙 NOCHE" or "☀️ DÍA", season, tostring(lastBMDay))

        -- Formato MM:SS
        local mins = math.floor(countdown / 60)
        local secs = math.floor(countdown % 60)
        CountdownNumber.Text = string.format("%02d:%02d", mins, secs)

        -- ALERTA CRÍTICA: 30 SEGUNDOS O MENOS
        if countdown > 0 and countdown <= 30 then
            CountdownCard.BackgroundColor3 = Color3.fromRGB(80, 20, 25)
            CountdownNumber.TextColor3 = Color3.fromRGB(255, 60, 70)
            CountdownDetail.Text = string.format("⚠️ ¡FALTAN %d SEGUNDOS!\nPrepárate para la oleada\nHora Solar: %.2f", math.floor(countdown), Lighting.ClockTime)

            -- Notificación única al cruzar la barrera de los 30s
            if (tick() - DiagnosticData.LastAlertTriggered) > 40 then
                DiagnosticData.LastAlertTriggered = tick()
                pcall(function()
                    local sound = Instance.new("Sound")
                    sound.SoundId = "rbxassetid://4590662766" -- Pitido de alerta
                    sound.Volume = 1.0
                    sound.Parent = workspace
                    sound:Play()
                    game:GetService("Debris"):AddItem(sound, 3)
                end)
            end
        else
            CountdownCard.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
            CountdownNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
            CountdownDetail.Text = string.format("Estado: Tiempo Normal\nAlerta: Inactiva (>30s)\nHora Solar: %.2f", Lighting.ClockTime)
        end

        TelemetryBox.Text = string.format(
            "• Workspace.Countdown = %s\n" ..
            "• Workspace.CurrentDay = %s | Workspace.Night = %s\n" ..
            "• Workspace.BloodMoon = %s | Workspace.BanditRaid = %s\n" ..
            "• Workspace.Blizzard = %s | Workspace.Raining = %s\n" ..
            "• Lighting.ClockTime = %.2f | TimeOfDay = %s",
            tostring(workspace:GetAttribute("Countdown") or "N/A"),
            tostring(day), tostring(isNight),
            tostring(workspace:GetAttribute("BloodMoon") or "false"),
            tostring(workspace:GetAttribute("BanditRaid") or "false"),
            tostring(workspace:GetAttribute("Blizzard") or "false"),
            tostring(workspace:GetAttribute("Raining") or "false"),
            Lighting.ClockTime,
            Lighting.TimeOfDay
        )
    end
end)
