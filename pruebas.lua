-- ==============================================================================
-- ESCÁNER FORENSE PROFUNDO DE OLEADAS Y NOCHES (DUMP COMPLETO)xd
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local DumpLogs = {}

local function addLog(txt)
    local entry = string.format("[%s] %s", os.date("%X"), txt)
    table.insert(DumpLogs, 1, entry)
    if #DumpLogs > 50 then table.remove(DumpLogs) end
    print(entry)
end

-- ==============================================================================
-- 1. INSPECCIÓN GENERAL DE VARIABLES, TIEMPO Y ATRIBUTOS
-- ==============================================================================
local function getGlobalGameState()
    local report = {}
    table.insert(report, string.format("Reloj Lighting (Hora): %.2f (%s)", Lighting.ClockTime, Lighting.TimeOfDay))

    -- Atributos en Lighting
    for k, v in pairs(Lighting:GetAttributes()) do
        table.insert(report, string.format("Lighting [Attr]: %s = %s", k, tostring(v)))
    end

    -- Atributos en ReplicatedStorage
    for k, v in pairs(ReplicatedStorage:GetAttributes()) do
        table.insert(report, string.format("ReplicatedStorage [Attr]: %s = %s", k, tostring(v)))
    end

    -- Values dentro de ReplicatedStorage
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("ValueBase") then
            local n = desc.Name:lower()
            if n:find("wave") or n:find("night") or n:find("time") or n:find("day") or n:find("state") or n:find("horde") then
                table.insert(report, string.format("RS Value: %s = %s", desc:GetFullName(), tostring(desc.Value)))
            end
        end
    end

    -- Atributos en Workspace
    for k, v in pairs(workspace:GetAttributes()) do
        table.insert(report, string.format("Workspace [Attr]: %s = %s", k, tostring(v)))
    end

    return report
end

-- ==============================================================================
-- 2. RASTREO PROFUNDO DE ESE ICONO (!) EN WORKSPACE Y PLAYERGUI
-- ==============================================================================
local function findActiveAlertObjects()
    local found = {}

    -- A) RASTREO EN WORKSPACE (BillboardGuis en 3D)
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BillboardGui") and desc.Enabled then
            local p = desc.Parent
            local adornee = desc.Adornee or p
            local pos = adornee and (adornee:IsA("BasePart") and adornee.Position or (adornee:IsA("Model") and adornee:GetPivot().Position)) or Vector3.zero
            table.insert(found, {
                Type = "BillboardGui en Workspace",
                Name = desc.Name,
                FullName = desc:GetFullName(),
                WorldPos = pos,
                Details = string.format("Adornee: %s | Pos: Vector3(%.1f, %.1f, %.1f)", tostring(adornee), pos.X, pos.Y, pos.Z)
            })
        end
    end

    -- B) RASTREO EN PLAYERGUI (ScreenGuis activas)
    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, desc in ipairs(pGui:GetDescendants()) do
            if desc:IsA("ImageLabel") and desc.Visible and desc.Image ~= "" then
                local img = desc.Image:lower()
                local name = desc.Name:lower()
                -- Si tiene nombre o imagen sospechosa de alerta
                if name:find("alert") or name:find("warn") or name:find("icon") or name:find("horde") or name:find("wave") or name:find("marker") or img:find("rbxassetid") then
                    local parentName = desc.Parent and desc.Parent.Name or ""
                    table.insert(found, {
                        Type = "ImageLabel en PlayerGui",
                        Name = desc.Name,
                        FullName = desc:GetFullName(),
                        WorldPos = Vector3.zero,
                        Details = string.format("Image: %s | Parent: %s | Size: %s", desc.Image, parentName, tostring(desc.Size))
                    })
                end
            elseif desc:IsA("TextLabel") and desc.Visible and (desc.Text:find("!") or desc.Text:lower():find("wave") or desc.Text:lower():find("horde")) then
                table.insert(found, {
                    Type = "TextLabel en PlayerGui",
                    Name = desc.Name,
                    FullName = desc:GetFullName(),
                    WorldPos = Vector3.zero,
                    Details = string.format("Text: '%s'", desc.Text)
                })
            end
        end
    end

    return found
end

-- ==============================================================================
-- 3. VIGILANCIA EN VIVO (HOOKS DE VISIBILIDAD)
-- ==============================================================================
task.spawn(function()
    local pGui = lp:WaitForChild("PlayerGui")
    for _, desc in ipairs(pGui:GetDescendants()) do
        if desc:IsA("GuiObject") then
            desc:GetPropertyChangedSignal("Visible"):Connect(function()
                if desc.Visible then
                    local n = desc.Name:lower()
                    if n:find("alert") or n:find("warn") or n:find("horde") or n:find("icon") or n:find("wave") then
                        addLog(string.format("🟢 Cambio a Visible: %s (%s)", desc.Name, desc:GetFullName()))
                    end
                end
            end)
        elseif desc:IsA("BillboardGui") then
            desc:GetPropertyChangedSignal("Enabled"):Connect(function()
                if desc.Enabled then
                    addLog(string.format("🟢 Billboard Activado: %s (%s)", desc.Name, desc:GetFullName()))
                end
            end)
        end
    end
end)

