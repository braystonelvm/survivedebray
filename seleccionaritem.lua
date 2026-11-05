-- ==============================================================================
-- INSPECTOR FORENSE DE APUNTADO: TECLA [0] / TÁCTIL (TODO VS ESPECÍFICO)
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local CurrentInspected = nil
local InspectHighlight = nil
local InspectMode = "Todo" -- "Todo" (Modelo raíz) | "Especifico" (Parte exacta)

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local function clearHighlight()
    if InspectHighlight then
        InspectHighlight:Destroy()
        InspectHighlight = nil
    end
end

local function applyInspectHighlight(obj)
    clearHighlight()
    if obj then
        InspectHighlight = Instance.new("Highlight")
        InspectHighlight.Name = "ScrapInspectHighlight"
        InspectHighlight.Adornee = obj
        InspectHighlight.FillColor = (InspectMode == "Todo") and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 200, 255)
        InspectHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        InspectHighlight.FillTransparency = 0.35
        InspectHighlight.OutlineTransparency = 0
        InspectHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        InspectHighlight.Parent = CoreGui
    end
end

-- Busca el modelo superior relevante (Modo: Todo)
local function getTargetModel(targetPart)
    if not targetPart then return nil end
    local current = targetPart
    local bestModel = nil

    while current and current ~= workspace do
        if current:IsA("Model") and current ~= lp.Character then
            bestModel = current
        end
        current = current.Parent
    end

    return bestModel or targetPart
end

-- ==============================================================================
-- 1. EXTRACCIÓN DE METADATOS Y REPORTE
-- ==============================================================================

local function generateReport(target, rawHitPart)
    if not target then
        return "⚠️ No estás apuntando a ningún objeto en el mapa."
    end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local myPos = root and root.Position or Vector3.zero

    local part = target:IsA("BasePart") and target or (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart"))
    local tPos = part and part.Position or Vector3.zero
    local dist = math.floor((tPos - myPos).Magnitude)

    local modeLabel = (InspectMode == "Todo") and "TODO (MODELO RAÍZ COMPLETO)" or "ESPECÍFICO (PARTE / ÍTEM EXACTO)"

    local lines = {
        "==================================================================",
        string.format("       REPORTE DE INSPECCIÓN | MODO: %s", modeLabel),
        "==================================================================",
        string.format("📌 Nombre: '%s' | Clase: %s", target.Name, target.ClassName),
        string.format("📍 Ruta: %s", target:GetFullName())
    }

    if InspectMode == "Especifico" and rawHitPart and rawHitPart.Parent then
        table.insert(lines, string.format("📂 Padre Directo: '%s' (%s)", rawHitPart.Parent.Name, rawHitPart.Parent.ClassName))
    end

    table.insert(lines, string.format("📏 Distancia: %d studs | Posición: Vector3.new(%.1f, %.1f, %.1f)", dist, tPos.X, tPos.Y, tPos.Z))

    -- 1. Atributos
    table.insert(lines, "\n[1. ATRIBUTOS DEL SERVIDOR]:")
    local attrs = {}
    for k, v in pairs(target:GetAttributes()) do
        table.insert(attrs, string.format("%s = %s", tostring(k), tostring(v)))
    end

    -- Si está en específico y no tiene atributos directos, revisar los del padre inmediato
    if #attrs == 0 and InspectMode == "Especifico" and rawHitPart and rawHitPart.Parent then
        for k, v in pairs(rawHitPart.Parent:GetAttributes()) do
            table.insert(attrs, string.format("(De Padre) %s = %s", tostring(k), tostring(v)))
        end
    end

    if #attrs > 0 then
        table.insert(lines, "   • " .. table.concat(attrs, "\n   • "))
    else
        table.insert(lines, "   (Sin atributos directos)")
    end

    -- 2. Descendientes / Detectores
    table.insert(lines, "\n[2. DETECTORES & COMPONENTES]:")
    local comps = {}

    local function checkComponent(desc)
        if desc:IsA("ProximityPrompt") then
            table.insert(comps, string.format("ProximityPrompt('%s' | Action: '%s' | Enabled: %s)", desc.Name, desc.ActionText, tostring(desc.Enabled)))
        elseif desc:IsA("ClickDetector") then
            table.insert(comps, string.format("ClickDetector('%s' | MaxDist: %d)", desc.Name, desc.MaxActivationDistance))
        elseif desc:IsA("DragDetector") or desc.Name == "ItemDrag" then
            table.insert(comps, string.format("%s('%s')", desc.ClassName, desc.Name))
        elseif desc:IsA("ValueBase") then
            table.insert(comps, string.format("%s('%s' = %s)", desc.ClassName, desc.Name, tostring(desc.Value)))
        elseif desc:IsA("Humanoid") then
            table.insert(comps, string.format("Humanoid(HP: %.0f / %.0f)", desc.Health, desc.MaxHealth))
        elseif desc:IsA("VehicleSeat") or desc.Name == "DriveSeat" then
            table.insert(comps, string.format("VehicleSeat('%s')", desc.Name))
        end
    end

    -- Buscar en el propio target y en sus hijos/descendientes
    for _, desc in ipairs(target:GetDescendants()) do
        checkComponent(desc)
    end
    for _, child in ipairs(target:GetChildren()) do
        checkComponent(child)
    end

    -- Si es específico, comprobar si el padre tiene ItemDrag asociado
    if InspectMode == "Especifico" and rawHitPart and rawHitPart.Parent then
        local pDrag = rawHitPart.Parent:FindFirstChild("ItemDrag")
        if pDrag then
            table.insert(comps, string.format("(En Padre) %s('%s')", pDrag.ClassName, pDrag.Name))
        end
    end

    if #comps > 0 then
        table.insert(lines, "   • " .. table.concat(comps, "\n   • "))
    else
        table.insert(lines, "   (No contiene detectores ni prompts interactivos)")
    end

    -- 3. Físicas
    table.insert(lines, "\n[3. PROPIEDADES FÍSICAS]:")
    if part then
        table.insert(lines, string.format("   • Tamaño: (%.1f, %.1f, %.1f)", part.Size.X, part.Size.Y, part.Size.Z))
        table.insert(lines, string.format("   • Masa: %.2f", part:GetMass()))
        table.insert(lines, string.format("   • Material: %s | CanCollide: %s | Anchored: %s", tostring(part.Material.Name), tostring(part.CanCollide), tostring(part.Anchored)))
        table.insert(lines, string.format("   • Velocidad Lineal: (%.1f, %.1f, %.1f)", part.AssemblyLinearVelocity.X, part.AssemblyLinearVelocity.Y, part.AssemblyLinearVelocity.Z))
    end

    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 2. INTERFAZ GRÁFICA DEL INSPECTOR
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ScrapInspectorDualModeGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 490, 0, 420)
MainFrame.Position = UDim2.new(0.5, -245, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "   🔍 INSPECTOR DUAL: TODO / ESPECÍFICO | TECLA [0]"
TitleBar.TextColor3 = Color3.fromRGB(255, 215, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 265)
OutputBox.Position = UDim2.new(0, 10, 0, 44)
OutputBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
OutputBox.TextColor3 = Color3.fromRGB(225, 225, 225)
OutputBox.TextSize = 10
OutputBox.Font = Enum.Font.Code
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextEditable = false
OutputBox.Text = "Apunta con el mouse a cualquier objeto y presiona [0] o el botón INSPECCIONAR..."
OutputBox.Parent = MainFrame

local OutputCorner = Instance.new("UICorner")
OutputCorner.CornerRadius = UDim.new(0, 6)
OutputCorner.Parent = OutputBox

-- Botón 1: Selector de Modo (Todo / Específico)
local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(1, -20, 0, 32)
ModeBtn.Position = UDim2.new(0, 10, 0, 318)
ModeBtn.BackgroundColor3 = Color3.fromRGB(190, 140, 20)
ModeBtn.Text = "MODO: SELECCIONAR TODO EN SÍ (MODELO RAÍZ)"
ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeBtn.TextSize = 10
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.Parent = MainFrame

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 6)
ModeCorner.Parent = ModeBtn

