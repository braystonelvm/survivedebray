-- ==============================================================================
-- REGISTRADOR FORENSE DE FÍSICAS & RUBBERBAND (CON SCRIPT VS SIN SCRIPT)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local Sessions = {
    ConScript = {
        Name = "PRUEBA 1: CON SCRIPT",
        Recording = false,
        StartTime = 0,
        Logs = {},
        PullbackCount = 0,
        MaxAirTime = 0
    },
    SinScript = {
        Name = "PRUEBA 2: SIN SCRIPT (MANUAL)",
        Recording = false,
        StartTime = 0,
        Logs = {},
        PullbackCount = 0,
        MaxAirTime = 0
    }
}

local ActiveSessionKey = nil
local UIStatusLabel = nil
local UICountLabels = {}

-- ==============================================================================
-- 1. UTILIDADES DE SERIALIZACIÓN Y CAPTURA DE ESTADO
-- ==============================================================================

local function fmtVec(v)
    return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function getActiveForcesSummary(char)
    if not char then return "Ninguna" end
    local found = {}
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BodyMover") or desc:IsA("Constraint") or desc:IsA("LinearVelocity") or desc:IsA("AlignPosition") then
            table.insert(found, desc.ClassName .. ":" .. desc.Name)
        end
    end
    return (#found > 0) and table.concat(found, ",") or "Ninguna"
end

local function getAttributesSummary(inst)
    if not inst then return "{}" end
    local attrs = inst:GetAttributes()
    local parts = {}
    for k, v in pairs(attrs) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    return (#parts > 0) and ("{" .. table.concat(parts, ", ") .. "}") or "{}"
end

local function appendLog(session, tag, msg)
    if not session or not session.Recording then return end
    local elapsed = tick() - session.StartTime
    local line = string.format("[t+%06.2fs] [%s] %s", elapsed, tag, msg)
    table.insert(session.Logs, line)
    if UIStatusLabel then
        UIStatusLabel.Text = line
    end
    if UICountLabels[ActiveSessionKey] then
        UICountLabels[ActiveSessionKey].Text = string.format("Eventos: %d | Jalones: %d", #session.Logs, session.PullbackCount)
    end
end

-- ==============================================================================
-- 2. MONITOR DE FÍSICAS, ESTADOS, ATRIBUTOS Y DETECCIÓN DE JALONES
-- ==============================================================================

local StateConn = nil
local FloorConn = nil
local AttrConn = nil

local function bindCharacterEvents(session)
    if StateConn then StateConn:Disconnect(); StateConn = nil end
    if FloorConn then FloorConn:Disconnect(); FloorConn = nil end
    if AttrConn then AttrConn:Disconnect(); AttrConn = nil end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not root then return end

    appendLog(session, "INIT", string.format(
        "Pos=%s | Floor=%s | WS=%.1f | JP=%.1f | Attrs=%s | Fuerzas=%s",
        fmtVec(root.Position),
        hum.FloorMaterial.Name,
        hum.WalkSpeed,
        hum.JumpPower,
        getAttributesSummary(char),
        getActiveForcesSummary(char)
    ))

    StateConn = hum.StateChanged:Connect(function(oldSt, newSt)
        if not session.Recording then return end
        local r = char:FindFirstChild("HumanoidRootPart")
        local vel = r and r.AssemblyLinearVelocity or Vector3.zero
        local pos = r and r.Position or Vector3.zero
        appendLog(session, "STATE", string.format(
            "%s -> %s | Pos=%s | Vel=%s | Floor=%s",
            oldSt.Name, newSt.Name, fmtVec(pos), fmtVec(vel), hum.FloorMaterial.Name
        ))
    end)

    FloorConn = hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
        if not session.Recording then return end
        local r = char:FindFirstChild("HumanoidRootPart")
        local pos = r and r.Position or Vector3.zero
        appendLog(session, "FLOOR", string.format(
            "FloorMaterial=%s | Pos=%s | State=%s",
            hum.FloorMaterial.Name, fmtVec(pos), hum:GetState().Name
        ))
    end)

    AttrConn = char.AttributeChanged:Connect(function(attrName)
        if not session.Recording then return end
        appendLog(session, "ATTR", string.format(
            "%s = %s", attrName, tostring(char:GetAttribute(attrName))
        ))
    end)
end

-- Bucle de muestreo continuo (detecta rubberbands en cada frame + snapshot cada 0.25s)
task.spawn(function()
    local lastPos = nil
    local lastSampleTick = 0
    local airStart = nil
    local startAnchorPos = nil

    while true do
        local dt = RunService.Heartbeat:Wait()
        if not ActiveSessionKey then
            lastPos = nil
            airStart = nil
            startAnchorPos = nil
            continue
        end

        local session = Sessions[ActiveSessionKey]
        if not session or not session.Recording then
            lastPos = nil
            airStart = nil
            startAnchorPos = nil
            continue
        end

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then continue end

        local now = tick()
        local curPos = root.Position
        local vel = root.AssemblyLinearVelocity

        if not startAnchorPos then
            startAnchorPos = curPos
        end

        -- Medir tiempo continuo en el aire (FloorMaterial == Air)
        local inAir = (hum.FloorMaterial == Enum.Material.Air)
        if inAir then
            if not airStart then
                airStart = now
            end
            local airDur = now - airStart
            if airDur > session.MaxAirTime then
                session.MaxAirTime = airDur
            end
        else
            if airStart then
                local totalAir = now - airStart
                if totalAir > 0.25 then
                    appendLog(session, "LAND", string.format("Tocó suelo tras %.2fs en aire | Pos=%s", totalAir, fmtVec(curPos)))
                end
                airStart = nil
            end
        end

        -- Detectar teletransporte o jalón repentino del servidor (Rubberband)
        if lastPos then
            local frameDelta = (curPos - lastPos).Magnitude
            local expectedMaxStep = math.max(vel.Magnitude * dt * 2.5, 4.5)
            if frameDelta > expectedMaxStep and frameDelta >= 5.0 then
                session.PullbackCount = session.PullbackCount + 1
                local airDur = airStart and (now - airStart) or 0
                local distFromStart = (curPos - startAnchorPos).Magnitude
                appendLog(session, "RUBBERBAND!", string.format(
                    "JALÓN #%d de %.1f studs! %s -> %s | TiempoEnAire=%.2fs | DistAlInicio=%.1f | Vel=%s | State=%s | Fuerzas=%s",
                    session.PullbackCount,
                    frameDelta,
                    fmtVec(lastPos),
                    fmtVec(curPos),
                    airDur,
                    distFromStart,
                    fmtVec(vel),
                    hum:GetState().Name,
                    getActiveForcesSummary(char)
                ))
            end
        end

        -- Snapshot periódico cada 0.25s para ver la curva de vuelo/salto
        if (now - lastSampleTick) >= 0.25 then
            lastSampleTick = now
            local airDur = airStart and (now - airStart) or 0
            local distHoriz = (Vector3.new(curPos.X, 0, curPos.Z) - Vector3.new(startAnchorPos.X, 0, startAnchorPos.Z)).Magnitude
            appendLog(session, "TICK", string.format(
                "Pos=%s | Vel=%s | Air=%.2fs | DistH=%.1f | State=%s | Floor=%s | Fuerzas=%s",
                fmtVec(curPos),
                fmtVec(vel),
                airDur,
                distHoriz,
                hum:GetState().Name,
                hum.FloorMaterial.Name,
                getActiveForcesSummary(char)
            ))
        end

        lastPos = curPos
    end
end)

-- ==============================================================================
-- 3. CONTROL DE GRABACIÓN Y EXPORTACIÓN AL PORTAPAPELES
-- ==============================================================================

local function startSession(key)
    -- Detener si había otra grabando
    if ActiveSessionKey and Sessions[ActiveSessionKey] then
        Sessions[ActiveSessionKey].Recording = false
    end

    local s = Sessions[key]
    s.Logs = {}
    s.PullbackCount = 0
    s.MaxAirTime = 0
    s.StartTime = tick()
    s.Recording = true
    ActiveSessionKey = key

    bindCharacterEvents(s)
end

local function stopSession(key)
    local s = Sessions[key]
    if s and s.Recording then
        appendLog(s, "STOP", string.format(
            "Grabación finalizada | Duración=%.2fs | Jalones=%d | MaxAire=%.2fs",
            tick() - s.StartTime,
            s.PullbackCount,
            s.MaxAirTime
        ))
        s.Recording = false
    end
    if ActiveSessionKey == key then
        ActiveSessionKey = nil
    end
    if StateConn then StateConn:Disconnect(); StateConn = nil end
    if FloorConn then FloorConn:Disconnect(); FloorConn = nil end
    if AttrConn then AttrConn:Disconnect(); AttrConn = nil end
end

local function buildExportReport(key)
    local s = Sessions[key]
    local header = {
        "====================================================",
        s.Name,
        string.format("Total Eventos: %d | Total Jalones (Rubberband): %d | Max Tiempo en Aire: %.2fs", #s.Logs, s.PullbackCount, s.MaxAirTime),
        "===================================================="
    }
    if #s.Logs == 0 then
        table.insert(header, "(Sin datos grabados aún)")
    else
        for _, line in ipairs(s.Logs) do
            table.insert(header, line)
        end
    end
    return table.concat(header, "\n")
end

local function copyToClipboardSafe(text)
    if setclipboard then
        setclipboard(text)
        return true
    elseif toclipboard then
        toclipboard(text)
        return true
    elseif Clipboard and Clipboard.set then
        Clipboard.set(text)
        return true
    end
    return false
end

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA FLOTANTE NATIVA (2 PANELES: CON SCRIPT Y SIN SCRIPT)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("PhysicsTelemetryRecorderGui")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PhysicsTelemetryRecorderGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.22, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(165, 55, 135)
FloatBtn.Text = "📊\nLOG"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 490, 0, 330)
MainFrame.Position = UDim2.new(0.5, -245, 0.12, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 32)
TitleBar.BackgroundColor3 = Color3.fromRGB(26, 31, 44)
TitleBar.Text = "  📊 REGISTRADOR FORENSE DE FÍSICAS (CON SCRIPT vs SIN SCRIPT)"
TitleBar.TextColor3 = Color3.fromRGB(255, 130, 220)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local function createSessionPanel(yPos, sessionKey, titleText, accentColor)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -20, 0, 102)
    card.Position = UDim2.new(0, 10, 0, yPos)
    card.BackgroundColor3 = Color3.fromRGB(21, 25, 36)
    card.Parent = MainFrame
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local lblTitle = Instance.new("TextLabel")
    lblTitle.Size = UDim2.new(0.55, 0, 0, 22)
    lblTitle.Position = UDim2.new(0, 10, 0, 6)
    lblTitle.BackgroundTransparency = 1
    lblTitle.Text = titleText
    lblTitle.TextColor3 = accentColor
    lblTitle.TextSize = 10
    lblTitle.Font = Enum.Font.GothamBold
    lblTitle.TextXAlignment = Enum.TextXAlignment.Left
    lblTitle.Parent = card

    local lblCount = Instance.new("TextLabel")
    lblCount.Size = UDim2.new(0.43, -10, 0, 22)
    lblCount.Position = UDim2.new(0.55, 0, 0, 6)
    lblCount.BackgroundTransparency = 1
    lblCount.Text = "Eventos: 0 | Jalones: 0"
    lblCount.TextColor3 = Color3.fromRGB(200, 210, 225)
    lblCount.TextSize = 9
    lblCount.Font = Enum.Font.Code
    lblCount.TextXAlignment = Enum.TextXAlignment.Right
    lblCount.Parent = card
    UICountLabels[sessionKey] = lblCount

    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(0.32, -8, 0, 32)
    playBtn.Position = UDim2.new(0, 10, 0, 32)
    playBtn.BackgroundColor3 = Color3.fromRGB(30, 155, 80)
    playBtn.Text = "▶️ PLAY"
    playBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    playBtn.TextSize = 10
    playBtn.Font = Enum.Font.GothamBold
    playBtn.Parent = card
    Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 6)

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.32, -8, 0, 32)
    stopBtn.Position = UDim2.new(0.32, 6, 0, 32)
    stopBtn.BackgroundColor3 = Color3.fromRGB(185, 45, 55)
    stopBtn.Text = "⏹️ STOP"
    stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopBtn.TextSize = 10
    stopBtn.Font = Enum.Font.GothamBold
    stopBtn.Parent = card
    Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0.36, -12, 0, 32)
    copyBtn.Position = UDim2.new(0.64, 4, 0, 32)
    copyBtn.BackgroundColor3 = Color3.fromRGB(0, 125, 200)
    copyBtn.Text = "📋 COPIAR DATOS"
    copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyBtn.TextSize = 9
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.Parent = card
    Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 6)

    local stateIndicator = Instance.new("TextLabel")
    stateIndicator.Size = UDim2.new(1, -20, 0, 22)
    stateIndicator.Position = UDim2.new(0, 10, 0, 72)
    stateIndicator.BackgroundTransparency = 1
    stateIndicator.Text = "Estado: Listo para grabar"
    stateIndicator.TextColor3 = Color3.fromRGB(150, 160, 175)
    stateIndicator.TextSize = 9
    stateIndicator.Font = Enum.Font.Code
    stateIndicator.TextXAlignment = Enum.TextXAlignment.Left
    stateIndicator.Parent = card

    playBtn.MouseButton1Click:Connect(function()
        startSession(sessionKey)
        stateIndicator.Text = "🔴 GRABANDO EN VIVO..."
        stateIndicator.TextColor3 = Color3.fromRGB(255, 95, 95)
    end)

    stopBtn.MouseButton1Click:Connect(function()
        stopSession(sessionKey)
        stateIndicator.Text = "⏹️ Detenido. Pulsa 'COPIAR DATOS' para exportar."
        stateIndicator.TextColor3 = Color3.fromRGB(120, 235, 160)
    end)

    copyBtn.MouseButton1Click:Connect(function()
        if Sessions[sessionKey].Recording then
            stopSession(sessionKey)
            stateIndicator.Text = "⏹️ Detenido y copiado."
        end
        local report = buildExportReport(sessionKey)
        local ok = copyToClipboardSafe(report)
        if ok then
            copyBtn.Text = "✅ ¡COPIADO!"
            stateIndicator.Text = string.format("✅ %d líneas copiadas al portapapeles.", #Sessions[sessionKey].Logs)
        else
            print(report)
            copyBtn.Text = "⚠️ VER CONSOLA F9"
        end
        task.wait(1.5)
        copyBtn.Text = "📋 COPIAR DATOS"
    end)
end

-- Panel 1: Con Script
createSessionPanel(40, "ConScript", "1️⃣ PRUEBA CON SCRIPT DE VUELO", Color3.fromRGB(90, 200, 255))

-- Panel 2: Sin Script (Manual)
createSessionPanel(150, "SinScript", "2️⃣ PRUEBA SIN SCRIPT (TUS SALTOS MANUALES)", Color3.fromRGB(255, 205, 80))

-- Barra inferior de telemetría en vivo
local LiveBar = Instance.new("Frame")
LiveBar.Size = UDim2.new(1, -20, 0, 58)
LiveBar.Position = UDim2.new(0, 10, 0, 260)
LiveBar.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
LiveBar.Parent = MainFrame
Instance.new("UICorner", LiveBar).CornerRadius = UDim.new(0, 6)

UIStatusLabel = Instance.new("TextLabel")
UIStatusLabel.Size = UDim2.new(1, -12, 1, -8)
UIStatusLabel.Position = UDim2.new(0, 6, 0, 4)
UIStatusLabel.BackgroundTransparency = 1
UIStatusLabel.Text = "Último evento: Esperando que pulses PLAY en una de las pruebas..."
UIStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 175)
UIStatusLabel.TextSize = 9
UIStatusLabel.Font = Enum.Font.Code
UIStatusLabel.TextWrapped = true
UIStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UIStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
UIStatusLabel.Parent = LiveBar

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
