-- ==============================================================================
-- ZOMBIE HUB MASTER V15.2: RADAR HÍBRIDO + SALUD RESTAURADA + RUTEO PERIMETRAL
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local BaseCenter = Vector3.new(0, 0, 0)
local BASE_FORBIDDEN_RADIUS = 105 -- Prohibido cruzar la base central

-- COORDENADAS ORIGINALES (+Z = SUR, -Z = NORTE)
local SECTOR_ROUTES = {
    SUR   = { Gate = Vector3.new(0, -1.9, 120.0),   Combat = Vector3.new(0, 14.5, 180.0) },
    NORTE = { Gate = Vector3.new(0, -1.7, -120.0),  Combat = Vector3.new(0, 14.5, -180.0) },
    ESTE  = { Gate = Vector3.new(120.0, -1.9, 0.0),  Combat = Vector3.new(180.0, 14.5, 0.0) },
    OESTE = { Gate = Vector3.new(-120.0, -1.9, 0.0), Combat = Vector3.new(-180.0, 14.5, 0.0) }
}

-- ANILLO PERIMETRAL DE PISTAS (ENLACE EXTERIOR)
local PERIMETER_NODES = {
    { Name = "T_SUR",   Pos = Vector3.new(0, -1.9, 120.0),    Sector = "SUR" },
    { Name = "C_SE",    Pos = Vector3.new(115.0, -1.9, 115.0), Sector = nil },
    { Name = "T_ESTE",  Pos = Vector3.new(120.0, -1.9, 0.0),   Sector = "ESTE" },
    { Name = "C_NE",    Pos = Vector3.new(115.0, -1.7, -115.0),Sector = nil },
    { Name = "T_NORTE", Pos = Vector3.new(0, -1.7, -120.0),   Sector = "NORTE" },
    { Name = "C_NW",    Pos = Vector3.new(-115.0, -1.7, -115.0),Sector = nil },
    { Name = "T_OESTE", Pos = Vector3.new(-120.0, -1.9, 0.0),  Sector = "OESTE" },
    { Name = "C_SW",    Pos = Vector3.new(-115.0, -1.9, 115.0), Sector = nil }
}

