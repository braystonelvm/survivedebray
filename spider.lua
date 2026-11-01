-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER, VIRTUAL WEB 1500m & GHOST-PROOF TRANSPORT V4.4
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local Config = {
    MaxMapRadius = 1500,

    -- Auto-Conducción por Pistas (Velocidad 115)
    AutoFarmRoads = false,
    VehicleSpeed = 115,
    RoadMaxHalfWidth = 12,
    ScrapSearchRadius = 450,
    CrushOvershoot = 16,

    -- Sistema de Transporte Seguro Anti-Fantasmas
    AutoSendItems = true,
    TransportMode = "Impulso Seguro (Anti-Fantasma)", -- Nuevo modo por defecto
    ItemsPerTick = 2,
    CollectRadius = 10,
    KickDistance = 85,
    KickArcHeight = 12,          -- Altura controlada para no violar límites
    TeleportInterval = 0.22,

    -- Filtros de Objetos
    MoveScrapAndMetal = true,
    MoveFuelCans = true,
    MoveAllResources = true,

    -- Red Virtual de 1500m + Puntos Manuales
    ChainTeleport = true,
    BasePrevent = true,
    GeneratorSafeRadius = 145,
    WebStepDistance = 35,
    WebGroundHeight = 0.6,
    SpreadRadius = 1.8,
    ShowWebVisuals = false,

    -- Auto-Eat Integrado
    AutoEatEnabled = true,
    EatHealthThreshold = 60,
    EatHungerThreshold = 50,
    EatScanRadius = 24,
    EatCooldown = 0.9,

    -- Auto-Gasolina
    AutoRefuelEnabled = true,
    LowFuelThreshold = 25,
    FullFuelThreshold = 90,
    FuelCanScanRadius = 45,

    -- Auditoría Forense
    ForensicLogging = true
}

local RoadNodes = {}
local VirtualWebGrid = {}
local ManualDeliveryPoints = {}
local VisualPool = {}
local RoadScrapList = {}
local IgnoredScrapUntil = {}
local RecentlyKicked = {}

local CachedGeneratorPos = nil
local CurrentScrapTarget = nil
local IsRecoveringToRoad = false

local ScrapForensicHistory = {}
local TotalForensicLogs = 0

local RoadTransit = {
    Waypoints = {},
    Index = 1,
    CurrentDirection = Vector3.new(0, 0, 1)
}

local AutoEatState = {
    IsEating = false,
    LastEatTick = 0,
    Status = "Monitoreando..."
}

local FuelState = {
    IsRefueling = false,
    CurrentFuel = 100,
    MaxFuel = 100,
    FuelPct = 100,
    Status = "Tanque OK"
}

local PickUpRemote = nil
task.spawn(function()
    local remFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
    local intFolder = remFolder and remFolder:WaitForChild("Interaction", 5)
    if intFolder then
        PickUpRemote = intFolder:WaitForChild("PickUpItem", 5)
    end
end)

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. MONITOR FORENSE
-- ==============================================================================

local function inspectScrapDetailed(targetEntity, mainPart, root)
    local report = {}
    report.Timestamp = os.date("%X")
    report.Name = targetEntity.Name
    report.Class = targetEntity.ClassName

    local pPos = mainPart and mainPart.Position or Vector3.zero
    local rPos = root and root.Position or Vector3.zero
    report.DistanceToPlayer = math.floor((pPos - rPos).Magnitude * 10) / 10
    report.WorldPos = string.format("(%.1f, %.1f, %.1f)", pPos.X, pPos.Y, pPos.Z)

    report.Anchored = mainPart and mainPart.Anchored
    report.CanCollide = mainPart and mainPart.CanCollide
    report.Mass = mainPart and math.floor(mainPart:GetMass() * 10) / 10 or 0
    report.Velocity = mainPart and string.format("(%.1f, %.1f, %.1f)", mainPart.AssemblyLinearVelocity.X, mainPart.AssemblyLinearVelocity.Y, mainPart.AssemblyLinearVelocity.Z) or "N/A"

    local det = targetEntity:FindFirstChild("ItemDrag", true) 
        or targetEntity:FindFirstChildWhichIsA("DragDetector", true)
        or targetEntity:FindFirstChildWhichIsA("ClickDetector", true)
    
    if det then
        report.Detector = det.ClassName .. "('" .. det.Name .. "')"
    else
        report.Detector = "❌ ELIMINADO POR SERVIDOR (FANTASMA)"
    end

    return report
