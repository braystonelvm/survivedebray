-- ==============================================================================
-- EXPLORADOR FORENSE DE TERRENO V9.0 (MODO PIEL INFERIOR + MODO BÚNKER + CONFIG)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local Config = {
    Mode = "UnderSkin",     -- "UnderSkin" (Bajo piel de roca) o "Bunker" (Dentro sobre suelo real)
    FlySpeed = 95,          -- Velocidad de bajada en vuelo
    WalkSpeed = 24,         -- Velocidad al caminar hacia la roca
    SkinOffset = 1.2,       -- Ajuste fino en studs respecto a la piel inferior de la roca
    HoldSeconds = 1.0,      -- Segundos de espera tras quitar Noclip antes de quitar Fly
    WalkFirst = true        -- Caminar hacia la roca antes de activar Fly
}

local State = {
    ClickInspect = false,
    SelectedPart = nil,
    HighlightMap = {},
    ExtraHighlight = nil,
    FilteredObjects = {},

    -- Control de movimiento
    IsWalkingToTarget = false,
    IsFlying = false,
    IsNoclip = false,
    GhostRocks = {},        -- Registro de rocas con CanCollide = false en Modo Búnker

    -- Línea guía (Beam)
    BeamObj = nil,
    Att0 = nil,
    Att1 = nil
}

local COLOR_YELLOW = Color3.fromRGB(255, 220, 0)
local COLOR_BLUE   = Color3.fromRGB(0, 145, 255)

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. DETECCIÓN EXACTA DE PIEL INFERIOR Y SUELO REAL MEDIANTE RAYCASTS
-- ==============================================================================

-- Encuentra el punto horizontal más bajo de la caja para aproximarse
local function getLowestCornerXZ(part)
    local cf = part.CFrame
    local half = part.Size * 0.5
    local lowestPoint = part.Position - Vector3.new(0, half.Y, 0)
    local minY = math.huge

    for _, sx in ipairs({-1, 1}) do
        for _, sy in ipairs({-1, 1}) do
            for _, sz in ipairs({-1, 1}) do
                local worldCorner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
                if worldCorner.Y < minY then
                    minY = worldCorner.Y
                    lowestPoint = worldCorner
                end
            end
        end
    end

    return Vector3.new(
        lowestPoint.X * 0.65 + part.Position.X * 0.35,
        lowestPoint.Y,
        lowestPoint.Z * 0.65 + part.Position.Z * 0.35
    ), minY
end

-- MODO 1: Raycast de abajo hacia arriba para tocar la PIEL FÍSICA REAL de la roca
local function getExactUndersideSkinPoint(part)
    local approachPos, bboxMinY = getLowestCornerXZ(part)

    local includeParams = RaycastParams.new()
    includeParams.FilterType = Enum.RaycastFilterType.Include
    includeParams.FilterDescendantsInstances = {part}

    -- Disparar varios rayos hacia arriba alrededor del punto más profundo para hallar la piel más baja
    local bestSkinPos = nil
    local lowestSkinY = math.huge

    local offsets = {
        Vector3.new(0, 0, 0),
        Vector3.new(1.5, 0, 0),
        Vector3.new(-1.5, 0, 0),
        Vector3.new(0, 0, 1.5),
        Vector3.new(0, 0, -1.5)
    }

    for _, off in ipairs(offsets) do
        local rayOrigin = Vector3.new(approachPos.X + off.X, bboxMinY - 15, approachPos.Z + off.Z)
        local rayDir = Vector3.new(0, part.Size.Y + 30, 0)
        local hit = workspace:Raycast(rayOrigin, rayDir, includeParams)

        if hit and hit.Position.Y < lowestSkinY then
            lowestSkinY = hit.Position.Y
            bestSkinPos = hit.Position
        end
    end

    -- Rayo de respaldo directo al centro de la roca desde abajo
    if not bestSkinPos then
        local centerOrigin = Vector3.new(part.Position.X, bboxMinY - 15, part.Position.Z)
        local centerHit = workspace:Raycast(centerOrigin, Vector3.new(0, part.Size.Y + 30, 0), includeParams)
        if centerHit then
            bestSkinPos = centerHit.Position
        else
            bestSkinPos = Vector3.new(approachPos.X, bboxMinY, approachPos.Z)
        end
    end

    return bestSkinPos