local Config = {
    ZigZagEnabled = false,
    AttackMode = "Depredador",     -- "Depredador", "Torbellino", "Zigzag Clásico", etc.
    SwitchInterval = 0.5,
    LateralDist = 25,
    MoveSpeed = 150,              -- 150 studs/s por defecto
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true,

    -- VALORES DE EMBESTIDA DEPREDADOR
    DepredadorBaseOvershoot = 5.0,    -- 5 studs hacia la base
    DepredadorFarOvershoot = 25.0,    -- 25 studs hacia la horda

    -- RETIRADA TÁCTICA: MÍNIMO 30% Y MÁXIMO 95%
    RetreatEnabled = true,
    LowHealthThreshold = 0.30,     -- 30% activa retirada
    FullHealthThreshold = 0.95,    -- 95% reanuda ataque
    RetreatDistance = 30.0,        -- Retrocede 30 studs hacia base
    RetreatSpeed = 110,

    -- RESCATES PEATONALES
    CombatAutoRescue = true,       -- Rescate en combate automático (ON)
    ManualDriveAutoRescue = false, -- Conducción manual (OFF por defecto, lo activas tú)
    SprintSpeed = 34,
    BunnyHop = true,
    RescueZombieScanDist = 100,    -- Filtro de 100 studs (Cero Lag)
    MaxCarSearchDist = 350
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local CurrentActiveSector = "SUR"

local CachedCombatRoads = {}
local CachedBloaterDangers = {}
local CachedHordeClusterOffset = 0
local LastDrivenVehicle = nil
local IsInContingency = false

local DefenseState = {
    IsRetreating = false,
    CurrentHP = 2500,
    MaxHP = 2500,
    HPRatio = 1.0,
    Source = "Desconocido"
}

local TransitState = {
    Active = false,
    Waypoints = {},
    Index = 1,
    TargetSector = "SUR"
}

-- ==============================================================================
-- CURSOR DEL MOUSE SIEMPRE VISIBLE (NUNCA SE OCULTA AL CONDUCIR)
-- ==============================================================================
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. DETECCIÓN ROBUSTA DE SALUD (ORIGINAL RESTAURADA)
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
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
        if model then LastDrivenVehicle = model end
        return model, seat
    end
    return nil, nil
end

local function getTruckHealth(truck)
    if not truck then return 2500, 2500, 1.0, "Sin auto" end
    local foundHP, foundMax = nil, nil
    local src = "Desconocido"

    local config = truck:FindFirstChild("Configuration", true) or truck:FindFirstChild("Config", true)
    if config then
        local h = config:GetAttribute("Health") or config:GetAttribute("HP")
        local mh = config:GetAttribute("MaxHealth") or config:GetAttribute("MaxHP")
        if h and type(h) == "number" then foundHP = h; src = "Config.Attr" end
        if mh and type(mh) == "number" then foundMax = mh end

        if not foundHP then
            local vH = config:FindFirstChild("Health") or config:FindFirstChild("HP")
            if vH and vH:IsA("ValueBase") then foundHP = vH.Value; src = "Config.Value" end
            local vM = config:FindFirstChild("MaxHealth") or config:FindFirstChild("MaxHP")
            if vM and vM:IsA("ValueBase") then foundMax = vM.Value end
        end
    end

    if not foundHP then
        for _, obj in ipairs({truck, truck.PrimaryPart}) do
            if obj then
                for _, attr in ipairs({"Health", "HP", "Durability", "Vida"}) do
                    local val = obj:GetAttribute(attr)
                    if val and type(val) == "number" then
                        foundHP = val
                        foundMax = obj:GetAttribute("Max" .. attr) or 2500
                        src = "Model.Attr"
                        break
                    end
                end
            end
            if foundHP then break end
        end
    end

    if not foundHP then
        for _, desc in ipairs(truck:GetDescendants()) do
            if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                local n = desc.Name:lower()
                if n == "health" or n == "hp" or n == "durability" then
                    foundHP = desc.Value
                    src = "Descendant.Value"
                    break
                end
            end
        end
    end

    if not foundHP then
        local mock = truck:FindFirstChild("MockHumanoid", true) or truck:FindFirstChildOfClass("Humanoid")
        if mock then
            foundHP = mock:GetAttribute("Health") or (mock:IsA("Humanoid") and mock.Health)
            foundMax = mock:GetAttribute("MaxHealth") or (mock:IsA("Humanoid") and mock.MaxHealth)
            src = "MockHumanoid"
        end
    end

    foundMax = foundMax or 2500
    foundHP = foundHP or foundMax
    local ratio = (foundMax > 0) and (foundHP / foundMax) or 1.0
    return foundHP, foundMax, ratio, src
end

-- ==============================================================================
-- 2. RUTEO PERIMETRAL DINÁMICO (BORDEANDO LA BASE SIN CORTAR EL CENTRO)
-- ==============================================================================

local function clearHighlight()
    if TargetHighlight then TargetHighlight:Destroy(); TargetHighlight = nil end
end

local function applyHighlight(obj)
    clearHighlight()
    if obj then
        TargetHighlight = Instance.new("Highlight")
        TargetHighlight.Name = "CustomTargetHighlight"
        TargetHighlight.FillColor = Color3.fromRGB(255, 30, 60)
        TargetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        TargetHighlight.FillTransparency = 0.4
        TargetHighlight.Adornee = obj
        TargetHighlight.Parent = obj
    end
end

-- Mapeo único de StraightRoads frontales
task.spawn(function()
    task.wait(1.0)
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("Tiles") or workspace
    for secName, routeData in pairs(SECTOR_ROUTES) do
        local cPos = routeData.Combat
        local best, shortest = nil, 90

        for _, obj in ipairs(mapFolder:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local n = obj.Name:lower()
                if (n:find("straight") or n:find("road") or n:find("pista")) and not n:find("corner") and not n:find("tsection") and not n:find("section") then
                    local p = obj:IsA("Model") and select(1, obj:GetBoundingBox()).Position or obj.Position
                    local dist = (p - cPos).Magnitude
                    if dist < shortest and (p - BaseCenter).Magnitude >= 135 then
                        shortest = dist
                        best = obj
                    end
                end
            end
        end
        CachedCombatRoads[secName] = best
    end
end)

local function getCombatStraightRoad(secName)
    if CachedCombatRoads[secName] and CachedCombatRoads[secName].Parent then
        return CachedCombatRoads[secName]
    end
    return nil
end

local function lineCrossesBaseCenter(p1, p2)
    local d = p2 - p1
    local dLen = d.Magnitude
    if dLen == 0 then return false end
    local dUnit = d.Unit

    local toCenter = BaseCenter - p1
    local t = math.clamp(toCenter:Dot(dUnit), 0, dLen)
    local closestPoint = p1 + (dUnit * t)

    return (Vector3.new(closestPoint.X, 0, closestPoint.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude < BASE_FORBIDDEN_RADIUS
end

local function calculateDynamicRoadPath(currentPos, targetSector)
    local targetGateIdx = 1
    for idx, node in ipairs(PERIMETER_NODES) do
        if node.Sector == targetSector then
            targetGateIdx = idx
            break
        end
    end

    local closestIdx = 1
    local minDist = math.huge
    for idx, node in ipairs(PERIMETER_NODES) do
        local d = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(node.Pos.X, 0, node.Pos.Z)).Magnitude
        if lineCrossesBaseCenter(currentPos, node.Pos) then
            d = d + 500
        end
        if d < minDist then
            minDist = d
            closestIdx = idx
        end
    end

    local waypoints = {}
    table.insert(waypoints, PERIMETER_NODES[closestIdx].Pos)

    if closestIdx ~= targetGateIdx then
        local total = #PERIMETER_NODES
        local fSteps = (targetGateIdx - closestIdx) % total
        local bSteps = (closestIdx - targetGateIdx) % total
        local dir = (fSteps <= bSteps) and 1 or -1
        local cur = closestIdx

        while cur ~= targetGateIdx do
            cur = cur + dir
            if cur > total then cur = 1 end
            if cur < 1 then cur = total end
            table.insert(waypoints, PERIMETER_NODES[cur].Pos)
        end
    end

    table.insert(waypoints, SECTOR_ROUTES[targetSector].Combat)
    return waypoints
end

local function startDynamicSectorTransition(newSector)
    local _, root = getCharacterParts()
    local carPos = root and root.Position or BaseCenter

    local wps = calculateDynamicRoadPath(carPos, newSector)
    TransitState.Active = true
    TransitState.Waypoints = wps
    TransitState.Index = 1
    TransitState.TargetSector = newSector
    CurrentTarget = nil
    clearHighlight()

    Fluent:Notify({
        Title = "🚗 RUTA PERIMETRAL: " .. newSector,
        Content = string.format("Bordeando la base hacia la entrada del %s...", newSector),
        Duration = 3
    })
end

-- ==============================================================================
-- 3. RADAR HÍBRIDO DEFINITIVO (INCOMINGPOSITION + RADAR DE ZOMBIES VIVOS)
-- ==============================================================================

local function parseSectorFromAttribute(val)
    local vec = nil
    if typeof(val) == "Vector3" then
        vec = val
    elseif type(val) == "string" then
        local x, y, z = val:match("([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)")
        if x and y and z then
            vec = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
        end
    end

    if not vec then return "DESCONOCIDO" end
    -- UNIFICADO: +Z = SUR (+180), -Z = NORTE (-180)
    if math.abs(vec.Z) > math.abs(vec.X) then
        return (vec.Z > 0) and "SUR" or "NORTE"
    else
        return (vec.X > 0) and "ESTE" or "OESTE"
    end
end

-- 1. Disparo inmediato por evento de servidor (0ms Lag)
workspace:GetAttributeChangedSignal("IncomingPosition"):Connect(function()
    local rawVal = workspace:GetAttribute("IncomingPosition")
    if rawVal then
        local sec = parseSectorFromAttribute(rawVal)
        if sec ~= "DESCONOCIDO" and sec ~= CurrentActiveSector then
            if Config.AutoRouteToWave and Config.ZigZagEnabled then
                startDynamicSectorTransition(sec)
            else
                CurrentActiveSector = sec
            end
        end
    end
end)

-- 2. Respaldo por densidad de zombies vivos (Resuelve cambios mid-wave o hordas dobles)
local function isValidZombie(entity)
    if not entity or not entity:IsA("Model") or entity == lp.Character or Players:GetPlayerFromCharacter(entity) then
        return false
    end
    local name = entity.Name:lower()
    if name:find("dropped") or name:find("bag") or name:find("loot") or name:find("item") 
       or name:find("crate") or name:find("debris") or name:find("corpse") or name:find("ragdoll") 
       or name:find("car") or name:find("fence") or name:find("door") then
        return false
    end
    local hum = entity:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local root = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
    return root ~= nil, root
end

task.spawn(function()
    while true do
        task.wait(2.5)
        local counts = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
        local totalZombies = 0
        local charFolder = workspace:FindFirstChild("Characters") or workspace

        for _, entity in ipairs(charFolder:GetChildren()) do
            local valid, eRoot = isValidZombie(entity)
            if valid then
                local p = eRoot.Position - BaseCenter
                if p.Magnitude <= 900 then
                    totalZombies = totalZombies + 1
                    -- UNIFICADO: +Z = SUR, -Z = NORTE
                    if math.abs(p.Z) > math.abs(p.X) then
                        if p.Z > 0 then counts.SUR = counts.SUR + 1 else counts.NORTE = counts.NORTE + 1 end
                    else
                        if p.X > 0 then counts.ESTE = counts.ESTE + 1 else counts.OESTE = counts.OESTE + 1 end
                    end
                end
            end
        end

        local topSector = CurrentActiveSector
        local maxCount = 0
        for s, c in pairs(counts) do
            if c > maxCount then
                maxCount = c
                topSector = s
            end
        end

        -- Si hay más de 12 zombies concentrados en otra puerta, reorienta el auto automáticamente
        if maxCount >= 12 and topSector ~= CurrentActiveSector then
            if Config.AutoRouteToWave and Config.ZigZagEnabled then
                startDynamicSectorTransition(topSector)
            else
                CurrentActiveSector = topSector
            end
        end
    end
end)

-- ==============================================================================
-- 4. BUCLE ORIGINAL DE DENSIDAD LATERAL DE HORDA (DEPREDADOR CLUSTER)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.ZigZagEnabled and Config.AttackMode == "Depredador" and CurrentTarget and not IsInContingency and not TransitState.Active then
            local tPos = CurrentTarget:IsA("BasePart") and CurrentTarget.Position or select(1, CurrentTarget:GetBoundingBox()).Position
            if tPos then
                local radialVec = Vector3.new(tPos.X - BaseCenter.X, 0, tPos.Z - BaseCenter.Z)
                local roadLengthDir = radialVec.Magnitude > 0 and radialVec.Unit or Vector3.new(0, 0, 1)
                local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

                local charFolder = workspace:FindFirstChild("Characters") or workspace
                local lateralSum, count = 0, 0

                for _, entity in ipairs(charFolder:GetChildren()) do
                    local valid, eRoot = isValidZombie(entity)
                    if valid then
                        local offset = eRoot.Position - tPos
                        local distAlong = math.abs(offset:Dot(roadLengthDir))
                        local distLateral = offset:Dot(roadWidthDir)

                        if distAlong <= 55 and math.abs(distLateral) <= Config.LateralDist + 10 then
                            lateralSum = lateralSum + distLateral
                            count = count + 1
                        end
                    end
                end
                CachedHordeClusterOffset = count > 0 and math.clamp(lateralSum / count, -Config.LateralDist * 0.8, Config.LateralDist * 0.8) or 0
            end
        else
            CachedHordeClusterOffset = 0
        end
    end
end)

-- ==============================================================================
-- 5. RESCATES PEATONALES Y FRENADO
-- ==============================================================================

local function applyBrake(duration)
    duration = duration or 1.0
    task.spawn(function()
        local endTime = tick() + duration
        while tick() < endTime do
            local carModel, seat = getCurrentVehicle()
            local primary = carModel and (carModel.PrimaryPart or seat)
            if primary then
                primary.AssemblyLinearVelocity = Vector3.new(0, primary.AssemblyLinearVelocity.Y, 0)
                primary.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

local function locateTargetCar()
    local _, root = getCharacterParts()
    if not root then return nil, nil end

    if LastDrivenVehicle and LastDrivenVehicle.Parent then
        local seat = LastDrivenVehicle:FindFirstChild("DriveSeat") or LastDrivenVehicle:FindFirstChildWhichIsA("VehicleSeat")
        if seat then return LastDrivenVehicle, seat end
    end

    local myPos = root.Position
    local bestSeat, bestModel = nil, nil
    local shortestDist = Config.MaxCarSearchDist

    local container = workspace:FindFirstChild("Structures") or workspace
    for _, model in ipairs(container:GetChildren()) do
        if model:IsA("Model") then
            local seat = model:FindFirstChild("DriveSeat") or model:FindFirstChildWhichIsA("VehicleSeat")
            if seat then
                local dist = (seat.Position - myPos).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    bestSeat = seat
                    bestModel = model
                end
            end
        end
    end
    return bestModel, bestSeat
end

local function executeGroundRescue(onBoardCallback)
    if IsInContingency then return end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end

    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        if onBoardCallback then onBoardCallback() end
        return
    end

    local carModel, seat = locateTargetCar()
    if not carModel or not seat then return end

    IsInContingency = true
    LastDrivenVehicle = carModel

    local runTimeout = tick() + 8.5
    local lastJumpTime = 0

    while IsInContingency and tick() < runTimeout do
        RunService.Heartbeat:Wait()
        if not hum or hum.Health <= 0 then break end
        if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then break end

        local hoodPos = (seat.CFrame * CFrame.new(0, 0, -6.5)).Position
        local diff = hoodPos - root.Position
        local horiz = Vector3.new(diff.X, 0, diff.Z)
        local dist = horiz.Magnitude

        if dist <= 6.5 then
            if carModel:GetAttribute("Dead") == true then
                local p = carModel:FindFirstChildWhichIsA("ProximityPrompt", true)
                if p and fireproximityprompt then
                    pcall(function() fireproximityprompt(p) end)
                    pcall(function() fireproximityprompt(p, 0) end)
                end
                task.wait(0.2)
            end

            local sitP = seat:FindFirstChild("SitPrompt") or seat:FindFirstChildOfClass("ProximityPrompt")
            if sitP and fireproximityprompt then
                pcall(function() fireproximityprompt(sitP) end)
                pcall(function() fireproximityprompt(sitP, 0) end)
            end
            hum:ChangeState(Enum.HumanoidStateType.Seated)
            pcall(function() seat:Sit(hum) end)
            task.wait(0.2)
            break
        end

        local avoidVector = Vector3.zero
        local charFolder = workspace:FindFirstChild("Characters") or workspace

        for _, ent in ipairs(charFolder:GetChildren()) do
            if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                if eRoot then
                    local offset = root.Position - eRoot.Position
                    local eDist = offset.Magnitude
                    if eDist <= Config.RescueZombieScanDist and eDist <= 14.0 and eDist > 0.5 then
                        avoidVector = avoidVector + (Vector3.new(offset.X, 0, offset.Z).Unit * (15.0 - eDist) * 1.8)
                    end
                end
            end
        end

        local runDir = (horiz.Unit + avoidVector).Unit
        root.AssemblyLinearVelocity = Vector3.new(runDir.X * Config.SprintSpeed, root.AssemblyLinearVelocity.Y, runDir.Z * Config.SprintSpeed)
        hum:MoveTo(root.Position + runDir * 10)

        if Config.BunnyHop and tick() - lastJumpTime >= 0.35 then
            hum.Jump = true
            lastJumpTime = tick()
        end
    end

    IsInContingency = false
    if onBoardCallback then onBoardCallback() end
end

-- ==============================================================================
-- 6. GUARDIÁN DE SALUD (RETIRADA AL 30%, REANUDACIÓN AL 95%)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.25)
        local truck = getCurrentVehicle()

        if truck then
            local hp, maxHp, ratio, src = getTruckHealth(truck)
            DefenseState.CurrentHP = hp
            DefenseState.MaxHP = maxHp
            DefenseState.HPRatio = ratio
            DefenseState.Source = src

            if Config.RetreatEnabled then
                if not DefenseState.IsRetreating and ratio <= Config.LowHealthThreshold then
                    DefenseState.IsRetreating = true
                    Fluent:Notify({
                        Title = "🛡️ RETIRADA TÁCTICA",
                        Content = string.format("Vida al %.0f%%. Retrocediendo 30 studs a esquivar.", ratio * 100),
                        Duration = 2.5
                    })
                elseif DefenseState.IsRetreating and ratio >= Config.FullHealthThreshold then
                    DefenseState.IsRetreating = false
                    Fluent:Notify({
                        Title = "⚔️ SALUD RECUPERADA",
                        Content = "Vida al 95%. Reanudando combate normal.",
                        Duration = 2.5
                    })
                end
            else
                DefenseState.IsRetreating = false
            end
        else
            DefenseState.IsRetreating = false

            local shouldRescue = false
            local _, _, hum = getCharacterParts()

            if hum and hum.Health > 0 and (not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat")) then
                if Config.ZigZagEnabled and Config.CombatAutoRescue then
                    shouldRescue = true
                elseif (not Config.ZigZagEnabled) and Config.ManualDriveAutoRescue then
                    shouldRescue = true
                end
            end

            if shouldRescue and not IsInContingency then
                task.spawn(function()
                    executeGroundRescue(function()
                        if not Config.ZigZagEnabled then
                            Fluent:Notify({
                                Title = "🚗 RESCATE MANUAL LISTO",
                                Content = "A bordo del vehículo. Conducción manual activa.",
                                Duration = 2.5
                            })
                        end
                    end)
                end)
            end
        end
    end
end)

-- BUCLE DE BLOATERS
task.spawn(function()
    while true do
        task.wait(0.4)
        if Config.EvadeBloaters and not IsInContingency then
            local _, root = getCharacterParts()
            local myPos = root and root.Position or BaseCenter
            local list = {}
            local folder = workspace:FindFirstChild("Characters")

            if folder then
                for _, ent in ipairs(folder:GetChildren()) do
                    if ent:IsA("Model") and ent ~= lp.Character then
                        local n = ent.Name:lower()
                        if n:find("bloat") or n:find("boom") then
                            local r = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                            if r and (r.Position - myPos).Magnitude <= 75 then
                                local h = ent:FindFirstChildOfClass("Humanoid")
                                if (h and h.Health <= 50) or ent:GetAttribute("Dead") == true then
                                    table.insert(list, r.Position)
                                end
                            end
                        end
                    end
                end
            end
            CachedBloaterDangers = list
        else
            table.clear(CachedBloaterDangers)
        end
    end
end)

-- ==============================================================================
-- 7. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V15.2",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 520),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate", Icon = "crosshair" }),
    Defense = Window:AddTab({ Title = "Defensa & Esquive", Icon = "shield" }),
    Rescue = Window:AddTab({ Title = "Auto-Rescate", Icon = "user-check" }),
    Horde = Window:AddTab({ Title = "Radar", Icon = "radar" })
}

