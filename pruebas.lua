-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER & SPIDERWEB RELAY V2.5 (MOTOR CINÉTICO V16 SIN VIBRACIÓN)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)
local MAX_MAP_RADIUS = 1200

local Config = {
    -- Auto-Conducción por Pistas (Motor V16)
    AutoFarmRoads = false,
    VehicleSpeed = 135,
    RoadMaxHalfWidth = 14,      -- Límite lateral desde el centro de la pista (nunca sale a tierra)
    ScrapSearchRadius = 500,    -- Radio de detección de cúmulos a tu alrededor
    CrushOvershoot = 18,        -- Rebasa el cúmulo 18 studs hacia adelante para no frenar ni vibrar

    -- Red Telaraña de Teletransporte (1 por 1, pasos cortos)
    AutoSendItems = true,
    OnlyScrap = true,
    ChainTeleport = true,
    BasePrevent = true,
    GeneratorSafeRadius = 145,  -- Radio donde ya deja los materiales en la base
    CollectRadius = 85,         -- Tu presencia necesaria en studs para mover el ítem sin buguearlo
    WebStepDistance = 65,       -- Distancia corta de cada salto en la telaraña (studs)
    SpreadRadius = 2.5,         -- Pequeña dispersión para que no colisionen entre sí
    TeleportInterval = 0.28,    -- Pausa entre cada ítem (procesa 1 por 1, 0% lag)
    ShowWebVisuals = false      -- Mostrar/ocultar las bolitas de la red
}

local RoadNodes = {}            -- Nodos de todas las pistas cargadas hasta 1200 studs
local DeliveryPoints = {}       -- Bolitas de la telaraña (automáticas + manuales)
local RoadScrapList = {}        -- Cúmulos y autos chatarra validados dentro de la pista
local IgnoredScrapUntil = {}    -- Evita quedarse pegado en un mismo cúmulo tras atravesarlo

local CachedGeneratorPos = nil
local CurrentScrapTarget = nil

-- Estado de Ruta Fluida (idéntico al TransitState del V16.0)
local RoadTransit = {
    Waypoints = {},
    Index = 1,
    CurrentDirection = Vector3.new(0, 0, 1)
}

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. OBTENCIÓN DE PERSONAJE Y VEHÍCULO (EXACTO AL V16.0)
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
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
-- 2. POSICIÓN DEL GENERADOR Y RED DE BOLITAS (TELARAÑA AUTOMÁTICA + MANUAL)
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
    marker.Size = Vector3.new(2.2, 2.2, 2.2)
    marker.Material = Enum.Material.Neon
    marker.Color = isManual and Color3.fromRGB(0, 255, 170) or Color3.fromRGB(0, 180, 255)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Transparency = Config.ShowWebVisuals and 0.2 or 1
    marker.Position = pos + Vector3.new(0, 1.2, 0)
    marker.Parent = workspace

    table.insert(DeliveryPoints, marker)
    return marker
end

local function tryAddWebNodeAtRoad(roadPos)
    local genPos = getGeneratorPosition()
    if (roadPos - genPos).Magnitude <= (Config.GeneratorSafeRadius - 15) then return end

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            if (pt.Position - roadPos).Magnitude < (Config.WebStepDistance * 0.85) then
                return
            end
        end
    end
    createWebMarker(roadPos, false)
end

-- ==============================================================================
-- 3. MAPEO PROGRESIVO DE PISTAS Y CONEXIÓN DE CARRILES (1200 STUDS)
-- ==============================================================================