end

-- MODO 2: Raycast hacia abajo ignorando la roca para hallar el SUELO REAL dentro de ella
local function getRealGroundInsideRock(part)
    local excludeParams = RaycastParams.new()
    excludeParams.FilterType = Enum.RaycastFilterType.Exclude
    local ignoreList = {part}
    if lp.Character then table.insert(ignoreList, lp.Character) end
    excludeParams.FilterDescendantsInstances = ignoreList

    local origin = Vector3.new(part.Position.X, part.Position.Y + (part.Size.Y * 0.5) + 10, part.Position.Z)
    local hit = workspace:Raycast(origin, Vector3.new(0, -(part.Size.Y + 50), 0), excludeParams)

    if hit then
        return Vector3.new(part.Position.X, hit.Position.Y + 3.0, part.Position.Z)
    end
    return part.Position + Vector3.new(0, 2, 0)
end

local function getPartBottomDepth(part)
    local _, minY = getLowestCornerXZ(part)
    return minY
end

-- ==============================================================================
-- 2. GESTIÓN DE HIGHLIGHTS Y LÍNEA GUÍA (BEAM 0% LAG)
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
-- 3. SISTEMA DE CAMINATA + FLY + NOCLIP (MODO PIEL INFERIOR Y MODO BÚNKER)
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

local function restoreGhostRocks()
    for part, origCollide in pairs(State.GhostRocks) do
        if part and part.Parent then
            part.CanCollide = origCollide
        end
    end
    State.GhostRocks = {}
end

local function stopFlyAndNoclipImmediate()
    State.IsWalkingToTarget = false
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