Tabs.Combat:AddSection("Controles de Embestida")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(v) Config.ZigZagEnabled = v end
})

Tabs.Combat:AddDropdown("ModeDropdown", {
    Title = "Modo de Ataque / Patrón",
    Values = { "Depredador", "Torbellino", "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico" },
    Default = "Depredador",
    Callback = function(v) Config.AttackMode = v end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 150,
    Min = 20,
    Max = 220,
    Rounding = 0,
    Callback = function(v) Config.MoveSpeed = v end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud Lateral (Studs)",
    Default = 25,
    Min = 2,
    Max = 70,
    Rounding = 0,
    Callback = function(v) Config.LateralDist = v end
})

Tabs.Combat:AddSlider("DepredadorFarSlider", {
    Title = "Depredador: Rebase Hacia Horda (Studs)",
    Default = 25,
    Min = 0,
    Max = 60,
    Rounding = 0,
    Callback = function(v) Config.DepredadorFarOvershoot = v end
})

Tabs.Combat:AddSlider("DepredadorBaseSlider", {
    Title = "Depredador: Rebase Hacia Base (Studs)",
    Default = 5,
    Min = 0,
    Max = 40,
    Rounding = 0,
    Callback = function(v) Config.DepredadorBaseOvershoot = v end
})

