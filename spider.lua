-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER, VIRTUAL WEB 1500m, KICK/THROW MODES & AUTO-FUEL V4.0
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
    -- Rango expandido a 1500 studs en TODO el mapa (Pistas + Terreno libre)
    MaxMapRadius = 1500,

    -- Auto-Conducción por Pistas (Velocidad 115)
    AutoFarmRoads = false,
    VehicleSpeed = 115,
    RoadMaxHalfWidth = 12,      -- Límite lateral estricto dentro del asfalto para el auto
    ScrapSearchRadius = 450,    -- Radio de detección de cúmulos
    CrushOvershoot = 16,        -- Rebasa el cúmulo sobre el mismo carril sin vibrar

    -- Sistema de Pateo / Lanzamiento / Telaraña Global (A pie y en Auto)
    AutoSendItems = true,
    TransportMode = "Patada Física (Lanzar)", -- 4 Modos disponibles
    ItemsPerTick = 2,           -- Agarra/Patea 2 objetos a la vez como pediste
    CollectRadius = 10,         -- Estar cerca (10 studs, dentro del MaxDist: 12 de ItemDrag)
    KickDistance = 100,         -- Distancia objetivo del lanzamiento/patada (~100 studs hacia la base)
    KickArcHeight = 28,         -- Impulso vertical para que vuele en arco y no se trabe en el piso
    TeleportInterval = 0.14,    -- Más rápido para lanzar continuo mientras caminas

    -- Filtros de Objetos (Incluye Scrap, Refined Metal, Fuel y Refined Fuel)
    MoveScrapAndMetal = true,   -- Scrap, Chatarra, Metal, Refined Metal, Barrel, Sheet
    MoveFuelCans = true,        -- Fuel y Refined Fuel
    MoveAllResources = true,    -- Cualquier objeto con ItemType = Resource

    -- Red Virtual de 1500m (Cero Lag) + Puntos Manuales
    ChainTeleport = true,
    BasePrevent = true,
    GeneratorSafeRadius = 145,  -- Radio donde ya deja los materiales en la base
    WebStepDistance = 35,       -- Espaciado de la cuadrícula en todo el mapa
    WebGroundHeight = 0.6,      -- Altura fija pegada al suelo
    SpreadRadius = 1.8,         -- Dispersión
    ShowWebVisuals = false,     -- Muestra solo los nodos cercanos para 0% lag

    -- Auto-Eat Integrado (Activado por defecto)
    AutoEatEnabled = true,
    EatHealthThreshold = 60,
    EatHungerThreshold = 50,
    EatScanRadius = 24,
    EatCooldown = 0.9,

    -- Auto-Gasolina desde el Auto
    AutoRefuelEnabled = true,
    LowFuelThreshold = 25,
    FullFuelThreshold = 90,
    FuelCanScanRadius = 45
}

local RoadNodes = {}            -- Nodos de las pistas para conducción del vehículo
local VirtualWebGrid = {}       -- Matriz matemática de puntos en TODO el mapa (1500 studs, 0% lag)
local ManualDeliveryPoints = {} -- Bolitas manuales agregadas por ti
local VisualPool = {}           -- Pool ligero por si activas ver las bolitas cercanas
local RoadScrapList = {}        -- Cúmulos y autos chatarra en pista
local IgnoredScrapUntil = {}    -- Cooldown de cúmulos embestidos
local RecentlyKicked = {}       -- Pequeño cooldown por ítem para que vuele tranquilo al ser pateado

local CachedGeneratorPos = nil
local CurrentScrapTarget = nil
local IsRecoveringToRoad = false

-- Estado de Ruta Fluida sobre Pistas
local RoadTransit = {
    Waypoints = {},
    Index = 1,
    CurrentDirection = Vector3.new(0, 0, 1)
}

-- Estado de Auto-Comer
local AutoEatState = {
    IsEating = false,
    LastEatTick = 0,
    Status = "Monitoreando..."
}

-- Estado de Gasolina del Vehículo
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

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. OBTENCIÓN DE PERSONAJE, STATS Y VEHÍCULO
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

    local hunger = char:GetAttribute("Hunger") or lp:GetAttribute("Hunger")
    local maxHunger = char:GetAttribute("MaxHunger") or lp:GetAttribute("MaxHunger") or 100

    local hungerPct = 100
    if type(hunger) == "number" then
        hungerPct = math.floor((hunger / maxHunger) * 100)
    else
        local hVal = char:FindFirstChild("Hunger") or lp:FindFirstChild("Hunger")
        if hVal and (hVal:IsA("NumberValue") or hVal:IsA("IntValue")) then
            hungerPct = math.floor((hVal.Value / 100) * 100)
        end
    end

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
-- 2. AUTO-COMER INTEGRADO (ZANAHORIA DORADA VIDA / NORMAL HAMBRE)
-- ==============================================================================

local function isGoldenCarrot(item)
    if item:GetAttribute("Golden") == true or item:GetAttribute("Rarity") == "Golden" then
        return true
    end

    local mainPart = item:FindFirstChild("MainPart") or item:FindFirstChildWhichIsA("BasePart")
    if mainPart then
        if mainPart.Material == Enum.Material.Metal then
            return true
        end
        if mainPart.Color.R > 0.9 then
            return true
        end
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
        local isFood = (item:GetAttribute("ItemType") == "Food")
            or item.Name:lower():find("carrot")

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
    if not targetFood then
        AutoEatState.Status = onlyGolden and "⚠️ Buscando Zanahoria Dorada..." or "⚠️ Sin comida en el suelo"
        return
    end

    AutoEatState.IsEating = true
    local isGold = isGoldenCarrot(targetFood)
    AutoEatState.Status = isGold and "✨ Comiendo DORADA..." or "🥕 Comiendo Normal..."

    local previousTool = nil
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            previousTool = item
            break
        end
    end

    pcall(function()
        PickUpRemote:FireServer(targetFood)
    end)

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
        if foodTool.Parent ~= char then
            hum:EquipTool(foodTool)
            task.wait(0.05)
        end

        pcall(function() foodTool:Activate() end)

        local useRemote = foodTool:FindFirstChild("Use") or foodTool:FindFirstChild("Consume")
        if useRemote and useRemote:IsA("RemoteEvent") then
            pcall(function() useRemote:FireServer() end)
        end

        task.wait(0.20)
    end

    if previousTool and previousTool.Parent then
        hum:EquipTool(previousTool)
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
        else
            AutoEatState.Status = "🔴 OFF"
        end
    end
