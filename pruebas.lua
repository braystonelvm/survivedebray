-- ==============================================================================
-- AUTO-FARM CHATARRA EN PISTAS (1200 STUDS) + TELARAÑA AUTOMÁTICA (WIDGET NATIVO)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local Config = {
    AutoFarmScrap = false,
    DriveSpeed = 115,
    MaxSearchRadius = 1200,
    HitOffsetLimit = 16.0,

    -- Telaraña Automática y Relevos
    RelayTeleportEnabled = true,
    AutoGenerateWeb = true,
    NodeSpacing = 35,       -- Separación de bolitas en la pista
    RelayStepDist = 42,     -- Salto máximo permitido entre nodos
    PresenceRadius = 70,    -- Distancia a tu vehículo para mantener NetworkOwnership
    ItemsPerCycle = 2,      -- 1 a 2 ítems por ciclo (cero desync)
    SafeBaseRadius = 110    -- Radio protegido de la base central
}

local KnownRoads = {}
local AutoDeliveryNodes = {}
local CurrentTargetScrap = nil

-- Cursor visible siempre
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. IDENTIFICACIÓN Y MAPEO DE PISTAS (HASTA 1200 STUDS)
-- ==============================================================================

local function isRoadPiece(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
    local name = obj.Name:lower()
    return (name:find("straight") or name:find("road") or name:find("pista") or name:find("corner") or name:find("tsection"))
        and not name:find("barrier") and not name:find("debris")
end

local function clearAutoWebMarkers()
    table.clear(AutoDeliveryNodes)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name:find("AutoRelayNode_") then
            obj:Destroy()
        end
    end
end

local function generateAutoWebFromRoads()
    clearAutoWebMarkers()

    local roadList = {}
    for _, rData in pairs(KnownRoads) do
        table.insert(roadList, rData)
    end

    table.sort(roadList, function(a, b)
        return a.DistFromBase > b.DistFromBase
    end)

    for _, road in ipairs(roadList) do
        local rPos = road.Position
        local distBase = road.DistFromBase

        if distBase > Config.SafeBaseRadius and distBase <= Config.MaxSearchRadius then
            local isFarEnough = true

            for _, existingPos in ipairs(AutoDeliveryNodes) do
                if (rPos - existingPos).Magnitude < (Config.NodeSpacing * 0.75) then
                    isFarEnough = false
                    break
                end
            end

            if isFarEnough then
                table.insert(AutoDeliveryNodes, rPos)

                local marker = Instance.new("Part")
                marker.Name = "AutoRelayNode_" .. #AutoDeliveryNodes
                marker.Shape = Enum.PartType.Ball
                marker.Size = Vector3.new(2.2, 2.2, 2.2)
                marker.Material = Enum.Material.Neon
                marker.Color = Color3.fromRGB(0, 255, 170)
                marker.Anchored = true
                marker.CanCollide = false
                marker.Position = rPos + Vector3.new(0, 1.2, 0)
                marker.Parent = workspace
            end
        end
    end
end

local function scanNearbyRoads()
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("Tiles") or workspace
    local addedNew = false

    for _, obj in ipairs(mapFolder:GetDescendants()) do
        if isRoadPiece(obj) then
            local pos = obj:IsA("Model") and select(1, obj:GetBoundingBox()).Position or obj.Position
            local distFromCenter = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

            if distFromCenter <= Config.MaxSearchRadius then
                if not KnownRoads[obj] then
                    local size = obj:IsA("Model") and select(2, obj:GetBoundingBox()) or obj.Size
                    KnownRoads[obj] = {
                        Instance = obj,
                        Position = pos,
                        Size = size,
                        DistFromBase = distFromCenter
                    }
                    addedNew = true
                end
            end
        end
    end

    if addedNew and Config.AutoGenerateWeb then
        generateAutoWebFromRoads()
    end
end

-- ==============================================================================
-- 2. DETECCIÓN DE CHATARRA ESTRICTAMENTE EN CALZADA
-- ==============================================================================

local function isScrapTarget(model)
    if not model or not model:IsA("Model") then return false end
    local name = model.Name:lower()

    if name:find("scrap pile") or name:find("crashed car") then
        if model:GetAttribute("Dead") == true then return false end
        return true
    end
    return false
end

local function getRoadUnderPosition(worldPos)
    local closestRoad = nil
    local shortestDist = 32

    for _, roadData in pairs(KnownRoads) do
        local rPos = roadData.Position
        local horizDist = (Vector3.new(worldPos.X, 0, worldPos.Z) - Vector3.new(rPos.X, 0, rPos.Z)).Magnitude
        if horizDist < shortestDist then
            shortestDist = horizDist
            closestRoad = roadData
        end
    end
    return closestRoad
end

local function findNextScrapOnRoads(carPos)
    local struct = workspace:FindFirstChild("Structures") or workspace
    local bestScrap = nil
    local bestDist = math.huge

    for _, item in ipairs(struct:GetChildren()) do
        if isScrapTarget(item) then
            local p = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
            if p then
                local distFromBase = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
                if distFromBase <= Config.MaxSearchRadius then
                    local road = getRoadUnderPosition(p.Position)
                    if road then
                        local distToCar = (p.Position - carPos).Magnitude
                        if distToCar < bestDist then
                            bestDist = distToCar
                            bestScrap = item
                        end
                    end
                end
            end
        end
    end
    return bestScrap
end

-- ==============================================================================
-- 3. MOTOR DE CONDUCCIÓN ROAD-LOCK (SIN SALIR DE LA PISTA)
-- ==============================================================================

local function getCarRoot()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model")
        local rootPart = carModel and (carModel.PrimaryPart or seat) or seat
        return carModel, rootPart, seat
    end
    return nil, nil, nil
end

RunService.Heartbeat:Connect(function()
    if not Config.AutoFarmScrap then return end

    local carModel, carRoot = getCarRoot()
    if not carModel or not carRoot then return end

    local carPos = carRoot.Position

    if not CurrentTargetScrap or not CurrentTargetScrap.Parent or CurrentTargetScrap:GetAttribute("Dead") == true then
        CurrentTargetScrap = findNextScrapOnRoads(carPos)
    end

    local destPos = nil

    if CurrentTargetScrap and CurrentTargetScrap.Parent then
        local targetPart = CurrentTargetScrap.PrimaryPart or CurrentTargetScrap:FindFirstChildWhichIsA("BasePart")
        if targetPart then
            local targetPos = targetPart.Position
            local currentRoad = getRoadUnderPosition(targetPos)

            if currentRoad then
                local roadVec = (targetPos - currentRoad.Position)
                local roadHoriz = Vector3.new(roadVec.X, 0, roadVec.Z)
                local clampedOffset = roadHoriz.Unit * math.min(roadHoriz.Magnitude, Config.HitOffsetLimit)
                destPos = currentRoad.Position + clampedOffset
            else
                destPos = targetPos
            end
        end
    else
        local nearestRoad = getRoadUnderPosition(carPos)
        if nearestRoad then
            destPos = nearestRoad.Position
        end
    end

    if destPos then
        local dir = (destPos - carPos)
        local hDir = Vector3.new(dir.X, 0, dir.Z)

        if hDir.Magnitude > 2.5 then
            local driveVel = hDir.Unit * Config.DriveSpeed
            carRoot.AssemblyLinearVelocity = Vector3.new(driveVel.X, carRoot.AssemblyLinearVelocity.Y, driveVel.Z)
        end
    end
end)

-- ==============================================================================
-- 4. TELARAÑA DE RELEVOS ESCALONADA (RELAY TELEPORT)
-- ==============================================================================

local function findNextRelayStep(currentPos)
    local bestNode = nil
    local currentDistToBase = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
    local shortestJump = math.huge

    for _, nodePos in ipairs(AutoDeliveryNodes) do
        local nodeDistToBase = (Vector3.new(nodePos.X, 0, nodePos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        local jumpDist = (currentPos - nodePos).Magnitude

        if nodeDistToBase < (currentDistToBase - 6) and jumpDist <= Config.RelayStepDist then
            if jumpDist < shortestJump then
                shortestJump = jumpDist
                bestNode = nodePos
            end
        end
    end

    if not bestNode and currentDistToBase <= (Config.SafeBaseRadius + 30) then
        bestNode = BaseCenter + Vector3.new(0, 1.5, 0)
    end

    return bestNode
end

task.spawn(function()
    while true do
        task.wait(0.25)
        if Config.RelayTeleportEnabled and #AutoDeliveryNodes > 0 then
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local myPos = root and root.Position

            local dropped = workspace:FindFirstChild("DroppedItems")
            if dropped and myPos then
                local movedCount = 0

                for _, item in ipairs(dropped:GetChildren()) do
                    if movedCount >= Config.ItemsPerCycle then break end

                    local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                    if part and not part.Anchored then
                        local itemPos = part.Position
                        local distToMe = (itemPos - myPos).Magnitude

                        if distToMe <= Config.PresenceRadius then
                            local distToBase = (Vector3.new(itemPos.X, 0, itemPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

                            if distToBase > Config.SafeBaseRadius then
                                local nextTargetPos = findNextRelayStep(itemPos)
                                if nextTargetPos then
                                    movedCount = movedCount + 1

                                    local stepCFrame = CFrame.new(nextTargetPos + Vector3.new(0, 0.8, 0))
                                    if item:IsA("Model") then
                                        item:PivotTo(stepCFrame)
                                    else
                                        part.CFrame = stepCFrame
                                    end

                                    part.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
                                    part.AssemblyAngularVelocity = Vector3.zero
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ==============================================================================
-- 5. INTERFAZ VISUAL NATIVA Y WIDGET FLOTANTE (ESTILO RADAR)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ScrapRoadFarmProGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Widget Flotante Circular
local WidgetBtn = Instance.new("TextButton")
WidgetBtn.Size = UDim2.new(0, 52, 0, 52)
WidgetBtn.Position = UDim2.new(0.04, 0, 0.48, 0)
WidgetBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
WidgetBtn.Text = "🚜\nAUTO"
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
MainFrame.Size = UDim2.new(0, 460, 0, 390)
MainFrame.Position = UDim2.new(0.5, -230, 0.5, -195)
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
TitleBar.Text = "  🚜 AUTO-FARM CHATARRA EN PISTAS | TELARAÑA 1200M"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Interruptor de Auto-Manejo en Pistas
local FarmToggle = Instance.new("TextButton")
FarmToggle.Size = UDim2.new(0.48, -8, 0, 34)
FarmToggle.Position = UDim2.new(0, 10, 0, 44)
FarmToggle.BackgroundColor3 = Color3.fromRGB(150, 35, 40)
FarmToggle.Text = "🚜 AUTO-MANEJO: OFF"
FarmToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
FarmToggle.TextSize = 10
FarmToggle.Font = Enum.Font.GothamBold
FarmToggle.Parent = MainFrame

local FarmToggleCorner = Instance.new("UICorner")
FarmToggleCorner.CornerRadius = UDim.new(0, 6)
FarmToggleCorner.Parent = FarmToggle

-- Interruptor de Telaraña Automática
local RelayToggle = Instance.new("TextButton")
RelayToggle.Size = UDim2.new(0.48, -8, 0, 34)
RelayToggle.Position = UDim2.new(0.52, 0, 0, 44)
RelayToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
RelayToggle.Text = "🕸️ TELARAÑA: ON"
RelayToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
RelayToggle.TextSize = 10
RelayToggle.Font = Enum.Font.GothamBold
RelayToggle.Parent = MainFrame

local RelayToggleCorner = Instance.new("UICorner")
RelayToggleCorner.CornerRadius = UDim.new(0, 6)
RelayToggleCorner.Parent = RelayToggle

FarmToggle.MouseButton1Click:Connect(function()
    Config.AutoFarmScrap = not Config.AutoFarmScrap
    if Config.AutoFarmScrap then
        FarmToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
        FarmToggle.Text = "🚜 AUTO-MANEJO: ON"
        scanNearbyRoads()
    else
        FarmToggle.BackgroundColor3 = Color3.fromRGB(150, 35, 40)
        FarmToggle.Text = "🚜 AUTO-MANEJO: OFF"
        CurrentTargetScrap = nil
        local _, carRoot = getCarRoot()
        if carRoot then
            carRoot.AssemblyLinearVelocity = Vector3.new(0, carRoot.AssemblyLinearVelocity.Y, 0)
        end
    end
end)

RelayToggle.MouseButton1Click:Connect(function()
    Config.RelayTeleportEnabled = not Config.RelayTeleportEnabled
    if Config.RelayTeleportEnabled then
        RelayToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
        RelayToggle.Text = "🕸️ TELARAÑA: ON"
        if #AutoDeliveryNodes == 0 then generateAutoWebFromRoads() end
    else
        RelayToggle.BackgroundColor3 = Color3.fromRGB(150, 35, 40)
        RelayToggle.Text = "🕸️ TELARAÑA: OFF"
    end
end)

-- Velocidad en Pista
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(0.68, 0, 0, 24)
SpeedLabel.Position = UDim2.new(0, 10, 0, 88)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "Velocidad del Vehículo (Studs/s):"
SpeedLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
SpeedLabel.TextSize = 10
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Parent = MainFrame

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(0.28, -10, 0, 26)
SpeedBox.Position = UDim2.new(0.72, 0, 0, 88)
SpeedBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
SpeedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SpeedBox.Text = tostring(Config.DriveSpeed)
SpeedBox.TextSize = 11
SpeedBox.Font = Enum.Font.Code
SpeedBox.ClearTextOnFocus = false
SpeedBox.Parent = MainFrame

local SpeedCorner = Instance.new("UICorner")
SpeedCorner.CornerRadius = UDim.new(0, 4)
SpeedCorner.Parent = SpeedBox

SpeedBox.FocusLost:Connect(function()
    local val = tonumber(SpeedBox.Text)
    if val then Config.DriveSpeed = math.clamp(math.floor(val), 40, 200) end
    SpeedBox.Text = tostring(Config.DriveSpeed)
end)

-- Radio de Búsqueda (Studs)
local RadiusLabel = Instance.new("TextLabel")
RadiusLabel.Size = UDim2.new(0.68, 0, 0, 24)
RadiusLabel.Position = UDim2.new(0, 10, 0, 122)
RadiusLabel.BackgroundTransparency = 1
RadiusLabel.Text = "Radio Radial de Pistas (Studs):"
RadiusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
RadiusLabel.TextSize = 10
RadiusLabel.Font = Enum.Font.GothamBold
RadiusLabel.TextXAlignment = Enum.TextXAlignment.Left
RadiusLabel.Parent = MainFrame

local RadiusBox = Instance.new("TextBox")
RadiusBox.Size = UDim2.new(0.28, -10, 0, 26)
RadiusBox.Position = UDim2.new(0.72, 0, 0, 122)
RadiusBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
RadiusBox.TextColor3 = Color3.fromRGB(255, 255, 255)
RadiusBox.Text = tostring(Config.MaxSearchRadius)
RadiusBox.TextSize = 11
RadiusBox.Font = Enum.Font.Code
RadiusBox.ClearTextOnFocus = false
RadiusBox.Parent = MainFrame

local RadiusCorner = Instance.new("UICorner")
RadiusCorner.CornerRadius = UDim.new(0, 4)
RadiusCorner.Parent = RadiusBox

RadiusBox.FocusLost:Connect(function()
    local val = tonumber(RadiusBox.Text)
    if val then
        Config.MaxSearchRadius = math.clamp(math.floor(val), 200, 1500)
        scanNearbyRoads()
    end
    RadiusBox.Text = tostring(Config.MaxSearchRadius)
end)

-- Monitor de Estado en Tiempo Real
local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(1, -20, 0, 130)
StatusFrame.Position = UDim2.new(0, 10, 0, 160)
StatusFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
StatusFrame.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusFrame

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -16, 1, -10)
StatusText.Position = UDim2.new(0, 8, 0, 5)
StatusText.BackgroundTransparency = 1
StatusText.Text = "Iniciando sistema vial..."
StatusText.TextColor3 = Color3.fromRGB(255, 205, 80)
StatusText.TextSize = 10
StatusText.Font = Enum.Font.Code
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.TextYAlignment = Enum.TextYAlignment.Top
StatusText.Parent = StatusFrame

-- Botón Forzar Regeneración de Telaraña
local RegenWebBtn = Instance.new("TextButton")
RegenWebBtn.Size = UDim2.new(0.48, -8, 0, 36)
RegenWebBtn.Position = UDim2.new(0, 10, 0, 338)
RegenWebBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 80)
RegenWebBtn.Text = "🔄 REGENERAR TELARAÑA"
RegenWebBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RegenWebBtn.TextSize = 10
RegenWebBtn.Font = Enum.Font.GothamBold
RegenWebBtn.Parent = MainFrame

local RegenCorner = Instance.new("UICorner")
RegenCorner.CornerRadius = UDim.new(0, 6)
RegenCorner.Parent = RegenWebBtn

RegenWebBtn.MouseButton1Click:Connect(function()
    scanNearbyRoads()
    generateAutoWebFromRoads()
end)

-- Botón Limpiar Bolitas
local ClearWebBtn = Instance.new("TextButton")
ClearWebBtn.Size = UDim2.new(0.48, -8, 0, 36)
ClearWebBtn.Position = UDim2.new(0.52, 0, 0, 338)
ClearWebBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
ClearWebBtn.Text = "🗑️ LIMPIAR BOLITAS"
ClearWebBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearWebBtn.TextSize = 10
ClearWebBtn.Font = Enum.Font.GothamBold
ClearWebBtn.Parent = MainFrame

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 6)
ClearCorner.Parent = ClearWebBtn

ClearWebBtn.MouseButton1Click:Connect(function()
    clearAutoWebMarkers()
end)

WidgetBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Actualización periódica de textos
task.spawn(function()
    while true do
        task.wait(0.4)
        local roadCount = 0
        for _ in pairs(KnownRoads) do roadCount = roadCount + 1 end

        local targetInfo = "Ninguno (Buscando en pista...)"
        if CurrentTargetScrap and CurrentTargetScrap.Parent then
            local part = CurrentTargetScrap.PrimaryPart or CurrentTargetScrap:FindFirstChildWhichIsA("BasePart")
            local d = part and math.floor((part.Position - (lp.Character and lp.Character:GetPivot().Position or Vector3.zero)).Magnitude) or 0
            targetInfo = string.format("%s (%dm)", CurrentTargetScrap.Name, d)
        end

        StatusText.Text = string.format(
            "📍 Pistas Mapeadas: %d / Radio: %dm\n🎯 Objetivo Actual: %s\n🕸️ Nodos Telaraña Activos: %d bolitas\n⚡ Estado Manejo: %s\n📦 Modo Relevo: %s (Max 2 ítems/ciclo)",
            roadCount,
            Config.MaxSearchRadius,
            targetInfo,
            #AutoDeliveryNodes,
            Config.AutoFarmScrap and "🟢 CONDUCIENDO" or "🔴 DETENIDO",
            Config.RelayTeleportEnabled and "🟢 ACTIVO" or "🔴 OFF"
        )
    end
end)

-- Escanear pistas que carguen por streaming en tiempo real
workspace.DescendantAdded:Connect(function(desc)
    if isRoadPiece(desc) then
        task.wait(0.15)
        scanNearbyRoads()
    end
end)

scanNearbyRoads()