Tabs.Combat:AddToggle("AutoRouteToggle", {
    Title = "🚗 Auto-Ruta Dinámica por Pistas",
    Default = true,
    Callback = function(v) Config.AutoRouteToWave = v end
})

-- PESTAÑA DEFENSA & RETIRADA
Tabs.Defense:AddSection("Retirada Táctica por Daño (100% Terrestre)")

Tabs.Defense:AddToggle("RetreatToggle", {
    Title = "🛡️ Activar Retirada y Esquive por Baja Vida",
    Default = true,
    Callback = function(v) Config.RetreatEnabled = v end
})

local DefenseStatusParagraph = Tabs.Defense:AddParagraph({
    Title = "Estado del Vehículo",
    Content = "Monitoreando salud..."
})

Tabs.Defense:AddSlider("LowHPSlider", {
    Title = "Umbral de Retirada (% Vida)",
    Default = 30, -- 30% por defecto
    Min = 10,
    Max = 50,
    Rounding = 0,
    Callback = function(v) Config.LowHealthThreshold = v / 100 end
})

Tabs.Defense:AddSlider("FullHPSlider", {
    Title = "Umbral de Reanudación (% Vida)",
    Default = 95, -- 95% por defecto
    Min = 50,
    Max = 100,
    Rounding = 0,
    Callback = function(v) Config.FullHealthThreshold = v / 100 end
})

