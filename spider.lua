-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER V4.5: ZHUB INSTANT CFRAME TRANSPORT (ANTI-FANTASMA)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)
local TARGET_DELIVERY_POINT = Vector3.new(8.0, 2.6, 29.4) -- Punto confirmado de entrega ZHUB

local Config = {
    MaxMapRadius = 1500,

    -- Auto-Conducción por Pistas
    AutoFarmRoads = false,
    VehicleSpeed = 115,
    RoadMaxHalfWidth = 12,
    ScrapSearchRadius = 450,
    CrushOvershoot = 16,

    -- Transporte ZHUB Style (Instant CFrame)
    AutoSendItems = true,
    TransportMode = "ZHUB Instant CFrame",
    ItemsPerTick = 2,
    CollectRadius = 8.5,        -- Cercanía estricta para asegurar Network Ownership
    HopDistance = 140,          -- Salto por paso hacia la base (o directo si está en rango)
    TeleportInterval = 0.15,

    -- Filtros
    MoveScrapAndMetal = true,
    MoveFuelCans = true,
    MoveAllResources = true,

    -- Base Prevent
    BasePrevent = true,
    GeneratorSafeRadius = 145,
    WebStepDistance = 35,
    WebGroundHeight = 0.6,

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
    FuelCanScanRadius = 45
}

local RoadNodes = {}
local VirtualWebGrid = {}
local RoadScrapList = {}
local IgnoredScrapUntil = {}
local RecentlyTeleported = {}

local CachedGeneratorPos = nil
local CurrentScrapTarget = nil
local IsRecoveringToRoad = false

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
-- 1. OBTENCIÓN DE PERSONAJE Y VEHÍCULO
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
-- 2. AUTO-COMER
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
-- 3. AUTO-GASOLINA
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
-- 4. RED VIRTUAL Y CÁLCULO DE DESTINO
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

local function getNextHopPositionZHUB(itemPos)
    local genPos = getGeneratorPosition()
    local itemHoriz = Vector3.new(itemPos.X, 0, itemPos.Z)
    local genHoriz = Vector3.new(genPos.X, 0, genPos.Z)
    local distToGen = (itemHoriz - genHoriz).Magnitude

    -- Si ya está a tiro de un solo salto de la base, enviar directo al punto ZHUB
    if distToGen <= Config.HopDistance or distToGen <= (Config.GeneratorSafeRadius + 20) then
        return Vector3.new(TARGET_DELIVERY_POINT.X, Config.WebGroundHeight + 0.8, TARGET_DELIVERY_POINT.Z)
    end

    -- Salto de avance hacia la base
    local dirToBase = (genHoriz - itemHoriz).Unit
    local targetPos = itemPos + (dirToBase * Config.HopDistance)
    return Vector3.new(targetPos.X, Config.WebGroundHeight + 0.8, targetPos.Z)
end

-- ==============================================================================
-- 5. TRANSPORTE INSTANTÁNEO ESTILO ZHUB (CFRAME PURO + RESPETO DE DETECTOR)
-- ==============================================================================

local function isMovableItem(entity)
    if not entity or not entity.Parent then return false end
    local n = entity.Name:lower()
    local itemType = tostring(entity:GetAttribute("ItemType") or ""):lower()

    if itemType == "food" or n:find("carrot") then return false end

    -- El ItemDrag DEBE estar presente
    local drag = entity:FindFirstChild("ItemDrag", true) or entity:FindFirstChildWhichIsA("DragDetector", true)
    if not drag then return false end

    local isFuel = (n == "fuel" or n == "refined fuel" or n:find("fuel") or n:find("gas")) and not n:find("mask")
    local isMetalOrScrap = n:find("scrap") or n:find("refined metal") or n:find("metal") or n:find("chatarra") or n:find("barrel") or n:find("sheet")
    local isResource = (itemType == "resource")

    if Config.MoveFuelCans and isFuel then return true end
    if Config.MoveScrapAndMetal and isMetalOrScrap then return true end
    if Config.MoveAllResources and isResource then return true end

    return false
end

