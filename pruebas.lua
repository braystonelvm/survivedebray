-- ==============================================================================
-- EXPLORADOR FORENSE DE TERRENO V7.3 (DESCENSO AJUSTADO -2 STUDS + BEAM + COORDS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local State = {
    ClickInspect = false,
    SelectedPart = nil,
    HighlightMap = {},       -- [BasePart] = Highlight
    ExtraHighlight = nil,    -- Para objetos seleccionados fuera del top 40
    FilteredObjects = {},

    -- Fly & Noclip controlado
    IsFlying = false,
    IsNoclip = false,

    -- Línea guía (Beam)
    BeamObj = nil,
    Att0 = nil,
    Att1 = nil
}

local COLOR_YELLOW = Color3.fromRGB(255, 220, 0)
local COLOR_BLUE   = Color3.fromRGB(0, 145, 255)

-- Cursor siempre activo para dispositivos móviles/emuladores
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. GESTIÓN DE HIGHLIGHTS Y LÍNEA GUÍA (BEAM 0% LAG)
-- ==============================================================================

local function clearGuideBeam()
    if State.BeamObj then State.BeamObj:Destroy(); State.BeamObj = nil end
    if State.Att0 then State.Att0:Destroy(); State.Att0 = nil end
    if State.Att1 then State.Att1:Destroy(); State.Att1 = nil end
end

local function updateGuideBeam(targetPart)
    clearGuideBeam()
    if not targetPart or not targetPart:IsA("BasePart") or not targetPart.Parent then return end

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local att0 = Instance.new("Attachment")
    att0.Name = "ForensicGuideAtt0"
    att0.Parent = root

    local att1 = Instance.new("Attachment")
    att1.Name = "ForensicGuideAtt1"
    att1.Parent = targetPart

    local beam = Instance.new("Beam")
    beam.Name = "ForensicGuideBeam"
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    beam.Width0 = 0.14
    beam.Width1 = 0.14
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.Transparency = NumberSequence.new(0.15)
    beam.Color = ColorSequence.new(COLOR_BLUE)
    beam.Parent = root

    State.Att0 = att0
    State.Att1 = att1
    State.BeamObj = beam
end

lp.CharacterAdded:Connect(function()
    task.wait(0.5)
    if State.SelectedPart and State.SelectedPart.Parent then
        updateGuideBeam(State.SelectedPart)
    end
end)

local function clearAllHighlights()
    for _, hl in pairs(State.HighlightMap) do
        if hl and hl.Parent then hl:Destroy() end
    end
    State.HighlightMap = {}

    if State.ExtraHighlight and State.ExtraHighlight.Parent then
        State.ExtraHighlight:Destroy()
        State.ExtraHighlight = nil
    end
end

local function applyHighlightStyle(hl, isSelected)
    if not hl then return end
    if isSelected then
        hl.FillColor = COLOR_BLUE
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.25
    else
        hl.FillColor = COLOR_YELLOW
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
    end
end

local function selectTargetPart(targetPart)
    if State.SelectedPart then
        local prevHl = State.HighlightMap[State.SelectedPart]
        if prevHl then
            applyHighlightStyle(prevHl, false)
        end
    end
    if State.ExtraHighlight then
        State.ExtraHighlight:Destroy()
        State.ExtraHighlight = nil
    end

    State.SelectedPart = targetPart

    if targetPart and targetPart:IsA("BasePart") then
        local existingHl = State.HighlightMap[targetPart]
        if existingHl then
            applyHighlightStyle(existingHl, true)
        else
            local hl = Instance.new("Highlight")
            hl.Name = "SelectedExtraHighlight"
            hl.Adornee = targetPart
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            applyHighlightStyle(hl, true)
            hl.Parent = CoreGui
            State.ExtraHighlight = hl
        end
        updateGuideBeam(targetPart)
    else
        clearGuideBeam()
    end
end

-- ==============================================================================
-- 2. SISTEMA DE FLY + NOCLIP PARA DESCENSO CONTROLADO (-2 STUDS)
-- ==============================================================================

RunService.Stepped:Connect(function()
    if State.IsNoclip then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = false
                end
            end
        end
    end
end)

local function stopFlyAndNoclipImmediate()
    State.IsNoclip = false
    State.IsFlying = false

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if root then
        for _, obj in ipairs(root:GetChildren()) do
            if obj.Name == "DescentBP" or obj.Name == "DescentBG" then
                obj:Destroy()
            end
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = true
            end
        end
    end

    if hum then
        hum.PlatformStand = false
    end
end

local function flyDescendBelowTarget(targetPart, statusCallback)
    if not targetPart or not targetPart.Parent then return end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    stopFlyAndNoclipImmediate()

    State.IsNoclip = true
    State.IsFlying = true
    hum.PlatformStand = true

    local bp = Instance.new("BodyPosition")
    bp.Name = "DescentBP"
    bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bp.P = 35000
    bp.D = 900
    bp.Position = root.Position
    bp.Parent = root

    local bg = Instance.new("BodyGyro")
    bg.Name = "DescentBG"
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.CFrame = root.CFrame
    bg.Parent = root

    local bottomY = targetPart.Position.Y - (targetPart.Size.Y * 0.5)
    local destPos = Vector3.new(targetPart.Position.X, bottomY - 2.0, targetPart.Position.Z)

    if statusCallback then
        statusCallback("✈️ Fly + Noclip activos: Viajando al objetivo (-2 studs)...")
    end

    local speed = 95
    local reachedTarget = false

    -- Bucle estricto: No desactiva noclip hasta haber llegado al objetivo
    while State.IsFlying do
        local dt = RunService.Heartbeat:Wait()
        if not targetPart or not targetPart.Parent or not root or not root.Parent then
            break
        end

        bottomY = targetPart.Position.Y - (targetPart.Size.Y * 0.5)
        destPos = Vector3.new(targetPart.Position.X, bottomY - 2.0, targetPart.Position.Z)

        local diff = destPos - root.Position
        local dist = diff.Magnitude

        if dist <= 1.5 then
            bp.Position = destPos
            reachedTarget = true
            break
        end

        local step = math.min(dist, speed * dt)
        bp.Position = root.Position + (diff.Unit * step)
    end

    -- Solo desactivar noclip y fly secuencialmente si llegó al objetivo
    if reachedTarget and State.IsFlying then
        -- 1. Primero desactivar Noclip al llegar al objetivo
        State.IsNoclip = false
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = true
                end
            end
        end

        if statusCallback then
            statusCallback("🛑 Objetivo alcanzado: Noclip OFF. Apagando Fly en 1s...")
        end

        -- 2. Esperar 1 segundo sosteniendo posición y luego desactivar Fly
        task.wait(1.0)
        stopFlyAndNoclipImmediate()

        if statusCallback then
            statusCallback("✅ Descenso completado (-2 studs debajo).")
        end
    else
        -- Si se canceló manualmente con 'CORTAR FLY' o desapareció el objeto
        stopFlyAndNoclipImmediate()
    end
end

-- ==============================================================================
-- 3. CLASIFICADOR Y RANKING DE PROFUNDIDAD
-- ==============================================================================

local function getPartBottomDepth(part)
    return part.Position.Y - (part.Size.Y * 0.5)
end

local function scanAndRankTerrain(keyword)
    clearAllHighlights()
    State.FilteredObjects = {}
    local baseCenter = Vector3.new(0, 0, 0)
    keyword = (keyword or ""):lower()

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 350 then
                local nLower = desc.Name:lower()
                local isCharacterPart = lp.Character and desc:IsDescendantOf(lp.Character)

                if not isCharacterPart and (keyword == "" or nLower:find(keyword, 1, true)) then
                    local bottomY = getPartBottomDepth(desc)
                    table.insert(State.FilteredObjects, {
                        Part = desc,
                        Name = desc.Name,
                        Class = desc.ClassName,
                        Pos = pos,
                        Size = desc.Size,
                        BottomY = bottomY,
                        CenterY = pos.Y
                    })
                end
            end
        end
    end

    table.sort(State.FilteredObjects, function(a, b)
        return a.BottomY < b.BottomY
    end)

    for i = 1, math.min(40, #State.FilteredObjects) do
        local obj = State.FilteredObjects[i]
        local hl = Instance.new("Highlight")
        hl.Name = "RankHighlight"
        hl.Adornee = obj.Part
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        applyHighlightStyle(hl, obj.Part == State.SelectedPart)
        hl.Parent = CoreGui
        State.HighlightMap[obj.Part] = hl
    end

    if State.SelectedPart and not State.HighlightMap[State.SelectedPart] then
        selectTargetPart(State.SelectedPart)
    end
end

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA FLOTANTE CON PESTAÑAS (EXPLORADOR + COORDENADAS)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("TerrainInspectorGuiV7")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TerrainInspectorGuiV7"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 120, 110)
FloatBtn.Text = "🔍\nTOOL"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 500)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -250)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
TitleBar.Text = "  🔍 EXPLORADOR TERRENO V7.3 | FLY -2 STUDS & GUÍA"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Barra de Pestañas
local TabExplorerBtn = Instance.new("TextButton")
TabExplorerBtn.Size = UDim2.new(0.5, -12, 0, 28)
TabExplorerBtn.Position = UDim2.new(0, 10, 0, 40)
TabExplorerBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
TabExplorerBtn.Text = "📊 EXPLORADOR & LISTA"
TabExplorerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TabExplorerBtn.TextSize = 10
TabExplorerBtn.Font = Enum.Font.GothamBold
TabExplorerBtn.Parent = MainFrame
Instance.new("UICorner", TabExplorerBtn).CornerRadius = UDim.new(0, 6)