Tabs.Defense:AddSlider("RetreatDistSlider", {
    Title = "Distancia de Retroceso hacia Base (Studs)",
    Default = 30,
    Min = 15,
    Max = 65,
    Rounding = 0,
    Callback = function(v) Config.RetreatDistance = v end
})

-- PESTAÑA RESCATES
Tabs.Rescue:AddSection("Sistemas de Auto-Rescate Terrestre")

Tabs.Rescue:AddToggle("ManualRescueToggle", {
    Title = "🚗 Auto-Rescate en Conducción MANUAL",
    Description = "Te rescata si manejas tú mismo y te expulsan",
    Default = false, -- Desactivado por defecto hasta que lo enciendas
    Callback = function(v) Config.ManualDriveAutoRescue = v end
})

Tabs.Rescue:AddToggle("CombatRescueToggle", {
    Title = "🤖 Auto-Rescate en Modo Combate",
    Default = true,
    Callback = function(v) Config.CombatAutoRescue = v end
})

Tabs.Rescue:AddSlider("SprintSpeedSlider", {
    Title = "Velocidad de Carrera al Auto",
    Default = 34,
    Min = 20,
    Max = 55,
    Rounding = 0,
    Callback = function(v) Config.SprintSpeed = v end
})

Tabs.Rescue:AddButton({
    Title = "🏃 Forzar Rescate Inmediato (Tecla 'V')",
    Callback = function() executeGroundRescue() end
})

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente Dominante",
    Content = "Escaneando..."
})

