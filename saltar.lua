-- ==============================================================================
-- ZOMBIE HUB MASTER V8.1: STALKER + RESCATE AÉREO INSTANTÁNEO (SIN NOCLIP)
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
    LateralDist = 25,
    MoveSpeed = 95,
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true,

    -- PROTOCOLO DE CONTINGENCIA / AUTO-RESCATE
    AutoRemountEnabled = true,   -- Siempre activo mientras el script funcione
    RescueFlyAltitude = 10.0,    -- 10 studs de elevación aérea segura
    RescueFlySpeed = 120,        -- Velocidad rápida de vuelo al auto
    MaxCarSearchDist = 250       -- Radio de búsqueda del vehículo
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local CurrentActiveSector = "SUR"

local CachedBloaterDangers = {}
local CachedHordeClusterOffset = 0
local LastDrivenVehicle = nil
local IsInContingency = false

-- ==============================================================================
-- UTILIDADES FÍSICAS Y DE VEHÍCULO
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getCurrentVehicle()
    local _, _, hum = getCharacterParts()
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local model = seat:FindFirstAncestorOfClass("Model") or seat.Parent
        LastDrivenVehicle = model
        return model, seat
    end
    return nil, nil
end

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

-- ==============================================================================
-- SISTEMA DE FLY TEMPORAL EXCLUSIVO PARA RESCATE (SIN NOCLIP)
-- ==============================================================================

local function getOrCreatePlayerFlight(root)
    local bp = root:FindFirstChild("ContingencyFlyBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "ContingencyFlyBP"
        bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bp.P = 30000
        bp.D = 800
        bp.Position = root.Position
        bp.Parent = root
    end

    local bg = root:FindFirstChild("ContingencyFlyBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "ContingencyFlyBG"
        bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bg.CFrame = root.CFrame
        bg.Parent = root
    end

    return bp, bg
end

local function removePlayerFlight(root)
    if root then
        local bp = root:FindFirstChild("ContingencyFlyBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("ContingencyFlyBG")
        if bg then bg:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- ==============================================================================
-- DETECCIÓN DE VEHÍCULO, REPARACIÓN Y MONTAJE INMEDIATO
-- ==============================================================================

local function getActiveRepairPrompt(carModel)
    for _, prompt in ipairs(carModel:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local name = prompt.Name:lower()
            local act = prompt.ActionText:lower()
            local obj = prompt.ObjectText:lower()
            if name:find("repair") or act:find("repair") or act:find("repar") or obj:find("repar") then
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
        if seat then
            return LastDrivenVehicle, seat
        end
    end

    local myPos = root.Position
    local bestSeat = nil
    local bestModel = nil
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

    -- 1. DESPEGUE VERTICAL RÁPIDO A 10 STUDS
    hum:ChangeState(Enum.HumanoidStateType.Running)
    local bp, bg = getOrCreatePlayerFlight(root)
    local safeTakeoffY = root.Position.Y + Config.RescueFlyAltitude
    bp.Position = Vector3.new(root.Position.X, safeTakeoffY, root.Position.Z)
    task.wait(0.08)

    -- 2. VUELO POR EL AIRE AL VEHÍCULO (A 10 STUDS DE ALTURA)
    local seatPos = seat.Position
    local cruiseAirTarget = Vector3.new(seatPos.X, seatPos.Y + Config.RescueFlyAltitude, seatPos.Z)

    local flyTimeout = tick() + 5.0
    while IsInContingency and tick() < flyTimeout do
        local diff = cruiseAirTarget - root.Position
        if diff.Magnitude <= 3.5 then break end

        local stepDir = diff.Unit
        local nextPos = root.Position + (stepDir * (Config.RescueFlySpeed * 0.05))
        bp.Position = nextPos
        bg.CFrame = CFrame.lookAt(root.Position, cruiseAirTarget)
        task.wait(0.03)
    end

    -- 3. REPARAR EL AUTO DIRECTAMENTE DESDE EL AIRE SI ESTÁ DESTRUIDO
    local isDead = carModel:GetAttribute("Dead") == true
    local repairPrompt = getActiveRepairPrompt(carModel)

    if isDead or repairPrompt then
        local hoodAirPos = seat.CFrame * CFrame.new(0, Config.RescueFlyAltitude, -6.5)
        bp.Position = hoodAirPos.Position
        bg.CFrame = hoodAirPos
        task.wait(0.08)

        local repairLimit = tick() + 3.0
        while (carModel:GetAttribute("Dead") == true or repairPrompt) and tick() < repairLimit do
            repairPrompt = getActiveRepairPrompt(carModel)
            if repairPrompt then
                repairPrompt.HoldDuration = 0
                repairPrompt.RequiresLineOfSight = false
                repairPrompt.MaxActivationDistance = 60 -- Activación ampliada desde el aire

                if fireproximityprompt then
                    pcall(function() fireproximityprompt(repairPrompt) end)
                    pcall(function() fireproximityprompt(repairPrompt, 0) end)
                end
            end
            task.wait(0.18)
        end
        task.wait(0.1)
    end

    -- 4. DESCENSO DIRECTO AL ASIENTO Y MONTAJE
    local seatEntranceCFrame = seat.CFrame * CFrame.new(0, 1.2, 0)
    bp.Position = seatEntranceCFrame.Position
    bg.CFrame = seat.CFrame
    task.wait(0.05)

    local sitPrompt = seat:FindFirstChild("SitPrompt") or seat:FindFirstChildOfClass("ProximityPrompt")
    if sitPrompt then
        sitPrompt.HoldDuration = 0
        sitPrompt.RequiresLineOfSight = false
        sitPrompt.MaxActivationDistance = 60
        if fireproximityprompt then
            pcall(function() fireproximityprompt(sitPrompt) end)
            pcall(function() fireproximityprompt(sitPrompt, 0) end)
        end
    end

    task.wait(0.04)
    hum:ChangeState(Enum.HumanoidStateType.Seated)
    pcall(function() seat:Sit(hum) end)

    task.wait(0.15)
    removePlayerFlight(root) -- Se quita el fly por completo
    IsInContingency = false
end

-- BUCLE GUARDIÁN: MONITOREA SI SALES DEL VEHÍCULO
task.spawn(function()
    while true do
        task.wait(0.2)
        if Config.AutoRemountEnabled and Config.ZigZagEnabled and not IsInContingency then
            local _, _, hum = getCharacterParts()
            if hum and hum.Health > 0 and (not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat")) then
                task.spawn(executeContingencyRescue)
            end
        end
    end
end)

-- ==============================================================================
-- BUCLE DE CACHÉ DE BLOATERS (CERO LAG: 0.3s)
-- ==============================================================================
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

-- ==============================================================================
-- BUCLE DE RASTREO DE HORDA EN CARRETERA (0.15s)
-- ==============================================================================
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
-- INTERFAZ FLUENT
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V8.1",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 500),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Rescue = Window:AddTab({ Title = "Auto-Rescate", Icon = "shield" }),
    Horde = Window:AddTab({ Title = "Radar", Icon = "radar" })
}

Tabs.Combat:AddSection("Controles de Movimiento y Evasión")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(Value) Config.ZigZagEnabled = Value end
})

Tabs.Combat:AddDropdown("ModeDropdown", {
    Title = "Modo de Ataque / Patrón",
    Values = { "Stalker", "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico" },
    Default = "Stalker",
    Callback = function(Value) Config.AttackMode = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 95,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud de Barrido Lateral (Studs)",
    Default = 25,
    Min = 4,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.LateralDist = Value end
})

Tabs.Rescue:AddSection("Contingencia Aérea (Sin Noclip)")

Tabs.Rescue:AddToggle("AutoRemountToggle", {
    Title = "🛡️ Rescate Aéreo Automático en Eyección",
    Description = "Vuela a 10 studs en caso de ser expulsado, repara y te monta de nuevo",
    Default = true,
    Callback = function(Value) Config.AutoRemountEnabled = Value end
})

Tabs.Rescue:AddSlider("RescueAltSlider", {
    Title = "Altura Aérea de Rescate (Studs)",
    Default = 10,
    Min = 6,
    Max = 25,
    Rounding = 0,
    Callback = function(Value) Config.RescueFlyAltitude = Value end
})

Tabs.Rescue:AddSlider("RescueSpeedSlider", {
    Title = "Velocidad de Vuelo al Auto",
    Default = 120,
    Min = 60,
    Max = 180,
    Rounding = 0,
    Callback = function(Value) Config.RescueFlySpeed = Value end
})

Tabs.Rescue:AddButton({
    Title = "🚗 Forzar Reparación y Montaje Ahora (Tecla 'V')",
    Callback = function() executeContingencyRescue() end
})

Tabs.Horde:AddSection("Radar de Entradas")

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente Dominante",
    Content = "Escaneando concentración de hordas..."
})