local TabCoordsBtn = Instance.new("TextButton")
TabCoordsBtn.Size = UDim2.new(0.5, -12, 0, 28)
TabCoordsBtn.Position = UDim2.new(0.5, 2, 0, 40)
TabCoordsBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabCoordsBtn.Text = "📍 MIS COORDENADAS"
TabCoordsBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabCoordsBtn.TextSize = 10
TabCoordsBtn.Font = Enum.Font.GothamBold
TabCoordsBtn.Parent = MainFrame
Instance.new("UICorner", TabCoordsBtn).CornerRadius = UDim.new(0, 6)

-- Contenedores de Pestañas
local ExplorerPage = Instance.new("Frame")
ExplorerPage.Size = UDim2.new(1, 0, 1, -74)
ExplorerPage.Position = UDim2.new(0, 0, 0, 74)
ExplorerPage.BackgroundTransparency = 1
ExplorerPage.Visible = true
ExplorerPage.Parent = MainFrame

local CoordsPage = Instance.new("Frame")
CoordsPage.Size = UDim2.new(1, 0, 1, -74)
CoordsPage.Position = UDim2.new(0, 0, 0, 74)
CoordsPage.BackgroundTransparency = 1
CoordsPage.Visible = false
CoordsPage.Parent = MainFrame