local function executeRefugeEntry(targetPart, statusCallback)
    if not targetPart or not targetPart.Parent then return end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    stopFlyAndNoclipImmediate()
    restoreGhostRocks()

    local approachPos, _ = getLowestCornerXZ(targetPart)

    -- FASE 1: CAMINAR HACIA LA ROCA PRIMERO
    if Config.WalkFirst then
        State.IsWalkingToTarget = true
        local originalWalkSpeed = hum.WalkSpeed
        hum.WalkSpeed = math.max(originalWalkSpeed, Config.WalkSpeed)

        if statusCallback then
            statusCallback("🚶 Caminando hacia la roca...")
        end

        local walkTimeout = tick() + 18.0
        local lastJump = 0

        while State.IsWalkingToTarget and tick() < walkTimeout do
            RunService.Heartbeat:Wait()
            if not targetPart or not targetPart.Parent or not root or not root.Parent or hum.Health <= 0 then
                break
            end

            approachPos, _ = getLowestCornerXZ(targetPart)
            local horizDiff = Vector3.new(approachPos.X - root.Position.X, 0, approachPos.Z - root.Position.Z)
            if horizDiff.Magnitude <= 5.0 then
                break
            end

            hum:MoveTo(Vector3.new(approachPos.X, root.Position.Y, approachPos.Z))

            if (tick() - lastJump) >= 0.7 and root.AssemblyLinearVelocity.Magnitude < (hum.WalkSpeed * 0.35) then
                hum.Jump = true
                lastJump = tick()
            end
        end

        hum.WalkSpeed = originalWalkSpeed
        if not State.IsWalkingToTarget then return end
        State.IsWalkingToTarget = false
    end

    -- ==========================================================================
    -- OPCIÓN A: MODO BÚNKER DENTRO (SUELO REAL + ROCA SIN COLISIÓN LOCAL)
    -- ==========================================================================
    if Config.Mode == "Bunker" then
        State.GhostRocks[targetPart] = targetPart.CanCollide
        targetPart.CanCollide = false

        local bunkerPos = getRealGroundInsideRock(targetPart)

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

        if statusCallback then
            statusCallback("🪨 Modo Búnker: Entrando al suelo firme dentro de la roca...")
        end

        local reached = false
        while State.IsFlying do
            local dt = RunService.Heartbeat:Wait()
            if not targetPart or not targetPart.Parent or not root or not root.Parent then break end
            local diff = bunkerPos - root.Position
            if diff.Magnitude <= 1.2 then
                bp.Position = bunkerPos
                reached = true
                break
            end
            bp.Position = root.Position + (diff.Unit * math.min(diff.Magnitude, Config.FlySpeed * dt))
        end

        if reached and State.IsFlying then
            State.IsNoclip = false
            task.wait(0.2)
            stopFlyAndNoclipImmediate()
            if statusCallback then
                statusCallback("✅ Búnker listo: De pie sobre suelo firme dentro de la roca.")
            end
        else
            stopFlyAndNoclipImmediate()
        end
        return
    end

    -- ==========================================================================
    -- OPCIÓN B: MODO BAJO PIEL DE ROCA (RAYCAST HACIA ARRIBA + CUÑA INVERTIDA)
    -- ==========================================================================
    local skinPoint = getExactUndersideSkinPoint(targetPart)
    local targetDest = Vector3.new(skinPoint.X, skinPoint.Y - Config.SkinOffset, skinPoint.Z)

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

    if statusCallback then
        statusCallback(string.format("🦇 Bajando a la piel inferior real (Y: %.1f)...", targetDest.Y))
    end

    local reachedTarget = false

    while State.IsFlying do
        local dt = RunService.Heartbeat:Wait()
        if not targetPart or not targetPart.Parent or not root or not root.Parent then
            break
        end

        local diff = targetDest - root.Position
        local dist = diff.Magnitude

        if dist <= 1.0 then
            bp.Position = targetDest
            reachedTarget = true
            break
        end

        local step = math.min(dist, Config.FlySpeed * dt)
        bp.Position = root.Position + (diff.Unit * step)
    end

    if reachedTarget and State.IsFlying then
        -- 1. Quitar Noclip al tocar la piel de la roca para que la gravedad/colisión la enganche
        State.IsNoclip = false
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = true
                end
            end
        end

        if statusCallback then
            statusCallback(string.format("🛑 Noclip OFF en piel inferior. Apagando Fly en %.1fs...", Config.HoldSeconds))
        end

        -- 2. Esperar el tiempo configurado y soltar Fly
        task.wait(Config.HoldSeconds)
        stopFlyAndNoclipImmediate()

        if statusCallback then
            statusCallback("✅ Enganchado bajo la piel de la roca.")
        end
    else
        stopFlyAndNoclipImmediate()
    end
end

-- ==============================================================================
-- 4. CLASIFICADOR Y RANKING DE PROFUNDIDAD
-- ==============================================================================

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
-- 5. INTERFAZ GRÁFICA FLOTANTE CON 3 PESTAÑAS (EXPLORADOR + CONFIG + COORDS)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("TerrainInspectorGuiV9")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TerrainInspectorGuiV9"
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
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 530, 0, 515)
MainFrame.Position = UDim2.new(0.5, -265, 0.5, -257)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
TitleBar.Text = "  🔍 EXPLORADOR TERRENO V9.0 | PIEL INFERIOR & BÚNKER"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

-- Barra de 3 Pestañas
local TabExplorerBtn = Instance.new("TextButton")
TabExplorerBtn.Size = UDim2.new(0.34, -8, 0, 28)
TabExplorerBtn.Position = UDim2.new(0, 10, 0, 40)
TabExplorerBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
TabExplorerBtn.Text = "📊 EXPLORADOR"
TabExplorerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TabExplorerBtn.TextSize = 10
TabExplorerBtn.Font = Enum.Font.GothamBold
TabExplorerBtn.Parent = MainFrame
Instance.new("UICorner", TabExplorerBtn).CornerRadius = UDim.new(0, 6)