-- BOTÓN FLOTANTE COMBINADO
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomHubFloatingBtn"
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
        Fluent:Notify({ Title = "Pausado [9]", Content = "Frenando 1s. Objetivo conservado.", Duration = 2 })
    end

    if input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.KeypadZero then
        CurrentTarget = nil
        clearHighlight()
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        applyBrake(1.0)
        Fluent:Notify({ Title = "Limpiado [0]", Content = "Movimiento apagado y frenando 1s.", Duration = 2 })
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
-- MOTOR CINÉTICO ULTRA-RÁPIDO (MODO STALKER Y PATRONES)
-- ==============================================================================
local side = 1
local lastSwitch = tick()
local currentStep = 1
local orbitAngle = 0
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

        if Config.AttackMode == "Stalker" then
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1)
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local maxReach = halfLength + 20.0

            local carOffset = root.Position - targetPos
            local carAlongRoad = carOffset:Dot(roadLengthDir)

            if stalkerDir == 1 and carAlongRoad >= (maxReach - 5.0) then
                stalkerDir = -1
                lastStalkerSwitch = tick()
            elseif stalkerDir == -1 and carAlongRoad <= -(maxReach - 5.0) then
                stalkerDir = 1
                lastStalkerSwitch = tick()
            end

            if tick() - lastStalkerSwitch >= 3.0 then
                stalkerDir = -stalkerDir
                lastStalkerSwitch = tick()
            end

            local longitudinalTarget = targetPos + (roadLengthDir * (stalkerDir * maxReach))
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
    Title = "ZOMBIE HUB V8.1 ACTIVO",
    Content = "Modo Stalker + Rescate Aéreo a 10 studs (Sin Noclip) listos.",
    Duration = 4
})

Window:SelectTab(1)