TabExplorerBtn.MouseButton1Click:Connect(function()
    ExplorerPage.Visible = true
    CoordsPage.Visible = false
    TabExplorerBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
    TabExplorerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    TabCoordsBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
    TabCoordsBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
end)

TabCoordsBtn.MouseButton1Click:Connect(function()
    ExplorerPage.Visible = false
    CoordsPage.Visible = true
    TabCoordsBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
    TabCoordsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    TabExplorerBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
    TabExplorerBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
end)

-- ==============================================================================
-- 5. CONTENIDO PESTAÑA 1: EXPLORADOR
-- ==============================================================================

local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -20, 0, 78)
InfoCard.Position = UDim2.new(0, 10, 0, 4)
InfoCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
InfoCard.Parent = ExplorerPage
Instance.new("UICorner", InfoCard).CornerRadius = UDim.new(0, 6)

local InfoTitle = Instance.new("TextLabel")
InfoTitle.Size = UDim2.new(1, -12, 0, 20)
InfoTitle.Position = UDim2.new(0, 6, 0, 4)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = "📌 Seleccionado: (Ninguno) | Highlight Azul + Línea Guía"
InfoTitle.TextColor3 = Color3.fromRGB(90, 190, 255)
InfoTitle.TextSize = 10
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.TextXAlignment = Enum.TextXAlignment.Left
InfoTitle.Parent = InfoCard