-- ==============================================================================
-- 8. WIDGETS FLOTANTES: MENU HUB + AUTO-PILOTO (ON / OFF SIN BOTAR DEL AUTO)
-- ==============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZombieHubMasterFloat"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

-- BOTÓN MENÚ
local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.72, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- WIDGET AUTO-PILOTO
local AutoPilotBtn = Instance.new("TextButton")
AutoPilotBtn.Size = UDim2.new(0, 48, 0, 48)
AutoPilotBtn.Position = UDim2.new(0.04, 0, 0.64, 0)
AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
AutoPilotBtn.Text = "⚡\nOFF"
AutoPilotBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoPilotBtn.TextSize = 11
AutoPilotBtn.Font = Enum.Font.GothamBold
AutoPilotBtn.Active = true
AutoPilotBtn.Draggable = true
AutoPilotBtn.Parent = ScreenGui

local AutoPilotCorner = Instance.new("UICorner")
AutoPilotCorner.CornerRadius = UDim.new(1, 0)
AutoPilotCorner.Parent = AutoPilotBtn

local function toggleAutoPilot()
    if Config.ZigZagEnabled then
        -- AL APAGAR: FRENA PERO NO EXPULSA AL PERSONAJE (TE QUEDAS SENTADO)
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        TransitState.Active = false
        applyBrake(1.0)

        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
        AutoPilotBtn.Text = "⚡\nOFF"

        Fluent:Notify({
            Title = "⏹ AUTO-PILOTO OFF",
            Content = "Auto-movimiento apagado y frenado. Sigues sentado.",
            Duration = 2
        })
    else
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 70)
        AutoPilotBtn.Text = "⚡\nON"

        executeGroundRescue(function()
            Config.ZigZagEnabled = true
            pcall(function() ZigZagToggleInstance:SetValue(true) end)
            startDynamicSectorTransition(CurrentActiveSector)
        end)
    end
