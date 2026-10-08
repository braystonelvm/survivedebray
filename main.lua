-- ==============================================================================
-- REACTOR NUCLEAR HUB - APERTURA PRIORITARIA, RONDAS (40s), GAS 128 Y EXPERIMENT
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer

-- COORDENADAS DE LA PARTIDA (NUEVO MAPA)
local DEFAULT_DOOR = Vector3.new(-1140.6, 5.5, -230.0)
local DEFAULT_CENTER = Vector3.new(-1123.2, 5.2, -176.4)

-- 7 COFRES REGISTRADOS (NUEVO MAPA)
local CHESTS = {
    Vector3.new(-1179.9, -13.7, -167.1),
    Vector3.new(-1170.7, -13.8, -147.0),
    Vector3.new(-1170.5, -13.8, -139.4),
    Vector3.new(-1153.3, -13.8, -125.6),
    Vector3.new(-1144.1, -13.8, -124.4),
    Vector3.new(-1072.1, -33.5, -124.7),
    Vector3.new(-1068.9, -33.5, -138.4)
}

-- 3 GASOLINERAS REGISTRADAS (NUEVO MAPA)
local GAS_STATIONS = {
    Vector3.new(-477.6, 5.0, -338.8),
    Vector3.new(19.1, 4.5, -364.0),
    Vector3.new(594.4, 5.8, -562.4)
}

local State = {
    Running = false,
    Paused = false,
    NoclipEnabled = false,    -- Se activa 3 segundos después del Fly
    CurrentStatus = "Inactivo",
    LootChests = false,       -- DESACTIVADO POR DEFECTO
    ChestWaitTime = 0.8,
    BaseNuclearWait = 900,    -- 15 minutos de espera en gasolineras
    GasStationStop = 4.0,     -- 4 segundos de parada por ciclo
    GasFlySpeed = 128,        -- Velocidad aumentada (+20 extra)
    WaveWaitTime = 40,        -- Espera de 40 segundos entre rondas
    DetectionRadius = 950,    -- 950 studs a la redonda
    CenterCampTime = 780      -- 10 minutos de espera en centro tras abrir puerta
}

local Point2_Door = DEFAULT_DOOR
local CalculatedCenter = DEFAULT_CENTER
local DoorForwardDir = Vector3.new(DEFAULT_CENTER.X - DEFAULT_DOOR.X, 0, DEFAULT_CENTER.Z - DEFAULT_DOOR.Z).Unit