local InfoDetails = Instance.new("TextLabel")
InfoDetails.Size = UDim2.new(1, -12, 0, 48)
InfoDetails.Position = UDim2.new(0, 6, 0, 25)
InfoDetails.BackgroundTransparency = 1
InfoDetails.Text = "Toca una fila para seleccionarla (Azul + Línea) o presiona '⬇️ BAJAR' para descender con Fly+Noclip 2 studs debajo."
InfoDetails.TextColor3 = Color3.fromRGB(200, 200, 200)
InfoDetails.TextSize = 9
InfoDetails.Font = Enum.Font.Code
InfoDetails.TextWrapped = true
InfoDetails.TextXAlignment = Enum.TextXAlignment.Left
InfoDetails.TextYAlignment = Enum.TextYAlignment.Top
InfoDetails.Parent = InfoCard

local ClickModeBtn = Instance.new("TextButton")
ClickModeBtn.Size = UDim2.new(0.33, -8, 0, 30)
ClickModeBtn.Position = UDim2.new(0, 10, 0, 88)
ClickModeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
ClickModeBtn.Text = "🎯 CLICK: OFF"
ClickModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClickModeBtn.TextSize = 9
ClickModeBtn.Font = Enum.Font.GothamBold
ClickModeBtn.Parent = ExplorerPage
Instance.new("UICorner", ClickModeBtn).CornerRadius = UDim.new(0, 6)

local CopyNameBtn = Instance.new("TextButton")
CopyNameBtn.Size = UDim2.new(0.34, -8, 0, 30)
CopyNameBtn.Position = UDim2.new(0.33, 4, 0, 88)
CopyNameBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 170)
CopyNameBtn.Text = "📋 COPIAR NOMBRE"
CopyNameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyNameBtn.TextSize = 9
CopyNameBtn.Font = Enum.Font.GothamBold
CopyNameBtn.Parent = ExplorerPage
Instance.new("UICorner", CopyNameBtn).CornerRadius = UDim.new(0, 6)

local StopFlyBtn = Instance.new("TextButton")
StopFlyBtn.Size = UDim2.new(0.33, -8, 0, 30)
StopFlyBtn.Position = UDim2.new(0.67, 0, 0, 88)
StopFlyBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 20)
StopFlyBtn.Text = "🛑 CORTAR FLY"
StopFlyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFlyBtn.TextSize = 9
StopFlyBtn.Font = Enum.Font.GothamBold
StopFlyBtn.Parent = ExplorerPage
Instance.new("UICorner", StopFlyBtn).CornerRadius = UDim.new(0, 6)

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(0.55, -10, 0, 30)
SearchBox.Position = UDim2.new(0, 10, 0, 124)
SearchBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
SearchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBox.PlaceholderText = "Filtrar (ej. rock, tree, ground)..."
SearchBox.Text = ""
SearchBox.TextSize = 10
SearchBox.Font = Enum.Font.Code
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = ExplorerPage
Instance.new("UICorner", SearchBox).CornerRadius = UDim.new(0, 6)

local FilterBtn = Instance.new("TextButton")
FilterBtn.Size = UDim2.new(0.45, -10, 0, 30)
FilterBtn.Position = UDim2.new(0.55, 0, 0, 124)
FilterBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
FilterBtn.Text = "📊 ORDENAR PROFUNDIDAD"
FilterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FilterBtn.TextSize = 9
FilterBtn.Font = Enum.Font.GothamBold
FilterBtn.Parent = ExplorerPage
Instance.new("UICorner", FilterBtn).CornerRadius = UDim.new(0, 6)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 1, -166)
ScrollFrame.Position = UDim2.new(0, 10, 0, 160)
ScrollFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = ExplorerPage
Instance.new("UICorner", ScrollFrame).CornerRadius = UDim.new(0, 6)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)
UIListLayout.Parent = ScrollFrame

-- ==============================================================================
-- 6. CONTENIDO PESTAÑA 2: COORDENADAS EN TIEMPO REAL
-- ==============================================================================

local CoordCard = Instance.new("Frame")
CoordCard.Size = UDim2.new(1, -20, 0, 180)
CoordCard.Position = UDim2.new(0, 10, 0, 10)
CoordCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
CoordCard.Parent = CoordsPage
Instance.new("UICorner", CoordCard).CornerRadius = UDim.new(0, 8)