local function isRoadObject(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    if n:find("straight") or n:find("road") or n:find("pista") or n:find("corner") or n:find("tsection") then
        if not n:find("sign") and not n:find("light") and not n:find("lamp") and not n:find("railing") then
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
    if distFromCenter > MAX_MAP_RADIUS or distFromCenter < 95 then return end

    for _, node in ipairs(RoadNodes) do
        if (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 24 then
            return
        end
    end

    local newNode = {
        Pos = Vector3.new(pos.X, pos.Y + 1.5, pos.Z),
        Size = size,
        Instance = obj,
        LastVisited = 0
    }
    table.insert(RoadNodes, newNode)
    tryAddWebNodeAtRoad(newNode.Pos)
end

-- Escaneo inicial por lotes sin congelar
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

-- Verifica si un punto está realmente dentro de la superficie de alguna pista (no solo cerca del centro)
local function getRoadInfoAtPosition(pos)
    local bestNode = nil
    local minCenterDist = math.huge
    local minEdgeDist = math.huge

    for _, node in ipairs(RoadNodes) do
        local dx = math.abs(pos.X - node.Pos.X)
        local dz = math.abs(pos.Z - node.Pos.Z)
        local centerDist = math.sqrt(dx * dx + dz * dz)

        local halfX = math.max((node.Size.X * 0.5), 18)
        local halfZ = math.max((node.Size.Z * 0.5), 18)

        local overX = math.max(0, dx - halfX)
        local overZ = math.max(0, dz - halfZ)
        local edgeDist = math.sqrt(overX * overX + overZ * overZ)

        if edgeDist < minEdgeDist or (edgeDist == 0 and centerDist < minCenterDist) then
            minEdgeDist = edgeDist
            minCenterDist = centerDist
            bestNode = node
        end
    end

    return bestNode, minEdgeDist, minCenterDist
end

-- ==============================================================================
-- 4. ESCÁNER DE SCRAP PILE Y CRASHED CAR (SOLO DENTRO DE LAS PISTAS)
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

                if distToBase <= MAX_MAP_RADIUS and distToBase >= 95 then
                    local distToMe = (Vector3.new(sPos.X, 0, sPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                    if distToMe <= Config.ScrapSearchRadius then
                        -- Confirmar que el cúmulo o auto chatarra está sobre el asfalto (edgeDist <= 6)
                        local roadNode, edgeDist = getRoadInfoAtPosition(sPos)
                        if roadNode and edgeDist <= 6 then
                            -- Priorizar los que están hacia adelante de nuestra dirección actual para no hacer ida y vuelta
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
-- 5. BUCLE DE TELETRANSPORTE EN TELARAÑA (1 POR 1, SALTOS CORTOS, CERO LAG)
-- ==============================================================================

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getNextSpiderwebPoint(itemPos)
    local genPos = getGeneratorPosition()
    local currentDistToGen = (itemPos - genPos).Magnitude
    local bestPoint = nil
    local shortestStep = math.huge

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local ptPos = pt.Position
            local stepDist = (itemPos - ptPos).Magnitude
            local pointDistToGen = (ptPos - genPos).Magnitude

            if Config.ChainTeleport then
                if pointDistToGen < (currentDistToGen - 5) and stepDist > 5 and stepDist <= (Config.WebStepDistance + 40) then
                    if stepDist < shortestStep then
                        shortestStep = stepDist
                        bestPoint = pt
                    end
                end
            else
                if stepDist < shortestStep and stepDist > 5 then
                    shortestStep = stepDist
                    bestPoint = pt
                end
            end
        end
    end

    if not bestPoint then
        for _, pt in ipairs(DeliveryPoints) do
            if pt and pt.Parent then
                local ptPos = pt.Position
                local stepDist = (itemPos - ptPos).Magnitude
                local pointDistToGen = (ptPos - genPos).Magnitude
                if pointDistToGen < (currentDistToGen - 8) and stepDist < shortestStep then
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
                overlapParams.FilterDescendantsInstances = {char}
                local partsNearby = workspace:GetPartBoundsInRadius(root.Position, Config.CollectRadius, overlapParams)
                local processedOne = false

                for _, hitPart in ipairs(partsNearby) do
                    if processedOne then break end

                    if not hitPart.Anchored and not hitPart:FindFirstAncestorOfClass("Humanoid") then
                        local itemModel = hitPart:FindFirstAncestorOfClass("Model")
                        local isVehicle = itemModel and (itemModel:FindFirstChild("DriveSeat") or itemModel:FindFirstChildWhichIsA("VehicleSeat"))

                        if not isVehicle then
                            local targetEntity = (itemModel and itemModel.Parent ~= workspace:FindFirstChild("Characters") and itemModel) or hitPart
                            local rootPos = (targetEntity:IsA("Model") and targetEntity:GetPivot().Position) or targetEntity.Position

                            local nameLower = targetEntity.Name:lower()
                            local isScrap = nameLower:find("scrap") or nameLower:find("chatarra") or nameLower:find("metal") or nameLower:find("barrel") or nameLower:find("sheet") or targetEntity:GetAttribute("ItemType") == "Resource"

                            if not Config.OnlyScrap or isScrap then
                                local genPos = getGeneratorPosition()
                                local insideBase = false
                                if Config.BasePrevent and genPos then
                                    if (rootPos - genPos).Magnitude <= Config.GeneratorSafeRadius then
                                        insideBase = true
                                    end
                                end

                                if not insideBase then
                                    local nextPoint = getNextSpiderwebPoint(rootPos)
                                    if nextPoint then
                                        processedOne = true

                                        local angle = math.random() * math.pi * 2
                                        local rDist = math.random() * Config.SpreadRadius
                                        local destPos = nextPoint.Position + Vector3.new(math.cos(angle) * rDist, 1.2, math.sin(angle) * rDist)

                                        if targetEntity:IsA("Model") then
                                            targetEntity:PivotTo(CFrame.new(destPos))
                                            for _, p in ipairs(targetEntity:GetDescendants()) do
                                                if p:IsA("BasePart") then
                                                    p.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
                                                    p.AssemblyAngularVelocity = Vector3.zero
                                                end
                                            end
                                        else
                                            targetEntity.CFrame = CFrame.new(destPos)
                                            targetEntity.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
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
end)

-- ==============================================================================
-- 6. MOTOR CINÉTICO DE CONDUCCIÓN FLUIDA (ESTILO ZOMBIE HUB V16.0 - CERO VIBRACIÓN)
-- ==============================================================================

-- Construye una cadena de nodos hacia adelante por la pista (igual que TransitState.Waypoints)
local function buildForwardRoadChain(startPos, currentDir)
    local chain = {}
    local curPos = startPos
    local curDir = currentDir
    local used = {}

    for step = 1, 6 do
        local bestNode = nil
        local bestScore = math.huge
        local now = tick()

        for _, node in ipairs(RoadNodes) do
            if not used[node] then
                local diff = Vector3.new(node.Pos.X - curPos.X, 0, node.Pos.Z - curPos.Z)
                local dist = diff.Magnitude

                if dist >= 28 and dist <= 170 then
                    local dirToNode = diff.Unit
                    local dot = dirToNode:Dot(curDir) -- Preferir seguir recto hacia adelante (> 0.2)
                    local unvisitedBonus = math.min((now - node.LastVisited) * 1.5, 90)

                    -- Penalizar fuertemente dar media vuelta hacia atrás para que nunca vibre
                    local backwardPenalty = (dot < -0.2) and 300 or ((dot < 0.2) and 80 or 0)
                    local score = dist + backwardPenalty - (dot * 45) - unvisitedBonus

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

    return chain
end

RunService.Heartbeat:Connect(function()
    if not Config.AutoFarmRoads then return end

    -- Exactamente igual que en V16.0: obtener root del jugador sentado en VehicleSeat
    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then return end

    local myPos = root.Position
    local currentRoad, edgeDist = getRoadInfoAtPosition(myPos)

    if currentRoad and edgeDist <= 8 then
        currentRoad.LastVisited = tick()
    end

    -- 1. PROTECCIÓN ANTI-SALIDA DE PISTA: Solo actúa si realmente saliste del borde de asfalto (edgeDist > 12)
    if currentRoad and edgeDist > 12 then
        local toRoad = Vector3.new(currentRoad.Pos.X - myPos.X, 0, currentRoad.Pos.Z - myPos.Z)
        if toRoad.Magnitude > 1.5 then
            local mDir = toRoad.Unit
            RoadTransit.CurrentDirection = mDir
            root.AssemblyLinearVelocity = Vector3.new(mDir.X * Config.VehicleSpeed, root.AssemblyLinearVelocity.Y, mDir.Z * Config.VehicleSpeed)
        end
        return
    end

    -- 2. MODO IMPACTO DE CHATARRA EN PISTA (CON OVERSHOOT PARA ATRAVESAR SIN FRENAR)
    local activeScrap = nil
    for _, sc in ipairs(RoadScrapList) do
        if sc.Model and sc.Model.Parent and sc.Model:GetAttribute("Dead") ~= true and not (IgnoredScrapUntil[sc.Model] and tick() < IgnoredScrapUntil[sc.Model]) then
            activeScrap = sc
            break
        end
    end

    if activeScrap then
        CurrentScrapTarget = activeScrap.Model
        local scrapPos = activeScrap.Pos
        local rNode = activeScrap.RoadNode

        -- Limitar desplazamiento lateral respecto al eje de la pista para no pisar fuera
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

        -- Si ya estamos encima/atravesándolo (<= 6.5 studs), marcarlo como embestido por 3s y pasar al siguiente sin frenar
        if distToScrap <= 6.5 then
            IgnoredScrapUntil[activeScrap.Model] = tick() + 3.0
        else
            local driveDir = diffToScrap.Unit
            RoadTransit.CurrentDirection = driveDir

            -- Apuntar con Overshoot (18 studs más allá del cúmulo) igual que Depredador en V16.0
            local overshootDest = safeTargetPos + (driveDir * Config.CrushOvershoot)
            local hDir = Vector3.new(overshootDest.X - myPos.X, 0, overshootDest.Z - myPos.Z)

            if hDir.Magnitude > 1.2 then
                local vel = hDir.Unit * Config.VehicleSpeed
                root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)
            end
            return
        end
    else
        CurrentScrapTarget = nil
    end

    -- 3. NAVEGACIÓN CONTINUA POR WAYPOINTS DE PISTA (IDÉNTICO A TRANSITSTATE DE V16.0)
    local wpNode = RoadTransit.Waypoints[RoadTransit.Index]
    if not wpNode then
        RoadTransit.Waypoints = buildForwardRoadChain(myPos, RoadTransit.CurrentDirection)
        RoadTransit.Index = 1
        wpNode = RoadTransit.Waypoints[1]
    end

    if wpNode then
        local diff = wpNode.Pos - myPos
        local horiz = Vector3.new(diff.X, 0, diff.Z)

        -- Igual que en tu V16.0: al estar a <= 22.0 studs salta al siguiente waypoint sin detenerse
        if horiz.Magnitude <= 22.0 then
            wpNode.LastVisited = tick()
            RoadTransit.Index = RoadTransit.Index + 1
            if RoadTransit.Index > #RoadTransit.Waypoints then
                RoadTransit.Waypoints = buildForwardRoadChain(myPos, RoadTransit.CurrentDirection)
                RoadTransit.Index = 1
            end
        else
            local mDir = horiz.Unit
            RoadTransit.CurrentDirection = mDir
            root.AssemblyLinearVelocity = Vector3.new(mDir.X * Config.VehicleSpeed, root.AssemblyLinearVelocity.Y, mDir.Z * Config.VehicleSpeed)
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
-- 7. INTERFAZ FLUENT + WIDGETS FLOTANTES
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP HIGHWAY & WEB RELAY V2.5",
    SubTitle = "Manejo V16.0 Fluido + Telaraña 1x1",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 480),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    RoadFarm = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    Items    = Window:AddTab({ Title = "Red Telaraña", Icon = "share-2" })
}

-- PESTAÑA 1: AUTO-PISTAS
Tabs.RoadFarm:AddSection("Atropello Fluido en Pistas (1200 Studs)")

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
    Default = 135,
    Min = 60,
    Max = 200,
    Rounding = 0,
    Callback = function(v) Config.VehicleSpeed = v end
})