local TabConfigBtn = Instance.new("TextButton")
TabConfigBtn.Size = UDim2.new(0.33, -8, 0, 28)
TabConfigBtn.Position = UDim2.new(0.34, 4, 0, 40)
TabConfigBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabConfigBtn.Text = "⚙️ CONFIGURACIÓN"
TabConfigBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabConfigBtn.TextSize = 10
TabConfigBtn.Font = Enum.Font.GothamBold
TabConfigBtn.Parent = MainFrame
Instance.new("UICorner", TabConfigBtn).CornerRadius = UDim.new(0, 6)

local TabCoordsBtn = Instance.new("TextButton")
TabCoordsBtn.Size = UDim2.new(0.33, -8, 0, 28)
TabCoordsBtn.Position = UDim2.new(0.67, 0, 0, 40)
TabCoordsBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabCoordsBtn.Text = "📍 COORDENADAS"
TabCoordsBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabCoordsBtn.TextSize = 10
TabCoordsBtn.Font = Enum.Font.GothamBold
TabCoordsBtn.Parent = MainFrame
Instance.new("UICorner", TabCoordsBtn).CornerRadius = UDim.new(0, 6)

local ExplorerPage = Instance.new("Frame")
ExplorerPage.Size = UDim2.new(1, 0, 1, -74)
ExplorerPage.Position = UDim2.new(0, 0, 0, 74)
ExplorerPage.BackgroundTransparency = 1
ExplorerPage.Visible = true
ExplorerPage.Parent = MainFrame

local ConfigPage = Instance.new("Frame")
ConfigPage.Size = UDim2.new(1, 0, 1, -74)
ConfigPage.Position = UDim2.new(0, 0, 0, 74)
ConfigPage.BackgroundTransparency = 1
ConfigPage.Visible = false
ConfigPage.Parent = MainFrame

local CoordsPage = Instance.new("Frame")
CoordsPage.Size = UDim2.new(1, 0, 1, -74)
CoordsPage.Position = UDim2.new(0, 0, 0, 74)
CoordsPage.BackgroundTransparency = 1
CoordsPage.Visible = false
CoordsPage.Parent = MainFrame

local function switchTab(activeBtn, activePage)
    ExplorerPage.Visible = (activePage == ExplorerPage)
    ConfigPage.Visible   = (activePage == ConfigPage)
    CoordsPage.Visible   = (activePage == CoordsPage)

    for _, btn in ipairs({TabExplorerBtn, TabConfigBtn, TabCoordsBtn}) do
        if btn == activeBtn then
            btn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            btn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
            btn.TextColor3 = Color3.fromRGB(200, 200, 200)
        end
    end
end

TabExplorerBtn.MouseButton1Click:Connect(function() switchTab(TabExplorerBtn, ExplorerPage) end)
TabConfigBtn.MouseButton1Click:Connect(function() switchTab(TabConfigBtn, ConfigPage) end)
TabCoordsBtn.MouseButton1Click:Connect(function() switchTab(TabCoordsBtn, CoordsPage) end)

-- ==============================================================================
-- 6. PESTAÑA 1: EXPLORADOR
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
InfoTitle.Text = "📌 Seleccionado: (Ninguno) | Modo: 🦇 Bajo Piel de Roca"
InfoTitle.TextColor3 = Color3.fromRGB(90, 190, 255)
InfoTitle.TextSize = 10
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.TextXAlignment = Enum.TextXAlignment.Left
InfoTitle.Parent = InfoCard

local InfoDetails = Instance.new("TextLabel")
InfoDetails.Size = UDim2.new(1, -12, 0, 48)
InfoDetails.Position = UDim2.new(0, 6, 0, 25)
InfoDetails.BackgroundTransparency = 1
InfoDetails.Text = "Toca una fila para seleccionarla o pulsa '⬇️ BAJAR'. Puedes alternar entre 'Bajo Piel de Roca' y 'Búnker Dentro' en Config."
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
StopFlyBtn.Text = "🛑 DETENER TODO"
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
-- 7. PESTAÑA 2: PANEL DE CONFIGURACIÓN (SELECTOR DE MODO + PARÁMETROS)
-- ==============================================================================

