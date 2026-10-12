-- ==============================================================================
-- ZOMBIE HUB MASTER V11: RADAR INSTANTÁNEO + RUTA PERIMETRAL + AUTO-STRAIGHTROAD
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local BaseCenter = Vector3.new(0, 0, 0)

-- COORDENADAS CALIBRADAS (+Z = NORTE, -Z = SUR)
local SECTOR_ROUTES = {
    NORTE = { Gate = Vector3.new(0, -1.9, 120.0), Combat = Vector3.new(0, 14.5, 180.0) },
    SUR   = { Gate = Vector3.new(0, -1.7, -120.0), Combat = Vector3.new(0, 14.5, -180.0) },
    ESTE  = { Gate = Vector3.new(120.0, -1.9, 0.0), Combat = Vector3.new(180.0, 14.5, 0.0) },
    OESTE = { Gate = Vector3.new(-120.0, -1.9, 0.0), Combat = Vector3.new(-180.0, 14.5, 0.0) }
}

-- PUNTOS DE TRÁNSITO PARA BORDEAR LA BASE (TSECTION & CORNERROADS)
local P_GATES = {
    NORTE = Vector3.new(0, -1.9, 120.0),
    SUR   = Vector3.new(0, -1.7, -120.0),
    ESTE  = Vector3.new(120.0, -1.9, 0.0),
    OESTE = Vector3.new(-120.0, -1.9, 0.0)
}

local P_CORNERS = {
    N_E = Vector3.new(115.0, -1.9, 115.0),
    N_W = Vector3.new(-115.0, -1.9, 115.0),
    S_E = Vector3.new(115.0, -1.7, -115.0),
    S_W = Vector3.new(-115.0, -1.7, -115.0)
}