end

AutoPilotBtn.MouseButton1Click:Connect(toggleAutoPilot)
Tabs.Combat:AddButton({ Title = "⚡ TOGGLE AUTO-PILOTO (ON / OFF)", Callback = toggleAutoPilot })

-- CONTROLES DE TECLADO ('T', '9', '0', 'V')
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end

    if input.KeyCode == Enum.KeyCode.T then
        local raw = mouse.Target
        if raw then
            local chosen = getCompleteObject(raw)
            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)
                Config.ZigZagEnabled = true
                pcall(function() ZigZagToggleInstance:SetValue(true) end)
                AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 70)
                AutoPilotBtn.Text = "⚡\nON"
            end
        end
    end

    if input.KeyCode == Enum.KeyCode.Nine or input.KeyCode == Enum.KeyCode.KeypadNine then
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
        AutoPilotBtn.Text = "⚡\nOFF"
        applyBrake(1.0)
    end

    if input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.KeypadZero then
        CurrentTarget = nil
        clearHighlight()
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
        AutoPilotBtn.Text = "⚡\nOFF"
        applyBrake(1.0)
    end

    if input.KeyCode == Enum.KeyCode.V then
        executeGroundRescue()
    end
end)

-- ACTUALIZACIÓN DE TEXTOS EN INTERFAZ
task.spawn(function()
    while true do
        task.wait(0.5)
        DefenseStatusParagraph:SetDesc(string.format(
            "Vida Vehículo: %.0f / %.0f (%.0f%%) [%s]\nRetirada Automática: %s\nModo Actual: %s",
            DefenseState.CurrentHP, DefenseState.MaxHP, DefenseState.HPRatio * 100, DefenseState.Source,
            Config.RetreatEnabled and "🟢 ACTIVA" or "🔴 OFF",
            DefenseState.IsRetreating and "🛡️ Retirada (-30 studs)" or (TransitState.Active and "🚗 Enrutando Pistas" or "⚔️ " .. Config.AttackMode)
        ))

        HordeStatusParagraph:SetDesc(string.format(
            "Frente Dominante: %s\nIncomingPosition: %s\nZombies Restantes: %d",
            CurrentActiveSector,
            tostring(workspace:GetAttribute("IncomingPosition") or "N/A"),
            workspace:GetAttribute("RemainingMobs") or 0
        ))
    end
end)

-- ==============================================================================
-- 9. MOTOR CINÉTICO ZERO-LAG
-- ==============================================================================

