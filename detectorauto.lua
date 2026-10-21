-- ==============================================================================
-- PANEL INTEGRADO: RADAR DE AUTOS (CON RASTREO Y GUÍA) + COFRES ROJOS
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera

local Config = {
    TruckESP = true,
    ChestESP = true
}

local RegisteredTrucks = {}
local SelectedTruck = nil

-- ==============================================================================
-- 1. FLECHA GUÍA 3D HACIA EL AUTO SELECCIONADO
-- ==============================================================================
local GuideBeam = nil
local GuideAttach0 = nil
local GuideAttach1 = nil

local function clearGuide()
    if GuideBeam then GuideBeam:Destroy(); GuideBeam = nil end
    if GuideAttach0 then GuideAttach0:Destroy(); GuideAttach0 = nil end
    if GuideAttach1 then GuideAttach1:Destroy(); GuideAttach1 = nil end
end

local function setGuideToTarget(targetPart)
    clearGuide()
    if not targetPart then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return end

    GuideAttach0 = Instance.new("Attachment")
    GuideAttach0.Name = "TruckGuide_Attach0"
    GuideAttach0.Parent = root

    GuideAttach1 = Instance.new("Attachment")
    GuideAttach1.Name = "TruckGuide_Attach1"
    GuideAttach1.Parent = targetPart

    GuideBeam = Instance.new("Beam")
    GuideBeam.Name = "TruckGuide_Beam"
    GuideBeam.Attachment0 = GuideAttach0
    GuideBeam.Attachment1 = GuideAttach1
    GuideBeam.Color = ColorSequence.new(Color3.fromRGB(255, 170, 0))
    GuideBeam.Width0 = 0.8
    GuideBeam.Width1 = 2.0
    GuideBeam.FaceCamera = true
    GuideBeam.Segments = 10
    GuideBeam.LightEmission = 1
    GuideBeam.Texture = "rbxassetid://446111271"
    GuideBeam.TextureSpeed = 2.5
    GuideBeam.TextureLength = 4
    GuideBeam.Parent = root
end

-- ==============================================================================
-- 2. LÓGICA DE COFRES (EXACTA, ROJO 360°, SE APAGA AL ABRIRSE)
-- ==============================================================================
local function getCratePrompt(model)
    return model:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function isCrateClosed(model)
    if not model or not model.Parent then return false end
    local prompt = getCratePrompt(model)
    if prompt and prompt.Enabled then
        return true
    end
    return false
end

local function clearCustomCrateESP(model)
    local tag = model:FindFirstChild("CustomCrateTag", true)
    if tag then tag:Destroy() end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Highlight") and desc.Name == "CrateESP_RedOverride" then
            desc:Destroy()
        end
    end
end

local function applyStrongRedESP(model)
    if not model:IsA("Model") or not Config.ChestESP then return end

    local isCrate = (model.Parent and model.Parent.Name == "Crates")
        or model:GetAttribute("Crate") == true
        or model:FindFirstChild("CrateServer") ~= nil

    if not isCrate then return end

    if not isCrateClosed(model) then
        clearCustomCrateESP(model)
        return
    end

    local existingHl = model:FindFirstChildWhichIsA("Highlight", true)
    if existingHl then
        existingHl.Name = "CrateESP_RedOverride"
        existingHl.FillColor = Color3.fromRGB(255, 0, 0)
        existingHl.OutlineColor = Color3.fromRGB(255, 255, 255)
        existingHl.FillTransparency = 0.3
        existingHl.OutlineTransparency = 0
        existingHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        existingHl.Enabled = true
    else
        local newHl = Instance.new("Highlight")
        newHl.Name = "CrateESP_RedOverride"
        newHl.FillColor = Color3.fromRGB(255, 0, 0)
        newHl.OutlineColor = Color3.fromRGB(255, 255, 255)
        newHl.FillTransparency = 0.3
        newHl.OutlineTransparency = 0
        newHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        newHl.Adornee = model
        newHl.Parent = model
    end

    local anchorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if anchorPart and not anchorPart:FindFirstChild("CustomCrateTag") then
        local bb = Instance.new("BillboardGui")
        bb.Name = "CustomCrateTag"
        bb.Size = UDim2.new(0, 120, 0, 30)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = anchorPart
        bb.Parent = anchorPart

        local lbl = Instance.new("TextLabel")
        lbl.Name = "DistanceLabel"
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "📦 COFRE"
        lbl.TextColor3 = Color3.fromRGB(255, 40, 40)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
    end

    local prompt = getCratePrompt(model)
    if prompt then
        prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not prompt.Enabled then
                clearCustomCrateESP(model)
                local hl = model:FindFirstChildWhichIsA("Highlight", true)
                if hl then hl.Enabled = false end
            end
        end)
        prompt.Triggered:Connect(function()
            task.wait(0.1)
            if not isCrateClosed(model) then
                clearCustomCrateESP(model)
                local hl = model:FindFirstChildWhichIsA("Highlight", true)
                if hl then hl.Enabled = false end
            end
        end)
    end

    model.DescendantRemoving:Connect(function(desc)
        if desc:IsA("ProximityPrompt") then
            clearCustomCrateESP(model)
            local hl = model:FindFirstChildWhichIsA("Highlight", true)
            if hl then hl.Enabled = false end
        end
    end)