local Config = {
    ZigZagEnabled = false,
    AttackMode = "Stalker",
    SwitchInterval = 0.5,
    LateralDist = 25,
    MoveSpeed = 150,              -- Velocidad por defecto en 150
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true,       -- Auto-ruta activa con radar instantáneo

    -- VALORES DE EMBESTIDA STALKER
    StalkerBaseOvershoot = 5.0,    -- 5 studs hacia la base
    StalkerFarOvershoot = 25.0,    -- 25 studs hacia la horda

    -- RETIRADA TÁCTICA POR DAÑO (100% TERRESTRE)
    RetreatEnabled = true,
    LowHealthThreshold = 0.20,     -- 20% activa retirada
    FullHealthThreshold = 0.70,    -- 70% reanuda combate
    RetreatDistance = 30.0,        -- Distancia de retroceso hacia base
    RetreatSpeed = 110,

    -- RESCATE TERRESTRE DE CONTINGENCIA
    AutoRemountEnabled = true,
    SprintSpeed = 34,
    BunnyHop = true,
    MaxCarSearchDist = 300
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local CurrentActiveSector = "NORTE"

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

-- ESTADO DE TRÁNSITO PERIMETRAL ENTRE ENTRADAS
local TransitState = {
    Active = false,
    Waypoints = {},
    Index = 1,
    TargetSector = "NORTE"
}

-- ==============================================================================
-- 1. DETECCIÓN ROBUSTA DE SALUD Y PARTES
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

    foundMax = foundMax or 2500
    foundHP = foundHP or foundMax
    local ratio = (foundMax > 0) and (foundHP / foundMax) or 1.0
    return foundHP, foundMax, ratio, src
end

-- ==============================================================================
-- 2. RUTAS PERIMETRALES Y SELECCIÓN DEL STRAIGHTROAD FRONTAL
-- ==============================================================================

-- Genera la lista de waypoints para bordear la base sin atravesarla
local function getPerimeterRoute(fromSec, toSec)
    if fromSec == toSec then
        return { SECTOR_ROUTES[toSec].Combat }
    end

    local waypoints = {}
    table.insert(waypoints, P_GATES[fromSec])

    if fromSec == "NORTE" then
        if toSec == "ESTE" then
            table.insert(waypoints, P_CORNERS.N_E)
            table.insert(waypoints, P_GATES.ESTE)
        elseif toSec == "OESTE" then
            table.insert(waypoints, P_CORNERS.N_W)
            table.insert(waypoints, P_GATES.OESTE)
        elseif toSec == "SUR" then
            table.insert(waypoints, P_CORNERS.N_E)
            table.insert(waypoints, P_GATES.ESTE)
            table.insert(waypoints, P_CORNERS.S_E)
            table.insert(waypoints, P_GATES.SUR)
        end
    elseif fromSec == "SUR" then
        if toSec == "ESTE" then
            table.insert(waypoints, P_CORNERS.S_E)
            table.insert(waypoints, P_GATES.ESTE)
        elseif toSec == "OESTE" then
            table.insert(waypoints, P_CORNERS.S_W)
            table.insert(waypoints, P_GATES.OESTE)
        elseif toSec == "NORTE" then
            table.insert(waypoints, P_CORNERS.S_E)
            table.insert(waypoints, P_GATES.ESTE)
            table.insert(waypoints, P_CORNERS.N_E)
            table.insert(waypoints, P_GATES.NORTE)
        end
    elseif fromSec == "ESTE" then
        if toSec == "NORTE" then
            table.insert(waypoints, P_CORNERS.N_E)
            table.insert(waypoints, P_GATES.NORTE)
        elseif toSec == "SUR" then
            table.insert(waypoints, P_CORNERS.S_E)
            table.insert(waypoints, P_GATES.SUR)
        elseif toSec == "OESTE" then
            table.insert(waypoints, P_CORNERS.N_E)
            table.insert(waypoints, P_GATES.NORTE)
            table.insert(waypoints, P_CORNERS.N_W)
            table.insert(waypoints, P_GATES.OESTE)
        end
    elseif fromSec == "OESTE" then
        if toSec == "NORTE" then
            table.insert(waypoints, P_CORNERS.N_W)
            table.insert(waypoints, P_GATES.NORTE)
        elseif toSec == "SUR" then
            table.insert(waypoints, P_CORNERS.S_W)
            table.insert(waypoints, P_GATES.SUR)
        elseif toSec == "ESTE" then
            table.insert(waypoints, P_CORNERS.N_W)
            table.insert(waypoints, P_GATES.NORTE)
            table.insert(waypoints, P_CORNERS.N_E)
            table.insert(waypoints, P_GATES.ESTE)
        end
    end

    table.insert(waypoints, SECTOR_ROUTES[toSec].Combat)
    return waypoints
end

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

-- Encuentra exclusivamente el StraightRoad frontal de la entrada activa
local function findCombatStraightRoad(sectorName)
    local route = SECTOR_ROUTES[sectorName]
    if not route then return nil end
    local combatPos = route.Combat
    local bestObj = nil
    local shortestDist = 80

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if (n:find("straight") or n:find("road") or n:find("pista")) then
                -- Descarta esquinas y uniones T
                if not n:find("corner") and not n:find("tsection") and not n:find("section") then
                    local pos = obj:IsA("Model") and select(1, obj:GetBoundingBox()).Position or obj.Position
                    local dist = (pos - combatPos).Magnitude
                    -- Solo selecciona el que esté en el eje frontal (>140 studs del centro)
                    if dist < shortestDist and (pos - BaseCenter).Magnitude >= 140 then
                        shortestDist = dist
                        bestObj = obj
                    end
                end
            end
        end
    end
    return bestObj
end

-- Inicia la transición por el perímetro
local function startSectorTransition(newSector)
    if TransitState.Active and TransitState.TargetSector == newSector then return end
    if CurrentActiveSector == newSector and not TransitState.Active then return end

    local wps = getPerimeterRoute(CurrentActiveSector, newSector)
    TransitState.Active = true
    TransitState.Waypoints = wps
    TransitState.Index = 1
    TransitState.TargetSector = newSector
    CurrentTarget = nil
    clearHighlight()

    Fluent:Notify({
        Title = "🚨 CAMBIO DE FRENTE: " .. newSector,
        Content = string.format("Bordeando la base hacia la entrada del %s...", newSector),
        Duration = 3.5
    })
end

-- ==============================================================================
-- 3. PARSER DEL ATRIBUTO INCOMINGPOSITION (0ms LAG)
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

    if not vec then return "DESCONOCIDO", Vector3.zero end

    local sector = "DESCONOCIDO"
    -- POLOS CALIBRADOS (+Z = NORTE, -Z = SUR)
    if math.abs(vec.Z) > math.abs(vec.X) then
        sector = (vec.Z > 0) and "NORTE" or "SUR"
    else
        sector = (vec.X > 0) and "ESTE" or "OESTE"
    end

    return sector, vec
end

local function onIncomingPositionChanged()
    local rawVal = workspace:GetAttribute("IncomingPosition")
    if rawVal then
        local sec, _ = parseSectorFromAttribute(rawVal)
        if sec ~= "DESCONOCIDO" and sec ~= CurrentActiveSector then
            if Config.AutoRouteToWave and Config.ZigZagEnabled then
                startSectorTransition(sec)
            else
                CurrentActiveSector = sec
            end
        end
    end
end

workspace:GetAttributeChangedSignal("IncomingPosition"):Connect(onIncomingPositionChanged)

-- ==============================================================================
-- 4. RESCATE TERRESTRE DE CONTINGENCIA (CORRER/SALTAR AL CAPÓ)
-- ==============================================================================

local function getActiveRepairPrompt(carModel)
    for _, prompt in ipairs(carModel:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local n = prompt.Name:lower()
            local a = prompt.ActionText:lower()
            local o = prompt.ObjectText:lower()
            if n:find("repair") or a:find("repair") or a:find("repar") or o:find("repar") then
                return prompt
            end
        end
    end
    return nil
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

local function executeGroundRescue()
    if IsInContingency then return end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return end

    local carModel, seat = locateTargetCar()
    if not carModel or not seat then return end

    IsInContingency = true
    LastDrivenVehicle = carModel

    local runTimeout = tick() + 9.0
    local lastJumpTime = 0

    while IsInContingency and tick() < runTimeout do
        RunService.Heartbeat:Wait()

        if not hum or hum.Health <= 0 then break end
        if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then break end

        local hoodPos = (seat.CFrame * CFrame.new(0, 0, -6.5)).Position
        local diff = hoodPos - root.Position
        local horizontalDiff = Vector3.new(diff.X, 0, diff.Z)
        local distToHood = horizontalDiff.Magnitude

        if distToHood <= 6.5 then
            local isDead = carModel:GetAttribute("Dead") == true
            local repairPrompt = getActiveRepairPrompt(carModel)

            if isDead or repairPrompt then
                local repStart = tick()
                while (carModel:GetAttribute("Dead") == true or repairPrompt) and tick() - repStart < 2.5 do
                    repairPrompt = getActiveRepairPrompt(carModel)
                    if repairPrompt and fireproximityprompt then
                        pcall(function() fireproximityprompt(repairPrompt) end)
                        pcall(function() fireproximityprompt(repairPrompt, 0) end)
                    end
                    task.wait(0.2)
                end
            end

            local sitPrompt = seat:FindFirstChild("SitPrompt") or seat:FindFirstChildOfClass("ProximityPrompt")
            if sitPrompt and fireproximityprompt then
                pcall(function() fireproximityprompt(sitPrompt) end)
                pcall(function() fireproximityprompt(sitPrompt, 0) end)
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
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
                if eRoot then
                    local eOffset = root.Position - eRoot.Position
                    local eDist = eOffset.Magnitude
                    if eDist <= 14.0 and eDist > 0.5 then
                        avoidVector = avoidVector + (Vector3.new(eOffset.X, 0, eOffset.Z).Unit * (15.0 - eDist) * 1.8)
                    end
                end
            end
        end

        local runDir = horizontalDiff.Unit
        local totalMoveDir = (runDir + avoidVector).Unit
        local sprintSpeed = Config.SprintSpeed

        root.AssemblyLinearVelocity = Vector3.new(totalMoveDir.X * sprintSpeed, root.AssemblyLinearVelocity.Y, totalMoveDir.Z * sprintSpeed)
        hum:MoveTo(root.Position + totalMoveDir * 10)

        if Config.BunnyHop and tick() - lastJumpTime >= 0.35 then
            hum.Jump = true
            lastJumpTime = tick()
        end
    end

    IsInContingency = false
end

-- ==============================================================================
-- 5. MONITOR DE SALUD DEL VEHÍCULO
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
                        Duration = 3
                    })
                elseif DefenseState.IsRetreating and ratio >= Config.FullHealthThreshold then
                    DefenseState.IsRetreating = false
                    Fluent:Notify({
                        Title = "⚔️ SALUD RECUPERADA",
                        Content = string.format("Vida al %.0f%%. Reanudando embestida Stalker.", ratio * 100),
                        Duration = 3
                    })
                end
            else
                DefenseState.IsRetreating = false
            end
        else
            DefenseState.IsRetreating = false
            if Config.AutoRemountEnabled and Config.ZigZagEnabled and not IsInContingency then
                local _, _, hum = getCharacterParts()
                if hum and hum.Health > 0 and (not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat")) then
                    task.spawn(executeGroundRescue)
                end
            end
        end
    end
end)