local CoordHeader = Instance.new("TextLabel")
CoordHeader.Size = UDim2.new(1, -20, 0, 28)
CoordHeader.Position = UDim2.new(0, 10, 0, 8)
CoordHeader.BackgroundTransparency = 1
CoordHeader.Text = "📍 POSICIÓN ACTUAL DE TU PERSONAJE (EN VIVO)"
CoordHeader.TextColor3 = Color3.fromRGB(0, 255, 190)
CoordHeader.TextSize = 11
CoordHeader.Font = Enum.Font.GothamBold
CoordHeader.TextXAlignment = Enum.TextXAlignment.Left
CoordHeader.Parent = CoordCard

local LiveCoordText = Instance.new("TextLabel")
LiveCoordText.Size = UDim2.new(1, -20, 0, 75)
LiveCoordText.Position = UDim2.new(0, 10, 0, 40)
LiveCoordText.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
LiveCoordText.TextColor3 = Color3.fromRGB(255, 255, 255)
LiveCoordText.TextSize = 12
LiveCoordText.Font = Enum.Font.Code
LiveCoordText.Text = "Calculando..."
LiveCoordText.Parent = CoordCard
Instance.new("UICorner", LiveCoordText).CornerRadius = UDim.new(0, 6)

local CopyVecBtn = Instance.new("TextButton")
CopyVecBtn.Size = UDim2.new(1, -20, 0, 42)
CopyVecBtn.Position = UDim2.new(0, 10, 0, 126)
CopyVecBtn.BackgroundColor3 = Color3.fromRGB(0, 135, 215)
CopyVecBtn.Text = "📋 COPIAR Vector3.new(X, Y, Z)"
CopyVecBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyVecBtn.TextSize = 11
CopyVecBtn.Font = Enum.Font.GothamBold
CopyVecBtn.Parent = CoordCard
Instance.new("UICorner", CopyVecBtn).CornerRadius = UDim.new(0, 6)

local currentFormattedVector = "Vector3.new(0, 0, 0)"

task.spawn(function()
    while true do
        task.wait(0.15)
        if CoordsPage.Visible then
            local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local p = root.Position
                currentFormattedVector = string.format("Vector3.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
                LiveCoordText.Text = string.format(
                    "X: %.2f   |   Y: %.2f   |   Z: %.2f\n\nFormato Lua:\n%s",
                    p.X, p.Y, p.Z, currentFormattedVector
                )
            else
                LiveCoordText.Text = "Personaje no encontrado..."
            end
        end
    end
end)

CopyVecBtn.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(currentFormattedVector) elseif toclipboard then toclipboard(currentFormattedVector) end
    CopyVecBtn.Text = "✅ ¡COORDENADAS COPIADAS!"
    task.wait(1.2)
    CopyVecBtn.Text = "📋 COPIAR Vector3.new(X, Y, Z)"
end)

-- ==============================================================================
-- 7. RENDERIZADO DE LISTA SELECCIONABLE + BOTÓN DE DESCENSO EN CADA FILA
-- ==============================================================================

local RowButtons = {}

local function refreshRowSelectionVisuals()
    for part, rowFrame in pairs(RowButtons) do
        if rowFrame and rowFrame.Parent then
            if part == State.SelectedPart then
                rowFrame.BackgroundColor3 = Color3.fromRGB(20, 65, 115)
            else
                rowFrame.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
            end
        end
    end
end