end)

-- ==============================================================================
-- 3. SISTEMA DE AUTO-GASOLINA DESDE EL AUTO (LECTURA + RECARGA EN TANQUE IZQUIERDO)
-- ==============================================================================

local function getTruckFuel(truck)
    if not truck then return 100, 100, 100 end
    local foundFuel, foundMax = nil, nil

    local config = truck:FindFirstChild("Configuration", true) or truck:FindFirstChild("Config", true)
    if config then
        for _, attr in ipairs({"Fuel", "Gas", "Gasoline", "Petrol", "Combustible"}) do
            local val = config:GetAttribute(attr)
            if val and type(val) == "number" then
                foundFuel = val
                foundMax = config:GetAttribute("Max" .. attr) or config:GetAttribute("MaxFuel")
                break
            end
        end
        if not foundFuel then
            for _, child in ipairs(config:GetChildren()) do
                if child:IsA("ValueBase") then
                    local n = child.Name:lower()
                    if n:find("fuel") or n:find("gas") then
                        foundFuel = tonumber(child.Value)
                    elseif n:find("maxfuel") or n:find("maxgas") then
                        foundMax = tonumber(child.Value)
                    end
                end
            end
        end
    end

    if not foundFuel then
        for _, obj in ipairs({truck, truck.PrimaryPart, truck:FindFirstChild("DriveSeat")}) do
            if obj then
                for _, attr in ipairs({"Fuel", "Gas", "Gasoline", "Petrol"}) do
                    local val = obj:GetAttribute(attr)
                    if val and type(val) == "number" then
                        foundFuel = val
                        foundMax = obj:GetAttribute("Max" .. attr) or obj:GetAttribute("MaxFuel")
                        break
                    end
                end
            end
            if foundFuel then break end
        end
    end

    if not foundFuel then
        for _, desc in ipairs(truck:GetDescendants()) do
            if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                local n = desc.Name:lower()
                if n == "fuel" or n == "gas" or n == "gasoline" then
                    foundFuel = desc.Value
                    break
                end
            end
        end
    end

    foundFuel = foundFuel or 100
    foundMax = foundMax or (foundFuel > 100 and foundFuel or 100)
    local pct = math.clamp(math.floor((foundFuel / math.max(foundMax, 1)) * 100), 0, 100)
    return foundFuel, foundMax, pct
end

local function getTruckFuelReceptor(truck, seat)
    for _, desc in ipairs(truck:GetDescendants()) do
        if desc:IsA("BasePart") then
            local n = desc.Name:lower()
            if n:find("fuel") or n:find("tank") or n:find("gas") or n:find("cap") or n:find("fill") then
                return desc, desc.Position
            end
        end
    end
    local refCF = (seat and seat.CFrame) or (truck.PrimaryPart and truck.PrimaryPart.CFrame) or CFrame.new()
    local rearLeftPos = (refCF * CFrame.new(-3.4, 0.8, 5.2)).Position
    return truck.PrimaryPart or seat, rearLeftPos
end

