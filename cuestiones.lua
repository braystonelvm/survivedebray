-- ==============================================================================
-- REGISTRADOR FORENSE DE DÍAS Y EVENTOS (0% LAG - ACCIONADO POR EVENTOS)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

-- Eliminar cualquier rastro de desenfoque
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

local DayHistory = {}
local TotalRecorded = 0
local LastLoggedDay = -1
local LastPhaseLogged = ""

-- ==============================================================================
-- 1. DETECTOR ULTRA-LIGERO DE MULTIPLICADOR (SOLO CUANDO CAMBIA EL DÍA)
-- ==============================================================================

local function getMultiplierFast()
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        -- Buscar solo en carteles visibles de nivel superior sin recorrer todo en profundidad
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled then
                for _, el in ipairs(gui:GetChildren()) do
                    if el:IsA("TextLabel") and el.Visible then
                        local m = el.Text:match("x(%d+)")
                        if m then return tonumber(m) end
                    end
                end
            end
        end
    end

    local diff = workspace:GetAttribute("PlayerDifficulty")
    if diff and type(diff) == "number" then return diff end
    return 1
end

-- ==============================================================================
-- 2. REGISTRADOR AUTOMÁTICO DE EVENTOS (SNAPSHOT)
-- ==============================================================================

local function logDaySnapshot(triggerReason)
    local ws = workspace
    local curDay = ws:GetAttribute("CurrentDay") or 0
    local isNight = ws:GetAttribute("Night")
    if isNight == nil then
        isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
    end

    local phaseKey = string.format("%d_%s", curDay, isNight and "Noche" or "Dia")
    if phaseKey == LastPhaseLogged then return end
    LastPhaseLogged = phaseKey
    LastLoggedDay = curDay
    TotalRecorded = TotalRecorded + 1

    local isBM = ws:GetAttribute("BloodMoon") == true
    local isRaid = ws:GetAttribute("BanditRaid") == true
    local isBlizz = ws:GetAttribute("Blizzard") == true
    local isRain = ws:GetAttribute("Raining") == true
    local lastBM = ws:GetAttribute("LastBloodMoonDay") or "N/A"
    local season = tostring(ws:GetAttribute("Season") or "N/A")
    local mult = getMultiplierFast()
    local timeOfDay = string.format("%.2f", Lighting.ClockTime)

    local eventName = "Normal"
    if isBM then
        eventName = "🔴 LUNA ROJA"
    elseif isRaid then
        eventName = "🤠 BANDIDOS"
    elseif isBlizz then
        eventName = "❄️ VENTISCA"
    elseif isRain then
        eventName = "🌧️ LLUVIA"
    end

    local entry = {
        Index = TotalRecorded,
        RealTime = os.date("%X"),
        Day = curDay,
        Phase = isNight and "🌙 NOCHE" or "☀️ DÍA",
        Event = eventName,
        Multiplier = mult,
        LastBMDay = lastBM,
        Season = season,
        ClockTime = timeOfDay,
        Trigger = triggerReason or "Auto"
    }

    table.insert(DayHistory, 1, entry)
    if #DayHistory > 60 then table.remove(DayHistory) end
end

-- ==============================================================================
-- 3. ESCUCHA EXCLUSIVA POR EVENTOS (CERO LAG: NO USA BUCLES PESADOS)
-- ==============================================================================

workspace:GetAttributeChangedSignal("CurrentDay"):Connect(function()
    task.wait(0.5)
    logDaySnapshot("Cambio de Día")
end)

workspace:GetAttributeChangedSignal("Night"):Connect(function()
    task.wait(0.5)
    logDaySnapshot("Cambio de Fase (Día/Noche)")
end)

workspace:GetAttributeChangedSignal("BloodMoon"):Connect(function()
    task.wait(0.2)
    logDaySnapshot("Activación Luna Roja")
end)

workspace:GetAttributeChangedSignal("BanditRaid"):Connect(function()
    task.wait(0.2)
    logDaySnapshot("Activación Bandidos")
end)

-- Snapshot inicial al cargar
task.spawn(function()
    task.wait(1.5)
    logDaySnapshot("Inicio de Script")
end)

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA ULTRA-LIVIANA
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DayLoggerZeroLagGui"
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
TitleBar.Text = "  📅 REGISTRADOR DE DÍAS Y EVENTOS (0% LAG)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel de Estado Actual
local CurrentStatusLabel = Instance.new("TextLabel")
CurrentStatusLabel.Size = UDim2.new(1, -20, 0, 58)
CurrentStatusLabel.Position = UDim2.new(0, 10, 0, 44)
CurrentStatusLabel.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
CurrentStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 170)
CurrentStatusLabel.TextSize = 11
CurrentStatusLabel.Font = Enum.Font.Code
CurrentStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
CurrentStatusLabel.Text = "Esperando eventos del juego..."
CurrentStatusLabel.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = CurrentStatusLabel

