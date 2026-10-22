-- ==============================================================================
-- INSPECTOR FORENSE DE APUNTADO: TECLA [0] / TÁCTIL (SCRAP PILES & AUTOS)
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local CurrentInspected = nil
local InspectHighlight = nil

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
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
        InspectHighlight.FillColor = Color3.fromRGB(255, 220, 0)
        InspectHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        InspectHighlight.FillTransparency = 0.35
        InspectHighlight.OutlineTransparency = 0
        InspectHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        InspectHighlight.Parent = CoreGui
    end
end

-- Busca el modelo superior relevante (evita partes individuales descontextualizadas)
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

local function generateReport(target)
    if not target then
        return "⚠️ No estás apuntando a ningún objeto en el mapa."
    end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local myPos = root and root.Position or Vector3.zero

    local part = target:IsA("BasePart") and target or (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart"))
    local tPos = part and part.Position or Vector3.zero
    local dist = math.floor((tPos - myPos).Magnitude)

    local lines = {
        "==================================================================",
        "             REPORTE DE OBJETO SELECCIONADO CON TECLA [0]         ",
        "==================================================================",
        string.format("📌 Nombre: '%s' | Clase: %s", target.Name, target.ClassName),
        string.format("📍 Ruta: %s", target:GetFullName()),
        string.format("📏 Distancia: %d studs | Posición: Vector3.new(%.1f, %.1f, %.1f)", dist, tPos.X, tPos.Y, tPos.Z),
        "\n[1. ATRIBUTOS DEL SERVIDOR]:"
    }

    local attrs = {}
    for k, v in pairs(target:GetAttributes()) do
        table.insert(attrs, string.format("%s = %s", tostring(k), tostring(v)))
    end
    if #attrs > 0 then
        table.insert(lines, "   • " .. table.concat(attrs, "\n   • "))
    else
        table.insert(lines, "   (Sin atributos directos en el modelo)")
    end

    lines[#lines + 1] = "\n[2. DESCENDIENTES CLAVE & COMPONENTES]:"
    local comps = {}
    for _, desc in ipairs(target:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            table.insert(comps, string.format("ProximityPrompt('%s' | Action: '%s' | Enabled: %s)", desc.Name, desc.ActionText, tostring(desc.Enabled)))
        elseif desc:IsA("ClickDetector") then
            table.insert(comps, string.format("ClickDetector('%s' | MaxDist: %d)", desc.Name, desc.MaxActivationDistance))
        elseif desc:IsA("ValueBase") then
            table.insert(comps, string.format("%s('%s' = %s)", desc.ClassName, desc.Name, tostring(desc.Value)))
        elseif desc:IsA("Humanoid") then
            table.insert(comps, string.format("Humanoid(HP: %.0f / %.0f)", desc.Health, desc.MaxHealth))
        elseif desc:IsA("VehicleSeat") or desc.Name == "DriveSeat" then
            table.insert(comps, string.format("VehicleSeat('%s')", desc.Name))
        end
    end

    if #comps > 0 then
        table.insert(lines, "   • " .. table.concat(comps, "\n   • "))
    else
        table.insert(lines, "   (No contiene prompts ni valores interactivos)")
    end

    lines[#lines + 1] = "\n[3. PROPIEDADES FÍSICAS DE LA PARTE PRINCIPAL]:"
    if part then
        table.insert(lines, string.format("   • Tamaño: (%.1f, %.1f, %.1f)", part.Size.X, part.Size.Y, part.Size.Z))
        table.insert(lines, string.format("   • Material: %s | CanCollide: %s | Anchored: %s", tostring(part.Material.Name), tostring(part.CanCollide), tostring(part.Anchored)))
    end

    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 2. INTERFAZ GRÁFICA DEL INSPECTOR
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ScrapInspectorGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 390)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -195)
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
TitleBar.Text = "  🔍 INSPECTOR DE APUNTADO | TECLA [0]"
TitleBar.TextColor3 = Color3.fromRGB(255, 215, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 285)
OutputBox.Position = UDim2.new(0, 10, 0, 46)
OutputBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
OutputBox.TextColor3 = Color3.fromRGB(225, 225, 225)
OutputBox.TextSize = 10
OutputBox.Font = Enum.Font.Code
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextEditable = false
OutputBox.Text = "Apunta con el mouse a la chatarra o auto y presiona [0] o el botón de abajo..."
OutputBox.Parent = MainFrame

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 342)
CopyBtn.BackgroundColor3 = Color3.fromRGB(210, 150, 20)
CopyBtn.Text = "📋 COPIAR DATOS"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

local ScanNowBtn = Instance.new("TextButton")
ScanNowBtn.Size = UDim2.new(0.48, -10, 0, 36)
ScanNowBtn.Position = UDim2.new(0.52, 0, 0, 342)
ScanNowBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 80)
ScanNowBtn.Text = "🎯 INSPECTOR [0]"
ScanNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanNowBtn.TextSize = 10
ScanNowBtn.Font = Enum.Font.GothamBold
ScanNowBtn.Parent = MainFrame

local ScanNowCorner = Instance.new("UICorner")
ScanNowCorner.CornerRadius = UDim.new(0, 6)
ScanNowCorner.Parent = ScanNowBtn

-- Botón flotante para minimizar/restaurar
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
-- 3. EVENTOS DE ACTIVACIÓN
-- ==============================================================================

local function triggerInspect()
    local rawTarget = mouse.Target
    if not rawTarget then
        OutputBox.Text = "⚠️ El mouse no está sobre ninguna parte sólida del mapa."
        clearHighlight()
        return
    end

    local targetObj = getTargetModel(rawTarget)
    CurrentInspected = targetObj
    applyInspectHighlight(targetObj)

    local report = generateReport(targetObj)
    OutputBox.Text = report
end

-- Activación por teclado: Tecla 0 (teclado normal y numpad)
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.KeypadZero then
        triggerInspect()
    end
end)

ScanNowBtn.MouseButton1Click:Connect(triggerInspect)

CopyBtn.MouseButton1Click:Connect(function()
    local txt = OutputBox.Text
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO!"
    task.wait(1.2)
    CopyBtn.Text = "📋 COPIAR DATOS"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