-- ==============================================================================
-- 6. UTILIDADES DE COMBATE (FRENO, HIGHLIGHT, FILTROS)
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

local function getCompleteObject(target)
    if not target or target == lp.Character or target:IsDescendantOf(lp.Character) then return nil end
    local humModel = target:FindFirstAncestorOfClass("Model")
    while humModel and not humModel:FindFirstChildOfClass("Humanoid") and humModel.Parent ~= workspace do
        local higherModel = humModel.Parent:FindFirstAncestorOfClass("Model")
        if higherModel then humModel = higherModel else break end
    end
    if humModel and humModel:FindFirstChildOfClass("Humanoid") then return humModel end

    local current = target
    local topModel = nil
    while current and current ~= workspace do
        if current:IsA("Model") then
            topModel = current
            local pName = current.Parent and current.Parent.Name:lower() or ""
            if current.Parent == workspace or pName == "characters" or pName == "structures" or pName == "tiles" or pName == "map" or pName == "roads" then
                return current
            end
        end
        current = current.Parent
    end
    return topModel or target
end

-- EVASIÓN DE BLOATERS
task.spawn(function()
    while true do
        task.wait(0.3)
        if Config.EvadeBloaters and not IsInContingency then
            local _, root = getCharacterParts()
            local myPos = root and root.Position or BaseCenter
            local newDangers = {}
            local charFolder = workspace:FindFirstChild("Characters") or workspace

            for _, entity in ipairs(charFolder:GetChildren()) do
                if entity:IsA("Model") and entity ~= lp.Character then
                    local name = entity.Name:lower()
                    local variant = tostring(entity:GetAttribute("Variant") or ""):lower()
                    local isBloater = name:find("bloat") or name:find("boom") or name:find("explod") or variant:find("bloat") or variant:find("boom")

                    if isBloater then
                        local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
                        if eRoot and (eRoot.Position - myPos).Magnitude <= 80 then
                            local hum = entity:FindFirstChildOfClass("Humanoid")
                            local isDowned = (hum and hum.Health <= 0) or entity:GetAttribute("Exploding") == true or entity:GetAttribute("Dead") == true
                            if isDowned or (hum and hum.Health <= 50) then
                                table.insert(newDangers, eRoot.Position)
                            end
                        end
                    end
                end
            end
            CachedBloaterDangers = newDangers
        else
            table.clear(CachedBloaterDangers)
        end
    end
end)

