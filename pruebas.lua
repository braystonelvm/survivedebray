-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER, SPIDERWEB RELAY, AUTO-EAT & AUTO-FUEL V3.0
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
    -- Rango total al 60% de 1200 (720 studs) y configurable
    MaxMapRadius = 720,

    -- Auto-Conducción por Pistas (Velocidad 115)
    AutoFarmRoads = false,
    VehicleSpeed = 115,
    RoadMaxHalfWidth = 12,      -- Límite lateral estricto dentro del asfalto
    ScrapSearchRadius = 400,    -- Radio de detección de cúmulos
    CrushOvershoot = 16,        -- Rebasa el cúmulo sobre el mismo carril sin vibrar

    -- Red Telaraña Ultra-Corta y al Ras del Suelo (Anti-Fantasma)
    AutoSendItems = true,
    OnlyScrap = true,
    ChainTeleport = true,
    BasePrevent = true,
    GeneratorSafeRadius = 145,  -- Radio donde ya deja los materiales en la base
    CollectRadius = 25,         -- Presencia cercana (25 studs) para garantizar Network Ownership
    WebStepDistance = 12,       -- Saltos cortos (12 studs, ajustable desde 8) entre bolitas
    WebGroundHeight = 0.6,      -- Altura fija pegada al suelo para que no floten en el aire
    SpreadRadius = 1.5,         -- Pequeña dispersión para que no colisionen entre sí
    TeleportInterval = 0.22,    -- Pausa entre cada ítem (procesa 1 por 1, 0% lag)
    ShowWebVisuals = false,     -- Mostrar/ocultar las bolitas de la red

    -- Auto-Eat Integrado (Activado por defecto)
    AutoEatEnabled = true,
    EatHealthThreshold = 60,    -- Come SOLO ZANAHORIA DORADA si la vida baja de este %
    EatHungerThreshold = 50,    -- Come CUALQUIER ZANAHORIA si el hambre baja de este %
    EatScanRadius = 24,         -- Radio para absorber comida del suelo
    EatCooldown = 0.9,

    -- Auto-Gasolina desde el Auto
    AutoRefuelEnabled = true,
    LowFuelThreshold = 25,      -- Ir a la base a echar gasolina si baja del 25%
    FullFuelThreshold = 90,     -- Reanudar patrulla cuando supere el 90%
    FuelCanScanRadius = 45      -- Radio para atraer el galón hacia el tanque del auto
}

local RoadNodes = {}            -- Nodos de todas las pistas cargadas dentro del rango
local DeliveryPoints = {}       -- Bolitas de la telaraña (automáticas + manuales)
local RoadScrapList = {}        -- Cúmulos y autos chatarra validados dentro de la pista
local IgnoredScrapUntil = {}    -- Evita quedarse pegado en un mismo cúmulo tras atravesarlo

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

-- Localiza el receptor de gasolina en la parte izquierda trasera del auto
local function getTruckFuelReceptor(truck, seat)
    for _, desc in ipairs(truck:GetDescendants()) do
        if desc:IsA("BasePart") then
            local n = desc.Name:lower()
            if n:find("fuel") or n:find("tank") or n:find("gas") or n:find("cap") or n:find("fill") then
                return desc, desc.Position
            end
        end
    end
    -- Posición exacta en la parte trasera izquierda del camión respecto al asiento de conducción
    local refCF = (seat and seat.CFrame) or (truck.PrimaryPart and truck.PrimaryPart.CFrame) or CFrame.new()
    local rearLeftPos = (refCF * CFrame.new(-3.4, 0.8, 5.2)).Position
    return truck.PrimaryPart or seat, rearLeftPos
end

-- Busca un galón de gasolina cerca y lo acopla al tanque izquierdo trasero del auto
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
                    local isGasCan = n:find("gas") or n:find("fuel") or n:find("jerry") or n:find("canister") or n:find("galon") or n:find("bidon") or itemType:find("fuel") or itemType:find("gas")

                    if isGasCan then
                        local p = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                        if p and not p.Anchored then
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
-- 4. POSICIÓN DEL GENERADOR Y RED DE BOLITAS AL RAS DEL SUELO
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