Tabs.RoadFarm:AddSlider("OvershootSlider", {
    Title = "Rebase de Impacto (Overshoot Studs)",
    Description = "Atraviesa el cúmulo de largo sin frenar ni vibrar",
    Default = 18,
    Min = 8,
    Max = 35,
    Rounding = 0,
    Callback = function(v) Config.CrushOvershoot = v end
})

Tabs.RoadFarm:AddSlider("RoadWidthSlider", {
    Title = "Ancho Máximo de Carril (Studs)",
    Description = "Mantiene el auto dentro de la pista sin pisar tierra",
    Default = 14,
    Min = 6,
    Max = 18,
    Rounding = 0,
    Callback = function(v) Config.RoadMaxHalfWidth = v end
})

-- PESTAÑA 2: TELETRANSPORTE EN TELARAÑA
Tabs.Items:AddSection("Red de Puntos de Entrega (Telaraña Automática + Manual)")

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Manual Aquí",
    Callback = function()
        local _, root = getCharacterParts()
        if not root then return end
        createWebMarker(root.Position - Vector3.new(0, 1.5, 0), true)
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
        for _, rNode in ipairs(RoadNodes) do
            tryAddWebNodeAtRoad(rNode.Pos)
        end
        Fluent:Notify({ Title = "Red Reiniciada", Content = "Telaraña reconstruida en pistas: " .. #DeliveryPoints .. " nodos.", Duration = 2 })
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
    Description = "Solo mueve chatarra cerca de ti para que el juego la detecte bien",
    Default = 85,
    Min = 35,
    Max = 160,
    Rounding = 0,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Items:AddSlider("StepDistSlider", {
    Title = "Distancia Corta de Cada Salto (Studs)",
    Default = 65,
    Min = 35,
    Max = 110,
    Rounding = 0,
    Callback = function(v) Config.WebStepDistance = v end
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

-- ==============================================================================
-- 8. WIDGETS FLOTANTES (MENÚ + BOTÓN ON/OFF RÁPIDO)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local FloatGui = Instance.new("ScreenGui")
FloatGui.Name = "ScrapWebMasterFloatGui"
FloatGui.ResetOnSpawn = false
FloatGui.Parent = GuiParent

-- Widget 1: Abrir / Ocultar Menú
local MenuBtn = Instance.new("ImageButton")
MenuBtn.Size = UDim2.new(0, 48, 0, 48)
MenuBtn.Position = UDim2.new(0.04, 0, 0.58, 0)
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

-- Actualización del monitor cada 0.6s
task.spawn(function()
    while true do
        task.wait(0.6)
        local targetText = CurrentScrapTarget and ("Embestida -> " .. CurrentScrapTarget.Name) or "Recorriendo red vial"
        StatusParagraph:SetDesc(string.format(
            "Pistas registradas (hasta 1200m): %d\nNodos de Telaraña activos: %d\nCúmulos en pista detectados: %d\nAcción actual: %s",
            #RoadNodes,
            #DeliveryPoints,
            #RoadScrapList,
            targetText
        ))
    end
end)

Window:SelectTab(1)