-- RASTREO LATERAL DE HORDAS
task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.ZigZagEnabled and Config.AttackMode == "Stalker" and CurrentTarget and not IsInContingency and not TransitState.Active then
            local tPos = CurrentTarget:IsA("BasePart") and CurrentTarget.Position or (CurrentTarget:IsA("Model") and select(1, CurrentTarget:GetBoundingBox()).Position)
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
        end
    end
end)

-- ==============================================================================
-- 7. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V11",
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

-- PESTAÑA COMBATE
Tabs.Combat:AddSection("Controles de Embestida (Stalker)")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(v) Config.ZigZagEnabled = v end
})

Tabs.Combat:AddDropdown("ModeDropdown", {
    Title = "Modo de Ataque",
    Values = { "Stalker", "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico" },
    Default = "Stalker",
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
    Title = "Amplitud Lateral Zigzag (Studs)",
    Description = "Ancho del barrido sobre la calzada",
    Default = 25,
    Min = 2,
    Max = 70,
    Rounding = 0,
    Callback = function(v) Config.LateralDist = v end
})

Tabs.Combat:AddSlider("StalkerFarSlider", {
    Title = "Rebase Hacia Afuera / Horda (Studs)",
    Description = "Distancia extra hacia el frente de ataque",
    Default = 25,
    Min = 0,
    Max = 60,
    Rounding = 0,
    Callback = function(v) Config.StalkerFarOvershoot = v end
})