-- Selector Principal de Modo
local ModeSelectorBtn = Instance.new("TextButton")
ModeSelectorBtn.Size = UDim2.new(1, -20, 0, 46)
ModeSelectorBtn.Position = UDim2.new(0, 10, 0, 8)
ModeSelectorBtn.BackgroundColor3 = Color3.fromRGB(115, 55, 175)
ModeSelectorBtn.Text = "MODO: 🦇 BAJO PIEL DE ROCA (RAYCAST INVERTIDO)"
ModeSelectorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeSelectorBtn.TextSize = 10
ModeSelectorBtn.Font = Enum.Font.GothamBold
ModeSelectorBtn.Parent = ConfigPage
Instance.new("UICorner", ModeSelectorBtn).CornerRadius = UDim.new(0, 8)

ModeSelectorBtn.MouseButton1Click:Connect(function()
    if Config.Mode == "UnderSkin" then
        Config.Mode = "Bunker"
        ModeSelectorBtn.BackgroundColor3 = Color3.fromRGB(35, 130, 95)
        ModeSelectorBtn.Text = "MODO: 🪨 BÚNKER DENTRO DE ROCA (EN SUELO REAL)"
        InfoTitle.Text = "📌 Modo Activo: 🪨 Búnker Dentro de Roca"
    else
        Config.Mode = "UnderSkin"
        ModeSelectorBtn.BackgroundColor3 = Color3.fromRGB(115, 55, 175)
        ModeSelectorBtn.Text = "MODO: 🦇 BAJO PIEL DE ROCA (RAYCAST INVERTIDO)"
        InfoTitle.Text = "📌 Modo Activo: 🦇 Bajo Piel de Roca"
    end
end)

local function createStepperControl(parent, yPos, titleText, getValText, onMinus, onPlus)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 52)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.60, -10, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = titleText .. "\n" .. getValText()
    lbl.TextColor3 = Color3.fromRGB(230, 235, 245)
    lbl.TextSize = 10
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local minusBtn = Instance.new("TextButton")
    minusBtn.Size = UDim2.new(0, 52, 0, 36)
    minusBtn.Position = UDim2.new(1, -118, 0, 8)
    minusBtn.BackgroundColor3 = Color3.fromRGB(160, 45, 55)
    minusBtn.Text = "➖"
    minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minusBtn.TextSize = 13
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.Parent = row
    Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

    local plusBtn = Instance.new("TextButton")
    plusBtn.Size = UDim2.new(0, 52, 0, 36)
    plusBtn.Position = UDim2.new(1, -60, 0, 8)
    plusBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
    plusBtn.Text = "➕"
    plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    plusBtn.TextSize = 13
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.Parent = row
    Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

    minusBtn.MouseButton1Click:Connect(function()
        onMinus()
        lbl.Text = titleText .. "\n" .. getValText()
    end)

    plusBtn.MouseButton1Click:Connect(function()
        onPlus()
        lbl.Text = titleText .. "\n" .. getValText()
    end)
end

-- Control 1: Ajuste fino de piel inferior
createStepperControl(
    ConfigPage, 62,
    "🎯 AJUSTE BAJO PIEL INFERIOR (STUDS)",
    function() return string.format("Actual: -%.1f studs bajo la piel real", Config.SkinOffset) end,
    function() Config.SkinOffset = math.max(0.0, Config.SkinOffset - 0.2) end,
    function() Config.SkinOffset = math.min(6.0, Config.SkinOffset + 0.2) end
)

-- Control 2: Velocidad de Bajada (Fly)
createStepperControl(
    ConfigPage, 120,
    "✈️ VELOCIDAD DE VUELO (FLY)",
    function() return string.format("Actual: %d studs/s", Config.FlySpeed) end,
    function() Config.FlySpeed = math.max(20, Config.FlySpeed - 10) end,
    function() Config.FlySpeed = math.min(250, Config.FlySpeed + 10) end
)