end

local function recordForensicIncident(stage, entity, mainPart, root, extraDetails)
    if not Config.ForensicLogging then return end
    TotalForensicLogs = TotalForensicLogs + 1

    local data = inspectScrapDetailed(entity, mainPart, root)
    data.Stage = stage
    data.Details = extraDetails or ""

    table.insert(ScrapForensicHistory, 1, data)
    if #ScrapForensicHistory > 45 then
        table.remove(ScrapForensicHistory)
    end
end

-- ==============================================================================
-- 2. PERSONAJE, STATS Y VEHÍCULO
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getPlayerStats()
    local char, _, hum = getCharacterParts()
    if not hum then return 100, 100 end

    local hpPct = math.floor((hum.Health / math.max(hum.MaxHealth, 1)) * 100)
    local hunger = char:GetAttribute("Hunger") or lp:GetAttribute("Hunger") or 100
    local maxHunger = char:GetAttribute("MaxHunger") or lp:GetAttribute("MaxHunger") or 100
    local hungerPct = math.floor((hunger / maxHunger) * 100)

    return hpPct, hungerPct
end

local function getVehicleRootModel(seat)
    if not seat then return nil end
    local current = seat
    local topModel = seat:FindFirstAncestorOfClass("Model")
    while current and current ~= workspace do
        if current:IsA("Model") then
            topModel = current
            local pName = current.Parent and current.Parent.Name:lower() or ""
            if current.Parent == workspace or pName == "structures" or pName == "vehicles" or pName == "map" then
                return current
            end
        end
        current = current.Parent
    end
    return topModel
end

local function getCurrentVehicle()
    local _, _, hum = getCharacterParts()
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local model = getVehicleRootModel(seat)
        return model, seat
    end
    return nil, nil
end