-- Historial
local HistoryBox = Instance.new("TextBox")
HistoryBox.Size = UDim2.new(1, -20, 0, 220)
HistoryBox.Position = UDim2.new(0, 10, 0, 110)
HistoryBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
HistoryBox.TextColor3 = Color3.fromRGB(220, 220, 220)
HistoryBox.TextSize = 9
HistoryBox.Font = Enum.Font.Code
HistoryBox.TextXAlignment = Enum.TextXAlignment.Left
HistoryBox.TextYAlignment = Enum.TextYAlignment.Top
HistoryBox.MultiLine = true
HistoryBox.ClearTextOnFocus = false
HistoryBox.TextEditable = false
HistoryBox.Text = "(El historial de cada día transcurrido aparecerá aquí...)"
HistoryBox.Parent = MainFrame

local HistoryCorner = Instance.new("UICorner")
HistoryCorner.CornerRadius = UDim.new(0, 6)
HistoryCorner.Parent = HistoryBox

-- Botones
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.68, -8, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 340)
CopyBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyBtn.Text = "📋 COPIAR HISTORIAL COMPLETO"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

local function compileReport()
    local lines = {
        "==================================================================",
        "          HISTORIAL DE DÍAS Y EVENTOS REGISTRADOS                 ",
        "==================================================================",
        string.format("Fecha de Extracción: %s", os.date("%Y-%m-%d %X")),
        string.format("Total de Registros Capturados: %d", #DayHistory),
        "\n[CRONOLOGÍA DE DÍAS Y NOCHES TRANSCURRIDAS]:"
    }

    if #DayHistory == 0 then
        table.insert(lines, "  (Sin eventos registrados aún)")
    else
        for i = #DayHistory, 1, -1 do
            local e = DayHistory[i]
            table.insert(lines, string.format(
                "• [%s] Día: %d (x%d) | %s | Evento: %s | LastBloodMoon: %s | Clima/Estación: %s | Hora: %s",
                e.RealTime, e.Day, e.Multiplier, e.Phase, e.Event, tostring(e.LastBMDay), e.Season, e.ClockTime
            ))
        end
    end

    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

CopyBtn.MouseButton1Click:Connect(function()
    local text = compileReport()
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡HISTORIAL COPIADO!"
    task.wait(1.2)
    CopyBtn.Text = "📋 COPIAR HISTORIAL COMPLETO"
end)

local ResetBtn = Instance.new("TextButton")
ResetBtn.Size = UDim2.new(0.32, -6, 0, 36)
ResetBtn.Position = UDim2.new(0.68, 4, 0, 340)
ResetBtn.BackgroundColor3 = Color3.fromRGB(140, 35, 40)
ResetBtn.Text = "🗑️ LIMPIAR"
ResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetBtn.TextSize = 10
ResetBtn.Font = Enum.Font.GothamBold
ResetBtn.Parent = MainFrame

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 6)
ResetCorner.Parent = ResetBtn

ResetBtn.MouseButton1Click:Connect(function()
    table.clear(DayHistory)
    TotalRecorded = 0
    HistoryBox.Text = "(Historial reiniciado)"
    ResetBtn.Text = "✅ LISTO"
    task.wait(0.8)
    ResetBtn.Text = "🗑️ LIMPIAR"
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "📅\nDIAS"
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
-- 5. BUCLE DE TEXTO DE BAJA FRECUENCIA (1s - ACTUALIZACIÓN SENCILLA)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(1.0)
        local curDay = workspace:GetAttribute("CurrentDay") or 0
        local isNight = workspace:GetAttribute("Night")
        if isNight == nil then
            isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
        end
        local countdown = math.floor(tonumber(workspace:GetAttribute("Countdown") or 0) or 0)

        CurrentStatusLabel.Text = string.format(
            " DÍA ACTUAL: %d  |  FASE: %s  |  RELOJ: %02d:%02d\n" ..
            " Eventos Registrados: %d  |  Último Guardado: Día %d",
            curDay, isNight and "🌙 NOCHE" or "☀️ DÍA",
            math.floor(countdown / 60), countdown % 60,
            #DayHistory, LastLoggedDay
        )

        if #DayHistory > 0 then
            local lines = {}
            for i = 1, math.min(8, #DayHistory) do
                local e = DayHistory[i]
                table.insert(lines, string.format("[%s] Día %d (%s) -> %s (LastBM: %s)", e.RealTime, e.Day, e.Phase, e.Event, tostring(e.LastBMDay)))
            end
            HistoryBox.Text = table.concat(lines, "\n")
        end
    end
end)
