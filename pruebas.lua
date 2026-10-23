-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER & SPIDERWEB RELAY V2.6 (100% ASFALTO + ANTI-FANTASMA)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local Config = {
    -- Rango total reducido al 60% de 1200 (720 studs) y configurable
    MaxMapRadius = 720,

    -- Auto-Conducción por Pistas (Velocidad reducida en 20: de 135 a 115)
    AutoFarmRoads = false,
    VehicleSpeed = 115,
    RoadMaxHalfWidth = 12,      -- Límite lateral estricto dentro del asfalto
    ScrapSearchRadius = 400,    -- Radio de detección de cúmulos
    CrushOvershoot = 16,        -- Rebasa el cúmulo sobre el mismo carril sin vibrar

    -- Red Telaraña Anti-Fantasma (1 por 1, pasos cortos y presencia cercana)
    AutoSendItems = true,
    OnlyScrap = true,
    ChainTeleport = true,
    BasePrevent = true,
    GeneratorSafeRadius = 145,  -- Radio donde ya deja los materiales en la base
    CollectRadius = 42,         -- Presencia cercana (42 studs) para garantizar Network Ownership y evitar fantasmas
    WebStepDistance = 32,       -- Saltos cortos (32 studs) entre bolitas para no perder sincronización con el servidor
    SpreadRadius = 2.0,         -- Pequeña dispersión para que no colisionen entre sí
    TeleportInterval = 0.25,    -- Pausa entre cada ítem (procesa 1 por 1, 0% lag)
    ShowWebVisuals = false      -- Mostrar/ocultar las bolitas de la red
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

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
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
-- 2. POSICIÓN DEL GENERADOR Y RED DE BOLITAS (TELARAÑA CORTA ANTI-BUG)
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
    marker.Size = Vector3.new(2.0, 2.0, 2.0)
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

-- Crea varios puntos cortos a lo largo de cada tramo de pista para que la distancia nunca sea larga
local function populateWebNodesForRoad(node)
    local genPos = getGeneratorPosition()
    local isX = node.Size.X >= node.Size.Z
    local length = math.max(node.Size.X, node.Size.Z)
    local axisDir = isX and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)

    local halfLen = length * 0.45
    local step = math.max(18, Config.WebStepDistance)

    for offset = -halfLen, halfLen, step do
        local candidatePos = node.Pos + (axisDir * offset)
        local distFromCenter = (Vector3.new(candidatePos.X, 0, candidatePos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

        if distFromCenter <= Config.MaxMapRadius and (candidatePos - genPos).Magnitude > (Config.GeneratorSafeRadius - 12) then
            local tooClose = false
            for _, pt in ipairs(DeliveryPoints) do
                if pt and pt.Parent then
                    if (pt.Position - candidatePos).Magnitude < (step * 0.75) then
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
    -- Conservar solo bolitas manuales si existen, o limpiar las automáticas para reajustarlas al nuevo radio/distancia
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
-- 3. MAPEO DE PISTAS Y VERIFICACIÓN ESTRICTA DE ASFALTO
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

    local newNode = {
        Pos = Vector3.new(pos.X, pos.Y + 1.5, pos.Z),
        Size = size,
        Instance = obj,
        LastVisited = 0
    }
    table.insert(RoadNodes, newNode)

    if distFromCenter <= Config.MaxMapRadius then
        populateWebNodesForRoad(newNode)
    end
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

-- Devuelve el nodo de pista más cercano y a cuántos studs está fuera del borde real del pavimento (edgeDist == 0 significa SOBRE la pista)
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

            -- Mitad real de la calzada (sin inflar para no pisar tierra)
            local halfX = math.max((node.Size.X * 0.48), 13)
            local halfZ = math.max((node.Size.Z * 0.48), 13)

            local overX = math.max(0, dx - halfX)
            local overZ = math.max(0, dz - halfZ)
            local edgeDist = math.sqrt(overX * overX + overZ * overZ)

            if edgeDist < minEdgeDist or (math.abs(edgeDist - minEdgeDist) < 0.5 and centerDist < minCenterDist) then
                minEdgeDist = edgeDist
                minCenterDist = centerDist
                bestNode = node

                -- Punto exacto dentro del carril de esa pista para subir al auto sin cortar esquina
                local clampedX = math.clamp(pos.X - node.Pos.X, -halfX + 4, halfX - 4)
                local clampedZ = math.clamp(pos.Z - node.Pos.Z, -halfZ + 4, halfZ - 4)
                closestSurfacePoint = Vector3.new(node.Pos.X + clampedX, node.Pos.Y, node.Pos.Z + clampedZ)
            end
        end
    end

    return bestNode, minEdgeDist, closestSurfacePoint
end

-- Comprueba matemáticamente que una línea recta entre A y B nunca salga del asfalto (impide cruzar pasto/tierra en diagonal)
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
-- 4. ESCÁNER DE SCRAP PILE Y CRASHED CAR (SOLO EN PISTA Y ACCESIBLE POR ASFALTO)
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
                        -- Verificar que el cúmulo esté estrictamente dentro del asfalto (edgeDist <= 3.0)
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
-- 5. BUCLE DE TELETRANSPORTE EN TELARAÑA (SALTOS CORTOS + PRESENCIA CERCANA)
-- ==============================================================================

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getNextSpiderwebPoint(itemPos, myPos)
    local genPos = getGeneratorPosition()
    local currentDistToGen = (itemPos - genPos).Magnitude
    local bestPoint = nil
    local shortestStep = math.huge

    -- Límite máximo del salto para que no salga de tu Network Ownership y no se vuelva fantasma
    local maxAllowedHop = Config.WebStepDistance + 18

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local ptPos = pt.Position
            local stepDist = (itemPos - ptPos).Magnitude
            local pointDistToGen = (ptPos - genPos).Magnitude
            local distToPlayer = (ptPos - myPos).Magnitude

            if Config.ChainTeleport then
                -- El punto debe acercar el ítem a la base en un salto corto y mantenerse cerca de tu radio de simulación
                if pointDistToGen < (currentDistToGen - 4) and stepDist > 4 and stepDist <= maxAllowedHop and distToPlayer <= (Config.CollectRadius + 35) then
                    if stepDist < shortestStep then
                        shortestStep = stepDist
                        bestPoint = pt
                    end
                end
            else
                if stepDist < shortestStep and stepDist > 4 and stepDist <= maxAllowedHop then
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

                            -- Confirmar distancia real al centro del ítem
                            if (rootPos - myPos).Magnitude <= Config.CollectRadius then
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
                                        local nextPoint = getNextSpiderwebPoint(rootPos, myPos)
                                        if nextPoint then
                                            processedOne = true

                                            local angle = math.random() * math.pi * 2
                                            local rDist = math.random() * Config.SpreadRadius
                                            local destPos = nextPoint.Position + Vector3.new(math.cos(angle) * rDist, 1.0, math.sin(angle) * rDist)

                                            -- Micro-velocidad física hacia abajo para forzar actualización de red en el servidor
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
-- 6. MOTOR DE CONDUCCIÓN 100% EN PISTA (PROHIBIDO CRUZAR TERRENO)
-- ==============================================================================

-- Construye una ruta de nodos que estén conectados exclusivamente por asfalto
local function buildForwardRoadChain(startPos, currentDir)
    local chain = {}
    local curPos = startPos
    local curDir = currentDir
    local used = {}

    for step = 1, 5 do
        local bestNode = nil
        local bestScore = math.huge
        local now = tick()

        for _, node in ipairs(RoadNodes) do
            local distBase = (Vector3.new(node.Pos.X, 0, node.Pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
            if not used[node] and distBase <= Config.MaxMapRadius then
                local diff = Vector3.new(node.Pos.X - curPos.X, 0, node.Pos.Z - curPos.Z)
                local dist = diff.Magnitude

                -- Solo enlaza tramos de pista contiguos Y verifica que el trayecto entre ambos sea 100% pista
                if dist >= 20 and dist <= 135 and isStraightLineOnRoad(curPos, node.Pos) then
                    local dirToNode = diff.Unit
                    local dot = dirToNode:Dot(curDir)
                    local unvisitedBonus = math.min((now - node.LastVisited) * 1.5, 95)

                    local backwardPenalty = (dot < -0.25) and 350 or ((dot < 0.15) and 90 or 0)
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

    -- Si llegó al final de una calle (60% del mapa) y debe dar la vuelta sobre la misma pista
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
    local currentRoad, edgeDist, closestRoadSurfacePos = getRoadInfoAtPosition(myPos, true)

    -- ==========================================================================
    -- REGLA #1: SI NO ESTÁ EN LA PISTA, VA PRIMERO A LA PISTA MÁS CERCANA
    -- ==========================================================================
    if not currentRoad or edgeDist > 2.2 then
        IsRecoveringToRoad = true
        CurrentScrapTarget = nil
        RoadTransit.Waypoints = {}

        if currentRoad then
            -- Se dirige directamente al punto de asfalto más cercano antes de iniciar su rutina
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
    -- REGLA #2: EMBESTIR CHATARRA SOLO SI EL CAMINO HACIA ELLA ES 100% PISTA
    -- ==========================================================================
    local activeScrap = nil
    for _, sc in ipairs(RoadScrapList) do
        if sc.Model and sc.Model.Parent and sc.Model:GetAttribute("Dead") ~= true and not (IgnoredScrapUntil[sc.Model] and tick() < IgnoredScrapUntil[sc.Model]) then
            -- Solo la ataca directamente si está cerca (<= 95 studs) y la línea recta hacia ella NUNCA pisa fuera de la pista
            if sc.Dist <= 95 and isStraightLineOnRoad(myPos, sc.Pos) then
                activeScrap = sc
                break
            end
        end
    end

    if activeScrap then
        CurrentScrapTarget = activeScrap.Model
        local scrapPos = activeScrap.Pos
        local rNode = activeScrap.RoadNode

        -- Clamping lateral dentro de los bordes de esa pista
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

            -- Verificar que el punto de Overshoot también siga dentro de la pista
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
        RoadTransit.Waypoints = buildForwardRoadChain(myPos, RoadTransit.CurrentDirection)
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
                RoadTransit.Waypoints = buildForwardRoadChain(myPos, RoadTransit.CurrentDirection)
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
-- 7. INTERFAZ FLUENT + WIDGETS FLOTANTES
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP HIGHWAY & WEB RELAY V2.6",
    SubTitle = "100% Pistas + Telaraña Corta Anti-Bug",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 500),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    RoadFarm = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    Items    = Window:AddTab({ Title = "Red Telaraña", Icon = "share-2" })
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
    Default = 115, -- Disminuida en 20 (antes 135)
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

-- PESTAÑA 2: TELETRANSPORTE EN TELARAÑA
Tabs.Items:AddSection("Red de Puntos de Entrega (Anti-Fantasma)")

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
        rebuildSpiderwebNetwork()
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
    Description = "Más cerca (42m) garantiza Network Ownership sin fantasmas",
    Default = 42,
    Min = 20,
    Max = 120,
    Rounding = 0,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Items:AddSlider("StepDistSlider", {
    Title = "Distancia Corta Entre Bolitas (Studs)",
    Description = "Saltos cortos (32m) evitan que la chatarra se buguee",
    Default = 32,
    Min = 18,
    Max = 90,
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
        local targetText = "Recorriendo red vial (100% Pista)"
        if IsRecoveringToRoad then
            targetText = "⚠️ Volviendo primero a la pista más cercana..."
        elseif CurrentScrapTarget then
            targetText = "Embestida en pista -> " .. CurrentScrapTarget.Name
        end

        StatusParagraph:SetDesc(string.format(
            "Rango activo configurado: %d studs (60%%)\nPistas registradas: %d | Bolitas Telaraña: %d\nCúmulos en pista detectados: %d\nAcción actual: %s",
            Config.MaxMapRadius,
            #RoadNodes,
            #DeliveryPoints,
            #RoadScrapList,
            targetText
        ))
    end
end)

Window:SelectTab(1)