-- ==============================================================================
-- 4. INTERFAZ NATIVA
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DeepForensicDumpGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

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
BtnIcon.Text = "🔬"
BtnIcon.TextSize = 22
BtnIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnIcon.Parent = FloatBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 440)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
TitleBar.Text = "  INSPECTOR PROFUNDO: DETECTOR DEL ICONO (!) Y NOCHE"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 12
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusPanel = Instance.new("TextLabel")
StatusPanel.Size = UDim2.new(1, -20, 0, 65)
StatusPanel.Position = UDim2.new(0, 10, 0, 42)
StatusPanel.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
StatusPanel.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusPanel.TextSize = 11
StatusPanel.Font = Enum.Font.Code
StatusPanel.TextXAlignment = Enum.TextXAlignment.Left
StatusPanel.TextYAlignment = Enum.TextYAlignment.Top
StatusPanel.Text = " Analizando objetos en vivo..."
StatusPanel.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusPanel

local LogBox = Instance.new("TextBox")
LogBox.Size = UDim2.new(1, -20, 0, 235)
LogBox.Position = UDim2.new(0, 10, 0, 114)
LogBox.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
LogBox.TextColor3 = Color3.fromRGB(220, 220, 220)
LogBox.TextSize = 10
LogBox.Font = Enum.Font.Code
LogBox.TextXAlignment = Enum.TextXAlignment.Left
LogBox.TextYAlignment = Enum.TextYAlignment.Top
LogBox.ClearTextOnFocus = false
LogBox.MultiLine = true
LogBox.TextEditable = false
LogBox.Text = "Presiona 'VOLCADO COMPLETO' cuando aparezca el icono (!) en pantalla..."
LogBox.Parent = MainFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogBox

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -10, 0, 36)
ScanBtn.Position = UDim2.new(0, 10, 0, 390)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 70)
ScanBtn.Text = "🔍 FORZAR ESCANEO"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 11
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

local ScanCorner = Instance.new("UICorner")
ScanCorner.CornerRadius = UDim.new(0, 6)
ScanCorner.Parent = ScanBtn

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 36)
CopyBtn.Position = UDim2.new(0.52, 5, 0, 390)
CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 160)
CopyBtn.Text = "📋 COPIAR VOLCADO COMPLETO"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

local function generateFullDump()
    local dump = {
        "==================================================================",
        "               VOLCADO FORENSE COMPLETO DE LA NOCHE               ",
        "==================================================================",
        "Hora local: " .. os.date("%X"),
        "\n[1. ESTADO GLOBAL Y VARIABLES]:"
    }

    local globals = getGlobalGameState()
    for _, g in ipairs(globals) do table.insert(dump, " • " .. g) end

    table.insert(dump, "\n[2. OBJETOS DE ALERTA ACTIVOS DETECTADOS]:")
    local alerts = findActiveAlertObjects()
    if #alerts == 0 then
        table.insert(dump, " • Ninguna alerta visible detectada con filtros comunes.")
    else
        for i, a in ipairs(alerts) do
            table.insert(dump, string.format(" [%d] %s (%s)", i, a.Name, a.Type))
            table.insert(dump, "     Ruta: " .. a.FullName)
            table.insert(dump, "     Info: " .. a.Details)
        end
    end

    table.insert(dump, "\n[3. HISTORIAL DE EVENTOS RECIENTES]:")
    for _, l in ipairs(DumpLogs) do table.insert(dump, " " .. l) end
    table.insert(dump, "==================================================================")

    return table.concat(dump, "\n")
end

ScanBtn.MouseButton1Click:Connect(function()
    local alerts = findActiveAlertObjects()
    addLog(string.format("Escaneo manual: %d objetos candidatos encontrados.", #alerts))
    local text = generateFullDump()
    LogBox.Text = text
end)

CopyBtn.MouseButton1Click:Connect(function()
    local text = generateFullDump()
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR VOLCADO COMPLETO"
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- Monitoreo continuo
task.spawn(function()
    while true do
        task.wait(0.5)
        local alerts = findActiveAlertObjects()
        StatusPanel.Text = string.format(
            " Hora Lighting: %.2f (%s)\n Alertas/Iconos Activos Detectados: %d\n Presiona 'COPIAR VOLCADO COMPLETO' mientras ves el icono en pantalla.",
            Lighting.ClockTime, Lighting.TimeOfDay, #alerts
        )
    end
end)