local function createWebMarker(pos, isManual)
    local marker = Instance.new("Part")
    marker.Name = isManual and "CustomDropPoint" or "AutoWebNode"
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(1.8, 1.8, 1.8)
    marker.Material = Enum.Material.Neon
    marker.Color = isManual and Color3.fromRGB(0, 255, 170) or Color3.fromRGB(0, 180, 255)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Transparency = Config.ShowWebVisuals and 0.2 or 1
    -- Altura fijada al ras del suelo (Config.WebGroundHeight = 0.6) para que ninguna bolita quede en lo alto
    marker.Position = Vector3.new(pos.X, Config.WebGroundHeight, pos.Z)
    marker.Parent = workspace

    table.insert(DeliveryPoints, marker)
    return marker
end

-- Crea puntos cortos a lo largo de cada tramo de pista permitiendo distancias desde 8 studs
local function populateWebNodesForRoad(node)
    local genPos = getGeneratorPosition()
    local isX = node.Size.X >= node.Size.Z
    local length = math.max(node.Size.X, node.Size.Z)
    local axisDir = isX and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)

    local halfLen = length * 0.48
    local step = math.max(8, Config.WebStepDistance)

    for offset = -halfLen, halfLen, step do
        local candidatePos = Vector3.new(
            node.Pos.X + (axisDir.X * offset),
            Config.WebGroundHeight,
            node.Pos.Z + (axisDir.Z * offset)
        )
        local distFromCenter = (Vector3.new(candidatePos.X, 0, candidatePos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

        if distFromCenter <= Config.MaxMapRadius and (Vector3.new(candidatePos.X, 0, candidatePos.Z) - Vector3.new(genPos.X, 0, genPos.Z)).Magnitude > (Config.GeneratorSafeRadius - 10) then
            local tooClose = false
            for _, pt in ipairs(DeliveryPoints) do
                if pt and pt.Parent then
                    local dHoriz = (Vector3.new(pt.Position.X, 0, pt.Position.Z) - Vector3.new(candidatePos.X, 0, candidatePos.Z)).Magnitude
                    if dHoriz < (step * 0.72) then
                        tooClose = true
                        break
                    end
                end
            end
            if not tooClose then
                createWebMarker(candidatePos, false)
            end
        end
    end
end

local function rebuildSpiderwebNetwork()
    for i = #DeliveryPoints, 1, -1 do
        local pt = DeliveryPoints[i]
        if not pt or not pt.Parent or pt.Name == "AutoWebNode" then
            if pt and pt.Parent then pt:Destroy() end
            table.remove(DeliveryPoints, i)
        end
    end

    for _, rNode in ipairs(RoadNodes) do
        local d = (Vector3.new(rNode.Pos.X, 0, rNode.Pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        if d <= Config.MaxMapRadius then
            populateWebNodesForRoad(rNode)
        end
    end
end

-- ==============================================================================
-- 5. MAPEO DE PISTAS Y VERIFICACIÓN ESTRICTA DE ASFALTO
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
    if distFromCenter > 1200 or distFromCenter < 92 then return end

    for _, node in ipairs(RoadNodes) do
        if (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 20 then
            return
        end
    end

    -- Altura nivelada cerca del suelo para evitar saltos bruscos de coordenada Y
    local newNode = {
        Pos = Vector3.new(pos.X, Config.WebGroundHeight, pos.Z),
        Size = size,
        Instance = obj,
        LastVisited = 0
    }
    table.insert(RoadNodes, newNode)

    if distFromCenter <= Config.MaxMapRadius then
        populateWebNodesForRoad(newNode)
    end
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
-- 7. BUCLE DE TELETRANSPORTE EN TELARAÑA (SALTOS ULTRA-CORTOS AL RAS DEL SUELO)
-- ==============================================================================

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getNextSpiderwebPoint(itemPos, myPos)
    local genPos = getGeneratorPosition()
    local itemHoriz = Vector3.new(itemPos.X, 0, itemPos.Z)
    local genHoriz = Vector3.new(genPos.X, 0, genPos.Z)
    local myHoriz = Vector3.new(myPos.X, 0, myPos.Z)

    local currentDistToGen = (itemHoriz - genHoriz).Magnitude
    local bestPoint = nil
    local shortestStep = math.huge

    local maxAllowedHop = Config.WebStepDistance + 14

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local ptHoriz = Vector3.new(pt.Position.X, 0, pt.Position.Z)
            local stepDist = (itemHoriz - ptHoriz).Magnitude
            local pointDistToGen = (ptHoriz - genHoriz).Magnitude
            local distToPlayer = (ptHoriz - myHoriz).Magnitude

            if Config.ChainTeleport then
                -- Permite saltos pequeños (desde 2.5 studs) acercando el material a la base dentro de tu radio
                if pointDistToGen < (currentDistToGen - 2.0) and stepDist > 2.5 and stepDist <= maxAllowedHop and distToPlayer <= (Config.CollectRadius + 25) then
                    if stepDist < shortestStep then
                        shortestStep = stepDist
                        bestPoint = pt
                    end
                end
            else
                if stepDist < shortestStep and stepDist > 2.5 and stepDist <= maxAllowedHop then
                    shortestStep = stepDist
                    bestPoint = pt
                end
            end
        end
    end

    return bestPoint
end

task.spawn(function()
    while true do
        task.wait(Config.TeleportInterval)
        if Config.AutoSendItems and #DeliveryPoints > 0 then
            local char, root = getCharacterParts()
            if root then
                local myPos = root.Position
                overlapParams.FilterDescendantsInstances = {char}
                local partsNearby = workspace:GetPartBoundsInRadius(myPos, Config.CollectRadius, overlapParams)
                local processedOne = false

                for _, hitPart in ipairs(partsNearby) do
                    if processedOne then break end

                    if not hitPart.Anchored and not hitPart:FindFirstAncestorOfClass("Humanoid") then
                        local itemModel = hitPart:FindFirstAncestorOfClass("Model")
                        local isVehicle = itemModel and (itemModel:FindFirstChild("DriveSeat") or itemModel:FindFirstChildWhichIsA("VehicleSeat"))

                        if not isVehicle then
                            local targetEntity = (itemModel and itemModel.Parent ~= workspace:FindFirstChild("Characters") and itemModel) or hitPart
                            local rootPos = (targetEntity:IsA("Model") and targetEntity:GetPivot().Position) or targetEntity.Position

                            if (Vector3.new(rootPos.X, 0, rootPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude <= Config.CollectRadius then
                                local nameLower = targetEntity.Name:lower()
                                local isScrap = nameLower:find("scrap") or nameLower:find("chatarra") or nameLower:find("metal") or nameLower:find("barrel") or nameLower:find("sheet") or targetEntity:GetAttribute("ItemType") == "Resource"

                                if not Config.OnlyScrap or isScrap then
                                    local genPos = getGeneratorPosition()
                                    local insideBase = false
                                    if Config.BasePrevent and genPos then
                                        if (Vector3.new(rootPos.X, 0, rootPos.Z) - Vector3.new(genPos.X, 0, genPos.Z)).Magnitude <= Config.GeneratorSafeRadius then
                                            insideBase = true
                                        end
                                    end

                                    if not insideBase then
                                        local nextPoint = getNextSpiderwebPoint(rootPos, myPos)
                                        if nextPoint then
                                            processedOne = true

                                            local angle = math.random() * math.pi * 2
                                            local rDist = math.random() * Config.SpreadRadius
                                            local destPos = Vector3.new(
                                                nextPoint.Position.X + math.cos(angle) * rDist,
                                                Config.WebGroundHeight + 0.5,
                                                nextPoint.Position.Z + math.sin(angle) * rDist
                                            )

                                            if targetEntity:IsA("Model") then
                                                targetEntity:PivotTo(CFrame.new(destPos))
                                                for _, p in ipairs(targetEntity:GetDescendants()) do
                                                    if p:IsA("BasePart") then
                                                        p.AssemblyLinearVelocity = Vector3.new(0, -2.5, 0)
                                                        p.AssemblyAngularVelocity = Vector3.zero
                                                    end
                                                end
                                            else
                                                targetEntity.CFrame = CFrame.new(destPos)
                                                targetEntity.AssemblyLinearVelocity = Vector3.new(0, -2.5, 0)
                                                targetEntity.AssemblyAngularVelocity = Vector3.zero
                                            end
                                        end
                                    end
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
-- 8. MOTOR DE CONDUCCIÓN 100% EN PISTA + RETORNO A BASE POR GASOLINA
-- ==============================================================================

-- Construye ruta por las pistas; si returnToBase == true, elige siempre las pistas que acercan al centro de la base
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
                        -- Priorizar nodos de pista que nos acerquen directamente a la base para recargar gasolina
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

    -- ==========================================================================
    -- MODO RECARGA DE GASOLINA: SI TIENE <= 25%, REGRESA A LA BASE Y SE DETIENE AL LLEGAR
    -- ==========================================================================
    if FuelState.IsRefueling then
        local distToBaseCenter = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
        -- Si ya llegó a la entrada de la base (<= 135 studs), entra al centro para acoplar los galones
        if distToBaseCenter <= 135 then
            if distToBaseCenter > 22 then
                local toBase = Vector3.new(BaseCenter.X - myPos.X, 0, BaseCenter.Z - myPos.Z).Unit
                root.AssemblyLinearVelocity = Vector3.new(
                    toBase.X * (Config.VehicleSpeed * 0.75),
                    root.AssemblyLinearVelocity.Y,
                    toBase.Z * (Config.VehicleSpeed * 0.75)
                )
            else
                -- Frenar en el centro de la base mientras los galones recargan el tanque
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            end
            return
        end
    end

    local currentRoad, edgeDist, closestRoadSurfacePos = getRoadInfoAtPosition(myPos, true)

    -- ==========================================================================
    -- REGLA #1: SI NO ESTÁ EN LA PISTA, VA PRIMERO A LA PISTA MÁS CERCANA
    -- ==========================================================================
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

    -- ==========================================================================
    -- REGLA #2: EMBESTIR CHATARRA SOLO SI NO ESTÁ EN EMERGENCIA DE GASOLINA Y ES 100% PISTA
    -- ==========================================================================
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

    -- ==========================================================================
    -- REGLA #3: NAVEGACIÓN ESTRICTA POR NODOS DE PISTA CONECTADOS
    -- ==========================================================================
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
-- 9. INTERFAZ FLUENT (AUTO-PISTAS, TELARAÑA, AUTO-COMER Y AUTO-GASOLINA)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP HIGHWAY & WEB RELAY V3.0",
    SubTitle = "Pistas + Telaraña Suelo + Auto-Eat + Gasolina",
    TabWidth = 155,
    Size = UDim2.fromOffset(600, 520),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    RoadFarm = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    Items    = Window:AddTab({ Title = "Red Telaraña", Icon = "share-2" }),
    AutoEat  = Window:AddTab({ Title = "Auto-Comer", Icon = "utensils" }),
    Fuel     = Window:AddTab({ Title = "Auto-Gasolina", Icon = "fuel" })
}

-- PESTAÑA 1: AUTO-PISTAS
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
    Title = "Monitor de Pistas y Chatarra",
    Content = "Cargando red vial..."
})

Tabs.RoadFarm:AddSlider("CarSpeedSlider", {
    Title = "Velocidad de Embestida en Pista",
    Default = 115,
    Min = 60,
    Max = 200,
    Rounding = 0,
    Callback = function(v) Config.VehicleSpeed = v end
})

Tabs.RoadFarm:AddSlider("MaxMapRadiusSlider1", {
    Title = "Rango Total de Pistas y Telaraña (Studs)",
    Description = "Por defecto al 60% (720 studs de 1200)",
    Default = 720,
    Min = 300,
    Max = 1200,
    Rounding = 0,
    Callback = function(v)
        Config.MaxMapRadius = v
        rebuildSpiderwebNetwork()
    end
})

Tabs.RoadFarm:AddSlider("OvershootSlider", {
    Title = "Rebase de Impacto (Overshoot Studs)",
    Description = "Atraviesa el cúmulo de largo sin frenar ni vibrar",
    Default = 16,
    Min = 8,
    Max = 35,
    Rounding = 0,
    Callback = function(v) Config.CrushOvershoot = v end
})

Tabs.RoadFarm:AddSlider("RoadWidthSlider", {
    Title = "Ancho Máximo de Carril (Studs)",
    Description = "Mantiene el auto dentro de la pista sin pisar tierra",
    Default = 12,
    Min = 6,
    Max = 18,
    Rounding = 0,
    Callback = function(v) Config.RoadMaxHalfWidth = v end
})

-- PESTAÑA 2: TELETRANSPORTE EN TELARAÑA (BOLITAS EN EL SUELO Y MÁS CORTAS)
Tabs.Items:AddSection("Red de Puntos al Ras del Suelo (Anti-Fantasma)")

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Manual Aquí",
    Callback = function()
        local _, root = getCharacterParts()
        if not root then return end
        createWebMarker(root.Position, true)
        Fluent:Notify({ Title = "Punto Agregado", Content = "Nodos totales en la red: " .. #DeliveryPoints, Duration = 2 })
    end
})

Tabs.Items:AddToggle("ShowBallsToggle", {
    Title = "👁️ Mostrar Bolitas de la Telaraña en el Mapa",
    Default = false,
    Callback = function(v)
        Config.ShowWebVisuals = v
        for _, pt in ipairs(DeliveryPoints) do
            if pt and pt.Parent then
                pt.Transparency = v and 0.2 or 1
            end
        end
    end
})

Tabs.Items:AddButton({
    Title = "Borrar y Regenerar Telaraña",
    Callback = function()
        for _, p in ipairs(DeliveryPoints) do
            if p and p.Parent then p:Destroy() end
        end
        table.clear(DeliveryPoints)
        rebuildSpiderwebNetwork()
        Fluent:Notify({ Title = "Red Reiniciada", Content = "Telaraña al ras del suelo: " .. #DeliveryPoints .. " nodos.", Duration = 2 })
    end
})

Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "🕸️ Activar Teletransporte de Ítems (1 por 1)",
    Default = true,
    Callback = function(v) Config.AutoSendItems = v end
})

Tabs.Items:AddToggle("OnlyScrapToggle", {
    Title = "Solo Teletransportar Chatarra (Scrap)",
    Default = true,
    Callback = function(v) Config.OnlyScrap = v end
})

Tabs.Items:AddToggle("ChainTeleportToggle", {
    Title = "Permitir Teletransporte Continuo en Saltos Cortos",
    Default = true,
    Callback = function(v) Config.ChainTeleport = v end
})

Tabs.Items:AddSlider("PresenceSlider", {
    Title = "Distancia de Tu Presencia (Studs)",
    Description = "Por defecto 25m para evitar objetos fantasma",
    Default = 25,
    Min = 15,
    Max = 100,
    Rounding = 0,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Items:AddSlider("StepDistSlider", {
    Title = "Distancia Corta Entre Bolitas (Studs)",
    Description = "Configurable desde 8 studs (Por defecto 12m)",
    Default = 12,
    Min = 8,
    Max = 80,
    Rounding = 0,
    Callback = function(v)
        Config.WebStepDistance = v
        rebuildSpiderwebNetwork()
    end
})

Tabs.Items:AddSlider("MaxWebRadiusSlider", {
    Title = "Rango Total de la Telaraña (Studs)",
    Description = "60% por defecto (720 studs alrededor de la base)",
    Default = 720,
    Min = 300,
    Max = 1200,
    Rounding = 0,
    Callback = function(v)
        Config.MaxMapRadius = v
        rebuildSpiderwebNetwork()
    end
})

Tabs.Items:AddSection("Protección del Generador")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Default = true,
    Callback = function(v) Config.BasePrevent = v end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio de Seguridad del Generador (Studs)",
    Default = 145,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(v) Config.GeneratorSafeRadius = v end
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
-- 10. WIDGETS FLOTANTES (MENÚ + AUTO-PISTAS + AUTO-EAT)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local FloatGui = Instance.new("ScreenGui")
FloatGui.Name = "ScrapWebMasterFloatGuiV3"
FloatGui.ResetOnSpawn = false
FloatGui.Parent = GuiParent

-- Widget 1: Abrir / Ocultar Menú
local MenuBtn = Instance.new("ImageButton")
MenuBtn.Size = UDim2.new(0, 48, 0, 48)
MenuBtn.Position = UDim2.new(0.04, 0, 0.66, 0)
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

-- Widget 2: Encender / Apagar Auto-Farm Vial
local DriveBtn = Instance.new("TextButton")
DriveBtn.Size = UDim2.new(0, 48, 0, 48)
DriveBtn.Position = UDim2.new(0.04, 0, 0.48, 0)
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

-- Widget 3: Auto-Eat (Por defecto ON)
local AutoEatWidgetBtn = Instance.new("TextButton")
AutoEatWidgetBtn.Size = UDim2.new(0, 48, 0, 48)
AutoEatWidgetBtn.Position = UDim2.new(0.04, 0, 0.57, 0)
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
        Fluent:Notify({ Title = "🥕 AUTO-EAT", Content = "Consumo automático activado.", Duration = 2 })
    else
        AutoEatWidgetBtn.BackgroundColor3 = Color3.fromRGB(160, 35, 40)
        AutoEatWidgetBtn.Text = "🥕\nOFF"
        Fluent:Notify({ Title = "🥕 AUTO-EAT", Content = "Consumo automático pausado.", Duration = 2 })
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
            "Rango activo: %d studs | Distancia bolitas: %dm\nPistas registradas: %d | Bolitas en suelo: %d\nCúmulos en pista: %d | Gasolina: %d%%\nAcción actual: %s",
            Config.MaxMapRadius,
            Config.WebStepDistance,
            #RoadNodes,
            #DeliveryPoints,
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
