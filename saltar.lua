-- ==============================================================================
-- ZOMBIE HUB MASTER V10: RETIRADA TÁCTICA TERRESTRE + CORRER/SALTAR AL AUTO
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local BaseCenter = Vector3.new(0, 0, 0)

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
    LateralDist = 25,             -- Amplitud lateral de zigzag regulable
    MoveSpeed = 150,              -- Velocidad por defecto en 150
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true,

    -- VALORES DE EMBESTIDA STALKER
    StalkerBaseOvershoot = 5.0,    -- 5 studs hacia la base
    StalkerFarOvershoot = 25.0,    -- 25 studs hacia la horda

    -- RETIRADA TÁCTICA POR DAÑO (100% TERRESTRE)
    RetreatEnabled = true,
    LowHealthThreshold = 0.20,     -- 20% activa retirada
    FullHealthThreshold = 0.70,    -- 70% reanuda combate
    RetreatDistance = 30.0,        -- Distancia de retroceso hacia base
    RetreatSpeed = 110,            -- Velocidad mientras esquiva en retirada

    -- RESCATE TERRESTRE DE CONTINGENCIA
    AutoRemountEnabled = true,
    SprintSpeed = 34,              -- Velocidad al correr hacia el auto
    BunnyHop = true,               -- Saltar mientras corre
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

local DefenseState = {
    IsRetreating = false,
    CurrentHP = 2500,
    MaxHP = 2500,
    HPRatio = 1.0,
    Source = "Desconocido"
}

-- ==============================================================================
-- 1. DETECCIÓN DE PARTES Y SALUD ROBUSTA
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
-- 2. RESCATE TERRESTRE DE CONTINGENCIA (CORRER + SALTO + ESQUIVE DE ZOMBIES)
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

        -- REPARAR Y MONTAR SI YA ESTÁ CERCA
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

            -- Subir al asiento
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

        -- VECTOR DE EVASIÓN CONTRA ZOMBIES CERCANOS
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

        -- Impulso de velocidad para correr fluidamente
        root.AssemblyLinearVelocity = Vector3.new(totalMoveDir.X * sprintSpeed, root.AssemblyLinearVelocity.Y, totalMoveDir.Z * sprintSpeed)
        hum:MoveTo(root.Position + totalMoveDir * 10)

        -- BUNNY HOP: SALTAR CADA 0.35s PARA NO SER ALCANZADO
        if Config.BunnyHop and tick() - lastJumpTime >= 0.35 then
            hum.Jump = true
            lastJumpTime = tick()
        end
    end

    IsInContingency = false
end

-- ==============================================================================
-- 3. MONITOR EN SEGUNDO PLANO (SALUD & DISPARADORES)
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

            -- CONTROL DE RETIRADA TÁCTICA
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
            -- RESCATE INMEDIATO SI EL JUGADOR FUE EXPULSADO
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
-- 4. UTILIDADES DE COMBATE (FRENO, HIGHLIGHT, FILTROS)
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

-- RASTREO LATERAL DE HORDAS (0.15s)
task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.ZigZagEnabled and Config.AttackMode == "Stalker" and CurrentTarget and not IsInContingency then
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
-- 5. INTERFAZ FLUENT (MENÚ COMPLETO Y TOTALMENTE INTEGRADO)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V10",
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
    Default = 150,               -- Velocidad 150 fija por defecto
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
Tabs.Horde:AddSection("Radar de Entradas")

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente Dominante",
    Content = "Escaneando concentración de hordas..."
})

-- ACTUALIZACIÓN EN VIVO DEL MONITOR
task.spawn(function()
    while true do
        task.wait(0.3)
        local statusText = "⚔️ En Combate Normal"
        if DefenseState.IsRetreating then
            statusText = string.format("🛡️ RETIRADA: Esquivando a 30 studs de base (Cura al 70%%)...")
        elseif IsInContingency then
            statusText = "🏃 RESCATE: Corriendo y saltando hacia el auto con esquive..."
        end

        DefenseStatusParagraph:SetDesc(string.format(
            "Vida Vehículo: %.0f / %.0f (%.0f%%) [%s]\nRetirada Automática: %s\nModo Actual: %s",
            DefenseState.CurrentHP, DefenseState.MaxHP, DefenseState.HPRatio * 100, DefenseState.Source,
            Config.RetreatEnabled and "🟢 ACTIVA" or "🔴 OFF",
            statusText
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
-- 6. MOTOR CINÉTICO STALKER & MODO RETIRADA DEFENSA
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
        local speed = Config.MoveSpeed

        -- =====================================================================
        -- CASO 1: RETIRADA TÁCTICA ACTIVA (VIDA <= 20%)
        -- =====================================================================
        if DefenseState.IsRetreating then
            speed = Config.RetreatSpeed
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1)
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

            -- Retroceder hacia la base la distancia configurada
            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local retreatAnchor = targetPos - (roadLengthDir * (halfLength + Config.RetreatDistance))

            -- Maniobra constante de esquive lateral para no dejarse arrinconar
            local evadeOscillation = math.sin(tick() * 4.0) * d
            destination = retreatAnchor + (roadWidthDir * evadeOscillation)

        -- =====================================================================
        -- CASO 2: ATAQUE STALKER NORMAL (VIDA >= 70%)
        -- =====================================================================
        elseif Config.AttackMode == "Stalker" then
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1)
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)

            -- Rebase configurado: +25 afuera, +5 hacia base
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
            local targetVelocity = horizontalDir.Unit * speed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB MASTER V10",
    Content = "Retirada a 30 studs + Rescate corriendo/saltando activos.",
    Duration = 4
})

Window:SelectTab(1)