-- Botón 2: Copiar Datos
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -5, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 360)
CopyBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
CopyBtn.Text = "📋 COPIAR DATOS"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

-- Botón 3: Disparar Inspección Manual
local ScanNowBtn = Instance.new("TextButton")
ScanNowBtn.Size = UDim2.new(0.48, -5, 0, 36)
ScanNowBtn.Position = UDim2.new(0.52, 0, 0, 360)
ScanNowBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
ScanNowBtn.Text = "🎯 INSPECCIONAR [0]"
ScanNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanNowBtn.TextSize = 10
ScanNowBtn.Font = Enum.Font.GothamBold
ScanNowBtn.Parent = MainFrame

local ScanNowCorner = Instance.new("UICorner")
ScanNowCorner.CornerRadius = UDim.new(0, 6)
ScanNowCorner.Parent = ScanNowBtn

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 50, 0, 50)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(210, 150, 20)
FloatBtn.Text = "🎯\n[0]"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 11
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

-- ==============================================================================
-- 3. LÓGICA DE CONTROL Y ACTIVACIÓN
-- ==============================================================================

-- Alternar modo Todo / Específico
ModeBtn.MouseButton1Click:Connect(function()
    if InspectMode == "Todo" then
        InspectMode = "Especifico"
        ModeBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 200)
        ModeBtn.Text = "MODO: SELECCIONAR ESPECÍFICO (PARTE / ÍTEM EXACTO)"
    else
        InspectMode = "Todo"
        ModeBtn.BackgroundColor3 = Color3.fromRGB(190, 140, 20)
        ModeBtn.Text = "MODO:
