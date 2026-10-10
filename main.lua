-- ==============================================================================
-- REACTOR NUCLEAR HUB - APERTURA PRIORITARIA, RONDAS (10s), GAS 128 Y EXPERIMENT
-- V10 MASTER: CAJAS ESTRICTAS + PARADAS INMÓVILES + PHASER READY + COFRES
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
local DEFAULT_CENTER_2 = Vector3.new(-1100.9, 5.4, -174.5) -- CENTRO 2

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
    LootChests = true,        -- ACTIVADO POR DEFECTO
    ChestWaitTime = 0.8,
    BaseNuclearWait = 900,    -- 15 minutos de espera en gasolineras
    GasStationStop = 4.0,     -- 4 segundos de parada por ciclo
    GasFlySpeed = 128,        -- Velocidad aumentada (+20 extra)
    WaveWaitTime = 10,        -- 10 segundos de espera antes de ir a los cofres
    DetectionRadius = 950,    -- 950 studs a la redonda
    CenterCampTime = 780,     -- 13 minutos de espera manual clásico
    
    -- CONFIGURACIÓN DE LAS 3 PARADAS INICIALES AÑADIDAS
    EnableInitialStops = true, -- Activado por defecto
    Center1Radius = 10,        -- 10 studs para Centro 1
    Center2Radius = 8,         -- 8 studs para Centro 2
    ShowRangeVisuals = true,
    
    -- REGISTRO DE HORARIOS
    ButtonSuccessTime = "Pendiente",
    CycleFinishTime = "Pendiente"
}

local Point2_Door = DEFAULT_DOOR
local CalculatedCenter = DEFAULT_CENTER
local Center2_Pos = DEFAULT_CENTER_2
local DoorForwardDir = Vector3.new(DEFAULT_CENTER.X - DEFAULT_DOOR.X, 0, DEFAULT_CENTER.Z - DEFAULT_DOOR.Z).Unit

local Markers = {}
local RangeVisuals = {}

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "REACTOR HUB | NUCLEAR V10",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 500),
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