Tabs.Combat:AddSlider("StalkerBaseSlider", {
    Title = "Rebase Hacia la Base (Studs)",
    Description = "Distancia extra que retrocede hacia la puerta",
    Default = 5,
    Min = 0,
    Max = 40,
    Rounding = 0,
    Callback = function(v) Config.StalkerBaseOvershoot = v end
})

Tabs.Combat:AddToggle("AutoRouteToggle", {
    Title = "🚗 Auto-Ruta con Radar Instantáneo",
    Description = "Bordea la base y cambia de pista al instante",
    Default = true,
    Callback = function(v) Config.AutoRouteToWave = v end
})

Tabs.Combat:AddToggle("BloaterEvadeToggle", {
    Title = "🛡️ Evasión de Bloaters",
    Default = true,
    Callback = function(v) Config.EvadeBloaters = v end
})

-- PESTAÑA DEFENSA & RETIRADA
Tabs.Defense:AddSection("Retirada Táctica por Daño (100% Terrestre)")

Tabs.Defense:AddToggle("RetreatToggle", {
    Title = "🛡️ Activar Retirada y Esquive por Baja Vida",
    Description = "Retrocede hacia la base y esquiva zombies mientras se cura",
    Default = true,
    Callback = function(v) Config.RetreatEnabled = v end
})

local DefenseStatusParagraph = Tabs.Defense:AddParagraph({
    Title = "Estado del Vehículo",
    Content = "Leyendo datos de salud..."
})

Tabs.Defense:AddSlider("LowHPSlider", {
    Title = "Umbral de Retirada (% Vida)",
    Default = 20,
    Min = 10,
    Max = 40,
    Rounding = 0,
    Callback = function(v) Config.LowHealthThreshold = v / 100 end
})

Tabs.Defense:AddSlider("FullHPSlider", {
    Title = "Umbral de Reanudación de Ataque (% Vida)",
    Default = 70,
    Min = 50,
    Max = 95,
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

-- PESTAÑA RESCATE
Tabs.Rescue:AddSection("Rescate Terrestre de Personaje")

Tabs.Rescue:AddToggle("AutoRemountToggle", {
    Title = "🛡️ Auto-Rescate en Eyección",
    Description = "Corre y salta hacia el auto esquivando zombies",
    Default = true,
    Callback = function(v) Config.AutoRemountEnabled = v end
})

Tabs.Rescue:AddToggle("BunnyHopToggle", {
    Title = "🐇 Saltar Continuamente al Correr (Bunny Hop)",
    Default = true,
    Callback = function(v) Config.BunnyHop = v end
})

Tabs.Rescue:AddSlider("SprintSpeedSlider", {
    Title = "Velocidad de Carrera hacia el Auto",
    Default = 34,
    Min = 20,
    Max = 55,
    Rounding = 0,
    Callback = function(v) Config.SprintSpeed = v end
})

Tabs.Rescue:AddButton({
    Title = "🏃 Forzar Carrera y Montaje (Tecla 'V')",
    Callback = function() executeGroundRescue() end
})

-- PESTAÑA RADAR
Tabs.Horde:AddSection("Radar de Oleadas de Noche")

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente Dominante",
    Content = "Esperando que inicie la noche..."
})

