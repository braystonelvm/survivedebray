-- ==============================================================================
-- ZOMBIE HUB MASTER V8.7: VUELO CINÉTICO SUAVE (ANTI-BUG LLANTAS) + STALKER (+5/-25)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local BaseCenter = Vector3.new(0, 0, 0)
local BASE_HEAL_AIR_POS = Vector3.new(0, 32.0, 0) -- Centro exacto en altura Y=32

local SECTOR_ROUTES = {
    SUR = { Gate = Vector3.new(0, -1.9, 120.0), Combat = Vector3.new(0, 14.5, 180.0) },
    NORTE = { Gate = Vector3.new(0, -1.7, -120.0), Combat = Vector3.new(0, 14.5, -180.0) },
    ESTE = { Gate = Vector3.new(120.0, -1.9, 0.0), Combat = Vector3.new(180.0, 14.5, 0.0) },
    OESTE = { Gate = Vector3.new(-120.0, -1.9, 0.0), Combat = Vector3.new(-180.0, 14.5, 0.0) }
}

local Config = {
    ZigZagEnabled = false,
    AttackMode = "Stalker",
    SwitchInterval = 0.5,
    LateralDist = 25,
    MoveSpeed = 95,
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true,

    -- VALORES DE EMBESTIDA STALKER PEDIDOS
    StalkerBaseOvershoot = 5.0,    -- 5 studs hacia la base
    StalkerFarOvershoot = 25.0,    -- 25 studs hacia el lado contrario

    -- PROTOCOLO DE EVACUACIÓN Y CURA EN BASE (Y=32)
    EmergencyHealEnabled = true,
    LowHealthThreshold = 0.20,     -- 20% activa huida a base
    FullHealthThreshold = 0.70,    -- 70% regresa al combate
    FlightAltitude = 32.0,         -- Altura Y para sobrevolar estructuras
    TruckFlySpeed = 85,            -- Velocidad crucero aérea estable

    -- PROTOCOLO DE RESCATE DEL PERSONAJE (CONTINGENCIA EN CAPÓ)
    AutoRemountEnabled = true,     -- Siempre activo ante eyección
    RescueFlyAltitude = 8.0,       -- Altura aérea de traslado seguro
    RescueFlySpeed = 80,           -- Velocidad moderada anti-rollback
    MaxCarSearchDist = 300
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local CurrentActiveSector = "SUR"

local CachedBloaterDangers = {}
local CachedHordeClusterOffset = 0
local LastDrivenVehicle = nil
local IsInContingency = false

local EvacState = {
    IsActive = false,
    Stage = "IDLE",
    SavedCombatTarget = nil,
    SavedCombatPos = nil,
    CurrentHP = 2500,
    MaxHP = 2500,
    HPRatio = 1.0,
    Source = "Desconocido"
}

-- ==============================================================================
-- 1. DETECCIÓN ROBUSTA DE SALUD DEL VEHÍCULO
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

    -- 1. Configuration (carpeta u objeto de valores)
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

    -- 2. Atributos en modelo raíz
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

    -- 3. NumberValues descendientes
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

    -- 4. MockHumanoid
    if not foundHP then
        local mock = truck:FindFirstChild("MockHumanoid", true) or truck:FindFirstChildOfClass("Humanoid")
        if mock then
            foundHP = mock:GetAttribute("Health") or (mock:IsA("Humanoid") and mock.Health)
            foundMax = mock:GetAttribute("MaxHealth") or (mock:IsA("Humanoid") and mock.MaxHealth)
            src = "MockHumanoid"
        end
    end

    -- 5. PlayerGui
    if not foundHP then
        local pGui = lp:FindFirstChild("PlayerGui")
        if pGui then
            for _, desc in ipairs(pGui:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible and desc.Text:find("%d") then
                    local pName = desc.Parent and desc.Parent.Name:lower() or ""
                    local lName = desc.Name:lower()
                    if (pName:find("car") or pName:find("veh") or lName:find("hp") or lName:find("health")) then
                        local n = tonumber(desc.Text:match("%d+"))
                        if n and n > 0 and n <= 5000 then
                            foundHP = n
                            src = "GUI"
                            break
                        end
                    end
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
-- 2. SISTEMA CINÉTICO SUAVE PARA EL AUTO (BODYVELOCITY + BODYGYRO)
-- ==============================================================================

local function getOrCreateVehicleFlight(primary)
    local bv = primary:FindFirstChild("TruckAirBV")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "TruckAirBV"
        bv.MaxForce = Vector3.new(2e6, 2e6, 2e6)
        bv.Velocity = Vector3.zero
        bv.Parent = primary
    end

    local bg = primary:FindFirstChild("TruckAirBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "TruckAirBG"
        bg.MaxTorque = Vector3.new(2e6, 2e6, 2e6)
        bg.P = 15000
        bg.D = 1200
        -- Mantiene el auto horizontal sin inclinarlo
        bg.CFrame = CFrame.new(primary.Position) * CFrame.Angles(0, math.rad(primary.Orientation.Y), 0)
        bg.Parent = primary
    end

    return bv, bg
end

local function removeVehicleFlight(primary)
    if primary then
        local bv = primary:FindFirstChild("TruckAirBV")
        if bv then bv:Destroy() end
        local bg = primary:FindFirstChild("TruckAirBG")
        if bg then bg:Destroy() end
        primary.AssemblyLinearVelocity = Vector3.zero
        primary.AssemblyAngularVelocity = Vector3.zero
    end
end

local function getOrCreatePlayerFlight(root)
    local bp = root:FindFirstChild("RescueFlyBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "RescueFlyBP"
        bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bp.P = 25000
        bp.D = 800
        bp.Position = root.Position
        bp.Parent = root
    end
    local bg = root:FindFirstChild("RescueFlyBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "RescueFlyBG"
        bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bg.CFrame = root.CFrame
        bg.Parent = root
    end
    return bp, bg
end

local function removePlayerFlight(root)
    if root then
        local bp = root:FindFirstChild("RescueFlyBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("RescueFlyBG")
        if bg then bg:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

-- ==============================================================================
-- 3. PROTOCOLO DE AUTO-EVACUACIÓN AÉREA AL 20% (Y = 32 SIN COLAPSO DE RESORTES)
-- ==============================================================================

local function executeAirEvacuation()
    local truck, seat = getCurrentVehicle()
    if not truck then return end
    local primary = truck.PrimaryPart or seat

    EvacState.IsActive = true
    EvacState.SavedCombatTarget = CurrentTarget
    EvacState.SavedCombatPos = primary.Position

    local bv, bg = getOrCreateVehicleFlight(primary)
    local targetAirY = Config.FlightAltitude

    -- 1. ASCENSO VERTICAL CINÉTICO (Sin forzar BodyPosition rígido)
    EvacState.Stage = "ASCENDING"
    local ascendLimit = tick() + 4.0
    while EvacState.IsActive and primary.Position.Y < (targetAirY - 1.5) and tick() < ascendLimit do
        bv.Velocity = Vector3.new(0, 24, 0)
        bg.CFrame = CFrame.new(primary.Position) * CFrame.Angles(0, math.rad(primary.Orientation.Y), 0)
        task.wait(0.04)
    end
    bv.Velocity = Vector3.zero

    -- 2. TRASLADO CINÉTICO AL CENTRO (Y=32)
    EvacState.Stage = "FLYING_TO_BASE"
    local flyTarget = Vector3.new(BASE_HEAL_AIR_POS.X, targetAirY, BASE_HEAL_AIR_POS.Z)

    local travelLimit = tick() + 20.0
    while EvacState.IsActive and tick() < travelLimit do
        local curPos = primary.Position
        local diff = flyTarget - curPos
        local horizontalDiff = Vector3.new(diff.X, 0, diff.Z)

        if horizontalDiff.Magnitude <= 6.0 then
            bv.Velocity = Vector3.zero
            break
        end

        local stepDir = horizontalDiff.Unit
        local yCorrection = math.clamp((targetAirY - curPos.Y) * 3, -10, 10)
        bv.Velocity = (stepDir * Config.TruckFlySpeed) + Vector3.new(0, yCorrection, 0)
        bg.CFrame = CFrame.lookAt(curPos, curPos + Vector3.new(stepDir.X, 0, stepDir.Z))
        task.wait(0.04)
    end
    bv.Velocity = Vector3.zero

    -- 3. ESPERA EN SUSPENSIÓN HASTA ALCANZAR EL 70% DE VIDA
    EvacState.Stage = "HEALING"
    local healTimeout = tick() + 55.0
    while EvacState.IsActive and tick() < healTimeout do
        local curPos = primary.Position
        local yCorrection = math.clamp((targetAirY - curPos.Y) * 2, -6, 6)
        bv.Velocity = Vector3.new(0, yCorrection, 0)

        local hp, maxHp, ratio, src = getTruckHealth(truck)
        EvacState.CurrentHP = hp
        EvacState.MaxHP = maxHp
        EvacState.HPRatio = ratio
        EvacState.Source = src

        if ratio >= Config.FullHealthThreshold then
            break
        end
        task.wait(0.3)
    end
    bv.Velocity = Vector3.zero

    -- 4. RETORNO AÉREO A LA POSICIÓN DE COMBATE (Y=32)
    EvacState.Stage = "RETURNING"
    local returnGroundPos = EvacState.SavedCombatPos or primary.Position
    local returnAirTarget = Vector3.new(returnGroundPos.X, targetAirY, returnGroundPos.Z)

    local returnLimit = tick() + 20.0
    while EvacState.IsActive and tick() < returnLimit do
        local curPos = primary.Position
        local diff = returnAirTarget - curPos
        local horizontalDiff = Vector3.new(diff.X, 0, diff.Z)

        if horizontalDiff.Magnitude <= 6.0 then
            bv.Velocity = Vector3.zero
            break
        end

        local stepDir = horizontalDiff.Unit
        local yCorrection = math.clamp((targetAirY - curPos.Y) * 3, -10, 10)
        bv.Velocity = (stepDir * Config.TruckFlySpeed) + Vector3.new(0, yCorrection, 0)
        bg.CFrame = CFrame.lookAt(curPos, curPos + Vector3.new(stepDir.X, 0, stepDir.Z))
        task.wait(0.04)
    end
    bv.Velocity = Vector3.zero

    -- 5. ATERRIZAJE INTELIGENTE CON RAYCAST (CERO HUNDIMIENTO BAJO TIERRA)
    EvacState.Stage = "DESCENDING"
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {truck, lp.Character}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local descentLimit = tick() + 6.0
    while EvacState.IsActive and tick() < descentLimit do
        local curPos = primary.Position
        local hit = workspace:Raycast(curPos, Vector3.new(0, -50, 0), rayParams)
        local groundY = hit and hit.Position.Y or (returnGroundPos.Y)
        local safeChassisHoverY = groundY + 3.2 -- Altura natural del chasis sobre las ruedas

        if curPos.Y <= (safeChassisHoverY + 0.8) then
            -- Amortiguación final suave: deja que las ruedas toquen el suelo por gravedad
            bv.Velocity = Vector3.new(0, -2, 0)
            task.wait(0.35)
            break
        else
            -- Descenso suave y constante
            bv.Velocity = Vector3.new(0, -12, 0)
        end
        bg.CFrame = CFrame.new(curPos) * CFrame.Angles(0, math.rad(primary.Orientation.Y), 0)
        task.wait(0.04)
    end

    removeVehicleFlight(primary)
    EvacState.IsActive = false
    EvacState.Stage = "IDLE"

    if EvacState.SavedCombatTarget then
        CurrentTarget = EvacState.SavedCombatTarget
    end
end

-- ==============================================================================
-- 4. PROTOCOLO DE RESCATE: VUELO CONTROLADO Y REPARACIÓN EN CAPÓ
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

local function executeContingencyRescue()
    if IsInContingency then return end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return end

    local carModel, seat = locateTargetCar()
    if not carModel or not seat then return end

    IsInContingency = true
    LastDrivenVehicle = carModel

    -- 1. ELEVACIÓN DE SEGURIDAD (8 STUDS)
    hum:ChangeState(Enum.HumanoidStateType.Running)
    local bp, bg = getOrCreatePlayerFlight(root)
    local safeAirY = root.Position.Y + Config.RescueFlyAltitude
    bp.Position = Vector3.new(root.Position.X, safeAirY, root.Position.Z)
    task.wait(0.08)

    -- 2. TRASLADO POR EL AIRE AL AUTO A VELOCIDAD ESTABLE (ANTI-ROLLBACK)
    local seatPos = seat.Position
    local cruiseAirTarget = Vector3.new(seatPos.X, seatPos.Y + Config.RescueFlyAltitude, seatPos.Z)

    local flyTimeout = tick() + 6.0
    while IsInContingency and tick() < flyTimeout do
        local diff = cruiseAirTarget - root.Position
        if diff.Magnitude <= 4.0 then break end

        local stepDir = diff.Unit
        local nextPos = root.Position + (stepDir * (Config.RescueFlySpeed * 0.05))
        bp.Position = nextPos
        bg.CFrame = CFrame.lookAt(root.Position, cruiseAirTarget)
        task.wait(0.03)
    end

    -- 3. DESCENSO DIRECTO AL CAPÓ (PEGADO AL MOTOR PARA QUE EL SERVER ACEPTE)
    local isDead = carModel:GetAttribute("Dead") == true
    local repairPrompt = getActiveRepairPrompt(carModel)

    if isDead or repairPrompt then
        local hoodPos = seat.CFrame * CFrame.new(0, 0.5, -6.5)
        bp.Position = hoodPos.Position
        bg.CFrame = hoodPos
        task.wait(0.1)

        local repairLimit = tick() + 3.0
        while (carModel:GetAttribute("Dead") == true or repairPrompt) and tick() < repairLimit do
            repairPrompt = getActiveRepairPrompt(carModel)
            if repairPrompt then
                repairPrompt.HoldDuration = 0
                repairPrompt.RequiresLineOfSight = false
                if fireproximityprompt then
                    pcall(function() fireproximityprompt(repairPrompt) end)
                    pcall(function() fireproximityprompt(repairPrompt, 0) end)
                    pcall(function() fireproximityprompt(repairPrompt, 5) end)
                end
            end
            task.wait(0.18)
        end
        task.wait(0.1)
    end

    -- 4. ENTRADA Y MONTAJE EN EL ASIENTO
    local seatEntryCF = seat.CFrame * CFrame.new(0, 1.2, 0)
    bp.Position = seatEntryCF.Position
    bg.CFrame = seat.CFrame
    task.wait(0.05)

    local sitPrompt = seat:FindFirstChild("SitPrompt") or seat:FindFirstChildOfClass("ProximityPrompt")
    if sitPrompt then
        sitPrompt.HoldDuration = 0
        sitPrompt.RequiresLineOfSight = false
        if fireproximityprompt then
            pcall(function() fireproximityprompt(sitPrompt) end)
            pcall(function() fireproximityprompt(sitPrompt, 0) end)
        end
    end

    task.wait(0.05)
    hum:ChangeState(Enum.HumanoidStateType.Seated)
    pcall(function() seat:Sit(hum) end)

    task.wait(0.15)
    removePlayerFlight(root)
    IsInContingency = false
end

-- ==============================================================================
-- 5. GUARDIANES EN SEGUNDO PLANO (SALUD & RESCATE)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.25)
        local truck = getCurrentVehicle()
        if truck then
            local hp, maxHp, ratio, src = getTruckHealth(truck)
            EvacState.CurrentHP = hp
            EvacState.MaxHP = maxHp
            EvacState.HPRatio = ratio
            EvacState.Source = src

            -- Disparador automático de huida al 20%
            if Config.EmergencyHealEnabled and not EvacState.IsActive and not IsInContingency and ratio <= Config.LowHealthThreshold then
                task.spawn(executeAirEvacuation)
            end
        else
            -- Si el jugador sale del auto con el ataque encendido -> Rescate inmediato
            if Config.AutoRemountEnabled and Config.ZigZagEnabled and not IsInContingency and not EvacState.IsActive then
                local _, _, hum = getCharacterParts()
                if hum and hum.Health > 0 and (not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat")) then
                    task.spawn(executeContingencyRescue)
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

-- EVASIÓN DE BLOATERS (0.3s)
task.spawn(function()
    while true do
        task.wait(0.3)
        if Config.EvadeBloaters and not EvacState.IsActive and not IsInContingency then
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

-- RASTREO LATERAL DE HORDAS (0.15s)
task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.ZigZagEnabled and Config.AttackMode == "Stalker" and CurrentTarget and not EvacState.IsActive and not IsInContingency then
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
-- 7. INTERFAZ FLUENT (CONFIGURACIONES COMPLETAS CONSERVADAS)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V8.7",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 500),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate", Icon = "crosshair" }),
    Evac = Window:AddTab({ Title = "Evacuación Y=32", Icon = "shield" }),
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
    Title = "Modo de Ataque",
    Values = { "Stalker", "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico" },
    Default = "Stalker",
    Callback = function(v) Config.AttackMode = v end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 95,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(v) Config.MoveSpeed = v end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud Lateral (Studs)",
    Default = 25,
    Min = 4,
    Max = 60,
    Rounding = 0,
    Callback = function(v) Config.LateralDist = v end
})

Tabs.Combat:AddToggle("BloaterEvadeToggle", {
    Title = "🛡️ Evasión de Bloaters",
    Default = true,
    Callback = function(v) Config.EvadeBloaters = v end
})

Tabs.Combat:AddToggle("AutoRouteToggle", {
    Title = "🚗 Auto-Ruta a Entrada Activa",
    Default = true,
    Callback = function(v) Config.AutoRouteToWave = v end
})

-- PESTAÑA EVACUACIÓN
Tabs.Evac:AddSection("Huida Aérea por Daño Crítico")

Tabs.Evac:AddToggle("EmergencyHealToggle", {
    Title = "🛡️ Activar Huida Aérea (Y=32)",
    Description = "Vuela al centro de forma suave sin desarmar las llantas",
    Default = true,
    Callback = function(v) Config.EmergencyHealEnabled = v end
})

local EvacStatusParagraph = Tabs.Evac:AddParagraph({
    Title = "Monitor de Salud del Vehículo",
    Content = "Leyendo datos..."
})

Tabs.Evac:AddSlider("LowHPSlider", {
    Title = "Umbral de Huida (% Vida)",
    Default = 20,
    Min = 10,
    Max = 40,
    Rounding = 0,
    Callback = function(v) Config.LowHealthThreshold = v / 100 end
})

Tabs.Evac:AddSlider("FullHPSlider", {
    Title = "Umbral de Retorno (% Vida)",
    Default = 70,
    Min = 50,
    Max = 95,
    Rounding = 0,
    Callback = function(v) Config.FullHealthThreshold = v / 100 end
})

Tabs.Evac:AddButton({
    Title = "🛫 Probar Evacuación Aérea Ahora",
    Callback = function()
        if not EvacState.IsActive then task.spawn(executeAirEvacuation) end
    end
})

-- PESTAÑA RESCATE
Tabs.Rescue:AddSection("Contingencia Aérea (Sin Noclip)")

Tabs.Rescue:AddToggle("AutoRemountToggle", {
    Title = "🛡️ Auto-Rescate en Eyección / Destrucción",
    Description = "Vuela al auto, baja al capó a reparar y se sienta de nuevo",
    Default = true,
    Callback = function(v) Config.AutoRemountEnabled = v end
})

Tabs.Rescue:AddSlider("RescueAltSlider", {
    Title = "Altura de Traslado (Studs)",
    Default = 8,
    Min = 6,
    Max = 20,
    Rounding = 0,
    Callback = function(v) Config.RescueFlyAltitude = v end
})

Tabs.Rescue:AddSlider("RescueSpeedSlider", {
    Title = "Velocidad de Vuelo al Auto",
    Default = 80,
    Min = 40,
    Max = 140,
    Rounding = 0,
    Callback = function(v) Config.RescueFlySpeed = v end
})

Tabs.Rescue:AddButton({
    Title = "🚗 Forzar Reparación y Montaje (Tecla 'V')",
    Callback = function() executeContingencyRescue() end
})

-- PESTAÑA RADAR
Tabs.Horde:AddSection("Radar de Entradas")

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente Dominante",
    Content = "Escaneando concentración de hordas..."
})

-- ACTUALIZACIÓN EN VIVO DEL MONITOR
task.spawn(function()
    while true do
        task.wait(0.3)
        local stageText = "⚔️ En Combate Normal"
        if EvacState.IsActive then
            if EvacState.Stage == "ASCENDING" then stageText = "🛫 Ascendiendo suavemente a Y=32..."
            elseif EvacState.Stage == "FLYING_TO_BASE" then stageText = "🛩️ Traslado cinético a Base (0, 32, 0)..."
            elseif EvacState.Stage == "HEALING" then stageText = "💉 Suspendido en Base hasta 70%..."
            elseif EvacState.Stage == "RETURNING" then stageText = "🚀 Retorno aéreo al frente de combate..."
            elseif EvacState.Stage == "DESCENDING" then stageText = "🛬 Aterrizaje inteligente por Raycast..." end
        elseif IsInContingency then
            stageText = "🚨 Rescatando personaje (Vuelo -> Capó -> Asiento)..."
        end

        EvacStatusParagraph:SetDesc(string.format(
            "Vida Vehículo: %.0f / %.0f (%.0f%%) [%s]\nProtocolo Huida: %s\nEstado Actual: %s",
            EvacState.CurrentHP, EvacState.MaxHP, EvacState.HPRatio * 100, EvacState.Source,
            Config.EmergencyHealEnabled and "🟢 ACTIVO" or "🔴 INACTIVO",
            stageText
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
        executeContingencyRescue()
    end
end)

-- RADAR EN SEGUNDO PLANO
task.spawn(function()
    while true do
        task.wait(3.0)
        local counts = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
        local totalZombies = 0
        local charFolder = workspace:FindFirstChild("Characters") or workspace

        for _, entity in ipairs(charFolder:GetChildren()) do
            local valid, eRoot = isValidZombie(entity)
            if valid then
                local p = eRoot.Position - BaseCenter
                if p.Magnitude <= 900 then
                    totalZombies = totalZombies + 1
                    if math.abs(p.Z) > math.abs(p.X) then
                        if p.Z < 0 then counts.NORTE = counts.NORTE + 1 else counts.SUR = counts.SUR + 1 end
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

        HordeStatusParagraph:SetDesc(string.format(
            "Frente Dominante: %s (%d zombies)\nN: %d | S: %d | E: %d | O: %d | Total: %d",
            topSector, maxCount, counts.NORTE, counts.SUR, counts.ESTE, counts.OESTE, totalZombies
        ))

        if maxCount >= 10 and topSector ~= CurrentActiveSector then
            CurrentActiveSector = topSector
        end
    end
end)

-- ==============================================================================
-- 8. MOTOR CINÉTICO ULTRA-RÁPIDO (MODO STALKER RECALIBRADO: +5 / +25 STUDS)
-- ==============================================================================

local side = 1
local lastSwitch = tick()
local stalkerDir = 1
local lastStalkerSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or EvacState.IsActive or IsInContingency then return end

    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then return end

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
    elseif Config.AutoRouteToWave and SECTOR_ROUTES[CurrentActiveSector] then
        local routeData = SECTOR_ROUTES[CurrentActiveSector]
        local distToGate = (root.Position - routeData.Gate).Magnitude

        if distToGate > 35 and (root.Position - BaseCenter).Magnitude < 110 then
            targetPos = routeData.Gate
            targetCF = CFrame.new(routeData.Gate)
        else
            targetPos = routeData.Combat
            targetCF = CFrame.new(routeData.Combat)
        end
    end

    if targetPos and targetCF then
        local destination = targetPos
        local d = Config.LateralDist

        if Config.AttackMode == "Stalker" then
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1)
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)

            -- LÍMITES CALIBRADOS: +25 studs hacia afuera, +5 studs hacia la base
            local reachAway = halfLength + Config.StalkerFarOvershoot   -- +25 studs afuera
            local reachBase = halfLength + Config.StalkerBaseOvershoot  -- +5 studs hacia base

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
        elseif Config.AttackMode == "Zigzag Clásico" then
            if Config.SwitchInterval <= 0.05 then
                local wave = math.sin(tick() * 3.8)
                destination = targetPos + (targetCF.RightVector * (wave * d))
            else
                if tick() - lastSwitch >= Config.SwitchInterval then
                    side = -side
                    lastSwitch = tick()
                end
                destination = targetPos + (targetCF.RightVector * (side * d))
            end
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
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB V8.7 LISTO",
    Content = "Vuelo cinético suave, aterrizaje por Raycast y Stalker (+5/-25) activos.",
    Duration = 4
})

Window:SelectTab(1)