local function applyBrake(duration)
    duration = duration or 0.8
    task.spawn(function()
        local endTime = tick() + duration
        while tick() < endTime do
            local _, root, hum = getCharacterParts()
            if root and hum and hum.SeatPart then
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                root.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- ==============================================================================
-- 3. AUTO-COMER
-- ==============================================================================

local function isGoldenCarrot(item)
    if item:GetAttribute("Golden") == true or item:GetAttribute("Rarity") == "Golden" then
        return true
    end
    local mainPart = item:FindFirstChild("MainPart") or item:FindFirstChildWhichIsA("BasePart")
    if mainPart and (mainPart.Material == Enum.Material.Metal or mainPart.Color.R > 0.9) then
        return true
    end
    return false
end

local function findBestGroundFood(onlyGolden)
    local _, root = getCharacterParts()
    if not root then return nil end
    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local myPos = root.Position
    local bestItem = nil
    local maxRadius = Config.EatScanRadius
    local shortestDistSq = maxRadius * maxRadius

    for _, item in ipairs(dropped:GetChildren()) do
        local isFood = (item:GetAttribute("ItemType") == "Food") or item.Name:lower():find("carrot")
        if isFood and item:GetAttribute("CanPickUp") ~= false then
            local isGold = isGoldenCarrot(item)
            if not onlyGolden or isGold then
                local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                if part then
                    local pPos = part.Position
                    local dx = pPos.X - myPos.X
                    local dz = pPos.Z - myPos.Z
                    if math.abs(dx) <= maxRadius and math.abs(dz) <= maxRadius then
                        local dy = pPos.Y - myPos.Y
                        local distSq = (dx * dx) + (dy * dy) + (dz * dz)
                        if distSq <= shortestDistSq then
                            shortestDistSq = distSq
                            bestItem = item
                        end
                    end
                end
            end
        end
    end
    return bestItem
end

local function eatGroundFood(onlyGolden)
    if AutoEatState.IsEating or not PickUpRemote then return end
    if (tick() - AutoEatState.LastEatTick) < Config.EatCooldown then return end

    local char, _, hum = getCharacterParts()
    if not hum or hum.Health <= 0 then return end

    local targetFood = findBestGroundFood(onlyGolden)
    if not targetFood then return end

    AutoEatState.IsEating = true
    pcall(function() PickUpRemote:FireServer(targetFood) end)

    local foodTool = nil
    local startWait = tick()

    while (tick() - startWait) < 0.6 do
        for _, cont in ipairs({char, lp:FindFirstChild("Backpack")}) do
            if cont then
                for _, item in ipairs(cont:GetChildren()) do
                    if item:IsA("Tool") and (item:GetAttribute("ItemType") == "Food" or item.Name:lower():find("carrot")) then
                        foodTool = item
                        break
                    end
                end
            end
        end
        if foodTool then break end
        task.wait(0.04)
    end

    if foodTool then
        if foodTool.Parent ~= char then hum:EquipTool(foodTool); task.wait(0.05) end
        pcall(function() foodTool:Activate() end)
        local useRemote = foodTool:FindFirstChild("Use") or foodTool:FindFirstChild("Consume")
        if useRemote and useRemote:IsA("RemoteEvent") then pcall(function() useRemote:FireServer() end) end
        task.wait(0.20)
    end

    AutoEatState.LastEatTick = tick()
    AutoEatState.IsEating = false
end

task.spawn(function()
    while true do
        task.wait(0.35)
        if Config.AutoEatEnabled then
            local hpPct, hungerPct = getPlayerStats()
            if hpPct <= Config.EatHealthThreshold then
                eatGroundFood(true)
            elseif hungerPct <= Config.EatHungerThreshold then
                eatGroundFood(false)
            else
                AutoEatState.Status = string.format("🟢 OK (Vida: %d%% | Comida: %d%%)", hpPct, hungerPct)
            end
        end
    end
end)

-- ==============================================================================
-- 4. AUTO-GASOLINA
-- ==============================================================================

local function getTruckFuel(truck)
    if not truck then return 100, 100, 100 end
    local foundFuel, foundMax = nil, nil
    local config = truck:FindFirstChild("Configuration", true) or truck:FindFirstChild("Config", true)
    if config then
        for _, attr in ipairs({"Fuel", "Gas", "Gasoline", "Petrol"}) do
            local val = config:GetAttribute(attr)
            if val and type(val) == "number" then
                foundFuel = val
                foundMax = config:GetAttribute("Max" .. attr) or 100
                break
            end
        end
    end
    foundFuel = foundFuel or 100
    foundMax = foundMax or 100
    return foundFuel, foundMax, math.clamp(math.floor((foundFuel / foundMax) * 100), 0, 100)
end

local function getTruckFuelReceptor(truck, seat)
    for _, desc in ipairs(truck:GetDescendants()) do
        if desc:IsA("BasePart") then
            local n = desc.Name:lower()
            if n:find("fuel") or n:find("tank") or n:find("gas") or n:find("cap") then
                return desc, desc.Position
            end
        end
    end
    local refCF = (seat and seat.CFrame) or (truck.PrimaryPart and truck.PrimaryPart.CFrame) or CFrame.new()
    return truck.PrimaryPart or seat, (refCF * CFrame.new(-3.4, 0.8, 5.2)).Position
end

local function refuelTruckFromNearbyCan()
    local truck, seat = getCurrentVehicle()
    if not truck or not seat then return false end

    local _, root = getCharacterParts()
    local myPos = root and root.Position or seat.Position
    local receptorPart, tankWorldPos = getTruckFuelReceptor(truck, seat)

    local bestCan, bestPart = nil, nil
    local shortest = Config.FuelCanScanRadius

    for _, folder in ipairs({workspace:FindFirstChild("DroppedItems"), workspace:FindFirstChild("Structures"), workspace}) do
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                if (item:IsA("Model") or item:IsA("BasePart")) and item ~= truck and item ~= lp.Character then
                    local n = item.Name:lower()
                    if n == "fuel" or n == "refined fuel" or n:find("fuel") or n:find("gas") then
                        local p = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                        if p then
                            local d = (p.Position - myPos).Magnitude
                            if d < shortest then
                                shortest = d
                                bestCan = item
                                bestPart = p
                            end
                        end
                    end
                end
            end
        end
        if bestCan then break end
    end

    if bestCan and bestPart then
        local targetCF = CFrame.new(tankWorldPos)
        if bestCan:IsA("Model") then
            for _, p in ipairs(bestCan:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
            bestCan:PivotTo(targetCF)
        else
            bestPart.Anchored = false
            bestPart.CFrame = targetCF
        end
        if firetouchinterest and receptorPart then
            pcall(function()
                firetouchinterest(bestPart, receptorPart, 0)
                firetouchinterest(bestPart, receptorPart, 1)
            end)
        end
        return true
    end
    return false
end

-- ==============================================================================
-- 5. RED VIRTUAL 1500m
-- ==============================================================================

local function getGeneratorPosition()
    if CachedGeneratorPos then return CachedGeneratorPos end
    local gen = workspace:FindFirstChild("Generator") or workspace:FindFirstChild("Center")
    if gen then
        local p = (gen:IsA("Model") and (gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart"))) or gen
        if p and p:IsA("BasePart") then
            CachedGeneratorPos = p.Position
            return CachedGeneratorPos
        end
    end
    return BaseCenter
end

local function rebuildSpiderwebNetwork()
    table.clear(VirtualWebGrid)
    local genPos = getGeneratorPosition()
    local step = math.max(15, Config.WebStepDistance)
    local maxR = Config.MaxMapRadius
    local safeR = math.max(40, Config.GeneratorSafeRadius - 12)

    for r = safeR, maxR, step do
        local circumference = 2 * math.pi * r
        local numPoints = math.max(8, math.floor(circumference / step))
        for i = 1, numPoints do
            local angle = (i / numPoints) * (math.pi * 2)
            local px = genPos.X + math.cos(angle) * r
            local pz = genPos.Z + math.sin(angle) * r
            table.insert(VirtualWebGrid, Vector3.new(px, Config.WebGroundHeight, pz))
        end
    end

    for _, m in ipairs(ManualDeliveryPoints) do
        if m and m.Parent then table.insert(VirtualWebGrid, m.Position) end
    end
end

rebuildSpiderwebNetwork()

-- ==============================================================================
-- 6. MAPEO DE PISTAS Y CHATARRA EN PISTA
-- ==============================================================================

local function isRoadObject(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    return (n:find("straight") or n:find("road") or n:find("pista") or n:find("corner") or n:find("tsection"))
        and not (n:find("sign") or n:find("light") or n:find("lamp") or n:find("railing"))
end

local function registerRoadPiece(obj)
    local pos = obj:IsA("Model") and select(1, obj:GetBoundingBox()).Position or obj.Position
    local size = obj:IsA("Model") and select(2, obj:GetBoundingBox()) or obj.Size
    local distFromCenter = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
    if distFromCenter > 1550 or distFromCenter < 92 then return end

    for _, node in ipairs(RoadNodes) do
        if (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 20 then return end
    end

    table.insert(RoadNodes, {
        Pos = Vector3.new(pos.X, Config.WebGroundHeight, pos.Z),
        Size = size,
        Instance = obj,
        LastVisited = 0
    })
end

task.spawn(function()
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("Tiles") or workspace
    for _, desc in ipairs(mapFolder:GetDescendants()) do
        if isRoadObject(desc) then registerRoadPiece(desc) end
    end
end)

local function getRoadInfoAtPosition(pos, respectMaxRadius)
    local bestNode = nil
    local minEdgeDist = math.huge
    local closestSurfacePoint = pos

    for _, node in ipairs(RoadNodes) do
        local distBase = (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        if not respectMaxRadius or distBase <= Config.MaxMapRadius then
            local dx = math.abs(pos.X - node.Pos.X)
            local dz = math.abs(pos.Z - node.Pos.Z)
            local halfX = math.max((node.Size.X * 0.48), 13)
            local halfZ = math.max((node.Size.Z * 0.48), 13)
            local overX = math.max(0, dx - halfX)
            local overZ = math.max(0, dz - halfZ)
            local edgeDist = math.sqrt(overX * overX + overZ * overZ)

            if edgeDist < minEdgeDist then
                minEdgeDist = edgeDist
                bestNode = node
                local clampedX = math.clamp(pos.X - node.Pos.X, -halfX + 4, halfX - 4)
                local clampedZ = math.clamp(pos.Z - node.Pos.Z, -halfZ + 4, halfZ - 4)
                closestSurfacePoint = Vector3.new(node.Pos.X + clampedX, node.Pos.Y, node.Pos.Z + clampedZ)
            end
        end
    end
    return bestNode, minEdgeDist, closestSurfacePoint
end

local function isStraightLineOnRoad(p1, p2)
    local dist = (Vector3.new(p2.X - p1.X, 0, p2.Z - p1.Z)).Magnitude
    if dist <= 6 then return true end
    local steps = math.clamp(math.ceil(dist / 12), 2, 10)
    for i = 1, steps do
        local _, edgeDist = getRoadInfoAtPosition(p1:Lerp(p2, i / steps), false)
        if edgeDist > 3.5 then return false end
    end
    return true
end

-- ==============================================================================
-- 7. DISCRIMINADOR ESTRICTO ANTI-FANTASMAS (SOLO OBJETOS CON ITEMDRAG VIVO)
-- ==============================================================================

local function isMovableTargetItem(entity)
    if not entity or not entity.Parent then return false end
    local n = entity.Name:lower()
    local itemType = tostring(entity:GetAttribute("ItemType") or ""):lower()

    if itemType == "food" or n:find("carrot") then return false end

    -- REGLA DE ORO ANTI-FANTASMA: El objeto DEBE tener su ItemDrag activo
    local dragDetector = entity:FindFirstChild("ItemDrag", true) or entity:FindFirstChildWhichIsA("DragDetector", true)
    if not dragDetector then
        return false -- Descartar si el servidor ya le quitó el detector (fantasma)
    end

    local isFuel = (n == "fuel" or n == "refined fuel" or n:find("fuel") or n:find("gas")) and not n:find("mask")
    local isMetalOrScrap = n:find("scrap") or n:find("refined metal") or n:find("metal") or n:find("chatarra") or n:find("barrel") or n:find("sheet")
    local isResource = (itemType == "resource")

    if Config.MoveFuelCans and isFuel then return true end
    if Config.MoveScrapAndMetal and isMetalOrScrap then return true end
    if Config.MoveAllResources and isResource then return true end

    return false
end

local function getTargetNodeTowardsBase(itemPos, desiredHopDist)
    local genPos = getGeneratorPosition()
    local itemHoriz = Vector3.new(itemPos.X, 0, itemPos.Z)
    local genHoriz = Vector3.new(genPos.X, 0, genPos.Z)
    local currentDistToGen = (itemHoriz - genHoriz).Magnitude

    local toBaseDir = (genHoriz - itemHoriz).Unit
    local distToSafeBorder = math.max(10, currentDistToGen - (Config.GeneratorSafeRadius - 10))
    local actualHop = math.min(desiredHopDist, distToSafeBorder)
    local idealPoint = itemPos + (toBaseDir * actualHop)

    local bestNodePos = idealPoint
    local shortestDiff = math.huge

    for _, vPos in ipairs(VirtualWebGrid) do
        local vHoriz = Vector3.new(vPos.X, 0, vPos.Z)
        if (vHoriz - genHoriz).Magnitude < (currentDistToGen - 3) then
            local d = (vHoriz - Vector3.new(idealPoint.X, 0, idealPoint.Z)).Magnitude
            if d < shortestDiff then
                shortestDiff = d
                bestNodePos = vPos
            end
        end
    end
    return bestNodePos
end

-- ==============================================================================
-- 8. MOTOR DE TRANSPORTE ANTI-FANTASMAS (CINÉTICA CONTROLADA)
-- ==============================================================================

local function launchOrMoveItemSafe(targetEntity, mainPart, itemPos, genPos, root)
    local drag = targetEntity:FindFirstChild("ItemDrag", true) or targetEntity:FindFirstChildWhichIsA("DragDetector", true)
    if not drag then
        recordForensicIncident("❌ FANTASMA RECHAZADO", targetEntity, mainPart, root, "No tiene ItemDrag. Objeto inservible.")
        return
    end

    recordForensicIncident("1. INICIO TRANSPORTE SEGURO", targetEntity, mainPart, root, "ItemDrag detectado activo.")

    -- 1. Desanclar partes suavemente
    if targetEntity:IsA("Model") then
        for _, p in ipairs(targetEntity:GetDescendants()) do
            if p:IsA("BasePart") then p.Anchored = false end
        end
    elseif targetEntity:IsA("BasePart") then
        targetEntity.Anchored = false
    end

    -- 2. Notificar propiedad física tocándolo sin teletransportarlo abruptamente
    if root and firetouchinterest then
        pcall(function()
            firetouchinterest(mainPart, root, 0)
            firetouchinterest(mainPart, root, 1)
        end)
    end

    task.wait(0.04)
    if not targetEntity.Parent or not mainPart.Parent then return end

    local itemHoriz = Vector3.new(mainPart.Position.X, 0, mainPart.Position.Z)
    local genHoriz = Vector3.new(genPos.X, 0, genPos.Z)
    local dirToBase = (genHoriz - itemHoriz).Unit
    local distToSafeEdge = math.max(12, (itemHoriz - genHoriz).Magnitude - (Config.GeneratorSafeRadius - 12))
    local targetDist = math.min(Config.KickDistance, distToSafeEdge)

    -- Vector cinético seguro (Control de velocidad: Máximo 34 studs/s para no alertar al servidor)
    local safeSpeed = math.clamp(targetDist * 0.42, 18, 36)
    local safeVelocity = (dirToBase * safeSpeed) + Vector3.new(0, Config.KickArcHeight, 0)

    -- Aplicar impulso legítimo
    mainPart.AssemblyLinearVelocity = safeVelocity
    mainPart.AssemblyAngularVelocity = Vector3.new(math.random(-2, 2), math.random(-2, 2), math.random(-2, 2))

    recordForensicIncident("2. IMPULSO SEGURO APLICADO", targetEntity, mainPart, root, string.format("Velocidad controlada: %.1f studs/s", safeSpeed))

    -- Verificación post-vuelo a 0.4s
    task.spawn(function()
        task.wait(0.4)
        if targetEntity.Parent and mainPart.Parent then
            local hasDragStill = targetEntity:FindFirstChild("ItemDrag", true) or targetEntity:FindFirstChildWhichIsA("DragDetector", true)
            if hasDragStill then
                recordForensicIncident("3. VERIFICACIÓN POST-VUELO", targetEntity, mainPart, root, "✅ ItemDrag INTACTO. El objeto sigue vivo.")
            else
                recordForensicIncident("3. VERIFICACIÓN POST-VUELO", targetEntity, mainPart, root, "❌ Servidor lo borró. Reducir velocidad de lanzamiento.")
            end
        end
    end)
end

-- Bucle de pateo/transporte seguro
task.spawn(function()
    while true do
        task.wait(Config.TeleportInterval)
        if Config.AutoSendItems then
            local _, root = getCharacterParts()
            if root then
                local myPos = root.Position
                local genPos = getGeneratorPosition()
                local droppedFolder = workspace:FindFirstChild("DroppedItems") or workspace
                local candidates = {}
                local now = tick()

                for _, item in ipairs(droppedFolder:GetChildren()) do
                    if (item:IsA("Model") or item:IsA("BasePart")) and not (RecentlyKicked[item] and now < RecentlyKicked[item]) then
                        if isMovableTargetItem(item) then
                            local mainPart = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                            if mainPart then
                                local iPos = mainPart.Position
                                local distToMe = (iPos - myPos).Magnitude

                                if distToMe <= Config.CollectRadius then
                                    local distToGen = (Vector3.new(iPos.X, 0, iPos.Z) - Vector3.new(genPos.X, 0, genPos.Z)).Magnitude
                                    local insideBase = Config.BasePrevent and (distToGen <= Config.GeneratorSafeRadius)

                                    if not insideBase and distToGen <= Config.MaxMapRadius then
                                        table.insert(candidates, {
                                            Entity = item,
                                            Part = mainPart,
                                            Pos = iPos,
                                            Dist = distToMe
                                        })
                                    end
                                end
                            end
                        end
                    end
                end

                table.sort(candidates, function(a, b) return a.Dist < b.Dist end)

                local countToProcess = math.min(#candidates, Config.ItemsPerTick)
                for i = 1, countToProcess do
                    local c = candidates[i]
                    RecentlyKicked[c.Entity] = tick() + 0.85
                    task.spawn(function()
                        launchOrMoveItemSafe(c.Entity, c.Part, c.Pos, genPos, root)
                    end)
                end
            end
        end
    end
end)

-- ==============================================================================
-- 9. CONDUCCIÓN POR PISTAS
-- ==============================================================================

local function buildForwardRoadChain(startPos, currentDir, returnToBase)
    local chain = {}
    local curPos = startPos
    local curDir = currentDir
    local used = {}

    for step = 1, 5 do
        local bestNode = nil
        local bestScore = math.huge
        local now = tick()
        local curDistToBase = (Vector3.new(curPos.X, 0, curPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

        for _, node in ipairs(RoadNodes) do
            local distBase = (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
            if not used[node] and distBase <= Config.MaxMapRadius then
                local diff = Vector3.new(node.Pos.X - curPos.X, 0, node.Pos.Z - curPos.Z)
                local dist = diff.Magnitude

                if dist >= 20 and dist <= 135 and isStraightLineOnRoad(curPos, node.Pos) then
                    local score
                    if returnToBase then
                        score = distBase + (dist * 0.3)
                        if distBase > curDistToBase then score = score + 250 end
                    else
                        local dirToNode = diff.Unit
                        local dot = dirToNode:Dot(curDir)
                        local unvisitedBonus = math.min((now - node.LastVisited) * 1.5, 95)
                        local backwardPenalty = (dot < -0.25) and 350 or ((dot < 0.15) and 90 or 0)
                        score = dist + backwardPenalty - (dot * 45) - unvisitedBonus
                    end

                    if score < bestScore then
                        bestScore = score
                        bestNode = node
                    end
                end
            end
        end

        if bestNode then
            used[bestNode] = true
            table.insert(chain, bestNode)
            local stepVec = Vector3.new(bestNode.Pos.X - curPos.X, 0, bestNode.Pos.Z - curPos.Z)
            if stepVec.Magnitude > 0.1 then curDir = stepVec.Unit end
            curPos = bestNode.Pos
        else
            break
        end
    end

    return chain
end

RunService.Heartbeat:Connect(function()
    if not Config.AutoFarmRoads then return end

    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then return end

    local myPos = root.Position
    local currentRoad, edgeDist, closestRoadSurfacePos = getRoadInfoAtPosition(myPos, true)

    if not currentRoad or edgeDist > 2.2 then
        IsRecoveringToRoad = true
        RoadTransit.Waypoints = {}
        if currentRoad then
            local toAsphalt = Vector3.new(closestRoadSurfacePos.X - myPos.X, 0, closestRoadSurfacePos.Z - myPos.Z)
            if toAsphalt.Magnitude > 1.0 then
                local mDir = toAsphalt.Unit
                RoadTransit.CurrentDirection = mDir
                root.AssemblyLinearVelocity = Vector3.new(mDir.X * Config.VehicleSpeed, root.AssemblyLinearVelocity.Y, mDir.Z * Config.VehicleSpeed)
            end
        end
        return
    end

    IsRecoveringToRoad = false
    currentRoad.LastVisited = tick()

    local wpNode = RoadTransit.Waypoints[RoadTransit.Index]
    if not wpNode or not isStraightLineOnRoad(myPos, wpNode.Pos) then
        RoadTransit.Waypoints = buildForwardRoadChain(myPos, RoadTransit.CurrentDirection, FuelState.IsRefueling)
        RoadTransit.Index = 1
        wpNode = RoadTransit.Waypoints[1]
    end

    if wpNode then
        local diff = wpNode.Pos - myPos
        local horiz = Vector3.new(diff.X, 0, diff.Z)
        if horiz.Magnitude <= 18.0 then
            wpNode.LastVisited = tick()
            RoadTransit.Index = RoadTransit.Index + 1
            if RoadTransit.Index > #RoadTransit.Waypoints then
                RoadTransit.Waypoints = buildForwardRoadChain(myPos, RoadTransit.CurrentDirection, FuelState.IsRefueling)
                RoadTransit.Index = 1
            end
        else
            local mDir = horiz.Unit
            RoadTransit.CurrentDirection = mDir
            root.AssemblyLinearVelocity = Vector3.new(mDir.X * Config.VehicleSpeed, root.AssemblyLinearVelocity.Y, mDir.Z * Config.VehicleSpeed)
        end
    end
end)

-- ==============================================================================
-- 10. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP CRUSHER V4.4 | GHOST-PROOF",
    SubTitle = "Protección DragDetector + Red 1500m",
    TabWidth = 155,
    Size = UDim2.fromOffset(630, 540),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Forensics = Window:AddTab({ Title = "Bitácora Forense", Icon = "file-text" }),
    Items     = Window:AddTab({ Title = "Patear / Telaraña", Icon = "share-2" }),
    RoadFarm  = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    AutoEat   = Window:AddTab({ Title = "Auto-Comer", Icon = "utensils" }),
    Fuel      = Window:AddTab({ Title = "Auto-Gasolina", Icon = "fuel" })
}

-- FORENSE
Tabs.Forensics:AddSection("Auditoría Anti-Fantasmas")

local function compileFullForensicReport()
    local lines = {
        "==================================================================",
        "          REPORTE FORENSE ANTI-FANTASMAS (V4.4)                  ",
        "==================================================================",
        string.format("Fecha de Extracción: %s", os.date("%Y-%m-%d %X")),
        string.format("Registros: %d", #ScrapForensicHistory),
        "\n[HISTORIAL DETALLADO]:\n"
    }
    for i = 1, #ScrapForensicHistory do
        local e = ScrapForensicHistory[i]
        table.insert(lines, string.format("[%s] ETAPA: %s | Objeto: '%s' | Detector: %s", e.Timestamp, e.Stage, e.Name, e.Detector))
        if e.Details and e.Details ~= "" then table.insert(lines, string.format("   Detalles: %s", e.Details)) end
    end
    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

Tabs.Forensics:AddButton({
    Title = "📋 COPIAR BITÁCORA FORENSE",
    Callback = function()
        local rep = compileFullForensicReport()
        if setclipboard then setclipboard(rep) elseif toclipboard then toclipboard(rep) end
        Fluent:Notify({ Title = "Copiado", Content = "Bitácora copiada al portapapeles.", Duration = 2.5 })
    end
})

-- ITEMS
Tabs.Items:AddSection("Transporte Seguro hacia la Base")

Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "👟 Activar Transporte Seguro (Anti-Fantasmas)",
    Default = true,
    Callback = function(v) Config.AutoSendItems = v end
})

Tabs.Items:AddSlider("KickDistSlider", {
    Title = "Distancia de Desplazamiento Seguro (Studs)",
    Default = 85,
    Min = 30,
    Max = 160,
    Rounding = 0,
    Callback = function(v) Config.KickDistance = v end
})

Tabs.Items:AddSection("Filtro de Recursos")

Tabs.Items:AddToggle("MoveScrapMetalToggle", {
    Title = "🔩 Mover Scrap y Refined Metal",
    Default = true,
    Callback = function(v) Config.MoveScrapAndMetal = v end
})

Tabs.Items:AddToggle("MoveFuelToggle", {
    Title = "⛽ Mover Fuel y Refined Fuel",
    Default = true,
    Callback = function(v) Config.MoveFuelCans = v end
})

-- AUTO-PISTAS
Tabs.RoadFarm:AddSection("Conducción en Pista")

Tabs.RoadFarm:AddToggle("AutoFarmToggle", {
    Title = "🚜 Activar Auto-Atropello en Pistas",
    Default = false,
    Callback = function(v)
        Config.AutoFarmRoads = v
        if not v then applyBrake(0.8) end
    end
})

Tabs.RoadFarm:AddSlider("CarSpeedSlider", {
    Title = "Velocidad de Conducción",
    Default = 115,
    Min = 60,
    Max = 180,
    Rounding = 0,
    Callback = function(v) Config.VehicleSpeed = v end
})

-- AUTO-EAT
Tabs.AutoEat:AddSection("Auto-Comer")

Tabs.AutoEat:AddToggle("AutoEatToggle", {
    Title = "🥕 Activar Auto-Comer",
    Default = true,
    Callback = function(v) Config.AutoEatEnabled = v end
})

-- AUTO-GASOLINA
Tabs.Fuel:AddSection("Auto-Gasolina")

Tabs.Fuel:AddToggle("AutoRefuelToggle", {
    Title = "⛽ Recarga Automática",
    Default = true,
    Callback = function(v) Config.AutoRefuelEnabled = v end
})

Tabs.Fuel:AddButton({
    Title = "⛽ Acoplar Galón Cercano Ahora",
    Callback = function()
        local ok = refuelTruckFromNearbyCan()
        Fluent:Notify({ Title = "Gasolina", Content = ok and "Galón acoplado." or "Sin galones cerca.", Duration = 2 })
    end
})

Window:SelectTab(1)