local side = 1
local lastSwitch = tick()
local depredadorDir = 1
local lastDepredadorSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or IsInContingency then return end

    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then return end

    -- FASE A: TRANSICIÓN DINÁMICA POR PISTAS
    if TransitState.Active then
        local wp = TransitState.Waypoints[TransitState.Index]
        if wp then
            local diff = wp - root.Position
            local horiz = Vector3.new(diff.X, 0, diff.Z)

            if horiz.Magnitude <= 22.0 then
                TransitState.Index = TransitState.Index + 1
                if TransitState.Index > #TransitState.Waypoints then
                    TransitState.Active = false
                    CurrentActiveSector = TransitState.TargetSector

                    local road = getCombatStraightRoad(CurrentActiveSector)
                    if road then
                        CurrentTarget = road
                        applyHighlight(road)
                    end
                end
            else
                local mDir = horiz.Unit
                root.AssemblyLinearVelocity = Vector3.new(mDir.X * Config.MoveSpeed, root.AssemblyLinearVelocity.Y, mDir.Z * Config.MoveSpeed)
            end
        else
            TransitState.Active = false
        end
        return
    end

    -- FASE B: COMBATE / DEPREDADOR / TORBELLINO / RETIRADA
    local targetPos = nil
    local targetSize = Vector3.new(60, 10, 60)

    if CurrentTarget then
        targetPos = CurrentTarget:IsA("BasePart") and CurrentTarget.Position or select(1, CurrentTarget:GetBoundingBox()).Position
        targetSize = CurrentTarget:IsA("BasePart") and CurrentTarget.Size or select(2, CurrentTarget:GetBoundingBox())
    elseif SECTOR_ROUTES[CurrentActiveSector] then
        targetPos = SECTOR_ROUTES[CurrentActiveSector].Combat
    end

    if targetPos then
        local destination = targetPos
        local d = Config.LateralDist
        local speed = Config.MoveSpeed

        local toRoad = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
        local roadLen = toRoad.Magnitude > 0 and toRoad.Unit or Vector3.new(0, 0, 1)
        local roadWid = Vector3.new(-roadLen.Z, 0, roadLen.X)

        -- 1. RETIRADA TÁCTICA ACTIVA (VIDA <= 30%, HASTA 95%)
        if DefenseState.IsRetreating then
            speed = Config.RetreatSpeed
            local hLen = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local anchor = targetPos - (roadLen * (hLen + Config.RetreatDistance))
            destination = anchor + (roadWid * (math.sin(tick() * 4.0) * d))

        -- 2. MODO DEPREDADOR (CON CLUSTER DE HORDAS RESTABLECIDO)
        elseif Config.AttackMode == "Depredador" then
            local hLen = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local reachAway = hLen + Config.DepredadorFarOvershoot
            local reachBase = hLen + Config.DepredadorBaseOvershoot

            local carAlong = (root.Position - targetPos):Dot(roadLen)

            if depredadorDir == 1 and carAlong >= (reachAway - 3.5) then
                depredadorDir = -1
                lastDepredadorSwitch = tick()
            elseif depredadorDir == -1 and carAlong <= -(reachBase - 3.5) then
                depredadorDir = 1
                lastDepredadorSwitch = tick()
            end

            if tick() - lastDepredadorSwitch >= 3.2 then
                depredadorDir = -depredadorDir
                lastDepredadorSwitch = tick()
            end

            local tDist = (depredadorDir == 1) and reachAway or -reachBase
            local weaveWave = math.sin(tick() * 5.5) * d
            local totalLateral = math.clamp(weaveWave + CachedHordeClusterOffset, -d, d)

            destination = targetPos + (roadLen * tDist) + (roadWid * totalLateral)

        -- 3. MODO TORBELLINO (SINUSOIDAL PURA)
        elseif Config.AttackMode == "Torbellino" then
            local hLen = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local reachAway = hLen + Config.DepredadorFarOvershoot
            local reachBase = hLen + Config.DepredadorBaseOvershoot

            local carAlong = (root.Position - targetPos):Dot(roadLen)
            if depredadorDir == 1 and carAlong >= (reachAway - 3.5) then
                depredadorDir = -1
            elseif depredadorDir == -1 and carAlong <= -(reachBase - 3.5) then
                depredadorDir = 1
            end

            local tDist = (depredadorDir == 1) and reachAway or -reachBase
            destination = targetPos + (roadLen * tDist) + (roadWid * (math.sin(tick() * 7.5) * d))
        end

        -- EVASIÓN DE BLOATERS
        if Config.EvadeBloaters and #CachedBloaterDangers > 0 then
            for _, bPos in ipairs(CachedBloaterDangers) do
                if (root.Position - bPos).Magnitude <= Config.BloaterDangerDist then
                    local aDir = (root.Position - bPos).Unit
                    destination = destination + Vector3.new(aDir.X, 0, aDir.Z) * 26
                end
            end
        end

        local dir = (destination - root.Position)
        local hDir = Vector3.new(dir.X, 0, dir.Z)

        if hDir.Magnitude > 1.2 then
            local vel = hDir.Unit * speed
            root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB MASTER V15.2 LISTO",
    Content = "Modo Depredador configurado. Cursor siempre visible y sin expulsión en OFF.",
    Duration = 4
})

Window:SelectTab(1)
