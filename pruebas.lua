-- ==============================================================================
-- SCRAP ROAD-PATROL V2.0: AUTO-GENERADOR DE TELARAÑA + CONDUCCIÓN EN PISTAS
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local Config = {
    AutoFarmScrap = false,
    DriveSpeed = 110,
    MaxSearchRadius = 1200,
    HitOffsetLimit = 16.0,

    -- Telaraña Automática y Relevo
    RelayTeleportEnabled = true,
    AutoGenerateWeb = true,
    NodeSpacing = 35,       -- Distancia entre bolitas automáticas sobre la pista
    RelayStepDist = 40,     -- Rango de salto permitido entre nodos
    PresenceRadius = 70,    -- Distancia a tu auto para no perder NetworkOwnership
    ItemsPerCycle = 2,      -- 1 a 2 ítems por tanda (0% lag / cero rollback)
    SafeBaseRadius = 110    -- Radio de la base central donde se suelta el material
}

local KnownRoads = {}
local AutoDeliveryNodes = {}
local CurrentTargetScrap = nil

RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. IDENTIFICACIÓN Y MAPEO DINÁMICO DE PISTAS (HASTA 1200 STUDS)
-- ==============================================================================

local function isRoadPiece(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
    local name = obj.Name:lower()
    return (name:find("straight") or name:find("road") or name:find("pista") or name:find("corner") or name:find("tsection"))
        and not name:find("barrier") and not name:find("debris")
end

-- ==============================================================================
-- 2. GENERADOR AUTOMÁTICO DE TELARAÑA (CADENA DE RELEVOS HACIA LA BASE)
-- ==============================================================================

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

    -- Ordenar las pistas de afuera hacia adentro (mayor distancia a menor distancia de base)
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

        -- Solo generar nodos fuera del radio protegido de la base y dentro del radio máximo
        if distBase > Config.SafeBaseRadius and distBase <= Config.MaxSearchRadius then
            local isFarEnoughFromOthers = true

            for _, existingPos in ipairs(AutoDeliveryNodes) do
                if (rPos - existingPos).Magnitude < (Config.NodeSpacing * 0.75) then
                    isFarEnoughFromOthers = false
                    break
                end
            end

            if isFarEnoughFromOthers then
                table.insert(AutoDeliveryNodes, rPos)

                -- Marcador visual (bolita verde neón que guía el camino a la base)
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
-- 3. DETECCIÓN Y FILTRO DE CHATARRA ESTRICTAMENTE EN PISTA
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
-- 4. CONDUCCIÓN AUTOMÁTICA ROAD-LOCK (NUNCA PISA FUERA DE LA CALZADA)
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
        -- Si no hay chatarra cerca, mantenerse patrullando pistas conocidas
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
-- 5. MOTOR DE TELETRANSPORTE ESCALONADO (TELARAÑA AUTOMÁTICA / BUCKET-BRIGADE)
-- ==============================================================================

local function findNextRelayStep(currentPos)
    local bestNode = nil
    local currentDistToBase = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
    local shortestJump = math.huge

    for _, nodePos in ipairs(AutoDeliveryNodes) do
        local nodeDistToBase = (Vector3.new(nodePos.X, 0, nodePos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        local jumpDist = (currentPos - nodePos).Magnitude

        -- Escalonamiento: el salto debe acercarlo hacia la base pero en distancia corta
        if nodeDistToBase < (currentDistToBase - 6) and jumpDist <= Config.RelayStepDist then
            if jumpDist < shortestJump then
                shortestJump = jumpDist
                bestNode = nodePos
            end
        end
    end

    -- Si ya está cerca del perímetro interior de la base, el relevo final va al centro
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

                        -- Solo teletransporta materiales si estás presente para no romper el socket de red
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
-- 6. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | ROAD & AUTO-WEB V2.0",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 490),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Farm   = Window:AddTab({ Title = "Auto-Farm Chatarra", Icon = "truck" }),
    Relay  = Window:AddTab({ Title = "Telaraña Automática", Icon = "network" })
}

Tabs.Farm:AddSection("Atropello en Pistas")

Tabs.Farm:AddToggle("FarmToggle", {
    Title = "⚡ Activar Auto-Atropello en Pistas",
    Default = false,
    Callback = function(v)
        Config.AutoFarmScrap = v
        if v then scanNearbyRoads() end
    end
})

Tabs.Farm:AddSlider("SpeedSlider", {
    Title = "Velocidad en Pista (Studs/s)",
    Default = 110,
    Min = 50,
    Max = 180,
    Rounding = 0,
    Callback = function(v) Config.DriveSpeed = v end
})

Tabs.Farm:AddSlider("RadiusSlider", {
    Title = "Radio Máximo de Pistas (Studs)",
    Default = 1200,
    Min = 300,
    Max = 1500,
    Rounding = 0,
    Callback = function(v)
        Config.MaxSearchRadius = v
        scanNearbyRoads()
    end
})

local FarmStatus = Tabs.Farm:AddParagraph({
    Title = "Estado de Farm",
    Content = "Inactivo..."
})

-- PESTAÑA TELARAÑA AUTOMÁTICA
Tabs.Relay:AddSection("Telaraña Dinámica (0% Lag / Cero Rollback)")

Tabs.Relay:AddToggle("RelayToggle", {
    Title = "Activar Teletransporte Escalonado",
    Default = true,
    Callback = function(v) Config.RelayTeleportEnabled = v end
})

Tabs.Relay:AddToggle("AutoWebToggle", {
    Title = "🕸️ Auto-Generar Telaraña sobre Pistas",
    Default = true,
    Callback = function(v)
        Config.AutoGenerateWeb = v
        if v then
            generateAutoWebFromRoads()
        else
            clearAutoWebMarkers()
        end
    end
})

Tabs.Relay:AddSlider("NodeSpacingSlider", {
    Title = "Distancia entre Bolitas de Pista (Studs)",
    Default = 35,
    Min = 20,
    Max = 60,
    Rounding = 0,
    Callback = function(v)
        Config.NodeSpacing = v
        if Config.AutoGenerateWeb then generateAutoWebFromRoads() end
    end
})

Tabs.Relay:AddSlider("PresenceSlider", {
    Title = "Radio de Presencia del Auto (Studs)",
    Default = 70,
    Min = 30,
    Max = 120,
    Rounding = 0,
    Callback = function(v) Config.PresenceRadius = v end
})

Tabs.Relay:AddButton({
    Title = "🔄 Regenerar Telaraña de Pistas Ahora",
    Callback = function()
        scanNearbyRoads()
        generateAutoWebFromRoads()
        Fluent:Notify({
            Title = "Telaraña Actualizada",
            Content = string.format("%d bolitas creadas hacia la base.", #AutoDeliveryNodes),
            Duration = 2.5
        })
    end
})

task.spawn(function()
    while true do
        task.wait(0.5)
        local roadCount = 0
        for _ in pairs(KnownRoads) do roadCount = roadCount + 1 end
        local tName = CurrentTargetScrap and CurrentTargetScrap.Name or "Buscando en calzada..."

        FarmStatus:SetDesc(string.format("Pistas Mapeadas: %d\nObjetivo: %s\nNodos Telaraña Activos: %d",
            roadCount,
            tName,
            #AutoDeliveryNodes
        ))
    end
end)

-- Actualización continua por streaming
workspace.DescendantAdded:Connect(function(desc)
    if isRoadPiece(desc) then
        task.wait(0.2)
        scanNearbyRoads()
    end
end)

scanNearbyRoads()