local function executeZHUBTeleport(targetEntity, mainPart, root)
    if not targetEntity or not targetEntity.Parent or not mainPart or not mainPart.Parent then return end

    -- 1. Despertar por toque con el personaje
    if root and firetouchinterest then
        pcall(function()
            firetouchinterest(mainPart, root, 0)
            firetouchinterest(mainPart, root, 1)
        end)
    end

    -- 2. Asegurar que las partes estén desancladas antes del salto
    if targetEntity:IsA("Model") then
        for _, p in ipairs(targetEntity:GetDescendants()) do
            if p:IsA("BasePart") then p.Anchored = false end
        end
    elseif targetEntity:IsA("BasePart") then
        targetEntity.Anchored = false
    end

    -- 3. Calcular posición de destino (Salto ZHUB)
    local destPos = getNextHopPositionZHUB(mainPart.Position)
    local targetCF = CFrame.new(destPos)

    -- 4. Traslado instantáneo por CFrame (Sin alterar velocidades abruptamente)
    if targetEntity:IsA("Model") then
        targetEntity:PivotTo(targetCF)
    else
        mainPart.CFrame = targetCF
    end

    -- 5. Anular inercia residual para que no caiga al vacío
    mainPart.AssemblyLinearVelocity = Vector3.new(0, -1.0, 0)
    mainPart.AssemblyAngularVelocity = Vector3.zero
end

-- Bucle de despacho ZHUB
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
                    if (item:IsA("Model") or item:IsA("BasePart")) and not (RecentlyTeleported[item] and now < RecentlyTeleported[item]) then
                        if isMovableItem(item) then
                            local mainPart = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                            if mainPart then
                                local iPos = mainPart.Position
                                local distToMe = (iPos - myPos).Magnitude

                                -- Proximidad estricta para garantizar posesión de red (≤ 8.5 studs)
                                if distToMe <= Config.CollectRadius then
                                    local distToGen = (Vector3.new(iPos.X, 0, iPos.Z) - Vector3.new(genPos.X, 0, genPos.Z)).Magnitude
                                    local insideBase = Config.BasePrevent and (distToGen <= Config.GeneratorSafeRadius)

                                    if not insideBase and distToGen <= Config.MaxMapRadius then
                                        table.insert(candidates, {
                                            Entity = item,
                                            Part = mainPart,
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
                    RecentlyTeleported[c.Entity] = tick() + 0.45
                    task.spawn(function()
                        executeZHUBTeleport(c.Entity, c.Part, root)
                    end)
                end
            end
        end
    end
end)

-- ==============================================================================
-- 6. MAPEO DE PISTAS Y CONDUCCIÓN
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
-- 7. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP CRUSHER V4.5 | ZHUB ENGINE",
    SubTitle = "Teletransporte CFrame Puro (Anti-Fantasma)",
    TabWidth = 155,
    Size = UDim2.fromOffset(610, 520),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Transport = Window:AddTab({ Title = "Teletransporte", Icon = "zap" }),
    RoadFarm  = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    AutoEat   = Window:AddTab({ Title = "Auto-Comer", Icon = "utensils" }),
    Fuel      = Window:AddTab({ Title = "Auto-Gasolina", Icon = "fuel" })
}

-- PESTAÑA TRANSPORTE
Tabs.Transport:AddSection("Motor de Salto Instantáneo (Técnica ZHUB)")

Tabs.Transport:AddToggle("AutoSendToggle", {
    Title = "⚡ Activar Teletransporte Instantáneo a Base",
    Description = "Teletransporta chatarra y gasolina por CFrame manteniendo el ItemDrag activo",
    Default = true,
    Callback = function(v) Config.AutoSendItems = v end
})