end

-- ==============================================================================
-- 3. LÓGICA DE AUTOS (TRUCK EXACTO + REGISTRO PARA MENÚ)
-- ==============================================================================
local function clearTruckESP(model)
    local hl = model:FindFirstChild("TruckESP_Highlight")
    if hl then hl:Destroy() end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc.Name == "TruckESP_Tag" then
            desc:Destroy()
        end
    end
end

local function tagTruck(model)
    if not model:IsA("Model") then return end
    if model.Name:lower() ~= "truck" then return end

    local anchorPart = model:FindFirstChild("DriveSeat") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    
    -- Registrar en la tabla de autos si aún no está
    local exists = false
    for _, t in ipairs(RegisteredTrucks) do
        if t.Model == model then exists = true; break end
    end
    if not exists and anchorPart then
        table.insert(RegisteredTrucks, {
            Model = model,
            Anchor = anchorPart,
            Name = model.Name
        })
    end

    if not Config.TruckESP then
        clearTruckESP(model)
        return
    end

    if model:FindFirstChild("TruckESP_Highlight") then return end

    local hl = Instance.new("Highlight")
    hl.Name = "TruckESP_Highlight"
    hl.FillColor = Color3.fromRGB(255, 160, 0)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model

    if anchorPart and not anchorPart:FindFirstChild("TruckESP_Tag") then
        local bb = Instance.new("BillboardGui")
        bb.Name = "TruckESP_Tag"
        bb.Size = UDim2.new(0, 100, 0, 26)
        bb.StudsOffset = Vector3.new(0, 4.5, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = anchorPart
        bb.Parent = anchorPart

        local lbl = Instance.new("TextLabel")
        lbl.Name = "DistanceLabel"
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "🚚 TRUCK"
        lbl.TextColor3 = Color3.fromRGB(255, 180, 0)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0.2
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
    end
end

-- ==============================================================================
-- 4. INTERFAZ VISUAL (WIDGET FLOTANTE + MENÚ COMPLETO)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RadarTruckChestProGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante / Widget
local WidgetBtn = Instance.new("TextButton")
WidgetBtn.Size = UDim2.new(0, 52, 0, 52)
WidgetBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
WidgetBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
WidgetBtn.Text = "📡\nRADAR"
WidgetBtn.TextColor3 = Color3.fromRGB(0, 255, 190)
WidgetBtn.TextSize = 10
WidgetBtn.Font = Enum.Font.GothamBold
WidgetBtn.Active = true
WidgetBtn.Draggable = true
WidgetBtn.Parent = ScreenGui

local WidgetCorner = Instance.new("UICorner")
WidgetCorner.CornerRadius = UDim.new(1, 0)
WidgetCorner.Parent = WidgetBtn

local WidgetStroke = Instance.new("UIStroke")
WidgetStroke.Color = Color3.fromRGB(0, 255, 190)
WidgetStroke.Thickness = 1.5
WidgetStroke.Parent = WidgetBtn

-- Ventana Principal
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 450, 0, 400)
MainFrame.Position = UDim2.new(0.5, -225, 0.5, -200)
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
TitleBar.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
TitleBar.Text = "  📡 RADAR | AUTOS (TRUCKS) & COFRES ROJOS"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Interruptor de Autos
local TruckToggle = Instance.new("TextButton")
TruckToggle.Size = UDim2.new(0.48, -8, 0, 34)
TruckToggle.Position = UDim2.new(0, 10, 0, 44)
TruckToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
TruckToggle.Text = "🚚 AUTOS (TRUCK): ON"
TruckToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
TruckToggle.TextSize = 10
TruckToggle.Font = Enum.Font.GothamBold
TruckToggle.Parent = MainFrame