-- Control 3: Velocidad al Caminar hacia la roca
createStepperControl(
    ConfigPage, 178,
    "🚶 VELOCIDAD AL CAMINAR A LA ROCA",
    function() return string.format("Actual: %d WalkSpeed", Config.WalkSpeed) end,
    function() Config.WalkSpeed = math.max(16, Config.WalkSpeed - 4) end,
    function() Config.WalkSpeed = math.min(80, Config.WalkSpeed + 4) end
)

-- Control 4: Tiempo de espera antes de apagar Fly
createStepperControl(
    ConfigPage, 236,
    "⏱️ ESPERA ANTES DE SOLTAR FLY",
    function() return string.format("Actual: %.1f segundos tras quitar Noclip", Config.HoldSeconds) end,
    function() Config.HoldSeconds = math.max(0.2, Config.HoldSeconds - 0.2) end,
    function() Config.HoldSeconds = math.min(5.0, Config.HoldSeconds + 0.2) end
)

-- Control 5: Toggle Caminar Primero + Anclaje AFK
local WalkFirstToggle = Instance.new("TextButton")
WalkFirstToggle.Size = UDim2.new(0.5, -14, 0, 42)
WalkFirstToggle.Position = UDim2.new(0, 10, 0, 296)
WalkFirstToggle.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
WalkFirstToggle.Text = "🚶 CAMINAR PRIMERO: ON"
WalkFirstToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
WalkFirstToggle.TextSize = 9
WalkFirstToggle.Font = Enum.Font.GothamBold
WalkFirstToggle.Parent = ConfigPage
Instance.new("UICorner", WalkFirstToggle).CornerRadius = UDim.new(0, 8)

WalkFirstToggle.MouseButton1Click:Connect(function()
    Config.WalkFirst = not Config.WalkFirst
    if Config.WalkFirst then
        WalkFirstToggle.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
        WalkFirstToggle.Text = "🚶 CAMINAR PRIMERO: ON"
    else
        WalkFirstToggle.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        WalkFirstToggle.Text = "✈️ VOLAR DIRECTO: OFF"
    end
end)

local AnchorAfkBtn = Instance.new("TextButton")
AnchorAfkBtn.Size = UDim2.new(0.5, -14, 0, 42)
AnchorAfkBtn.Position = UDim2.new(0.5, 4, 0, 296)
AnchorAfkBtn.BackgroundColor3 = Color3.fromRGB(45, 85, 155)
AnchorAfkBtn.Text = "⚓ ANCLAR POSICIÓN AFK: OFF"
AnchorAfkBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AnchorAfkBtn.TextSize = 9
AnchorAfkBtn.Font = Enum.Font.GothamBold
AnchorAfkBtn.Parent = ConfigPage
Instance.new("UICorner", AnchorAfkBtn).CornerRadius = UDim.new(0, 8)

AnchorAfkBtn.MouseButton1Click:Connect(function()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = not root.Anchored
        if root.Anchored then
            AnchorAfkBtn.BackgroundColor3 = Color3.fromRGB(210, 120, 20)
            AnchorAfkBtn.Text = "⚓ ANCLADO AFK: ON"
        else
            AnchorAfkBtn.BackgroundColor3 = Color3.fromRGB(45, 85, 155)
            AnchorAfkBtn.Text = "⚓ ANCLAR POSICIÓN AFK: OFF"
        end
    end
end)

-- ==============================================================================
-- 8. PESTAÑA 3: COORDENADAS EN TIEMPO REAL
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
-- 9. RENDERIZADO DE LISTA SELECCIONABLE + BOTÓN DE ENTRADA EN CADA FILA
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
                executeRefugeEntry(obj.Part, function(statusMsg)
                    InfoDetails.Text = statusMsg .. string.format("\nModo: %s | Pieza: %s", Config.Mode, obj.Name)
                end)
            end)
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #State.FilteredObjects * 40)
end

-- ==============================================================================
-- 10. EVENTOS DE INTERFAZ Y INSPECCIÓN POR CLICK
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
    restoreGhostRocks()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then root.Anchored = false end
    InfoDetails.Text = "🛑 Movimiento, Fly, Noclip y Anclaje detenidos."
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