local function refuelTruckFromNearbyCan()
    local truck, seat = getCurrentVehicle()
    if not truck or not seat then return false end

    local _, root = getCharacterParts()
    local myPos = root and root.Position or seat.Position
    local receptorPart, tankWorldPos = getTruckFuelReceptor(truck, seat)

    local bestCan = nil
    local bestPart = nil
    local shortest = Config.FuelCanScanRadius

    for _, folder in ipairs({workspace:FindFirstChild("DroppedItems"), workspace:FindFirstChild("Structures"), workspace}) do
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                if (item:IsA("Model") or item:IsA("BasePart")) and item ~= truck and item ~= lp.Character then
                    local n = item.Name:lower()
                    local itemType = tostring(item:GetAttribute("ItemType") or ""):lower()
                    local isGasCan = n == "fuel" or n == "refined fuel" or n:find("gas") or n:find("fuel") or n:find("jerry") or n:find("canister") or itemType:find("fuel")

                    if isGasCan then
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
        -- Despertar con ClickDetector ItemDrag si existe y desanclar
        local cd = bestCan:FindFirstChildOfClass("ClickDetector") or bestCan:FindFirstChildWhichIsA("ClickDetector", true)
        if cd and fireclickdetector then
            pcall(function() fireclickdetector(cd) end)
        end

        local targetCF = CFrame.new(tankWorldPos)
        if bestCan:IsA("Model") then
            for _, p in ipairs(bestCan:GetDescendants()) do
                if p:IsA("BasePart") then p.Anchored = false end
            end
            bestCan:PivotTo(targetCF)
            for _, p in ipairs(bestCan:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity = Vector3.new(0, -1, 0)
                    p.AssemblyAngularVelocity = Vector3.zero
                    if firetouchinterest and receptorPart then
                        pcall(function()
                            firetouchinterest(p, receptorPart, 0)
                            firetouchinterest(p, receptorPart, 1)
                        end)
                    end
                end
            end
        else
            bestPart.Anchored = false
            bestPart.CFrame = targetCF
            bestPart.AssemblyLinearVelocity = Vector3.new(0, -1, 0)
            bestPart.AssemblyAngularVelocity = Vector3.zero
            if firetouchinterest and receptorPart then
                pcall(function()
                    firetouchinterest(bestPart, receptorPart, 0)
                    firetouchinterest(bestPart, receptorPart, 1)
                end)
            end
        end
        return true
    end

    return false
end

task.spawn(function()
    while true do
        task.wait(0.4)
        local truck = getCurrentVehicle()
        if truck then
            local f, maxF, pct = getTruckFuel(truck)
            FuelState.CurrentFuel = f
            FuelState.MaxFuel = maxF
            FuelState.FuelPct = pct

            if Config.AutoRefuelEnabled then
                if not FuelState.IsRefueling and pct <= Config.LowFuelThreshold then
                    FuelState.IsRefueling = true
                    FuelState.Status = "⛽ Bajo (" .. pct .. "%): Volviendo a Base..."
                    Fluent:Notify({
                        Title = "⛽ GASOLINA BAJA (" .. pct .. "%)",
                        Content = "Regresando por las pistas hacia la base para recargar gasolina.",
                        Duration = 3
                    })
                elseif FuelState.IsRefueling and pct >= Config.FullFuelThreshold then
                    FuelState.IsRefueling = false
                    FuelState.Status = "🟢 Tanque Lleno (" .. pct .. "%)"
                end

                if FuelState.IsRefueling then
                    local usedCan = refuelTruckFromNearbyCan()
                    if usedCan then
                        FuelState.Status = "⛽ Echando gasolina al tanque (" .. pct .. "%)..."
                    else
                        FuelState.Status = "⛽ En ruta a la Base para buscar galón (" .. pct .. "%)..."
                    end
                else
                    FuelState.Status = string.format("🟢 Gasolina OK (%d%%)", pct)
                end
            else
                FuelState.IsRefueling = false
                FuelState.Status = string.format("Gasolina: %d%% (Auto-Refuel OFF)", pct)
            end
        else
            FuelState.IsRefueling = false
            FuelState.Status = "Sin vehículo"
        end
    end
end)

-- ==============================================================================
-- 4. RED VIRTUAL DE 1500 STUDS EN TODO EL MAPA (0% LAG EN RAM)
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

local function createManualWebMarker(pos)
    local marker = Instance.new("Part")
    marker.Name = "CustomDropPoint"
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(2.0, 2.0, 2.0)
    marker.Material = Enum.Material.Neon
    marker.Color = Color3.fromRGB(0, 255, 170)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Transparency = Config.ShowWebVisuals and 0.2 or 1
    marker.Position = Vector3.new(pos.X, Config.WebGroundHeight, pos.Z)
    marker.Parent = workspace

    table.insert(ManualDeliveryPoints, marker)
    table.insert(VirtualWebGrid, marker.Position)
    return marker
end

-- Construye todos los puntos dentro de los 1500 studs en todo el mapa (Pistas + Pasto + Tierra) sin crear Parts pesadas
local function rebuildSpiderwebNetwork()
    table.clear(VirtualWebGrid)

    local genPos = getGeneratorPosition()
    local step = math.max(15, Config.WebStepDistance)
    local maxR = Config.MaxMapRadius
    local safeR = math.max(40, Config.GeneratorSafeRadius - 12)

    -- Anillos concéntricos uniformes que llenan cada rincón dentro de los 1500 studs
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

    -- Re-agregar las bolitas manuales
    for _, m in ipairs(ManualDeliveryPoints) do
        if m and m.Parent then
            table.insert(VirtualWebGrid, m.Position)
        end
    end
end

rebuildSpiderwebNetwork()

-- Renderizador ligero de bolitas cercanas solo si activas "Mostrar Bolitas" (Cero Lag)
task.spawn(function()
    while true do
        task.wait(0.8)
        if Config.ShowWebVisuals then
            local _, root = getCharacterParts()
            if root then
                local myPos = root.Position
                local nearbyPositions = {}

                for _, vPos in ipairs(VirtualWebGrid) do
                    if (Vector3.new(vPos.X, 0, vPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude <= 140 then
                        table.insert(nearbyPositions, vPos)
                        if #nearbyPositions >= 60 then break end
                    end
                end

                for i = 1, 60 do
                    local targetPos = nearbyPositions[i]
                    local ball = VisualPool[i]
                    if targetPos then
                        if not ball or not ball.Parent then
                            ball = Instance.new("Part")
                            ball.Name = "VirtualWebPreview"
                            ball.Shape = Enum.PartType.Ball
                            ball.Size = Vector3.new(1.6, 1.6, 1.6)
                            ball.Material = Enum.Material.Neon
                            ball.Color = Color3.fromRGB(0, 180, 255)
                            ball.Anchored = true
                            ball.CanCollide = false
                            ball.Transparency = 0.25
                            ball.Parent = workspace
                            VisualPool[i] = ball
                        end
                        ball.Position = targetPos
                    elseif ball and ball.Parent then
                        ball.Parent = nil
                    end
                end
            end
        else
            for i, ball in pairs(VisualPool) do
                if ball and ball.Parent then ball:Destroy() end
            end
            table.clear(VisualPool)
        end
    end
end)

-- ==============================================================================
-- 5. MAPEO DE PISTAS Y VERIFICACIÓN ESTRICTA DE ASFALTO (PARA EL AUTO)
-- ==============================================================================

local function isRoadObject(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    if n:find("straight") or n:find("road") or n:find("pista") or n:find("corner") or n:find("tsection") then
        if not n:find("sign") and not n:find("light") and not n:find("lamp") and not n:find("railing") and not n:find("sidewalk") then
            return true
        end
    end
    return false
end

local function registerRoadPiece(obj)
    local pos, size
    if obj:IsA("Model") then
        local cf, sz = obj:GetBoundingBox()
        pos = cf.Position
        size = sz
    else
        pos = obj.Position
        size = obj.Size
    end

    local distFromCenter = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
    if distFromCenter > 1550 or distFromCenter < 92 then return end

    for _, node in ipairs(RoadNodes) do
        if (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 20 then
            return
        end
    end

    local newNode = {
        Pos = Vector3.new(pos.X, Config.WebGroundHeight, pos.Z),
        Size = size,
        Instance = obj,
        LastVisited = 0
    }
    table.insert(RoadNodes, newNode)
end

task.spawn(function()
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("Tiles") or workspace
    local descendants = mapFolder:GetDescendants()
    for i, desc in ipairs(descendants) do
        if isRoadObject(desc) then
            registerRoadPiece(desc)
        end
        if i % 250 == 0 then task.wait() end
    end
end)

workspace.DescendantAdded:Connect(function(desc)
    if isRoadObject(desc) then
        task.wait(0.15)
        registerRoadPiece(desc)
    end
end)

local function getRoadInfoAtPosition(pos, respectMaxRadius)
    local bestNode = nil
    local minCenterDist = math.huge
    local minEdgeDist = math.huge
    local closestSurfacePoint = pos

    for _, node in ipairs(RoadNodes) do
        local distBase = (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        if not respectMaxRadius or distBase <= Config.MaxMapRadius then
            local dx = math.abs(pos.X - node.Pos.X)
            local dz = math.abs(pos.Z - node.Pos.Z)
            local centerDist = math.sqrt(dx * dx + dz * dz)

            local halfX = math.max((node.Size.X * 0.48), 13)
            local halfZ = math.max((node.Size.Z * 0.48), 13)

            local overX = math.max(0, dx - halfX)
            local overZ = math.max(0, dz - halfZ)
            local edgeDist = math.sqrt(overX * overX + overZ * overZ)

            if edgeDist < minEdgeDist or (math.abs(edgeDist - minEdgeDist) < 0.5 and centerDist < minCenterDist) then
                minEdgeDist = edgeDist
                minCenterDist = centerDist
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
    local diff = Vector3.new(p2.X - p1.X, 0, p2.Z - p1.Z)
    local dist = diff.Magnitude
    if dist <= 6 then return true end

    local steps = math.clamp(math.ceil(dist / 12), 2, 12)
    for i = 1, steps do
        local alpha = i / steps
        local samplePos = p1:Lerp(p2, alpha)
        local _, edgeDist = getRoadInfoAtPosition(samplePos, false)
        if edgeDist > 3.5 then
            return false
        end
    end
    return true
end

-- ==============================================================================
-- 6. ESCÁNER DE SCRAP PILE Y CRASHED CAR (SOLO DENTRO DE LAS PISTAS)
-- ==============================================================================

local function isValidScrapTarget(model)
    if not model or not model.Parent or not model:IsA("Model") then return false end
    if model:GetAttribute("Dead") == true then return false end
    if IgnoredScrapUntil[model] and tick() < IgnoredScrapUntil[model] then return false end

    local n = model.Name:lower()
    if n:find("scrap pile") or n:find("crashed car") then
        return true
    end
    return false
end

local function scanRoadScrapTargets()
    local _, root = getCharacterParts()
    if not root then return end

    local myPos = root.Position
    local structFolder = workspace:FindFirstChild("Structures") or workspace
    local validTargets = {}

    for _, item in ipairs(structFolder:GetChildren()) do
        if isValidScrapTarget(item) then
            local part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
            if part then
                local sPos = part.Position
                local distToBase = (Vector3.new(sPos.X, 0, sPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

                if distToBase <= Config.MaxMapRadius and distToBase >= 95 then
                    local distToMe = (Vector3.new(sPos.X, 0, sPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                    if distToMe <= Config.ScrapSearchRadius then
                        local roadNode, edgeDist = getRoadInfoAtPosition(sPos, true)
                        if roadNode and edgeDist <= 3.0 then
                            local toTarget = Vector3.new(sPos.X - myPos.X, 0, sPos.Z - myPos.Z)
                            local forwardDot = (toTarget.Magnitude > 0) and toTarget.Unit:Dot(RoadTransit.CurrentDirection) or 1
                            local priorityScore = distToMe - (forwardDot * 35)

                            table.insert(validTargets, {
                                Model = item,
                                Part = part,
                                Pos = sPos,
                                RoadNode = roadNode,
                                Dist = distToMe,
                                Score = priorityScore
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(validTargets, function(a, b)
        return a.Score < b.Score
    end)

    RoadScrapList = validTargets
end

-- ==============================================================================
-- 7. MOTOR DE PATEO, LANZAMIENTO Y TELARAÑA (A PIE Y EN AUTO - 2 OBJETOS A 10m)
-- ==============================================================================

-- Verifica si el objeto es Scrap, Refined Metal, Fuel o Refined Fuel
local function isMovableTargetItem(entity)
    if not entity or not entity.Parent then return false end
    local n = entity.Name:lower()
    local itemType = tostring(entity:GetAttribute("ItemType") or ""):lower()

    -- Nunca patear zanahorias/comida para que el Auto-Eat las use
    if itemType == "food" or n:find("carrot") then
        return false
    end

    local isFuel = (n == "fuel" or n == "refined fuel" or n:find("fuel") or n:find("gas") or n:find("jerry") or n:find("canister")) and not n:find("mask")
    local isMetalOrScrap = n:find("scrap") or n:find("refined metal") or n:find("metal") or n:find("chatarra") or n:find("barrel") or n:find("sheet") or n:find("iron")
    local isResource = (itemType == "resource")

    if Config.MoveFuelCans and isFuel then return true end
    if Config.MoveScrapAndMetal and isMetalOrScrap then return true end
    if Config.MoveAllResources and isResource then return true end

    return false
end

-- Encuentra el punto objetivo en la matriz virtual de 1500m hacia la base
local function getTargetNodeTowardsBase(itemPos, desiredHopDist)
    local genPos = getGeneratorPosition()
    local itemHoriz = Vector3.new(itemPos.X, 0, itemPos.Z)
    local genHoriz = Vector3.new(genPos.X, 0, genPos.Z)
    local currentDistToGen = (itemHoriz - genHoriz).Magnitude

    local toBaseDir = (genHoriz - itemHoriz)
    if toBaseDir.Magnitude < 1 then return genPos end
    toBaseDir = toBaseDir.Unit

    -- Si la distancia que falta para llegar al borde seguro de la base es menor que la patada, apuntar justo al borde de la base
    local distToSafeBorder = math.max(10, currentDistToGen - (Config.GeneratorSafeRadius - 10))
    local actualHop = math.min(desiredHopDist, distToSafeBorder)

    local idealPoint = itemPos + (toBaseDir * actualHop)

    -- Buscar el nodo de la red virtual de 1500m más cercano a ese punto ideal
    local bestNodePos = idealPoint
    local shortestDiff = math.huge

    for _, vPos in ipairs(VirtualWebGrid) do
        local vHoriz = Vector3.new(vPos.X, 0, vPos.Z)
        local vDistToGen = (vHoriz - genHoriz).Magnitude
        if vDistToGen < (currentDistToGen - 3) then
            local d = (vHoriz - Vector3.new(idealPoint.X, 0, idealPoint.Z)).Magnitude
            if d < shortestDiff then
                shortestDiff = d
                bestNodePos = vPos
            end
        end
    end

    return bestNodePos
end

-- Despierta la propiedad de red usando el ClickDetector('ItemDrag') descubierto en tu reporte
local function wakeUpItemOwnership(targetEntity)
    local dragDetector = targetEntity:FindFirstChild("ItemDrag", true) or targetEntity:FindFirstChildWhichIsA("ClickDetector", true)
    if dragDetector and fireclickdetector then
        pcall(function() fireclickdetector(dragDetector) end)
    end

    if targetEntity:IsA("Model") then
        for _, p in ipairs(targetEntity:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
            end
        end
    elseif targetEntity:IsA("BasePart") then
        targetEntity.Anchored = false
    end
end

-- Ejecuta el movimiento según el modo elegido en el menú
local function launchOrMoveItem(targetEntity, mainPart, itemPos, genPos)
    wakeUpItemOwnership(targetEntity)

    local mode = Config.TransportMode
    local itemHoriz = Vector3.new(itemPos.X, 0, itemPos.Z)
    local genHoriz = Vector3.new(genPos.X, 0, genPos.Z)
    local dirToBase = (genHoriz - itemHoriz).Unit

    local angle = (math.random() - 0.5) * 0.22
    local cosA, sinA = math.cos(angle), math.sin(angle)
    local spreadDir = Vector3.new(
        dirToBase.X * cosA - dirToBase.Z * sinA,
        0,
        dirToBase.X * sinA + dirToBase.Z * cosA
    ).Unit

    local distToSafeEdge = math.max(12, (itemHoriz - genHoriz).Magnitude - (Config.GeneratorSafeRadius - 12))
    local targetThrowDist = math.min(Config.KickDistance, distToSafeEdge)

    local function applyVelocityToAll(vel, angVel)
        if targetEntity:IsA("Model") then
            for _, p in ipairs(targetEntity:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity = vel
                    p.AssemblyAngularVelocity = angVel
                end
            end
        else
            mainPart.AssemblyLinearVelocity = vel
            mainPart.AssemblyAngularVelocity = angVel
        end
    end

    if mode == "Patada Física (Lanzar)" then
        -- 1. Levantar ligeramente del suelo (1.5 studs) para que no tropiece con el pasto/piso al salir disparado
        local liftPos = itemPos + Vector3.new(0, 1.6, 0) + (spreadDir * 1.5)
        if targetEntity:IsA("Model") then
            targetEntity:PivotTo(CFrame.new(liftPos))
        else
            mainPart.CFrame = CFrame.new(liftPos)
        end

        -- 2. Calcular velocidad de lanzamiento parabólico para ~100 studs hacia la base
        local horizSpeed = math.clamp(targetThrowDist * 1.15, 25, 165)
        local verticalBoost = Config.KickArcHeight
        local kickVel = (spreadDir * horizSpeed) + Vector3.new(0, verticalBoost, 0)
        local spin = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))

        applyVelocityToAll(kickVel, spin)
        RecentlyKicked[targetEntity] = tick() + 0.55

    elseif mode == "Arrastre + Impulso (Drag)" then
        -- Eleva el objeto a la altura del torso/mano, avanza 15 studs y lo lanza el resto hacia la base
        local handPos = itemPos + Vector3.new(0, 3.2, 0) + (spreadDir * math.min(14, targetThrowDist * 0.3))
        if targetEntity:IsA("Model") then
            targetEntity:PivotTo(CFrame.new(handPos))
        else
            mainPart.CFrame = CFrame.new(handPos)
        end

        local pushSpeed = math.clamp(targetThrowDist * 0.95, 20, 140)
        applyVelocityToAll((spreadDir * pushSpeed) + Vector3.new(0, Config.KickArcHeight * 0.75, 0), Vector3.zero)
        RecentlyKicked[targetEntity] = tick() + 0.45

    elseif mode == "Deslizamiento Rápido" then
        -- Desliza al ras del suelo dando saltos cortos + velocidad horizontal hacia la base
        local nextNode = getTargetNodeTowardsBase(itemPos, math.min(28, targetThrowDist))
        local slidePos = Vector3.new(nextNode.X, itemPos.Y + 0.8, nextNode.Z)
        if targetEntity:IsA("Model") then
            targetEntity:PivotTo(CFrame.new(slidePos))
        else
            mainPart.CFrame = CFrame.new(slidePos)
        end

        applyVelocityToAll((spreadDir * 55) + Vector3.new(0, 4, 0), Vector3.zero)
        RecentlyKicked[targetEntity] = tick() + 0.20

    else -- "Teletransporte Telaraña"
        local nextNode = getTargetNodeTowardsBase(itemPos, Config.WebStepDistance)
        local rDist = math.random() * Config.SpreadRadius
        local rAng = math.random() * math.pi * 2
        local destPos = Vector3.new(
            nextNode.X + math.cos(rAng) * rDist,
            Config.WebGroundHeight + 0.6,
            nextNode.Z + math.sin(rAng) * rDist
        )

        if targetEntity:IsA("Model") then
            targetEntity:PivotTo(CFrame.new(destPos))
        else
            mainPart.CFrame = CFrame.new(destPos)
        end
        applyVelocityToAll(Vector3.new(0, -2.5, 0), Vector3.zero)
        RecentlyKicked[targetEntity] = tick() + 0.12
    end
end

-- Bucle principal de pateo/agarre (Funciona tanto caminando a pie como dentro del auto)
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

                                -- Estrictamente dentro de tu radio de presencia cercano (por defecto 10 studs)
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

                -- Ordenar por los más cercanos a tus pies/manos (menor de 10 studs primero)
                table.sort(candidates, function(a, b)
                    return a.Dist < b.Dist
                end)

                -- Procesar hasta Config.ItemsPerTick (por defecto 2 objetos a la vez)
                local countToProcess = math.min(#candidates, Config.ItemsPerTick)
                for i = 1, countToProcess do
                    local c = candidates[i]
                    launchOrMoveItem(c.Entity, c.Part, c.Pos, genPos)
                end
            end
        end
    end
end)

-- ==============================================================================
-- 8. MOTOR DE CONDUCCIÓN 100% EN PISTA + RETORNO A BASE POR GASOLINA
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
                        if distBase > curDistToBase then
                            score = score + 250
                        end
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
            if stepVec.Magnitude > 0.1 then
                curDir = stepVec.Unit
            end
            curPos = bestNode.Pos
        else
            break
        end
    end

    if #chain == 0 then
        local fallbackNode = nil
        local shortest = math.huge
        for _, node in ipairs(RoadNodes) do
            local distBase = (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
            if distBase <= Config.MaxMapRadius then
                local d = (Vector3.new(node.Pos.X - startPos.X, 0, node.Pos.Z - startPos.Z)).Magnitude
                if d >= 20 and d <= 135 and isStraightLineOnRoad(startPos, node.Pos) and d < shortest then
                    shortest = d
                    fallbackNode = node
                end
            end
        end
        if fallbackNode then
            table.insert(chain, fallbackNode)
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

    if FuelState.IsRefueling then
        local distToBaseCenter = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        if distToBaseCenter <= 135 then
            if distToBaseCenter > 22 then
                local toBase = Vector3.new(BaseCenter.X - myPos.X, 0, BaseCenter.Z - myPos.Z).Unit
                root.AssemblyLinearVelocity = Vector3.new(
                    toBase.X * (Config.VehicleSpeed * 0.75),
                    root.AssemblyLinearVelocity.Y,
                    toBase.Z * (Config.VehicleSpeed * 0.75)
                )
            else
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            end
            return
        end
    end

    local currentRoad, edgeDist, closestRoadSurfacePos = getRoadInfoAtPosition(myPos, true)

    if not currentRoad or edgeDist > 2.2 then
        IsRecoveringToRoad = true
        CurrentScrapTarget = nil
        RoadTransit.Waypoints = {}

        if currentRoad then
            local toAsphalt = Vector3.new(closestRoadSurfacePos.X - myPos.X, 0, closestRoadSurfacePos.Z - myPos.Z)
            if toAsphalt.Magnitude > 1.0 then
                local mDir = toAsphalt.Unit
                RoadTransit.CurrentDirection = mDir
                root.AssemblyLinearVelocity = Vector3.new(
                    mDir.X * Config.VehicleSpeed,
                    root.AssemblyLinearVelocity.Y,
                    mDir.Z * Config.VehicleSpeed
                )
            end
        end
        return
    end

    IsRecoveringToRoad = false
    currentRoad.LastVisited = tick()

    local activeScrap = nil
    if not FuelState.IsRefueling then
        for _, sc in ipairs(RoadScrapList) do
            if sc.Model and sc.Model.Parent and sc.Model:GetAttribute("Dead") ~= true and not (IgnoredScrapUntil[sc.Model] and tick() < IgnoredScrapUntil[sc.Model]) then
                if sc.Dist <= 95 and isStraightLineOnRoad(myPos, sc.Pos) then
                    activeScrap = sc
                    break
                end
            end
        end
    end

    if activeScrap then
        CurrentScrapTarget = activeScrap.Model
        local scrapPos = activeScrap.Pos
        local rNode = activeScrap.RoadNode

        local roadAxisX = rNode.Size.X >= rNode.Size.Z
        local safeTargetPos = scrapPos
        if roadAxisX then
            local clampedZ = math.clamp(scrapPos.Z - rNode.Pos.Z, -Config.RoadMaxHalfWidth, Config.RoadMaxHalfWidth)
            safeTargetPos = Vector3.new(scrapPos.X, scrapPos.Y, rNode.Pos.Z + clampedZ)
        else
            local clampedX = math.clamp(scrapPos.X - rNode.Pos.X, -Config.RoadMaxHalfWidth, Config.RoadMaxHalfWidth)
            safeTargetPos = Vector3.new(rNode.Pos.X + clampedX, scrapPos.Y, scrapPos.Z)
        end

        local diffToScrap = Vector3.new(safeTargetPos.X - myPos.X, 0, safeTargetPos.Z - myPos.Z)
        local distToScrap = diffToScrap.Magnitude

        if distToScrap <= 6.5 then
            IgnoredScrapUntil[activeScrap.Model] = tick() + 3.0
        else
            local driveDir = diffToScrap.Unit
            RoadTransit.CurrentDirection = driveDir

            local candidateOvershoot = safeTargetPos + (driveDir * Config.CrushOvershoot)
            local _, overEdgeDist = getRoadInfoAtPosition(candidateOvershoot, true)
            local finalDest = (overEdgeDist <= 2.0) and candidateOvershoot or safeTargetPos

            local hDir = Vector3.new(finalDest.X - myPos.X, 0, finalDest.Z - myPos.Z)
            if hDir.Magnitude > 1.2 then
                local vel = hDir.Unit * Config.VehicleSpeed
                root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)
            end
            return
        end
    else
        CurrentScrapTarget = nil
    end

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
            root.AssemblyLinearVelocity = Vector3.new(
                mDir.X * Config.VehicleSpeed,
                root.AssemblyLinearVelocity.Y,
                mDir.Z * Config.VehicleSpeed
            )
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.4)
        if Config.AutoFarmRoads then
            scanRoadScrapTargets()
        end
    end
end)

-- ==============================================================================
-- 9. INTERFAZ FLUENT (AUTO-PISTAS, PATADA/TELARAÑA 1500m, AUTO-EAT Y GASOLINA)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP CRUSHER & KICKER V4.0",
    SubTitle = "Red 1500m + Patada 100m + Fuel & Metal",
    TabWidth = 155,
    Size = UDim2.fromOffset(610, 530),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Items    = Window:AddTab({ Title = "Patear / Telaraña", Icon = "share-2" }),
    RoadFarm = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    AutoEat  = Window:AddTab({ Title = "Auto-Comer", Icon = "utensils" }),
    Fuel     = Window:AddTab({ Title = "Auto-Gasolina", Icon = "fuel" })
}

-- PESTAÑA 1: PATEAR / LANZAR Y TELARAÑA 1500 STUDS (A PIE Y EN AUTO)
Tabs.Items:AddSection("Modos de Lanzamiento / Patada hacia la Base (A Pie y Auto)")

local KickSendToggle = Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "👟 Activar Patear / Mover Objetos hacia la Base",
    Description = "Funciona caminando a pie y también manejando el auto",
    Default = true,
    Callback = function(v) Config.AutoSendItems = v end
})

Tabs.Items:AddDropdown("TransportModeDropdown", {
    Title = "Modo de Movimiento de Objetos",
    Values = {
        "Patada Física (Lanzar)",
        "Arrastre + Impulso (Drag)",
        "Deslizamiento Rápido",
        "Teletransporte Telaraña"
    },
    Default = "Patada Física (Lanzar)",
    Callback = function(v) Config.TransportMode = v end
})

Tabs.Items:AddSlider("PresenceSlider", {
    Title = "Distancia para Agarrar / Patear (Studs)",
    Description = "Por defecto 10 studs (Dentro del límite de 12m de ItemDrag)",
    Default = 10,
    Min = 5,
    Max = 35,
    Rounding = 0,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Items:AddSlider("KickDistSlider", {
    Title = "Fuerza / Distancia de la Patada (Studs)",
    Description = "Qué tan lejos lanza el objeto hacia la base (Defecto: 100m)",
    Default = 100,
    Min = 30,
    Max = 220,
    Rounding = 0,
    Callback = function(v) Config.KickDistance = v end
})

Tabs.Items:AddSlider("ArcHeightSlider", {
    Title = "Altura del Arco al Patear",
    Description = "Elevación para que no choque con piedras al volar",
    Default = 28,
    Min = 10,
    Max = 65,
    Rounding = 0,
    Callback = function(v) Config.KickArcHeight = v end
})

Tabs.Items:AddSlider("BatchItemsSlider", {
    Title = "Cantidad de Objetos a la Vez",
    Description = "Por defecto agarra y patea 2 cosas al mismo tiempo",
    Default = 2,
    Min = 1,
    Max = 5,
    Rounding = 0,
    Callback = function(v) Config.ItemsPerTick = v end
})

Tabs.Items:AddSection("Objetos Permitidos (Metal, Scrap y Gasolina)")

Tabs.Items:AddToggle("MoveScrapMetalToggle", {
    Title = "🔩 Mover Scrap y Refined Metal",
    Default = true,
    Callback = function(v) Config.MoveScrapAndMetal = v end
})

Tabs.Items:AddToggle("MoveFuelToggle", {
    Title = "⛽ Mover Fuel y Refined Fuel (Galones)",
    Default = true,
    Callback = function(v) Config.MoveFuelCans = v end
})

Tabs.Items:AddSection("Red Global de 1500 Studs (Todo el Mapa - 0% Lag)")

Tabs.Items:AddSlider("MaxWebRadiusSlider", {
    Title = "Rango Total Cubierto en Todo el Mapa (Studs)",
    Description = "Llena todo (pistas y campo abierto) hasta 1500 studs sin lag",
    Default = 1500,
    Min = 400,
    Max = 2000,
    Rounding = 0,
    Callback = function(v)
        Config.MaxMapRadius = v
        rebuildSpiderwebNetwork()
    end
})

Tabs.Items:AddSlider("StepDistSlider", {
    Title = "Espaciado de Puntos en el Mapa (Studs)",
    Default = 35,
    Min = 12,
    Max = 90,
    Rounding = 0,
    Callback = function(v)
        Config.WebStepDistance = v
        rebuildSpiderwebNetwork()
    end
})

Tabs.Items:AddToggle("ShowBallsToggle", {
    Title = "👁️ Mostrar Bolitas Cercanas (Vista Previa sin Lag)",
    Default = false,
    Callback = function(v)
        Config.ShowWebVisuals = v
        for _, pt in ipairs(ManualDeliveryPoints) do
            if pt and pt.Parent then
                pt.Transparency = v and 0.2 or 1
            end
        end
    end
})

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Manual Aquí",
    Callback = function()
        local _, root = getCharacterParts()
        if not root then return end
        createManualWebMarker(root.Position)
        Fluent:Notify({ Title = "Punto Agregado", Content = "Puntos virtuales + manuales: " .. #VirtualWebGrid, Duration = 2 })
    end
})

Tabs.Items:AddSection("Protección del Generador")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent (No patear lo que ya llegó)",
    Default = true,
    Callback = function(v) Config.BasePrevent = v end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio de Seguridad de la Base (Studs)",
    Default = 145,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(v)
        Config.GeneratorSafeRadius = v
        rebuildSpiderwebNetwork()
    end
})

-- PESTAÑA 2: AUTO-PISTAS
Tabs.RoadFarm:AddSection("Atropello 100% en Pistas (Sin Cruzar Terreno)")

local AutoFarmToggle = Tabs.RoadFarm:AddToggle("AutoFarmToggle", {
    Title = "🚜 Activar Auto-Atropello en Pistas",
    Default = false,
    Callback = function(v)
        Config.AutoFarmRoads = v
        if v then
            RoadTransit.Waypoints = {}
            scanRoadScrapTargets()
        else
            applyBrake(0.8)
        end
    end
})

local StatusParagraph = Tabs.RoadFarm:AddParagraph({
    Title = "Monitor de Pistas, Patada y Red 1500m",
    Content = "Cargando red..."
})

Tabs.RoadFarm:AddSlider("CarSpeedSlider", {
    Title = "Velocidad de Embestida en Pista",
    Default = 115,
    Min = 60,
    Max = 200,
    Rounding = 0,
    Callback = function(v) Config.VehicleSpeed = v end
})

Tabs.RoadFarm:AddSlider("OvershootSlider", {
    Title = "Rebase de Impacto (Overshoot Studs)",
    Default = 16,
    Min = 8,
    Max = 35,
    Rounding = 0,
    Callback = function(v) Config.CrushOvershoot = v end
})

Tabs.RoadFarm:AddSlider("RoadWidthSlider", {
    Title = "Ancho Máximo de Carril (Studs)",
    Default = 12,
    Min = 6,
    Max = 18,
    Rounding = 0,
    Callback = function(v) Config.RoadMaxHalfWidth = v end
})

-- PESTAÑA 3: AUTO-EAT (ON POR DEFECTO)
Tabs.AutoEat:AddSection("Consumo Inteligente de Zanahorias (0% Lag)")

local AutoEatToggleInstance = Tabs.AutoEat:AddToggle("AutoEatToggle", {
    Title = "🥕 Activar Auto-Comer en Suelo",
    Default = true,
    Callback = function(v) Config.AutoEatEnabled = v end
})

local EatStatusParagraph = Tabs.AutoEat:AddParagraph({
    Title = "Estado del Auto-Eat",
    Content = "Monitoreando comida y salud..."
})

Tabs.AutoEat:AddSlider("EatHpSlider", {
    Title = "Vida Baja (%): Comer SOLO DORADAS ✨",
    Default = 60,
    Min = 10,
    Max = 95,
    Rounding = 0,
    Callback = function(v) Config.EatHealthThreshold = v end
})

Tabs.AutoEat:AddSlider("EatHungerSlider", {
    Title = "Hambre Baja (%): Comer CUALQUIERA 🥕",
    Default = 50,
    Min = 10,
    Max = 90,
    Rounding = 0,
    Callback = function(v) Config.EatHungerThreshold = v end
})

Tabs.AutoEat:AddSlider("EatRadiusSlider", {
    Title = "Radio de Absorción al Conducir (Studs)",
    Default = 24,
    Min = 10,
    Max = 45,
    Rounding = 0,
    Callback = function(v) Config.EatScanRadius = v end
})

Tabs.AutoEat:AddButton({
    Title = "✨ Forzar Comer Zanahoria Dorada",
    Callback = function() eatGroundFood(true) end
})

Tabs.AutoEat:AddButton({
    Title = "🥕 Forzar Comer Cualquier Zanahoria",
    Callback = function() eatGroundFood(false) end
})

-- PESTAÑA 4: AUTO-GASOLINA DESDE EL AUTO
Tabs.Fuel:AddSection("Recarga Automática en Tanque Trasero Izquierdo")

Tabs.Fuel:AddToggle("AutoRefuelToggle", {
    Title = "⛽ Ir a Base y Echar Gasolina Automáticamente",
    Default = true,
    Callback = function(v) Config.AutoRefuelEnabled = v end
})

local FuelStatusParagraph = Tabs.Fuel:AddParagraph({
    Title = "Estado del Combustible",
    Content = "Monitoreando tanque..."
})

Tabs.Fuel:AddSlider("LowFuelSlider", {
    Title = "Ir a la Base si la Gasolina Baja de (%)",
    Default = 25,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(v) Config.LowFuelThreshold = v end
})

Tabs.Fuel:AddSlider("FuelRadiusSlider", {
    Title = "Radio para Atraer Galón al Tanque (Studs)",
    Default = 45,
    Min = 15,
    Max = 80,
    Rounding = 0,
    Callback = function(v) Config.FuelCanScanRadius = v end
})

Tabs.Fuel:AddButton({
    Title = "⛽ Echar Gasolina Ahora (Acercar Galón al Auto)",
    Callback = function()
        local ok = refuelTruckFromNearbyCan()
        if ok then
            Fluent:Notify({ Title = "⛽ Gasolina", Content = "Galón acoplado a la parte trasera izquierda del auto.", Duration = 2 })
        else
            Fluent:Notify({ Title = "⚠️ Sin Galones Cerca", Content = "Acércate a la base donde tengas galones de gasolina.", Duration = 2 })
        end
    end
})

-- ==============================================================================
-- 10. WIDGETS FLOTANTES (MENÚ + AUTO-PISTAS + PATEADOR + AUTO-EAT)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local FloatGui = Instance.new("ScreenGui")
FloatGui.Name = "ScrapWebMasterFloatGuiV4"
FloatGui.ResetOnSpawn = false
FloatGui.Parent = GuiParent

-- Widget 1: Abrir / Ocultar Menú
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

-- Widget 2: Encender / Apagar Auto-Farm Vial (Auto)
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

-- Widget 3: Encender / Apagar Pateador de Ítems (Por defecto ON)
local KickWidgetBtn = Instance.new("TextButton")
KickWidgetBtn.Size = UDim2.new(0, 48, 0, 48)
KickWidgetBtn.Position = UDim2.new(0.04, 0, 0.54, 0)
KickWidgetBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 180)
KickWidgetBtn.Text = "👟\nON"
KickWidgetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KickWidgetBtn.TextSize = 11
KickWidgetBtn.Font = Enum.Font.GothamBold
KickWidgetBtn.Active = true
KickWidgetBtn.Draggable = true
KickWidgetBtn.Parent = FloatGui

local KickCorner = Instance.new("UICorner")
KickCorner.CornerRadius = UDim.new(1, 0)
KickCorner.Parent = KickWidgetBtn

KickWidgetBtn.MouseButton1Click:Connect(function()
    Config.AutoSendItems = not Config.AutoSendItems
    pcall(function() KickSendToggle:SetValue(Config.AutoSendItems) end)
    if Config.AutoSendItems then
        KickWidgetBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 180)
        KickWidgetBtn.Text = "👟\nON"
    else
        KickWidgetBtn.BackgroundColor3 = Color3.fromRGB(160, 35, 40)
        KickWidgetBtn.Text = "👟\nOFF"
    end
end)

-- Widget 4: Auto-Eat (Por defecto ON)
local AutoEatWidgetBtn = Instance.new("TextButton")
AutoEatWidgetBtn.Size = UDim2.new(0, 48, 0, 48)
AutoEatWidgetBtn.Position = UDim2.new(0.04, 0, 0.63, 0)
AutoEatWidgetBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 60)
AutoEatWidgetBtn.Text = "🥕\nON"
AutoEatWidgetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoEatWidgetBtn.TextSize = 11
AutoEatWidgetBtn.Font = Enum.Font.GothamBold
AutoEatWidgetBtn.Active = true
AutoEatWidgetBtn.Draggable = true
AutoEatWidgetBtn.Parent = FloatGui

local EatCorner = Instance.new("UICorner")
EatCorner.CornerRadius = UDim.new(1, 0)
EatCorner.Parent = AutoEatWidgetBtn

AutoEatWidgetBtn.MouseButton1Click:Connect(function()
    Config.AutoEatEnabled = not Config.AutoEatEnabled
    pcall(function() AutoEatToggleInstance:SetValue(Config.AutoEatEnabled) end)
    if Config.AutoEatEnabled then
        AutoEatWidgetBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 60)
        AutoEatWidgetBtn.Text = "🥕\nON"
    else
        AutoEatWidgetBtn.BackgroundColor3 = Color3.fromRGB(160, 35, 40)
        AutoEatWidgetBtn.Text = "🥕\nOFF"
    end
end)

-- Actualización de monitores en tiempo real
task.spawn(function()
    while true do
        task.wait(0.6)
        local targetText = "Recorriendo red vial (100% Pista)"
        if FuelState.IsRefueling then
            targetText = "⛽ Volviendo a la Base para echar gasolina..."
        elseif IsRecoveringToRoad then
            targetText = "⚠️ Volviendo primero a la pista más cercana..."
        elseif CurrentScrapTarget then
            targetText = "Embestida en pista -> " .. CurrentScrapTarget.Name
        end

        StatusParagraph:SetDesc(string.format(
            "Rango global: %d studs | Nodos virtuales RAM: %d\nModo actual: %s (%d objetos a %dm)\nPistas: %d | Cúmulos: %d | Gasolina: %d%%\nEstado Auto: %s",
            Config.MaxMapRadius,
            #VirtualWebGrid,
            Config.TransportMode,
            Config.ItemsPerTick,
            Config.CollectRadius,
            #RoadNodes,
            #RoadScrapList,
            FuelState.FuelPct,
            targetText
        ))

        local pHP, pHunger = getPlayerStats()
        EatStatusParagraph:SetDesc(string.format(
            "Tu Vida: %d%% | Hambre: %d%%\nEstado Auto-Eat: %s\nModo Activo: %s",
            pHP, pHunger,
            Config.AutoEatEnabled and "🟢 ON" or "🔴 OFF",
            AutoEatState.Status
        ))

        FuelStatusParagraph:SetDesc(string.format(
            "Nivel del Tanque: %.0f / %.0f (%d%%)\nUmbral de Retorno: %d%%\nEstado: %s",
            FuelState.CurrentFuel, FuelState.MaxFuel, FuelState.FuelPct,
            Config.LowFuelThreshold,
            FuelState.Status
        ))
    end
end)

Window:SelectTab(1)