-- ACTUALIZACIÓN EN VIVO DEL MONITOR
task.spawn(function()
    while true do
        task.wait(0.3)
        local statusText = "⚔️ En Combate Normal"
        if TransitState.Active then
            statusText = string.format("🚗 TRANSICIÓN: Bordeando base hacia %s (Paso %d/%d)...", TransitState.TargetSector, TransitState.Index, #TransitState.Waypoints)
        elseif DefenseState.IsRetreating then
            statusText = "🛡️ RETIRADA: Esquivando a 30 studs de base (Cura al 70%)..."
        elseif IsInContingency then
            statusText = "🏃 RESCATE: Corriendo y saltando hacia el auto con esquive..."
        end

        DefenseStatusParagraph:SetDesc(string.format(
            "Vida Vehículo: %.0f / %.0f (%.0f%%) [%s]\nRetirada Automática: %s\nModo Actual: %s",
            DefenseState.CurrentHP, DefenseState.MaxHP, DefenseState.HPRatio * 100, DefenseState.Source,
            Config.RetreatEnabled and "🟢 ACTIVA" or "🔴 OFF",
            statusText
        ))

        local incoming = tostring(workspace:GetAttribute("IncomingPosition") or "Sin alerta")
        local mobs = workspace:GetAttribute("RemainingMobs") or 0
        local wave = workspace:GetAttribute("WaveActive") == true

        HordeStatusParagraph:SetDesc(string.format(
            "Frente Activo: %s\nIncomingPosition: %s\nZombies restantes: %d | Oleada Activa: %s",
            CurrentActiveSector, incoming, mobs, wave and "SÍ" or "NO"
        ))
    end
end)

-- BOTÓN FLOTANTE COMBINADO
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZombieHubMasterFloat"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

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

RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- CONTROLES DE TECLADO ('T', '9', '0', 'V')
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.T then
        local rawTarget = mouse.Target
        if rawTarget then
            local chosen = getCompleteObject(rawTarget)
            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)
                Config.ZigZagEnabled = true
                pcall(function() ZigZagToggleInstance:SetValue(true) end)
                Fluent:Notify({
                    Title = "Objetivo Fijado [T]",
                    Content = string.format("Fijado: %s | Modo: %s", chosen.Name, Config.AttackMode),
                    Duration = 2.5
                })
            end
        end
    end

    if input.KeyCode == Enum.KeyCode.Nine or input.KeyCode == Enum.KeyCode.KeypadNine then
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        applyBrake(1.0)
        Fluent:Notify({ Title = "Pausado [9]", Content = "Frenando 1s. Objetivo guardado.", Duration = 2 })
    end

    if input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.KeypadZero then
        CurrentTarget = nil
        clearHighlight()
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        applyBrake(1.0)
        Fluent:Notify({ Title = "Limpiado [0]", Content = "Movimiento apagado.", Duration = 2 })
    end

    if input.KeyCode == Enum.KeyCode.V then
        executeGroundRescue()
    end
end)

-- INICIALIZACIÓN DEL RADAR EN SEGUNDO PLANO
task.spawn(function()
    task.wait(0.5)
    local raw = workspace:GetAttribute("IncomingPosition")
    if raw then
        local sec, _ = parseSectorFromAttribute(raw)
        if sec ~= "DESCONOCIDO" then
            CurrentActiveSector = sec
            local road = findCombatStraightRoad(sec)
            if road then
                CurrentTarget = road
                applyHighlight(road)
            end
        end
    end
end)

-- ==============================================================================
-- 8. MOTOR CINÉTICO: TRANSICIÓN PERIMETRAL + STALKER
-- ==============================================================================