Tabs.Transport:AddSlider("CollectRadiusSlider", {
    Title = "Distancia de Activación (Studs)",
    Description = "Mantener en ≤ 8.5 studs para asegurar la propiedad de red del objeto",
    Default = 8.5,
    Min = 5.0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Transport:AddSlider("HopDistSlider", {
    Title = "Distancia del Salto hacia la Base (Studs)",
    Default = 140,
    Min = 60,
    Max = 300,
    Rounding = 0,
    Callback = function(v) Config.HopDistance = v end
})

Tabs.Transport:AddSection("Filtros de Recursos")

Tabs.Transport:AddToggle("MoveScrapToggle", {
    Title = "🔩 Mover Chatarra / Scrap / Metal",
    Default = true,
    Callback = function(v) Config.MoveScrapAndMetal = v end
})

Tabs.Transport:AddToggle("MoveFuelToggle", {
    Title = "⛽ Mover Galones de Gasolina",
    Default = true,
    Callback = function(v) Config.MoveFuelCans = v end
})

-- PESTAÑA AUTO-PISTAS
Tabs.RoadFarm:AddSection("Conducción Automática")

local AutoFarmToggle = Tabs.RoadFarm:AddToggle("AutoFarmToggle", {
    Title = "🚜 Activar Auto-Atropello en Pistas",
    Default = false,
    Callback = function(v)
        Config.AutoFarmRoads = v
        if not v then applyBrake(0.8) end
    end
})

Tabs.RoadFarm:AddSlider("CarSpeedSlider", {
    Title = "Velocidad del Auto",
    Default = 115,
    Min = 60,
    Max = 180,
    Rounding = 0,
    Callback = function(v) Config.VehicleSpeed = v end
})

-- PESTAÑA AUTO-EAT
Tabs.AutoEat:AddSection("Auto-Comer")

Tabs.AutoEat:AddToggle("AutoEatToggle", {
    Title = "🥕 Activar Auto-Comer en Suelo",
    Default = true,
    Callback = function(v) Config.AutoEatEnabled = v end
})

-- PESTAÑA AUTO-GASOLINA
Tabs.Fuel:AddSection("Auto-Gasolina")

Tabs.Fuel:AddToggle("AutoRefuelToggle", {
    Title = "⛽ Recarga Automática en Tanque",
    Default = true,
    Callback = function(v) Config.AutoRefuelEnabled = v end
})

Tabs.Fuel:AddButton({
    Title = "⛽ Acoplar Galón Cercano Ahora",
    Callback = function()
        local ok = refuelTruckFromNearbyCan()
        Fluent:Notify({ Title = "Gasolina", Content = ok and "Galón acoplado al tanque." or "Sin galones cerca.", Duration = 2 })
    end
})

-- ==============================================================================
-- 8. BOTONES FLOTANTES
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local FloatGui = Instance.new("ScreenGui")
FloatGui.Name = "ScrapZhubMasterFloatGuiV45"
FloatGui.ResetOnSpawn = false
FloatGui.Parent = GuiParent

local MenuBtn = Instance.new("ImageButton")
MenuBtn.Size = UDim2.new(0, 48, 0, 48)
MenuBtn.Position = UDim2.new(0.04, 0, 0.72, 0)
MenuBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
MenuBtn.Image = "rbxassetid://10723415903"
MenuBtn.Active = true
MenuBtn.Draggable = true
MenuBtn.Parent = FloatGui

local MenuCorner = Instance.new("UICorner")
MenuCorner.CornerRadius = UDim.new(1, 0)
MenuCorner.Parent = MenuBtn

local isMenuVisible = true
MenuBtn.MouseButton1Click:Connect(function()
    isMenuVisible = not isMenuVisible
    Window.Root.Visible = isMenuVisible
end)

local DriveBtn = Instance.new("TextButton")
DriveBtn.Size = UDim2.new(0, 48, 0, 48)
DriveBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
DriveBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
DriveBtn.Text = "🚜\nOFF"
DriveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DriveBtn.TextSize = 11
DriveBtn.Font = Enum.Font.GothamBold
DriveBtn.Active = true
DriveBtn.Draggable = true
DriveBtn.Parent = FloatGui

local DriveCorner = Instance.new("UICorner")
DriveCorner.CornerRadius = UDim.new(1, 0)
DriveCorner.Parent = DriveBtn

DriveBtn.MouseButton1Click:Connect(function()
    Config.AutoFarmRoads = not Config.AutoFarmRoads
    pcall(function() AutoFarmToggle:SetValue(Config.AutoFarmRoads) end)
    if Config.AutoFarmRoads then
        DriveBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 65)
        DriveBtn.Text = "🚜\nON"
    else
        DriveBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
        DriveBtn.Text = "🚜\nOFF"
        applyBrake(0.8)
    end
end)

Window:SelectTab(1)