local TimestampsParagraph = Tabs.Main:AddParagraph({
    Title = "⏱️ Horarios de Operación",
    Content = "Última apertura botón: Pendiente\nÚltimo fin de ciclo: Pendiente"
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

local function updateTimestampsUI()
    TimestampsParagraph:SetDesc(string.format("Última apertura botón: %s\nÚltimo fin de ciclo: %s", State.ButtonSuccessTime, State.CycleFinishTime))
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

-- VUELO HACIA UN DESTINO (CON +3 STUDS DE ALTURA AL DIRIGIRSE AL CENTRO)
local function flyMoveTo(targetPos, speed, stopDistance, lockAltitudeToDoor)
    stopDistance = stopDistance or 3.0
    local root = getRootPart()
    if not root then return false end

    local targetY = targetPos.Y + 3.0
    if lockAltitudeToDoor and Point2_Door then
        targetY = Point2_Door.Y + 6.0
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

-- ATAQUE CIRCULAR EN CACERÍA (DESDE -4 STUDS BAJO EL SUELO HASTA +5 STUDS DE ALTURA)
local function orbitTarget(targetRoot, radius, duration, speed)
    local root = getRootPart()
    if not root or not targetRoot or not targetRoot.Parent or not Point2_Door then return end

    local startTime = tick()
    local endTime = startTime + duration
    local angle = 0

    local initialTPos = targetRoot.Position
    local startY = initialTPos.Y - 4.0 -- Comienza a -4 studs por debajo
    local bodyPos = getOrCreatePhysics(root, startY)

    while State.Running and not State.Paused and targetRoot.Parent and tick() < endTime do
        RunService.Heartbeat:Wait()
        
        local eHum = targetRoot.Parent:FindFirstChildOfClass("Humanoid")
        if eHum and eHum.Health <= 0 then break end

        angle = angle + (speed * 0.010)
        local tPos = targetRoot.Position

        -- Ascenso dinámico durante el giro: desde -4 studs hasta +5 studs (recorrido de 9 studs)
        local progress = math.clamp((tick() - startTime) / duration, 0, 1)
        local currentY = (tPos.Y - 4.0) + (progress * 9.0)

        local orbitDest = Vector3.new(
            tPos.X + math.cos(angle) * radius,
            currentY,
            tPos.Z + math.sin(angle) * radius
        )
        bodyPos.Position = orbitDest
    end
end

-- ==============================================================================
-- FILTRO ESTRICTO CONTRA DROPPED BAGS, DRONES Y OBJETOS DEL SUELO
-- ==============================================================================
local function isValidZombieModel(entity)
    if not entity or not entity:IsA("Model") or entity == lp.Character or Players:GetPlayerFromCharacter(entity) then
        return false
    end

    local name = entity.Name:lower()
    -- EXCLUSIÓN TOTAL DE MOCHILAS, ITEMS, CAJAS, DRONES Y ESTRUCTURAS
    if name:find("dropped") or name:find("bag") or name:find("item") or name:find("loot") 
       or name:find("crate") or name:find("debris") or name:find("corpse") or name:find("drone")
       or name:find("turret") or name:find("sentry") or name:find("car") or name:find("vehicle")
       or name:find("structure") or name:find("door") or name:find("fence") then
        return false
    end

    -- EXIGIR HUMANOID VIVO
    local eHum = entity:FindFirstChildOfClass("Humanoid")
    if not eHum or eHum.Health <= 0 then
        return false
    end

    local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
    if not eRoot then
        return false
    end

    return true, eRoot, eHum
end

-- DETECCIÓN EXCLUSIVA Y PROFUNDA DE PHASERS (IGNORA HIBERNACIÓN)
local function getPriorityPhaser(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local bestPhaser = nil
    local bestRoot = nil
    local shortestDist = math.huge

    local function checkEntity(entity)
        local valid, eRoot = isValidZombieModel(entity)
        if valid then
            local dist = (eRoot.Position - centerPos).Magnitude
            if dist <= maxDist then
                local name = entity.Name:lower()
                local variant = tostring(entity:GetAttribute("Variant") or ""):lower()

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

    for _, entity in ipairs(charFolder:GetChildren()) do checkEntity(entity) end
    if charFolder ~= workspace then
        for _, entity in ipairs(workspace:GetChildren()) do checkEntity(entity) end
    end

    return bestPhaser, bestRoot
end

-- ILUMINACIÓN VISUAL DE LOS RANGOS DE CADA CENTRO (SIN LAG)
local function updateRangeVisuals()
    for _, v in pairs(RangeVisuals) do
        if v and v.Parent then v:Destroy() end
    end
    table.clear(RangeVisuals)

    if not State.ShowRangeVisuals then return end

    local function createBoxVisual(name, pos, rad, color)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = Vector3.new(rad * 2, rad * 2, rad * 2)
        part.CFrame = CFrame.new(pos)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Material = Enum.Material.ForceField
        part.Color = color
        part.Transparency = 0.82
        part.Parent = workspace

        local box = Instance.new("SelectionBox")
        box.Adornee = part
        box.Color3 = color
        box.LineThickness = 0.04
        box.Parent = part

        table.insert(RangeVisuals, part)
    end

    createBoxVisual("Visual_Center1_Range", CalculatedCenter, State.Center1Radius, Color3.fromRGB(0, 255, 170))
    createBoxVisual("Visual_Center2_Range", Center2_Pos, State.Center2Radius, Color3.fromRGB(255, 170, 0))
end

-- DETECCIÓN ESTRICTA DENTRO DEL VOLUMEN DE LA CAJA (IGNORA CUALQUIERA FUERA DEL RANGO)
local function getZombiesInBox(centerPos, radius)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local targets = {}

    local function checkEntity(entity)
        local valid, eRoot = isValidZombieModel(entity)
        if valid then
            local dx = math.abs(eRoot.Position.X - centerPos.X)
            local dz = math.abs(eRoot.Position.Z - centerPos.Z)
            local dy = math.abs(eRoot.Position.Y - centerPos.Y)
            local distHorizontal = math.sqrt(dx * dx + dz * dz)

            -- Medición matemática estricta: solo si está dentro del radio horizontal Y dentro de la altura
            if distHorizontal <= radius and dy <= radius then
                table.insert(targets, {Model = entity, Root = eRoot, Dist = distHorizontal})
            end
        end
    end

    for _, entity in ipairs(charFolder:GetChildren()) do checkEntity(entity) end
    if charFolder ~= workspace then
        for _, entity in ipairs(workspace:GetChildren()) do checkEntity(entity) end
    end

    table.sort(targets, function(a, b) return a.Dist < b.Dist end)
    return targets
end

-- ==============================================================================
-- RUTINA AÑADIDA: LAS 3 PARADAS 100% INMÓVILES (SIN ORBITAR ZOMBIES EN EL CENTRO)
-- ==============================================================================
local function executeThreeInitialStops()
    local root = getRootPart()
    local bp = root and root:FindFirstChild("ReactorFloatBP")
    local targetY = Point2_Door.Y + 6.0

    -- Si aparece un Phaser en el reactor, salir a eliminarlo y volver a la posición quieta
    local function checkPhaserInterrupt(returnPos)
        local phaserTarget, phaserRoot = getPriorityPhaser(CalculatedCenter, State.DetectionRadius)
        if phaserTarget and phaserRoot then
            updateStatus(string.format("👻 INTERRUPCIÓN: Caza prioritaria de PHASER [%s]...", phaserTarget.Name))
            flyMoveTo(phaserRoot.Position, 45, 6, true)
            orbitTarget(phaserRoot, 7, 55.0, 3)
            updateStatus("Phaser eliminado. Volviendo a la posición...")
            flyMoveTo(returnPos, 45, 2.5, true)
            return true
        end
        return false
    end

    -- PARADA 1: CENTRO 1 (QUIETO HASTA QUE LA CAJA DE 10 STUDS ESTÉ VACÍA)
    updateStatus("🛑 Parada 1/3: Centro 1 (Quieto hasta limpiar caja 10 studs)...")
    flyMoveTo(CalculatedCenter, 45, 2.5, true)
    if bp then bp.Position = Vector3.new(CalculatedCenter.X, targetY, CalculatedCenter.Z) end

    while State.Running and not State.Paused do
        if not checkPhaserInterrupt(CalculatedCenter) then
            if bp then bp.Position = Vector3.new(CalculatedCenter.X, targetY, CalculatedCenter.Z) end
            
            local inRange = getZombiesInBox(CalculatedCenter, State.Center1Radius)
            if #inRange == 0 then
                -- Caja vacía: completó la misión en Centro 1
                updateStatus("✅ Centro 1 limpio (caja vacía). Avanzando a Centro 2...")
                task.wait(0.5)
                break
            else
                updateStatus(string.format("Centro 1: Quieto esperando (%d en caja)...", #inRange))
            end
        end
        task.wait(0.25)
    end

    if not State.Running or State.Paused then return end

    -- PARADA 2: CENTRO 2 (QUIETO VERIFICANDO 10s EN CAJA DE 8 STUDS)
    updateStatus("🛑 Parada 2/3: Centro 2 (Quieto verificando 10s en caja 8 studs)...")
    flyMoveTo(Center2_Pos, 45, 2.5, true)
    if bp then bp.Position = Vector3.new(Center2_Pos.X, targetY, Center2_Pos.Z) end
    local verify2Start = tick()

    while State.Running and not State.Paused do
        if checkPhaserInterrupt(Center2_Pos) then
            verify2Start = tick()
        else
            if bp then bp.Position = Vector3.new(Center2_Pos.X, targetY, Center2_Pos.Z) end

            local inRange = getZombiesInBox(Center2_Pos, State.Center2Radius)
            if #inRange > 0 then
                -- Si entra un zombie en la caja, espera y reinicia los 10 segundos
                updateStatus(string.format("Centro 2: Zombie en caja (%d). Esperando...", #inRange))
                verify2Start = tick()
            else
                local elapsed = tick() - verify2Start
                updateStatus(string.format("Centro 2: Caja vacía. Verificando (%ds/10s)...", math.floor(elapsed)))
                if elapsed >= 10 then
                    updateStatus("✅ Centro 2 completado (10s limpio). Regresando a Centro 1...")
                    break
                end
            end
        end
        task.wait(0.25)
    end

    if not State.Running or State.Paused then return end

    -- PARADA 3: CENTRO 1 SEGUNDA VEZ (QUIETO RE-VERIFICANDO 10s EN CAJA DE 10 STUDS)
    updateStatus("🛑 Parada 3/3: Centro 1 (Quieto re-verificando 10s en caja 10 studs)...")
    flyMoveTo(CalculatedCenter, 45, 2.5, true)
    if bp then bp.Position = Vector3.new(CalculatedCenter.X, targetY, CalculatedCenter.Z) end
    local verify3Start = tick()

    while State.Running and not State.Paused do
        if checkPhaserInterrupt(CalculatedCenter) then
            verify3Start = tick()
        else
            if bp then bp.Position = Vector3.new(CalculatedCenter.X, targetY, CalculatedCenter.Z) end

            local inRange = getZombiesInBox(CalculatedCenter, State.Center1Radius)
            if #inRange > 0 then
                updateStatus(string.format("Centro 1: Zombie en caja (%d). Esperando...", #inRange))
                verify3Start = tick()
            else
                local elapsed = tick() - verify3Start
                updateStatus(string.format("Centro 1: Caja vacía. Re-verificando (%ds/10s)...", math.floor(elapsed)))
                if elapsed >= 10 then
                    updateStatus("✅ Las 3 paradas terminadas. ¡Iniciando cacería general como siempre!")
                    break
                end
            end
        end
        task.wait(0.25)
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
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        if fireproximityprompt then
            pcall(function() fireproximityprompt(prompt) end)
            pcall(function() fireproximityprompt(prompt, 0) end)
        end
    end
end)

-- FILTRO DE ASALTO COMPLETO (DETECCIÓN BASE ORIGINAL CON TODAS LAS PRIORIDADES)
local function getAnyTargetZombie(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local priorityScreamer, priorityScreamerRoot = nil, nil
    local priorityPhaser, priorityPhaserRoot = nil, nil
    local bestGlowingTarget, bestGlowingRoot = nil, nil
    local bestGlowingDist = math.huge
    local experimentTarget, experimentRoot = nil, nil

    for _, entity in ipairs(charFolder:GetChildren()) do
        local valid, eRoot = isValidZombieModel(entity)
        if valid then
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

                local isSpecial = isScreamer or isPhaser or isExperiment
                local isGlowing = (hasHighlight or isReactorAttr) and not isHibernating
                local isReactorZombie = isSpecial or isGlowing

                if isReactorZombie then
                    if isScreamer then
                        if not priorityScreamer then
                            priorityScreamer = entity
                            priorityScreamerRoot = eRoot
                        end
                    elseif isPhaser then
                        if not priorityPhaser then
                            priorityPhaser = entity
                            priorityPhaserRoot = eRoot
                        end
                    elseif isExperiment then
                        if not experimentTarget then
                            experimentTarget = entity
                            experimentRoot = eRoot
                        end
                    elseif dist < bestGlowingDist then
                        bestGlowingDist = dist
                        bestGlowingTarget = entity
                        bestGlowingRoot = eRoot
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
        local valid, eRoot = isValidZombieModel(entity)
        if valid then
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
    return screamers, phasers, others
end

-- CONTEO TOTAL DE ZOMBIES VIVOS
local function countLivingZombiesInReactor(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local count = 0
    for _, entity in ipairs(charFolder:GetChildren()) do
        local valid, eRoot = isValidZombieModel(entity)
        if valid then
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
        cMarker.Color = Color3.fromRGB(0, 255, 170)
        cMarker.Anchored = true
        cMarker.CanCollide = false
        cMarker.Position = CalculatedCenter
        cMarker.Parent = workspace
        Markers["Center1"] = cMarker
    end

    if Center2_Pos then
        local c2Marker = Instance.new("Part")
        c2Marker.Name = "NuclearCenter2Marker"
        c2Marker.Shape = Enum.PartType.Ball
        c2Marker.Size = Vector3.new(3, 3, 3)
        c2Marker.Material = Enum.Material.Neon
        c2Marker.Color = Color3.fromRGB(255, 170, 0)
        c2Marker.Anchored = true
        c2Marker.CanCollide = false
        c2Marker.Position = Center2_Pos
        c2Marker.Parent = workspace
        Markers["Center2"] = c2Marker
    end

    updateRangeVisuals()
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
    Default = true,
    Callback = function(Value) State.LootChests = Value end
})

-- PESTAÑA 2: CALIBRACIÓN
Tabs.Setup:AddSection("Coordenadas Predefinidas")

Tabs.Setup:AddButton({
    Title = "Restaurar Nuevas Coordenadas",
    Callback = function()
        Point2_Door = DEFAULT_DOOR
        CalculatedCenter = DEFAULT_CENTER
        Center2_Pos = DEFAULT_CENTER_2
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
Tabs.Settings:AddSection("3 Paradas Iniciales en Centros")

Tabs.Settings:AddToggle("InitialStopsToggle", {
    Title = "Activar 3 Paradas Iniciales",
    Description = "Limpia Centro 1 (10 studs), verifica Centro 2 (10s en 8 studs) y re-verifica Centro 1 (10s).",
    Default = true,
    Callback = function(Value) State.EnableInitialStops = Value end
})

Tabs.Settings:AddToggle("VisualRangeToggle", {
    Title = "Iluminar Rangos en Pantalla",
    Default = true,
    Callback = function(v)
        State.ShowRangeVisuals = v
        updateRangeVisuals()
    end
})

Tabs.Settings:AddSlider("Center1RadiusSlider", {
    Title = "Centro 1 - Rango de Limpieza (Studs)",
    Default = 10,
    Min = 6,
    Max = 30,
    Rounding = 0,
    Callback = function(v)
        State.Center1Radius = v
        updateRangeVisuals()
    end
})

Tabs.Settings:AddSlider("Center2RadiusSlider", {
    Title = "Centro 2 - Rango de Limpieza (Studs)",
    Default = 8,
    Min = 4,
    Max = 25,
    Rounding = 0,
    Callback = function(v)
        State.Center2Radius = v
        updateRangeVisuals()
    end
})

Tabs.Settings:AddSection("Tiempos de Espera Generales")

Tabs.Settings:AddSlider("WaveWaitSlider", {
    Title = "Espera en centro antes de cofres (Segundos)",
    Default = 10,
    Min = 5,
    Max = 45,
    Rounding = 0,
    Callback = function(Value) State.WaveWaitTime = Value end
})

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

-- ==============================================================================
-- MÁQUINA DE ESTADOS: BUCLE INFINITO DEL REACTOR
-- ==============================================================================
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

            -- REGISTRO DE HORARIO DE APERTURA SATISFACTORIA
            if doorWasPressed then
                State.ButtonSuccessTime = os.date("%H:%M:%S")
                updateTimestampsUI()
                Fluent:Notify({
                    Title = "🔘 Botón Activado",
                    Content = "Apertura confirmada: " .. State.ButtonSuccessTime,
                    Duration = 3
                })
            end

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
                -- 1. PRE-RUTINA AÑADIDA: LAS 3 PARADAS TOTALMENTE INMÓVILES
                if doorWasPressed and State.EnableInitialStops then
                    executeThreeInitialStops()
                else
                    updateStatus("[2/4] Accediendo al Centro del Reactor...")
                    flyMoveTo(CalculatedCenter, 42, 3, true)
                end

                -- 2. CACERÍA NORMAL DE SIEMPRE (RADIO 950 STUDS - INTACTA AL 100%)
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

                        -- CASO 1: SCREAMER (PRIORIDAD #1)
                        if targetType == "screamer" then
                            updateStatus("🚨 PRIORIDAD #1: Caza del SCREAMER para el dron...")
                            flyMoveTo(targetRoot.Position, 45, 6, true)
                            orbitTarget(targetRoot, 7, 55.0, 3)
                            flyMoveTo(CalculatedCenter, 42, 3, true)

                        -- CASO 2: PHASER (PRIORIDAD #2)
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
                                local targetY = Point2_Door.Y + 3.0

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
                                orbitTarget(targetRoot, 8, 44.0, 2.5)
                                flyMoveTo(CalculatedCenter, 42, 3, true)
                            end

                        -- CASO 3: RESTO DE ZOMBIES NUCLEARES RESPLANDECIENTES
                        else
                            updateStatus("Rodeando a " .. name .. " [Resplandor]...")
                            flyMoveTo(targetRoot.Position, 45, 6, true)
                            orbitTarget(targetRoot, 7, 55.0, 3)
                            if targetModel.Parent and targetRoot.Parent then
                                orbitTarget(targetRoot, 14, 60.0, 2.5)
                            end
                            flyMoveTo(CalculatedCenter, 42, 3, true)
                        end

                    else
                        -- NO HAY ZOMBIES: ESPERAR 10 SEGUNDOS EN EL CENTRO
                        screamerPhaserStuckTimer = nil
                        flyMoveTo(CalculatedCenter, 45, 3, true)
                        local roundCleared = true

                        for s = State.WaveWaitTime, 1, -1 do
                            if not State.Running or State.Paused then break end
                            updateStatus(string.format("Esperando en Centro (%02ds/10s)... Si no hay, a los cofres.", s))

                            local activeCount = countLivingZombiesInReactor(CalculatedCenter, State.DetectionRadius)
                            if activeCount > 0 then
                                roundCleared = false
                                updateStatus(string.format("¡Zombies detectados (%d)! Atacando...", activeCount))
                                break
                            end
                            task.wait(1)
                        end

                        -- Tras los 10 segundos limpios, IR DIRECTO A LOS COFRES
                        if roundCleared and State.Running and not State.Paused then
                            updateStatus("✅ Centro despejado tras 10s. ¡Yendo a los cofres!")
                            inCombat = false
                        end
                    end
                end

                -- 3. SAQUEO DE COFRES INMEDIATO TRAS CONFIRMAR EL CENTRO LIMPIO
                if State.LootChests and State.Running and not State.Paused then
                    lootAllChests()
                end

                -- 4. RECORRIDO DE LAS 3 GASOLINERAS TRAS SAQUEAR
                if State.Running and not State.Paused then
                    local cooldownStart = tick()
                    updateStatus(string.format("Reactor Despejado. Iniciando %d gasolineras...", #GAS_STATIONS))

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

            -- RETORNO A LA PUERTA Y REGISTRO DE HORARIO DE FINALIZACIÓN
            if State.Running and not State.Paused then
                State.CycleFinishTime = os.date("%H:%M:%S")
                updateTimestampsUI()
                Fluent:Notify({
                    Title = "✅ Ciclo Completado",
                    Content = "Finalizado con éxito a las: " .. State.CycleFinishTime,
                    Duration = 4
                })

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
    Title = "REACTOR HUB V10 LISTO",
    Content = "Cajas estrictas, paradas 100% inmóviles y cacería intacta.",
    Duration = 4
})

Window:SelectTab(1)