local side = 1
local lastSwitch = tick()
local stalkerDir = 1
local lastStalkerSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or IsInContingency then return end

    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then return end

    -- =========================================================================
    -- FASE A: TRÁNSITO PERIMETRAL (BORDEANDO LA BASE SIN TOCAR EL CENTRO)
    -- =========================================================================
    if TransitState.Active then
        local currentWP = TransitState.Waypoints[TransitState.Index]
        if currentWP then
            local diff = currentWP - root.Position
            local horizDiff = Vector3.new(diff.X, 0, diff.Z)

            if horizDiff.Magnitude <= 18.0 then
                TransitState.Index = TransitState.Index + 1
                if TransitState.Index > #TransitState.Waypoints then
                    -- Llegó a la entrada activa
                    TransitState.Active = false
                    CurrentActiveSector = TransitState.TargetSector

                    -- Auto-selecciona el StraightRoad frontal
                    local road = findCombatStraightRoad(CurrentActiveSector)
                    if road then
                        CurrentTarget = road
                        applyHighlight(road)
                    end

                    Fluent:Notify({
                        Title = "⚔️ EN POSICIÓN: " .. CurrentActiveSector,
                        Content = "StraightRoad frontal fijado. Iniciando embestida.",
                        Duration = 3
                    })
                end
            else
                local moveDir = horizDiff.Unit
                root.AssemblyLinearVelocity = Vector3.new(moveDir.X * Config.MoveSpeed, root.AssemblyLinearVelocity.Y, moveDir.Z * Config.MoveSpeed)
            end
        else
            TransitState.Active = false
        end
        return
    end

    -- =========================================================================
    -- FASE B: COMBATE NORMAL / STALKER / RETIRADA
    -- =========================================================================
    local targetPos = nil
    local targetCF = nil
    local targetSize = Vector3.new(60, 10, 60)

    if CurrentTarget then
        if CurrentTarget:IsA("BasePart") then
            targetPos = CurrentTarget.Position
            targetCF = CurrentTarget.CFrame
            targetSize = CurrentTarget.Size
        elseif CurrentTarget:IsA("Model") then
            local bbCF, bbSize = CurrentTarget:GetBoundingBox()
            targetPos = bbCF.Position
            targetCF = bbCF
            targetSize = bbSize
        end
    elseif SECTOR_ROUTES[CurrentActiveSector] then
        local routeData = SECTOR_ROUTES[CurrentActiveSector]
        targetPos = routeData.Combat
        targetCF = CFrame.new(routeData.Combat)
    end

    if targetPos and targetCF then
        local destination = targetPos
        local d = Config.LateralDist
        local speed = Config.MoveSpeed

        -- CASO 1: RETIRADA TÁCTICA ACTIVA (VIDA <= 20%)
        if DefenseState.IsRetreating then
            speed = Config.RetreatSpeed
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1)
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local retreatAnchor = targetPos - (roadLengthDir * (halfLength + Config.RetreatDistance))

            local evadeOscillation = math.sin(tick() * 4.0) * d
            destination = retreatAnchor + (roadWidthDir * evadeOscillation)

        -- CASO 2: ATAQUE STALKER NORMAL (VIDA >= 70%)
        elseif Config.AttackMode == "Stalker" then
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1)
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)

            local reachAway = halfLength + Config.StalkerFarOvershoot
            local reachBase = halfLength + Config.StalkerBaseOvershoot

            local carOffset = root.Position - targetPos
            local carAlongRoad = carOffset:Dot(roadLengthDir)

            if stalkerDir == 1 and carAlongRoad >= (reachAway - 3.5) then
                stalkerDir = -1
                lastStalkerSwitch = tick()
            elseif stalkerDir == -1 and carAlongRoad <= -(reachBase - 3.5) then
                stalkerDir = 1
                lastStalkerSwitch = tick()
            end

            if tick() - lastStalkerSwitch >= 3.2 then
                stalkerDir = -stalkerDir
                lastStalkerSwitch = tick()
            end

            local targetDistance = (stalkerDir == 1) and reachAway or -reachBase
            local longitudinalTarget = targetPos + (roadLengthDir * targetDistance)

            local weaveWave = math.sin(tick() * 5.5) * d
            local totalLateral = math.clamp(weaveWave + CachedHordeClusterOffset, -d, d)

            destination = longitudinalTarget + (roadWidthDir * totalLateral)
        end

        -- EVASIÓN DE BLOATERS
        if Config.EvadeBloaters and #CachedBloaterDangers > 0 then
            for _, bombPos in ipairs(CachedBloaterDangers) do
                local distToBomb = (root.Position - bombPos).Magnitude
                if distToBomb <= Config.BloaterDangerDist then
                    local avoidDir = (root.Position - bombPos).Unit
                    if avoidDir.Magnitude == 0 or avoidDir ~= avoidDir then
                        avoidDir = targetCF.RightVector * side
                    end
                    destination = destination + Vector3.new(avoidDir.X, 0, avoidDir.Z) * 26
                end
            end
        end

        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.2 then
            local targetVelocity = horizontalDir.Unit * speed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB MASTER V11",
    Content = "Radar instantáneo, ruta perimetral y auto-StraightRoad listos.",
    Duration = 4
})

Window:SelectTab(1)