local Markers = {}

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "REACTOR HUB | NUCLEAR V3",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 490),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Controles", Icon = "play" }),
    Setup = Window:AddTab({ Title = "Calibración", Icon = "map-pin" }),
    Coords = Window:AddTab({ Title = "Coords", Icon = "clipboard" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Bot",
    Content = "Inactivo. Presiona PLAY para iniciar el ciclo infinito."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function copyCurrentCoords()
    local root = getRootPart()
    if root then
        local p = root.Position
        local str = string.format("Vector3.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
        if setclipboard then setclipboard(str) elseif toclipboard then toclipboard(str) end
        print("\n[COORDS]: " .. str .. "\n")
        Fluent:Notify({ Title = "Coordenada Copiada", Content = str, Duration = 3 })
    end
end

-- LIMPIEZA AL DETENER
local function removePhysicsHelpers()
    local root = getRootPart()
    if root then
        local bp = root:FindFirstChild("ReactorFloatBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("ReactorFloatBG")
        if bg then bg:Destroy() end
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
end

local function restoreCollisions()
    local char = lp.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

-- NOCLIP ACTIVO SOLO TRAS 3 SEGUNDOS DE FLY
RunService.Stepped:Connect(function()
    if State.Running and not State.Paused and State.NoclipEnabled then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

-- SISTEMA DE VUELO RÍGIDO (BODYPOSITION + BODYGYRO)
local function getOrCreatePhysics(root, initialY)
    local bodyPos = root:FindFirstChild("ReactorFloatBP")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "ReactorFloatBP"
        bodyPos.MaxForce = Vector3.new(1e6, math.huge, 1e6)
        bodyPos.P = 25000
        bodyPos.D = 800
        bodyPos.Position = Vector3.new(root.Position.X, initialY, root.Position.Z)
        bodyPos.Parent = root
    end

    local bodyGyro = root:FindFirstChild("ReactorFloatBG")
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "ReactorFloatBG"
        bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bodyGyro.CFrame = root.CFrame
        bodyGyro.Parent = root
    end

    return bodyPos, bodyGyro
end

-- ANCLAJE PREVENTIVO INMEDIATO (FLY PRIMERO)
local function secureFlightStart()
    local root = getRootPart()
    if not root then return false end

    local safeY = Point2_Door.Y + 3.0
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    local bodyPos = getOrCreatePhysics(root, safeY)
    bodyPos.Position = Vector3.new(root.Position.X, safeY, root.Position.Z)
    task.wait(0.15)
    return true
end

-- VUELO HACIA UN DESTINO (ALTURA ORIGINAL CONSERVADA)
local function flyMoveTo(targetPos, speed, stopDistance, lockAltitudeToDoor)
    stopDistance = stopDistance or 3.0
    local root = getRootPart()
    if not root then return false end

    local targetY = targetPos.Y + 3.0
    if lockAltitudeToDoor and Point2_Door then
        targetY = Point2_Door.Y + 3.0
    end

    local finalDest = Vector3.new(targetPos.X, targetY, targetPos.Z)
    local timeout = tick() + 25

    local bodyPos = getOrCreatePhysics(root, targetY)
    local lastPos = root.Position
    local stuckCounter = 0

    while State.Running and tick() < timeout do
        RunService.Heartbeat:Wait()

        while State.Running and State.Paused do
            bodyPos.Position = Vector3.new(root.Position.X, targetY, root.Position.Z)
            task.wait(0.2)
        end

        if not State.Running then break end

        local dist = (finalDest - root.Position).Magnitude
        if dist <= stopDistance then
            bodyPos.Position = finalDest
            return true
        end

        if (root.Position - lastPos).Magnitude < 0.2 then
            stuckCounter = stuckCounter + 1
            if stuckCounter >= 25 then
                bodyPos.Position = Vector3.new(root.Position.X, targetY + 3, root.Position.Z)
                stuckCounter = 0
            end
        else
            stuckCounter = 0
            lastPos = root.Position
        end

        local stepDir = (finalDest - root.Position).Unit
        local nextStep = root.Position + (stepDir * (speed * 0.1))
        bodyPos.Position = Vector3.new(nextStep.X, targetY, nextStep.Z)
    end

    if bodyPos then bodyPos.Position = finalDest end
    return false
end

-- ATAQUE CIRCULAR (ALTURA ORIGINAL CONSERVADA)
local function orbitTarget(targetRoot, radius, duration, speed)
    local root = getRootPart()
    if not root or not targetRoot or not targetRoot.Parent or not Point2_Door then return end

    local targetY = Point2_Door.Y + 4.0
    local endTime = tick() + duration
    local angle = 0

    local bodyPos = getOrCreatePhysics(root, targetY)

    while State.Running and not State.Paused and targetRoot.Parent and tick() < endTime do
        RunService.Heartbeat:Wait()
        angle = angle + (speed * 0.010)
        local tPos = targetRoot.Position
        local orbitDest = Vector3.new(
            tPos.X + math.cos(angle) * radius,
            targetY,
            tPos.Z + math.sin(angle) * radius
        )
        bodyPos.Position = orbitDest
    end
end

-- LOCALIZAR LA PARTE EXACTA DE ENTRADA
local function getEntrancePart()
    local map = workspace:FindFirstChild("Map")
    local tiles = map and map:FindFirstChild("Tiles")
    local reactor = tiles and tiles:FindFirstChild("Nuclear Reactor")
    local entrance = reactor and reactor:FindFirstChild("Entrance")
    if entrance and entrance:IsA("BasePart") then
        return entrance
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == "Entrance" and obj.Parent and obj.Parent.Name == "Nuclear Reactor" then
            return obj
        end
    end
    return nil
end

-- ACCIÓN DE PULSAR PROMPT
local function triggerPromptRobust(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end

    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.MaxActivationDistance = 60

    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
        pcall(function() fireproximityprompt(prompt, 0) end)
    end
end

-- APERTURA DIRECTA Y AGRESIVA DE LA PUERTA (DEVUELVE TRUE SI ACTIVÓ UN PROMPT VÁLIDO)
local function openNuclearDoorDirect()
    local entrance = getEntrancePart()
    local targetPos = entrance and entrance.Position or Point2_Door

    flyMoveTo(targetPos, 50, 1.8, false)
    task.wait(0.15)

    local opened = false

    if entrance then
        local directPrompt = entrance:FindFirstChildOfClass("ProximityPrompt")
        if directPrompt and directPrompt.Enabled then
            triggerPromptRobust(directPrompt)
            opened = true
        end
    end

    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local pPart = prompt.Parent
            local pPos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition))

            if pPos and (pPos - targetPos).Magnitude <= 18 then
                local obj = prompt.ObjectText:lower()
                local act = prompt.ActionText:lower()
                local pName = pPart and pPart.Name:lower()

                if obj:find("nuclear") or pName == "entrance" or act:find("open") or act:find("abrir") then
                    triggerPromptRobust(prompt)
                    opened = true
                end
            end
        end
    end

    return opened
end

-- LECTURA DEL CONTADOR DE ENFRIAMIENTO
local function getDoorTimerText()
    local entrance = getEntrancePart()

    if entrance then
        local gui = entrance:FindFirstChildOfClass("SurfaceGui")
        local timerLbl = gui and gui:FindFirstChild("Timer")
        if timerLbl and timerLbl:IsA("TextLabel") and timerLbl.Visible then
            local txt = timerLbl.Text
            if txt and txt ~= "" and (txt:find("%d") or txt:lower():find("lock")) then
                return txt
            end
        end
    end

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Name == "Timer" and desc.Visible then
            local parentGui = desc:FindFirstAncestorOfClass("SurfaceGui")
            local adornee = parentGui and (parentGui.Adornee or parentGui.Parent)
            if adornee and adornee.Name == "Entrance" then
                local txt = desc.Text
                if txt and txt ~= "" and txt:find("%d") then
                    return txt
                end
            end
        end
    end

    return nil
end

-- INTERACCIÓN CON GASOLINERAS (MÉTODO EFECTIVO ORIGINAL)
local function interactWithGasPump(stationPos)
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local pPart = prompt.Parent
            local pos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition))

            if pos and (pos - stationPos).Magnitude <= 28 then
                prompt.HoldDuration = 0
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 50
                if fireproximityprompt then
                    pcall(function() fireproximityprompt(prompt) end)
                    pcall(function() fireproximityprompt(prompt, 0) end)
                end
            end
        end
    end
end

-- RUTINA PARA SAQUEAR LOS 7 COFRES
local function lootAllChests()
    if not State.LootChests then return end
    updateStatus("📦 Saqueando cofres del reactor...")
    for idx, chestPos in ipairs(CHESTS) do
        if not State.Running or State.Paused then break end
        updateStatus(string.format("📦 Yendo a Cofre [%d/%d]...", idx, #CHESTS))
        flyMoveTo(chestPos, 48, 2.5, false)
        task.wait(0.2)

        for _, prompt in ipairs(workspace:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                local pPart = prompt.Parent
                local pPos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition))
                if pPos and (pPos - chestPos).Magnitude <= 15 then
                    triggerPromptRobust(prompt)
                end
            end
        end
        task.wait(State.ChestWaitTime)
    end
end

-- RESPALDO AUTOMÁTICO PROXIMITY PROMPT
ProximityPromptService.PromptShown:Connect(function(prompt)
    local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") or text:find("abrir") or text:find("open") or text:find("cofre") or text:find("chest") then
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        if fireproximityprompt then
            pcall(function() fireproximityprompt(prompt) end)
            pcall(function() fireproximityprompt(prompt, 0) end)
        end
    end
end)

-- DETECCIÓN EXCLUSIVA Y PROFUNDA DE PHASERS (IGNORA HIBERNACIÓN COMPLETAMENTE)
local function getPriorityPhaser(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local bestPhaser = nil
    local bestRoot = nil
    local shortestDist = math.huge

    local function checkEntity(entity)
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
            local eHum = entity:FindFirstChildOfClass("Humanoid")

            if eRoot and (not eHum or eHum.Health > 0) then
                local dist = (eRoot.Position - centerPos).Magnitude
                if dist <= maxDist then
                    local name = entity.Name:lower()
                    local variant = tostring(entity:GetAttribute("Variant") or ""):lower()

                    -- Detección de todas las variantes de Phaser (SIN importar si tiene Hibernating = true)
                    local isPhaser = name:find("phaser") or name:find("ghost") or name:find("fantasma") or name:find("phase") or variant:find("phaser") or variant:find("ghost") or variant:find("phase")

                    if isPhaser then
                        if dist < shortestDist then
                            shortestDist = dist
                            bestPhaser = entity
                            bestRoot = eRoot
                        end
                    end
                end
            end
        end
    end

    -- 1. Revisar carpeta Characters
    for _, entity in ipairs(charFolder:GetChildren()) do
        checkEntity(entity)
    end

    -- 2. Revisión de respaldo directo en Workspace por si se movieron
    if charFolder ~= workspace then
        for _, entity in ipairs(workspace:GetChildren()) do
            checkEntity(entity)
        end
    end

    return bestPhaser, bestRoot
end

-- FILTRO DE ASALTO COMPLETO (DETECCIÓN BASE ORIGINAL)
local function getAnyTargetZombie(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local priorityScreamer, priorityScreamerRoot = nil, nil
    local priorityPhaser, priorityPhaserRoot = nil, nil
    local bestGlowingTarget, bestGlowingRoot = nil, nil
    local bestGlowingDist = math.huge
    local experimentTarget, experimentRoot = nil, nil

    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
            local eHum = entity:FindFirstChildOfClass("Humanoid")

            if eRoot and (not eHum or eHum.Health > 0) then
                local dist = (eRoot.Position - centerPos).Magnitude
                if dist <= maxDist then
                    local name = entity.Name:lower()
                    local variant = tostring(entity:GetAttribute("Variant") or ""):lower()

                    local hasHighlight = (entity:FindFirstChildOfClass("Highlight") ~= nil) or (entity:FindFirstChildWhichIsA("Highlight", true) ~= nil) or (entity:FindFirstChild("Highlight") ~= nil)
                    local isReactorAttr = (entity:GetAttribute("Reactor") == true) or (entity:GetAttribute("Raid") == true)
                    local isHibernating = (entity:GetAttribute("Hibernating") == true)

                    local isScreamer = name:find("scream") or name:find("gato") or variant:find("scream")
                    local isPhaser = name:find("phaser") or name:find("ghost") or name:find("fantasma") or name:find("phase") or variant:find("phaser") or variant:find("ghost") or variant:find("phase")
                    local isExperiment = name:find("experiment") or variant:find("experiment") or name:find("experimento") or variant:find("experimento")

                    -- Los zombies especiales (Phaser, Screamer, Experiment) son válidos siempre, incluso si están en reposo
                    local isSpecial = isScreamer or isPhaser or isExperiment
                    local isGlowing = (hasHighlight or isReactorAttr) and not isHibernating
                    local isReactorZombie = isSpecial or isGlowing

                    if isReactorZombie then
                        -- 1. PRIORIDAD MÁXIMA: SCREAMER ("GATO")
                        if isScreamer then
                            if not priorityScreamer then
                                priorityScreamer = entity
                                priorityScreamerRoot = eRoot
                            end

                        -- 2. PRIORIDAD 2: PHASER / GHOST
                        elseif isPhaser then
                            if not priorityPhaser then
                                priorityPhaser = entity
                                priorityPhaserRoot = eRoot
                            end

                        -- 4. ÚLTIMA PRIORIDAD: EXPERIMENT (JEFE FINAL)
                        elseif isExperiment then
                            if not experimentTarget then
                                experimentTarget = entity
                                experimentRoot = eRoot
                            end

                        -- 3. PRIORIDAD 3: RESTO DE ZOMBIES NUCLEARES RESPLANDECIENTES
                        elseif dist < bestGlowingDist then
                            bestGlowingDist = dist
                            bestGlowingTarget = entity
                            bestGlowingRoot = eRoot
                        end
                    end
                end
            end
        end
    end

    if priorityScreamer then
        return priorityScreamer, priorityScreamerRoot, "screamer"
    elseif priorityPhaser then
        return priorityPhaser, priorityPhaserRoot, "phaser"
    elseif bestGlowingTarget then
        return bestGlowingTarget, bestGlowingRoot, "glowing"
    elseif experimentTarget then
        return experimentTarget, experimentRoot, "experiment"
    end

    return nil, nil, nil
end

-- CONTEO Y CLASIFICACIÓN DE ZOMBIES EN EL REACTOR
local function countZombieTypes(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local screamers, phasers, others = 0, 0, 0
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
            local eHum = entity:FindFirstChildOfClass("Humanoid")
            if eRoot and (not eHum or eHum.Health > 0) then
                if (eRoot.Position - centerPos).Magnitude <= maxDist then
                    local name = entity.Name:lower()
                    local variant = tostring(entity:GetAttribute("Variant") or ""):lower()
                    local hasHighlight = (entity:FindFirstChildOfClass("Highlight") ~= nil) or (entity:FindFirstChildWhichIsA("Highlight", true) ~= nil) or (entity:FindFirstChild("Highlight") ~= nil)
                    local isReactorAttr = (entity:GetAttribute("Reactor") == true) or (entity:GetAttribute("Raid") == true)
                    local isHibernating = (entity:GetAttribute("Hibernating") == true)

                    local isScreamer = name:find("scream") or name:find("gato") or variant:find("scream")
                    local isPhaser = name:find("phaser") or name:find("ghost") or name:find("fantasma") or name:find("phase") or variant:find("phaser") or variant:find("ghost") or variant:find("phase")
                    local isExperiment = name:find("experiment") or variant:find("experiment") or name:find("experimento") or variant:find("experimento")

                    if isScreamer then
                        screamers = screamers + 1
                    elseif isPhaser then
                        phasers = phasers + 1
                    elseif ((hasHighlight or isReactorAttr) and not isHibernating) or isExperiment then
                        others = others + 1
                    end
                end
            end
        end
    end
    return screamers, phasers, others
end

-- CONTEO TOTAL DE ZOMBIES VIVOS
local function countLivingZombiesInReactor(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local count = 0
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
            local eHum = entity:FindFirstChildOfClass("Humanoid")
            if eRoot and (not eHum or eHum.Health > 0) then
                if (eRoot.Position - centerPos).Magnitude <= maxDist then
                    local name = entity.Name:lower()
                    local variant = tostring(entity:GetAttribute("Variant") or ""):lower()
                    local hasHighlight = (entity:FindFirstChildOfClass("Highlight") ~= nil) or (entity:FindFirstChildWhichIsA("Highlight", true) ~= nil) or (entity:FindFirstChild("Highlight") ~= nil)
                    local isReactorAttr = (entity:GetAttribute("Reactor") == true) or (entity:GetAttribute("Raid") == true)
                    local isHibernating = (entity:GetAttribute("Hibernating") == true)

                    local isSpecial = name:find("scream") or variant:find("scream") or name:find("experiment") or variant:find("experiment") or name:find("experimento") or variant:find("experimento") or name:find("phaser") or variant:find("phaser") or name:find("ghost") or variant:find("ghost")

                    if isSpecial or ((hasHighlight or isReactorAttr) and not isHibernating) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

-- MARCADORES VISUALES
local function refreshVisualMarkers()
    for _, m in pairs(Markers) do if m and m.Parent then m:Destroy() end end
    table.clear(Markers)

    if Point2_Door then
        local dMarker = Instance.new("Part")
        dMarker.Name = "NuclearDoorMarker"
        dMarker.Shape = Enum.PartType.Ball
        dMarker.Size = Vector3.new(3, 3, 3)
        dMarker.Material = Enum.Material.Neon
        dMarker.Color = Color3.fromRGB(255, 60, 0)
        dMarker.Anchored = true
        dMarker.CanCollide = false
        dMarker.Position = Point2_Door
        dMarker.Parent = workspace
        Markers["Door"] = dMarker
    end

    if CalculatedCenter then
        local cMarker = Instance.new("Part")
        cMarker.Name = "NuclearCenterMarker"
        cMarker.Shape = Enum.PartType.Ball
        cMarker.Size = Vector3.new(3, 3, 3)
        cMarker.Material = Enum.Material.Neon
        cMarker.Color = Color3.fromRGB(255, 170, 0)
        cMarker.Anchored = true
        cMarker.CanCollide = false
        cMarker.Position = CalculatedCenter
        cMarker.Parent = workspace
        Markers["Center"] = cMarker
    end
end

refreshVisualMarkers()

-- PESTAÑA 1: CONTROLES
Tabs.Main:AddSection("Operación Infinita")

Tabs.Main:AddButton({
    Title = "▶ PLAY / INICIAR BUCLE",
    Callback = function()
        if not Point2_Door or not CalculatedCenter then
            Fluent:Notify({ Title = "Sin Coordenadas", Content = "Falta fijar la puerta o el centro.", Duration = 3 })
            return
        end

        State.Running = true
        State.Paused = false
        State.NoclipEnabled = false

        updateStatus("Activando Fly seguro...")
        secureFlightStart()

        task.spawn(function()
            for s = 3, 1, -1 do
                if not State.Running then break end
                updateStatus(string.format("Fly activo. Esperando %ds para activar Noclip...", s))
                task.wait(1)
            end

            if State.Running then
                State.NoclipEnabled = true
                updateStatus("Noclip activado. Iniciando cacería y puerta...")
            end
        end)
    end
})

Tabs.Main:AddButton({
    Title = "⏸ PAUSA",
    Callback = function()
        if State.Running then
            State.Paused = not State.Paused
            updateStatus(State.Paused and "Pausado manualmente" or "Reanudado")
        end
    end
})

Tabs.Main:AddButton({
    Title = "⏹ STOP (CANCELAR TODO)",
    Description = "Apaga el bot, devuelve colisiones y físicas normales",
    Callback = function()
        State.Running = false
        State.Paused = false
        State.NoclipEnabled = false
        removePhysicsHelpers()
        restoreCollisions()
        updateStatus("Detenido. Físicas normales restauradas.")
    end
})

Tabs.Main:AddToggle("LootChestsQuickToggle", {
    Title = "Saquear Cofres tras Limpiar",
    Default = false,
    Callback = function(Value) State.LootChests = Value end
})

-- PESTAÑA 2: CALIBRACIÓN
Tabs.Setup:AddSection("Coordenadas Predefinidas")

Tabs.Setup:AddButton({
    Title = "Restaurar Nuevas Coordenadas",
    Callback = function()
        Point2_Door = DEFAULT_DOOR
        CalculatedCenter = DEFAULT_CENTER
        DoorForwardDir = Vector3.new(DEFAULT_CENTER.X - DEFAULT_DOOR.X, 0, DEFAULT_CENTER.Z - DEFAULT_DOOR.Z).Unit
        refreshVisualMarkers()
        Fluent:Notify({ Title = "Restaurado", Content = "Valores de tu partida fijados.", Duration = 2 })
    end
})

-- PESTAÑA 3: COORDS
Tabs.Coords:AddSection("Extraer Coordenadas")

local LiveCoordsParagraph = Tabs.Coords:AddParagraph({
    Title = "Posición en Vivo",
    Content = "X: 0, Y: 0, Z: 0"
})

task.spawn(function()
    while true do
        task.wait(0.3)
        local root = getRootPart()
        if root then
            local p = root.Position
            LiveCoordsParagraph:SetDesc(string.format("X: %.1f | Y: %.1f | Z: %.1f", p.X, p.Y, p.Z))
        end
    end
end)

Tabs.Coords:AddButton({
    Title = "📋 Copiar Mi Posición Actual (Tecla 'C')",
    Callback = function() copyCurrentCoords() end
})

-- PESTAÑA 4: AJUSTES
Tabs.Settings:AddSection("Tiempos de Espera")

Tabs.Settings:AddSlider("BaseWaitSlider", {
    Title = "Tiempo de enfriamiento en Base (Minutos)",
    Default = 15,
    Min = 5,
    Max = 30,
    Rounding = 0,
    Callback = function(Value) State.BaseNuclearWait = Value * 60 end
})

Tabs.Settings:AddSlider("GasStopSlider", {
    Title = "Parada en cada gasolinera (Segundos)",
    Default = 4,
    Min = 2,
    Max = 8,
    Rounding = 0,
    Callback = function(Value) State.GasStationStop = Value end
})

Tabs.Settings:AddSlider("WaveWaitSlider", {
    Title = "Espera entre rondas del reactor (Segundos)",
    Default = 40,
    Min = 15,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) State.WaveWaitTime = Value end
})

Tabs.Settings:AddSlider("CenterCampSlider", {
    Title = "Espera en Centro tras abrir puerta (Minutos)",
    Default = 13,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Callback = function(Value) State.CenterCampTime = Value * 60 end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReactorHubFloatingBtn"
ScreenGui.ResetOnSpawn = false
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.C then
        copyCurrentCoords()
    end
end)

-- MÁQUINA DE ESTADOS: BUCLE INFINITO DEL REACTOR
task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            -- Esperar hasta que se cumplan los 3 segundos de Fly para activar Noclip
            if not State.NoclipEnabled then
                task.wait(0.3)
                continue
            end

            -- PASO 1: APERTURA PRIORITARIA INMEDIATA CON CONFIRMACIÓN
            updateStatus("[1/4] Yendo a la Puerta del Reactor para abrirla...")
            local doorWasPressed = false
            for _ = 1, 5 do
                if not State.Running or State.Paused then break end
                if openNuclearDoorDirect() then
                    doorWasPressed = true
                end
                task.wait(0.2)
            end
            task.wait(0.5)

            -- PASO 2: VERIFICAR SI ESTÁ EN COOLDOWN O LIBRE
            local cdText = getDoorTimerText()

            -- SI LA PUERTA ESTÁ EN ENFRIAMIENTO (TIEMPO ACTIVO) -> IR DIRECTO A GASOLINERAS
            if cdText then
                updateStatus("Reactor en Cooldown (" .. cdText .. "). Yendo a Gasolineras...")
                local cooldownStart = tick()

                while State.Running and not State.Paused and (tick() - cooldownStart < State.BaseNuclearWait) do
                    for idx, gasPos in ipairs(GAS_STATIONS) do
                        if not State.Running or State.Paused then break end
                        if (tick() - cooldownStart >= State.BaseNuclearWait) then break end

                        local timeLeft = math.max(0, math.floor(State.BaseNuclearWait - (tick() - cooldownStart)))
                        local mins = math.floor(timeLeft / 60)
                        local secs = timeLeft % 60

                        local rootBefore = getRootPart()
                        local approachPos = rootBefore and rootBefore.Position or Point2_Door

                        -- === PARADA 1: VUELO Y ACTIVACIÓN (4 SEGUNDOS) ===
                        updateStatus(string.format("[Gas %d/%d] Parada 1/2 (Vuelo 128)... | Cooldown: %02dm %02ds", idx, #GAS_STATIONS, mins, secs))
                        flyMoveTo(gasPos, State.GasFlySpeed, 3.5, false)
                        task.wait(0.15)

                        updateStatus(string.format("[Gas %d/%d] Surtidor Activo 1 (4s)... | Cooldown: %02dm %02ds", idx, #GAS_STATIONS, mins, secs))
                        local stop1 = tick()
                        while State.Running and not State.Paused and (tick() - stop1 < State.GasStationStop) do
                            interactWithGasPump(gasPos)
                            task.wait(0.6)
                        end

                        if not State.Running or State.Paused then break end

                        -- === RETROCESO DE 20 STUDS ===
                        updateStatus(string.format("[Gas %d/%d] Retrocediendo 20 studs...", idx, #GAS_STATIONS))
                        local dirAway = (approachPos - gasPos).Unit
                        if dirAway.Magnitude == 0 or dirAway ~= dirAway then
                            dirAway = Vector3.new(0, 0, 1)
                        end
                        local retreatPos = Vector3.new(gasPos.X + dirAway.X * 20, gasPos.Y, gasPos.Z + dirAway.Z * 20)
                        flyMoveTo(retreatPos, State.GasFlySpeed, 3.0, false)
                        task.wait(0.3)

                        if not State.Running or State.Paused then break end

                        -- === PARADA 2: REINGRESO Y ACTIVACIÓN (4 SEGUNDOS) ===
                        updateStatus(string.format("[Gas %d/%d] Reingreso Parada 2/2 (4s)... | Cooldown: %02dm %02ds", idx, #GAS_STATIONS, mins, secs))
                        flyMoveTo(gasPos, State.GasFlySpeed, 3.5, false)
                        task.wait(0.15)

                        local stop2 = tick()
                        while State.Running and not State.Paused and (tick() - stop2 < State.GasStationStop) do
                            interactWithGasPump(gasPos)
                            task.wait(0.6)
                        end
                    end
                end

            -- SI LA PUERTA ESTÁ LISTA / SE CONFIRMÓ LA APERTURA
            else
                updateStatus("[2/4] Accediendo al Centro del Reactor...")
                flyMoveTo(CalculatedCenter, 42, 3, true)

                -- FASE 1: 10 MINUTOS EN EL CENTRO (CACERÍA ENCADENADA DE PHASERS)
                if doorWasPressed then
                    local centerDefenseEnd = tick() + State.CenterCampTime
                    updateStatus("🛡️ Puerta abierta confirmada: 10m en Centro (Caza Total de Phasers)...")

                    while State.Running and not State.Paused and tick() < centerDefenseEnd do
                        local timeLeft = math.max(0, math.floor(centerDefenseEnd - tick()))
                        local m = math.floor(timeLeft / 60)
                        local s = timeLeft % 60

                        -- 1. Buscar al Phaser más cercano (ignora Hibernación para que no se escape ninguno)
                        local phaserTarget, phaserRoot = getPriorityPhaser(CalculatedCenter, State.DetectionRadius)
                        if phaserTarget and phaserRoot then
                            local pName = phaserTarget.Name
                            updateStatus(string.format("👻 Cazando PHASER [%s] (%02dm %02ds rest)...", pName, m, s))
                            flyMoveTo(phaserRoot.Position, 45, 6, true)
                            orbitTarget(phaserRoot, 7, 55.0, 3) -- Aumentado +30s (de 25s a 55s)
                        else
                            -- 2. Si no hay ningún Phaser vivo en el radio de 950 studs, regresar/mantenerse en el centro
                            local myRoot = getRootPart()
                            local distToCenter = myRoot and (myRoot.Position - CalculatedCenter).Magnitude or 0

                            if distToCenter > 6 then
                                flyMoveTo(CalculatedCenter, 42, 3, true)
                            else
                                local bp = myRoot and myRoot:FindFirstChild("ReactorFloatBP")
                                local targetY = Point2_Door.Y + 7.0
                                if bp then
                                    bp.Position = Vector3.new(CalculatedCenter.X, targetY, CalculatedCenter.Z)
                                end
                            end

                            updateStatus(string.format("🛡️ Guardia Centro: %02dm %02ds | Sin Phasers en radar...", m, s))
                            task.wait(0.5)
                        end
                    end

                    updateStatus("✅ 10 min completados. Iniciando cacería completa...")
                end

                -- FASE 2: CACERÍA UNO POR UNO EN EL REACTOR (RADIO 950)
                updateStatus("[3/4] Cacería en Reactor (Radio 950)...")
                local inCombat = true
                local screamerPhaserStuckTimer = nil

                while State.Running and not State.Paused and inCombat do
                    task.wait(0.2)

                    -- REGLA: SI SOLO QUEDAN SCREAMER/PHASER POR MÁS DE 1 MINUTO -> SALIR 850 STUDS
                    local sCount, pCount, otherCount = countZombieTypes(CalculatedCenter, State.DetectionRadius)
                    if otherCount == 0 and (sCount > 0 or pCount > 0) then
                        if not screamerPhaserStuckTimer then
                            screamerPhaserStuckTimer = tick()
                        elseif (tick() - screamerPhaserStuckTimer >= 60) then
                            updateStatus("🚀 Solo quedan Screamer/Phaser (>1 min). Saliendo 850 studs para desbugear...")
                            local escapePos = CalculatedCenter - (DoorForwardDir * 850)
                            flyMoveTo(escapePos, State.GasFlySpeed, 8, false)
                            task.wait(3.5)
                            updateStatus("Regresando al Centro del Reactor...")
                            flyMoveTo(CalculatedCenter, State.GasFlySpeed, 3, true)
                            screamerPhaserStuckTimer = tick()
                        end
                    else
                        screamerPhaserStuckTimer = nil
                    end

                    local targetModel, targetRoot, targetType = getAnyTargetZombie(CalculatedCenter, State.DetectionRadius)

                    if targetModel and targetRoot then
                        local name = targetModel.Name

                        -- CASO 1: SCREAMER (PRIORIDAD #1) -> Aumentado +30s (de 25s a 55s)
                        if targetType == "screamer" then
                            updateStatus("🚨 PRIORIDAD #1: Caza del SCREAMER para el dron...")
                            flyMoveTo(targetRoot.Position, 45, 6, true)
                            orbitTarget(targetRoot, 7, 55.0, 3)
                            flyMoveTo(CalculatedCenter, 42, 3, true)

                        -- CASO 2: PHASER (PRIORIDAD #2) -> Aumentado +30s (de 25s a 55s)
                        elseif targetType == "phaser" then
                            updateStatus("👻 PRIORIDAD #2: Caza del PHASER...")
                            flyMoveTo(targetRoot.Position, 45, 6, true)
                            orbitTarget(targetRoot, 7, 55.0, 3)
                            flyMoveTo(CalculatedCenter, 42, 3, true)

                        -- CASO 4: EXPERIMENT (JEFE FINAL - ANCLADO EN EL CENTRO SI ESTÁ CERCA)
                        elseif targetType == "experiment" then
                            local distToCenter = (targetRoot.Position - CalculatedCenter).Magnitude

                            if distToCenter <= 22.0 then
                                updateStatus("👑 EXPERIMENT en rango: Anclado en Centro para el dron...")
                                flyMoveTo(CalculatedCenter, 45, 1.5, true)

                                local myRoot = getRootPart()
                                local bp = myRoot and myRoot:FindFirstChild("ReactorFloatBP")
                                local targetY = Point2_Door.Y + 7.0

                                local holdStart = tick()
                                while State.Running and not State.Paused and targetModel.Parent and (tick() - holdStart < 10) do
                                    local eHum = targetModel:FindFirstChildOfClass("Humanoid")
                                    if not eHum or eHum.Health <= 0 then break end
                                    local currentDist = (targetRoot.Position - CalculatedCenter).Magnitude
                                    if currentDist > 26.0 then break end

                                    if bp then
                                        bp.Position = Vector3.new(CalculatedCenter.X, targetY, CalculatedCenter.Z)
                                    end
                                    task.wait(0.4)
                                end
                            else
                                updateStatus(string.format("👑 Buscando a EXPERIMENT (%d studs)...", math.floor(distToCenter)))
                                flyMoveTo(targetRoot.Position, 45, 6, true)
                                orbitTarget(targetRoot, 8, 44.0, 2.5) -- Aumentado +30s (de 14s a 44s)
                                flyMoveTo(CalculatedCenter, 42, 3, true)
                            end

                        -- CASO 3: RESTO DE ZOMBIES NUCLEARES RESPLANDECIENTES -> Aumentado +30s
                        else
                            updateStatus("Rodeando a " .. name .. " [Resplandor]...")
                            flyMoveTo(targetRoot.Position, 45, 6, true)
                            orbitTarget(targetRoot, 7, 55.0, 3) -- Aumentado +30s (de 25s a 55s)
                            if targetModel.Parent and targetRoot.Parent then
                                orbitTarget(targetRoot, 14, 60.0, 2.5) -- Aumentado +30s (de 30s a 60s)
                            end
                            flyMoveTo(CalculatedCenter, 42, 3, true)
                        end

                    else
                        screamerPhaserStuckTimer = nil
                        flyMoveTo(CalculatedCenter, 45, 3, true)
                        local roundCleared = true

                        for s = State.WaveWaitTime, 1, -1 do
                            if not State.Running or State.Paused then break end
                            updateStatus(string.format("Ronda limpia. Esperando próxima ronda: %02ds...", s))

                            local activeCount = countLivingZombiesInReactor(CalculatedCenter, State.DetectionRadius)
                            if activeCount > 0 then
                                roundCleared = false
                                updateStatus(string.format("¡Nueva oleada detectada (%d zombies)! Atacando...", activeCount))
                                break
                            end
                            task.wait(1)
                        end

                        if roundCleared and State.Running and not State.Paused then
                            inCombat = false
                        end
                    end
                end

                -- FASE 3: SAQUEO DE COFRES TRAS LIMPIAR (SI SE ENCUENTRA ACTIVADO)
                if State.LootChests and State.Running and not State.Paused then
                    lootAllChests()
                end

                -- TRAS COMPLETAR LAS RONDAS, INICIAR EL RECORRIDO DE LAS 3 GASOLINERAS
                if State.Running and not State.Paused then
                    local cooldownStart = tick()
                    updateStatus(string.format("Reactor Despejado (3 Rondas). Iniciando %d gasolineras...", #GAS_STATIONS))

                    while State.Running and not State.Paused and (tick() - cooldownStart < State.BaseNuclearWait) do
                        for idx, gasPos in ipairs(GAS_STATIONS) do
                            if not State.Running or State.Paused then break end
                            if (tick() - cooldownStart >= State.BaseNuclearWait) then break end

                            local timeLeft = math.max(0, math.floor(State.BaseNuclearWait - (tick() - cooldownStart)))
                            local mins = math.floor(timeLeft / 60)
                            local secs = timeLeft % 60

                            local rootBefore = getRootPart()
                            local approachPos = rootBefore and rootBefore.Position or Point2_Door

                            -- === PARADA 1: VUELO Y ACTIVACIÓN (4 SEGUNDOS) ===
                            updateStatus(string.format("[Gas %d/%d] Parada 1/2 (Vuelo 128)... | Cooldown: %02dm %02ds", idx, #GAS_STATIONS, mins, secs))
                            flyMoveTo(gasPos, State.GasFlySpeed, 3.5, false)
                            task.wait(0.15)

                            updateStatus(string.format("[Gas %d/%d] Surtidor Activo 1 (4s)... | Cooldown: %02dm %02ds", idx, #GAS_STATIONS, mins, secs))
                            local stop1 = tick()
                            while State.Running and not State.Paused and (tick() - stop1 < State.GasStationStop) do
                                interactWithGasPump(gasPos)
                                task.wait(0.6)
                            end

                            if not State.Running or State.Paused then break end

                            -- === RETROCESO DE 20 STUDS ===
                            updateStatus(string.format("[Gas %d/%d] Retrocediendo 20 studs...", idx, #GAS_STATIONS))
                            local dirAway = (approachPos - gasPos).Unit
                            if dirAway.Magnitude == 0 or dirAway ~= dirAway then
                                dirAway = Vector3.new(0, 0, 1)
                            end
                            local retreatPos = Vector3.new(gasPos.X + dirAway.X * 20, gasPos.Y, gasPos.Z + dirAway.Z * 20)
                            flyMoveTo(retreatPos, State.GasFlySpeed, 3.0, false)
                            task.wait(0.3)

                            if not State.Running or State.Paused then break end

                            -- === PARADA 2: REINGRESO Y ACTIVACIÓN (4 SEGUNDOS) ===
                            updateStatus(string.format("[Gas %d/%d] Reingreso Parada 2/2 (4s)... | Cooldown: %02dm %02ds", idx, #GAS_STATIONS, mins, secs))
                            flyMoveTo(gasPos, State.GasFlySpeed, 3.5, false)
                            task.wait(0.15)

                            local stop2 = tick()
                            while State.Running and not State.Paused and (tick() - stop2 < State.GasStationStop) do
                                interactWithGasPump(gasPos)
                                task.wait(0.6)
                            end
                        end
                    end
                end
            end

            -- RETORNO A LA PUERTA TRAS LOS 15 MINUTOS PARA REINICIAR EL BUCLE
            if State.Running and not State.Paused then
                updateStatus("15 min completados. Regresando a la Puerta del Reactor...")
                flyMoveTo(Point2_Door, State.GasFlySpeed, 3.0, true)
                task.wait(1.5)
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Fluent:Notify({
    Title = "REACTOR HUB V3 PERFECCIONADO",
    Content = "Coordenadas actualizadas y tiempo de ataque aumentado +30s.",
    Duration = 4
})

Window:SelectTab(1)