local TruckToggleCorner = Instance.new("UICorner")
TruckToggleCorner.CornerRadius = UDim.new(0, 6)
TruckToggleCorner.Parent = TruckToggle

-- Interruptor de Cofres
local ChestToggle = Instance.new("TextButton")
ChestToggle.Size = UDim2.new(0.48, -8, 0, 34)
ChestToggle.Position = UDim2.new(0.52, 0, 0, 44)
ChestToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
ChestToggle.Text = "📦 COFRES ROJOS: ON"
ChestToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
ChestToggle.TextSize = 10
ChestToggle.Font = Enum.Font.GothamBold
ChestToggle.Parent = MainFrame

local ChestToggleCorner = Instance.new("UICorner")
ChestToggleCorner.CornerRadius = UDim.new(0, 6)
ChestToggleCorner.Parent = ChestToggle

TruckToggle.MouseButton1Click:Connect(function()
    Config.TruckESP = not Config.TruckESP
    if Config.TruckESP then
        TruckToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
        TruckToggle.Text = "🚚 AUTOS (TRUCK): ON"
        for _, t in ipairs(RegisteredTrucks) do tagTruck(t.Model) end
    else
        TruckToggle.BackgroundColor3 = Color3.fromRGB(150, 35, 40)
        TruckToggle.Text = "🚚 AUTOS (TRUCK): OFF"
        for _, t in ipairs(RegisteredTrucks) do clearTruckESP(t.Model) end
        clearGuide()
        SelectedTruck = nil
    end
end)

ChestToggle.MouseButton1Click:Connect(function()
    Config.ChestESP = not Config.ChestESP
    if Config.ChestESP then
        ChestToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
        ChestToggle.Text = "📦 COFRES ROJOS: ON"
    else
        ChestToggle.BackgroundColor3 = Color3.fromRGB(150, 35, 40)
        ChestToggle.Text = "📦 COFRES ROJOS: OFF"
        local cratesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                clearCustomCrateESP(crate)
                local hl = crate:FindFirstChildWhichIsA("Highlight", true)
                if hl then hl.Enabled = false end
            end
        end
    end
end)

local ListHeader = Instance.new("TextLabel")
ListHeader.Size = UDim2.new(1, -20, 0, 22)
ListHeader.Position = UDim2.new(0, 10, 0, 84)
ListHeader.BackgroundTransparency = 1
ListHeader.Text = "REGISTRO DE AUTOS ENCONTRADOS (Toca uno para activar flecha guía):"
ListHeader.TextColor3 = Color3.fromRGB(200, 200, 200)
ListHeader.TextSize = 9
ListHeader.Font = Enum.Font.GothamBold
ListHeader.TextXAlignment = Enum.TextXAlignment.Left
ListHeader.Parent = MainFrame

local TruckScroll = Instance.new("ScrollingFrame")
TruckScroll.Size = UDim2.new(1, -20, 0, 250)
TruckScroll.Position = UDim2.new(0, 10, 0, 108)
TruckScroll.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
TruckScroll.BorderSizePixel = 0
TruckScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
TruckScroll.Parent = MainFrame

local TruckScrollCorner = Instance.new("UICorner")
TruckScrollCorner.CornerRadius = UDim.new(0, 6)
TruckScrollCorner.Parent = TruckScroll

local UIList = Instance.new("UIListLayout")
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 4)
UIList.Parent = TruckScroll

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 24)
StatusLabel.Position = UDim2.new(0, 10, 0, 366)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Guía activa: Ninguna"
StatusLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame

local function updateTruckMenu()
    for _, child in ipairs(TruckScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local myPos = root and root.Position or Vector3.zero

    for i, t in ipairs(RegisteredTrucks) do
        if t.Model and t.Model.Parent and t.Anchor then
            local pos = t.Anchor.Position
            local dist = math.floor((pos - myPos).Magnitude)

            local itemBtn = Instance.new("TextButton")
            itemBtn.Size = UDim2.new(1, -6, 0, 34)
            itemBtn.BackgroundColor3 = (SelectedTruck == t.Model) and Color3.fromRGB(50, 75, 110) or Color3.fromRGB(20, 24, 34)
            itemBtn.Text = string.format(" 🚚 Auto #%d | Pos: (%.0f, %.0f, %.0f) | Distancia: %dm", i, pos.X, pos.Y, pos.Z, dist)
            itemBtn.TextColor3 = Color3.fromRGB(255, 200, 80)
            itemBtn.TextSize = 10
            itemBtn.Font = Enum.Font.Code
            itemBtn.TextXAlignment = Enum.TextXAlignment.Left
            itemBtn.Parent = TruckScroll

            local itemCorner = Instance.new("UICorner")
            itemCorner.CornerRadius = UDim.new(0, 4)
            itemCorner.Parent = itemBtn

            itemBtn.MouseButton1Click:Connect(function()
                if SelectedTruck == t.Model then
                    -- Deseleccionar y apagar flecha
                    SelectedTruck = nil
                    clearGuide()
                    StatusLabel.Text = "Guía activa: Ninguna"
                else
                    SelectedTruck = t.Model
                    setGuideToTarget(t.Anchor)
                    StatusLabel.Text = string.format("Guía activa: ➜ Auto #%d (%.0f, %.0f, %.0f)", i, pos.X, pos.Y, pos.Z)
                end
                updateTruckMenu()
            end)
        end
    end

    TruckScroll.CanvasSize = UDim2.new(0, 0, 0, #RegisteredTrucks * 38)
end

WidgetBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==============================================================================
-- 5. BUCLE EN TIEMPO REAL: ESCANEO DE ESTRUCTURAS, COFRES Y ACTUALIZACIÓN
-- ==============================================================================

-- Escaneo de Structures para Truck
local structFolder = workspace:FindFirstChild("Structures") or workspace
for _, child in ipairs(structFolder:GetChildren()) do
    tagTruck(child)
end
structFolder.ChildAdded:Connect(function(child)
    task.wait(0.2)
    tagTruck(child)
    updateTruckMenu()
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local char = lp.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local myPos = root and root.Position or Vector3.zero

        -- 1. Actualizar distancias y etiquetas de Trucks
        for _, t in ipairs(RegisteredTrucks) do
            if t.Model and t.Model.Parent and t.Anchor then
                local tag = t.Anchor:FindFirstChild("TruckESP_Tag")
                local lbl = tag and tag:FindFirstChild("DistanceLabel")
                if lbl then
                    local d = math.floor((t.Anchor.Position - myPos).Magnitude)
                    lbl.Text = string.format("🚚 TRUCK [%dm]", d)
                end
            end
        end

        -- 2. Procesar Cofres Cerrados (si está activado)
        if Config.ChestESP then
            local cratesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Crates")
            if cratesFolder then
                for _, crate in ipairs(cratesFolder:GetChildren()) do
                    if crate:IsA("Model") then
                        if isCrateClosed(crate) then
                            applyStrongRedESP(crate)
                            local part = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
                            local tag = crate:FindFirstChild("CustomCrateTag", true)
                            local lbl = tag and tag:FindFirstChild("DistanceLabel")
                            if part and lbl then
                                local dist = math.floor((part.Position - myPos).Magnitude)
                                lbl.Text = string.format("📦 COFRE [%dm]", dist)
                            end
                        else
                            clearCustomCrateESP(crate)
                            local hl = crate:FindFirstChildWhichIsA("Highlight", true)
                            if hl then hl.Enabled = false end
                        end
                    end
                end
            end
        end

        -- 3. Mantener flecha actualizada si nos movemos
        if SelectedTruck and GuideAttach0 and root and GuideAttach0.Parent ~= root then
            GuideAttach0.Parent = root
        end
    end
end)

-- Actualizar la lista del menú cada 2 segundos
task.spawn(function()
    while true do
        task.wait(2)
        if MainFrame.Visible then
            updateTruckMenu()
        end
    end
end)

updateTruckMenu()
