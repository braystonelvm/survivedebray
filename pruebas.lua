-- ==============================================================================
-- RADAR FORENSE DE OLEADAS: DETECTOR DE ALERTAS DE NOCHE & REMOTES
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local SECTORS = {
    SUR = Vector3.new(0, 0, 150),
    NORTE = Vector3.new(0, 0, -150),
    ESTE = Vector3.new(150, 0, 0),
    OESTE = Vector3.new(-150, 0, 0)
}

local RadarData = {
    ActiveSector = "ESPERANDO OLEADA...",
    DetectionMethod = "Ninguno",
    LastAlertTime = "Nunca",
    ActiveAlertsCount = 0,
    Logs = {}
}

local function addLog(txt)
    local timestamp = os.date("%X")
    local entry = string.format("[%s] %s", timestamp, txt)
    table.insert(RadarData.Logs, 1, entry)
    if #RadarData.Logs > 40 then table.remove(RadarData.Logs) end
    print("[RADAR FORENSE]: " .. entry)
end

-- Determinar sector cardinal a partir de coordenadas 3D
local function resolveSectorFromVector(pos)
    local diff = pos - BaseCenter
    if math.abs(diff.Z) > math.abs(diff.X) then
        return (diff.Z < 0) and "NORTE" or "SUR"
    else
        return (diff.X > 0) and "ESTE" or "OESTE"
    end
end

-- ==============================================================================
-- 1. ESPÍA DE REMOTES EN REPLICATEDSTORAGE (AVISO INSTANTÁNEO DEL SERVIDOR)
-- ==============================================================================
task.spawn(function()
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local rName = obj.Name:lower()
            -- Filtrar remotes que puedan estar vinculados al ciclo de noche u oleadas
            if rName:find("wave") or rName:find("horde") or rName:find("night") or rName:find("alert") or rName:find("spawn") or rName:find("sector") then
                obj.OnClientEvent:Connect(function(...)
                    local args = {...}
                    local argDump = {}
                    for i, v in ipairs(args) do
                        table.insert(argDump, tostring(v))
                    end
                    local details = table.concat(argDump, ", ")
                    addLog(string.format("📡 RemoteEvent disparado: '%s' | Args: [%s]", obj.Name, details))

                    -- Intentar resolver el sector por texto en argumentos
                    local strAll = (obj.Name .. " " .. details):lower()
                    for secName, _ in pairs(SECTORS) do
                        if strAll:find(secName:lower()) then
                            RadarData.ActiveSector = secName
                            RadarData.DetectionMethod = "RemoteEvent (" .. obj.Name .. ")"
                            RadarData.LastAlertTime = os.date("%X")
                        end
                    end
                end)
            end
        end
    end
end)

-- ==============================================================================
-- 2. ESPÍA DE ALERTAS VISUALES EN PLAYERGUI (DISCRIMINA LA MÁS NUEVA)
-- ==============================================================================
local TrackedAlertInstances = {} -- [Instancia] = CreationTick

local function inspectGuiObject(obj)
    if not obj:IsA("GuiObject") and not obj:IsA("BillboardGui") then return end

    local name = obj.Name:lower()
    local isCandidate = false

    -- Detección por nombre o tipo de interfaz de alerta
    if name:find("alert") or name:find("warning") or name:find("horde") or name:find("wave") or name:find("marker") or name:find("arrow") or name:find("sign") or name:find("indicator") then
        isCandidate = true
    end

    if obj:IsA("ImageLabel") and obj.Visible then
        local img = tostring(obj.Image):lower()
        if img:find("alert") or img:find("warning") or img:find("exclamation") or img:find("arrow") then
            isCandidate = true
        end
    end

    if isCandidate and not TrackedAlertInstances[obj] then
        TrackedAlertInstances[obj] = tick()
        addLog(string.format("⚠️ Nueva Alerta en Pantalla: '%s' (%s)", obj.Name, obj.ClassName))

        -- Si es un BillboardGui, tiene una posición en el mundo real (Adornee)
        local worldPos = nil
        if obj:IsA("BillboardGui") and obj.Adornee then
            local adornee = obj.Adornee
            worldPos = adornee:IsA("BasePart") and adornee.Position or (adornee:IsA("Model") and adornee:GetPivot().Position)
        elseif obj:IsA("GuiObject") then
            -- Si tiene atributos guardados por los desarrolladores
            for _, attr in ipairs({"Position", "Target", "Gate", "Sector", "WorldPosition"}) do
                local val = obj:GetAttribute(attr)
                if typeof(val) == "Vector3" then
                    worldPos = val
                    break
                elseif type(val) == "string" and SECTORS[val:upper()] then
                    RadarData.ActiveSector = val:upper()
                    RadarData.DetectionMethod = "Attribute (" .. attr .. ")"
                    RadarData.LastAlertTime = os.date("%X")
                    return
                end
            end
        end

        if worldPos then
            local sec = resolveSectorFromVector(worldPos)
            RadarData.ActiveSector = sec
            RadarData.DetectionMethod = string.format("3D Marker (%s -> %s)", obj.Name, sec)
            RadarData.LastAlertTime = os.date("%X")
            addLog(string.format("📍 Alerta 3D localizada en: Vector3(%.1f, %.1f, %.1f) -> Sector: %s", worldPos.X, worldPos.Y, worldPos.Z, sec))
        end
    end
end

-- Monitorear nuevas alertas creadas en PlayerGui
local pGui = lp:WaitForChild("PlayerGui")
pGui.DescendantAdded:Connect(inspectGuiObject)
workspace.DescendantAdded:Connect(inspectGuiObject)

-- ==============================================================================
-- 3. GESTOR DE CONFLICTO (CUANDO HAY 2 O MÁS ALERTAS ACTIVAS)
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.2)

        local validAlerts = {}
        for inst, birthTime in pairs(TrackedAlertInstances) do
            if inst.Parent and (inst:IsA("GuiObject") and inst.Visible or inst:IsA("BillboardGui") and inst.Enabled) then
                table.insert(validAlerts, { Instance = inst, Time = birthTime, Age = tick() - birthTime })
            else
                TrackedAlertInstances[inst] = nil
            end
        end

        RadarData.ActiveAlertsCount = #validAlerts

        -- Si hay múltiples alertas en pantalla, ordenamos por la MÁS NUEVA
        if #validAlerts > 1 then
            table.sort(validAlerts, function(a, b) return a.Time > b.Time end)
            local newest = validAlerts[1]
            local oldest = validAlerts[2]

            -- Si la alerta más nueva tiene menos de 4 segundos de vida, la tomamos como la activa
            if newest.Age <= 4.0 then
                -- Inspeccionar texto o etiquetas dentro de la nueva alerta
                for _, desc in ipairs(newest.Instance:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Text ~= "" then
                        local txt = desc.Text:upper()
                        for sName, _ in pairs(SECTORS) do
                            if txt:find(sName) then
                                RadarData.ActiveSector = sName
                                RadarData.DetectionMethod = "Alerta Más Reciente (Text: " .. desc.Text .. ")"
                                RadarData.LastAlertTime = os.date("%X")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ==============================================================================
-- 4. INTERFAZ VISUAL NATIVA (PANEL DE MONITOREO Y COPIA)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NightRadarDiagnosticsGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante Rojo
local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(1, 0)
BtnCorner.Parent = FloatBtn

local BtnIcon = Instance.new("TextLabel")
BtnIcon.Size = UDim2.new(1, 0, 1, 0)
BtnIcon.BackgroundTransparency = 1
BtnIcon.Text = "📡"
BtnIcon.TextSize = 22
BtnIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnIcon.Parent = FloatBtn

-- Ventana Principal
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 460, 0, 380)
MainFrame.Position = UDim2.new(0.5, -230, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
TitleBar.Text = "  RADAR FORENSE: ANALIZADOR DE OLEADAS DE NOCHE"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 12
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel de Estado Principal
local StatusPanel = Instance.new("TextLabel")
StatusPanel.Size = UDim2.new(1, -20, 0, 80)
StatusPanel.Position = UDim2.new(0, 10, 0, 44)
StatusPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
StatusPanel.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusPanel.TextSize = 11
StatusPanel.Font = Enum.Font.Code
StatusPanel.TextXAlignment = Enum.TextXAlignment.Left
StatusPanel.TextYAlignment = Enum.TextYAlignment.Top
StatusPanel.Text = " Inicializando sensores de noche..."
StatusPanel.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusPanel

-- Registro de Eventos en Vivo
local LogBox = Instance.new("TextBox")
LogBox.Size = UDim2.new(1, -20, 0, 180)
LogBox.Position = UDim2.new(0, 10, 0, 132)
LogBox.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
LogBox.TextColor3 = Color3.fromRGB(200, 200, 200)
LogBox.TextSize = 10
LogBox.Font = Enum.Font.Code
LogBox.TextXAlignment = Enum.TextXAlignment.Left
LogBox.TextYAlignment = Enum.TextYAlignment.Top
LogBox.ClearTextOnFocus = false
LogBox.MultiLine = true
LogBox.TextEditable = false
LogBox.Text = "Esperando que comience la noche o cambie la oleada..."
LogBox.Parent = MainFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogBox

-- Botón Copiar Informe
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 324)
CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 160)
CopyBtn.Text = "📋 COPIAR REPORTE AL PORTAPAPELES"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local report = {
        "=== REPORTE DE DETECCIÓN DE OLEADA DE NOCHE ===",
        "Sector detectado: " .. RadarData.ActiveSector,
        "Método de detección: " .. RadarData.DetectionMethod,
        "Hora de alerta: " .. RadarData.LastAlertTime,
        "Alertas simultáneas en pantalla: " .. RadarData.ActiveAlertsCount,
        "\n[REGISTRO DE EVENTOS]:"
    }
    for _, l in ipairs(RadarData.Logs) do table.insert(report, l) end
    local fullText = table.concat(report, "\n")
    if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end
    CopyBtn.Text = "✅ ¡REPORTE COPIADO!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR REPORTE AL PORTAPAPELES"
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- Bucle de actualización en tiempo real
task.spawn(function()
    while true do
        task.wait(0.3)
        StatusPanel.Text = string.format(
            " 🚨 SECTOR ACTIVO: %s\n Método: %s\n Hora del evento: %s\n Alertas simultáneas detectadas: %d",
            RadarData.ActiveSector,
            RadarData.DetectionMethod,
            RadarData.LastAlertTime,
            RadarData.ActiveAlertsCount
        )

        LogBox.Text = table.concat(RadarData.Logs, "\n")
    end
end)

print("[RADAR FORENSE]: Cargado con éxito.")