local function updateScrollList()
    for _, child in ipairs(ScrollFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    RowButtons = {}

    for rank, obj in ipairs(State.FilteredObjects) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 36)
        row.BackgroundColor3 = (obj.Part == State.SelectedPart) and Color3.fromRGB(20, 65, 115) or Color3.fromRGB(22, 26, 36)
        row.Parent = ScrollFrame
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        RowButtons[obj.Part] = row

        local selectBtn = Instance.new("TextButton")
        selectBtn.Size = UDim2.new(1, -82, 1, 0)
        selectBtn.Position = UDim2.new(0, 6, 0, 0)
        selectBtn.BackgroundTransparency = 1
        selectBtn.Text = string.format("#%d [%s] Base Y: %.1f | (%.0f, %.0f, %.0f)", rank, obj.Name, obj.BottomY, obj.Pos.X, obj.CenterY, obj.Pos.Z)
        selectBtn.TextColor3 = (obj.BottomY <= -5) and Color3.fromRGB(0, 255, 180) or Color3.fromRGB(220, 220, 220)
        selectBtn.TextSize = 9
        selectBtn.Font = Enum.Font.Code
        selectBtn.TextXAlignment = Enum.TextXAlignment.Left
        selectBtn.Parent = row

        selectBtn.MouseButton1Click:Connect(function()
            selectTargetPart(obj.Part)
            refreshRowSelectionVisuals()
            InfoTitle.Text = string.format("📌 #%d Seleccionado: '%s' (%s)", rank, obj.Name, obj.Class)
            InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)\nRuta: %s", obj.BottomY, obj.CenterY, obj.Size.X, obj.Size.Y, obj.Size.Z, obj.Part:GetFullName())
        end)

        local goBtn = Instance.new("TextButton")
        goBtn.Size = UDim2.new(0, 72, 0, 28)
        goBtn.Position = UDim2.new(1, -76, 0, 4)
        goBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        goBtn.Text = "⬇️ BAJAR"
        goBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        goBtn.TextSize = 9
        goBtn.Font = Enum.Font.GothamBold
        goBtn.Parent = row
        Instance.new("UICorner", goBtn).CornerRadius = UDim.new(0, 4)

        goBtn.MouseButton1Click:Connect(function()
            selectTargetPart(obj.Part)
            refreshRowSelectionVisuals()
            InfoTitle.Text = string.format("📌 #%d Destino: '%s' (%s)", rank, obj.Name, obj.Class)

            task.spawn(function()
                flyDescendBelowTarget(obj.Part, function(statusMsg)
                    InfoDetails.Text = statusMsg .. string.format("\nBase Y: %.2f | Objetivo Y: %.2f", obj.BottomY, obj.BottomY - 2.0)
                end)
            end)
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #State.FilteredObjects * 40)
end

-- ==============================================================================
-- 8. EVENTOS DE INTERFAZ Y INSPECCIÓN POR CLICK
-- ==============================================================================

local function handleWorldClick()
    if not State.ClickInspect then return end

    local targetPart = mouse.Target
    if targetPart and targetPart:IsA("BasePart") then
        local isSelf = lp.Character and targetPart:IsDescendantOf(lp.Character)
        if isSelf then return end

        selectTargetPart(targetPart)
        refreshRowSelectionVisuals()

        local bottomY = getPartBottomDepth(targetPart)
        InfoTitle.Text = string.format("📌 Click en: '%s' (%s)", targetPart.Name, targetPart.ClassName)
        InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)\nRuta: %s", bottomY, targetPart.Position.Y, targetPart.Size.X, targetPart.Size.Y, targetPart.Size.Z, targetPart:GetFullName())
        SearchBox.Text = targetPart.Name
    end
end

mouse.Button1Down:Connect(handleWorldClick)

ClickModeBtn.MouseButton1Click:Connect(function()
    State.ClickInspect = not State.ClickInspect
    if State.ClickInspect then
        ClickModeBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
        ClickModeBtn.Text = "🎯 CLICK: ON"
    else
        ClickModeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
        ClickModeBtn.Text = "🎯 CLICK: OFF"
    end
end)

CopyNameBtn.MouseButton1Click:Connect(function()
    if State.SelectedPart then
        local txt = State.SelectedPart.Name
        if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
        CopyNameBtn.Text = "✅ ¡COPIADO!"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE"
    else
        CopyNameBtn.Text = "⚠️ SIN SELECCIÓN"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE"
    end
end)

StopFlyBtn.MouseButton1Click:Connect(function()
    stopFlyAndNoclipImmediate()
    InfoDetails.Text = "🛑 Fly y Noclip detenidos manualmente."
end)

FilterBtn.MouseButton1Click:Connect(function()
    FilterBtn.Text = "⏳ ANALIZANDO..."
    scanAndRankTerrain(SearchBox.Text)
    updateScrollList()
    FilterBtn.Text = string.format("✅ %d ORDENADOS", #State.FilteredObjects)
    task.wait(1.2)
    FilterBtn.Text = "📊 ORDENAR PROFUNDIDAD"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Carga inicial
scanAndRankTerrain("")
updateScrollList()
