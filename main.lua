-- ==============================================================================
-- REACTOR NUCLEAR HUB - APERTURA EXACTA, TIMER REAL Y 6 GASOLINERAS CÍCLICAS
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer

-- NUEVAS COORDENADAS DE LA PARTIDA
local DEFAULT_DOOR = Vector3.new(-54.2, 3.5, 1140.1)
local DEFAULT_CENTER = Vector3.new(-1.4, 2.7, 1120.5)

-- 6 GASOLINERAS REGISTRADAS
local GAS_STATIONS = {
    Vector3.new(-581.7, 2.8, 1071.8),
    Vector3.new(-177.8, 2.3, 800.0),
    Vector3.new(-400.0, 2.4, 415.3),
    Vector3.new(-161.0, 2.3, 176.3),
    Vector3.new(421.0, 2.6, 438.9),
    Vector3.new(341.2, 2.0, 782.3)
}

local State = {
    Running = false,
    Paused = false,
    CurrentStatus = "Inactivo",
    LootChests = false,       -- DESACTIVADO POR DEFECTO
    ChestWaitTime = 0.8,
    BaseNuclearWait = 900,    -- 15 minutos de espera en gasolineras
    GasStationStop = 3.0,     -- 3 segundos de parada por gasolinera
    DetectionRadius = 300     -- 300 studs a la redonda
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

-- NOCLIP CONSTANTE (100% ACTIVO)
RunService.Stepped:Connect(function()
    if State.Running and not State.Paused then
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

-- ANCLAJE PREVENTIVO INMEDIATO
local function secureFlightStart()
    local root = getRootPart()
    if not root then return false end

    local safeY = Point2_Door.Y + 6.0
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    local bodyPos = getOrCreatePhysics(root, safeY)
    bodyPos.Position = Vector3.new(root.Position.X, safeY, root.Position.Z)
    task.wait(0.15)
    return true
end

-- VUELO HACIA UN DESTINO (VOLANDO EL 100% DEL TIEMPO)
local function flyMoveTo(targetPos, speed, stopDistance, lockAltitudeToDoor)
    stopDistance = stopDistance or 3.5
    local root = getRootPart()
    if not root then return false end

    local targetY = targetPos.Y + 6.0
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

-- ATAQUE CIRCULAR (ÓRBITA ALREDEDOR DEL ZOMBIE)
local function orbitTarget(targetRoot, radius, duration, speed)
    local root = getRootPart()
    if not root or not targetRoot or not targetRoot.Parent or not Point2_Door then return end

    local targetY = Point2_Door.Y + 6.0
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

-- APERTURA DIRECTA Y ROBUSTA DE LA PUERTA (DATOS DEL REPORTE)
local function openNuclearDoorDirect()
    local opened = false

    -- 1. Intento por ruta directa extraída en el reporte
    local map = workspace:FindFirstChild("Map")
    local tiles = map and map:FindFirstChild("Tiles")
    local reactor = tiles and tiles:FindFirstChild("Nuclear Reactor")
    local entrance = reactor and reactor:FindFirstChild("Entrance")
    local directPrompt = entrance and entrance:FindFirstChildOfClass("ProximityPrompt")

    if directPrompt then
        directPrompt.HoldDuration = 0
        directPrompt.RequiresLineOfSight = false
        directPrompt.MaxActivationDistance = 50
        fireproximityprompt(directPrompt)
        opened = true
    end

    -- 2. Barrido de respaldo para cuentas en inglés ('Open') o español ('Abrir')
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local obj = prompt.ObjectText:lower()
            local act = prompt.ActionText:lower()
            local pName = prompt.Parent and prompt.Parent.Name:lower()

            if obj:find("nuclear") or pName == "entrance" or act == "open" or act == "abrir" then
                prompt.HoldDuration = 0
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 50
                fireproximityprompt(prompt)
                opened = true
            end
        end
    end

    return opened
end

-- LECTURA DEL CONTADOR DE ENFRIAMIENTO (DATOS DEL REPORTE)
local function getDoorTimerText()
    -- 1. Lectura directa del TextLabel "Timer" dentro del SurfaceGui de Entrance
    local map = workspace:FindFirstChild("Map")
    local tiles = map and map:FindFirstChild("Tiles")
    local reactor = tiles and tiles:FindFirstChild("Nuclear Reactor")
    local entrance = reactor and reactor:FindFirstChild("Entrance")

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

    -- 2. Búsqueda de respaldo en todos los SurfaceGui de Entrance
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

    return nil -- Puerta lista para abrirse
end

-- SURTIDOR DE GASOLINA
local function interactWithGasPump(stationPos)
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local pPart = prompt.Parent
            local pos = pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition)
            if pos and (pos - stationPos).Magnitude <= 24 then
                prompt.HoldDuration = 0
                prompt.RequiresLineOfSight = false
                fireproximityprompt(prompt)
            end
        end
    end
end

ProximityPromptService.PromptShown:Connect(function(prompt)
    local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
        prompt.HoldDuration = 0
        fireproximityprompt(prompt)
    end
end)

-- DETECCIÓN DE ZOMBIES EN EL REACTOR
local function getAnyTargetZombie(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local bestTarget = nil
    local bestRoot = nil
    local bestDist = math.huge
    local priorityPhaser = nil
    local priorityRoot = nil

    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
            local eHum = entity:FindFirstChildOfClass("Humanoid")

            if eRoot and (not eHum or eHum.Health > 0) then
                local dist = (eRoot.Position - centerPos).Magnitude
                if dist <= maxDist then
                    local name = entity.Name:lower()
                    if name:find("phaser") or name:find("ghost") or name:find("fantasma") then
                        priorityPhaser = entity
                        priorityRoot = eRoot
                        break
                    elseif dist < bestDist then
                        bestDist = dist
                        bestTarget = entity
                        bestRoot = eRoot
                    end
                end
            end
        end
    end

    if priorityPhaser then
        return priorityPhaser, priorityRoot
    end
    return bestTarget, bestRoot
end

local function countLivingZombiesInReactor(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local count = 0
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
            local eHum = entity:FindFirstChildOfClass("Humanoid")
            if eRoot and (not eHum or eHum.Health > 0) then
                if (eRoot.Position - centerPos).Magnitude <= maxDist then
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
        secureFlightStart()
        State.Running = true
        State.Paused = false
        updateStatus("Iniciado con vuelo seguro.")
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
    Default = 3,
    Min = 1,
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

-- MÁQUINA DE ESTADOS: BUCLE INFINITO
task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            local root = getRootPart()
            local distToCenter = root and (root.Position - CalculatedCenter).Magnitude or 999
            local alreadyInside = distToCenter < 130

            -- FASE 1 Y 2: VOLAR A LA PUERTA Y ABRIRLA
            if not alreadyInside then
                updateStatus("[1/4] Volando a la Entrada del Reactor...")
                flyMoveTo(Point2_Door, 45, 4, true)
                task.wait(0.3)

                -- Verificar si el Timer en SurfaceGui muestra tiempo activo
                local cdText = getDoorTimerText()
                while State.Running and not State.Paused and cdText do
                    updateStatus("Reactor en Cooldown: " .. cdText)
                    task.wait(2)
                    cdText = getDoorTimerText()
                end

                if not State.Running then break end

                -- Intentar abrir la puerta
                updateStatus("[2/4] Abriendo Puerta (Open / Abrir)...")
                for _ = 1, 4 do
                    openNuclearDoorDirect()
                    task.wait(0.3)
                end
                task.wait(1.0)
            end

            -- FASE 3: ENTRAR AL CENTRO Y BARRER ZOMBIES
            flyMoveTo(CalculatedCenter, 42, 3, true)
            updateStatus("[3/4] Limpiando Reactor Nuclear (Radio 300)...")

            local inCombat = true
            local clearStreak = 0

            while State.Running and not State.Paused and inCombat do
                task.wait(0.2)
                local targetModel, targetRoot = getAnyTargetZombie(CalculatedCenter, State.DetectionRadius)

                if targetModel and targetRoot then
                    clearStreak = 0
                    local name = targetModel.Name
                    updateStatus("Rodeando a " .. name .. " para el dron...")

                    flyMoveTo(targetRoot.Position, 45, 6, true)

                    -- 1. Órbita cerrada (25s)
                    orbitTarget(targetRoot, 7, 25.0, 3)

                    -- 2. Órbita amplia (30s)
                    if targetModel.Parent and targetRoot.Parent then
                        orbitTarget(targetRoot, 14, 30.0, 2.5)
                    end

                    flyMoveTo(CalculatedCenter, 42, 3, true)
                else
                    local remaining = countLivingZombiesInReactor(CalculatedCenter, State.DetectionRadius)
                    updateStatus(string.format("Verificando sala... Restantes: %d", remaining))

                    if remaining == 0 then
                        clearStreak = clearStreak + 1
                        if clearStreak >= 3 then
                            inCombat = false
                        end
                    else
                        clearStreak = 0
                    end
                end
            end

            -- FASE 4: PATRULLA CÍCLICA POR LAS 6 GASOLINERAS DURANTE LOS 15 MINUTOS
            if State.Running and not State.Paused then
                local cooldownStart = tick()
                updateStatus("Reactor Despejado. Iniciando ciclo de 6 gasolineras...")

                while State.Running and not State.Paused and (tick() - cooldownStart < State.BaseNuclearWait) do
                    for idx, gasPos in ipairs(GAS_STATIONS) do
                        if not State.Running or State.Paused then break end
                        if (tick() - cooldownStart >= State.BaseNuclearWait) then break end

                        local timeLeft = math.max(0, math.floor(State.BaseNuclearWait - (tick() - cooldownStart)))
                        local mins = math.floor(timeLeft / 60)
                        local secs = timeLeft % 60

                        updateStatus(string.format("[Gas %d/6] Volando... | Cooldown: %02dm %02ds", idx, mins, secs))
                        flyMoveTo(gasPos, 58, 4, false)
                        task.wait(0.2)

                        -- Surtir gasolina y esperar 3 segundos
                        updateStatus(string.format("[Gas %d/6] Surtidor activo (3s)... | Cooldown: %02dm %02ds", idx, mins, secs))
                        interactWithGasPump(gasPos)
                        task.wait(State.GasStationStop)
                    end
                end

                -- Concluidos los 15 minutos, regresar a la puerta e iniciar el bucle de nuevo
                if State.Running and not State.Paused then
                    updateStatus("15 min completados. Regresando a la Puerta del Reactor...")
                    flyMoveTo(Point2_Door, 60, 4, true)
                    task.wait(1.5)
                end
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Fluent:Notify({
    Title = "REACTOR HUB LISTO",
    Content = "Apertura exacta y ciclo de 6 gasolineras configurados.",
    Duration = 4
})

Window:SelectTab(1)
