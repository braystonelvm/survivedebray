-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- Offsets relativos locales respecto a la puerta (Derecha, Altura_Y, Adelante)
local LOCAL_CHEST_OFFSETS = {
    Vector3.new(57.3, -18.9, 43.1),   -- Cofre 1
    Vector3.new(60.3, -19.0, 67.2),   -- Cofres 2 y 3
    Vector3.new(60.3, -19.0, 67.2),   -- Cofres 4 y 5
    Vector3.new(-34.0, -38.7, 115.2), -- Cofre 6
    Vector3.new(-36.2, -38.7, 107.6)  -- Cofre 7
}

local Config = {
    -- Combate / Atropello Constante
    AtropelloEnabled = false,
    AtropelloMode = "Embestida Frontal Continua",
    MoveSpeed = 160,              -- Máximo por defecto
    ChargeDistance = 25,          -- Radio de ataque amplio por defecto
    AntiBloaterPush = true,

    -- Teletransporte de Ítems
    AutoSendItems = false,
    CollectRadius = 22,
    OnlyScrap = true,
    ChainTeleport = true,
    SingleTeleportLimit = false,
    BasePrevent = true,
    GeneratorSafeRadius = 160,
    SpreadRadius = 4,

    -- Ruta Amarilla / Vuelo
    PatrolEnabled = false,
    FlyPatrol = false,
    FlyHeight = 10,
    WaypointWaitTime = 0,         -- Mínimo 0 segundos

    -- Utilidades
    InstantGasStation = true,

    -- Reactor Nuclear (Con Vuelo Estable +10 studs)
    ReactorFarmEnabled = false,
    LootChests = true,
    ChestWaitTime = 1.3,
    ReactorResetWaitTime = 10.0,
    ReactorDetectionRadius = 130
}

local CurrentTarget = nil
local TargetHighlight = nil
local DeliveryPoints = {}
local Waypoints = {}
local WaypointMarkers = {}
local TeleportedTracker = {}

-- Variables de calibración del reactor
local ReactorDoorPos = nil
local ReactorCenterPos = nil
local ReactorForwardDir = nil
local NuclearMarkers = {}
local CalculatedChests = {}
local ChestMarkers = {}

local CachedGeneratorPos = nil

local function clearHighlight()
    if TargetHighlight then
        TargetHighlight:Destroy()
        TargetHighlight = nil
    end
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

local function getCurrentVehicle()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model")
        local mainPart = carModel and (carModel.PrimaryPart or seat) or seat
        return carModel, seat, mainPart
    end
    return nil, nil, nil
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 520),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Items = Window:AddTab({ Title = "Teletransporte", Icon = "box" }),
    Patrol = Window:AddTab({ Title = "Ruta Amarilla", Icon = "map-pin" }),
    Reactor = Window:AddTab({ Title = "Reactor Nuclear", Icon = "flame" }),
    Misc = Window:AddTab({ Title = "Utilidades", Icon = "wrench" })
}

-- PESTAÑA 1: COMBATE Y ATROPELLO CONSTANTE
Tabs.Combat:AddSection("Atropello Constante")

Tabs.Combat:AddToggle("AtropelloToggle", {
    Title = "Activar Atropello Constante",
    Description = "Acelera sin detenerse contra el zombie fijado",
    Default = false,
    Callback = function(Value) Config.AtropelloEnabled = Value end
})

Tabs.Combat:AddToggle("AntiBloaterToggle", {
    Title = "Repeler Bloaters (Anti-Explosión)",
    Default = true,
    Callback = function(Value) Config.AntiBloaterPush = Value end
})

Tabs.Combat:AddDropdown("AtropelloModeSelect", {
    Title = "Patrón de Ataque",
    Values = {"Embestida Frontal Continua", "Zigzag Lateral"},
    Default = "Embestida Frontal Continua",
    Callback = function(Value) Config.AtropelloMode = Value end
})

Tabs.Combat:AddSlider("ChargeDistSlider", {
    Title = "Distancia de Persecución (Studs)",
    Default = 25,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.ChargeDistance = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 160,
    Min = 25,
    Max = 160,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

-- PESTAÑA 2: TELETRANSPORTE
Tabs.Items:AddSection("Red de Puntos de Entrega (Bolitas)")

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Aquí",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local marker = Instance.new("Part")
        marker.Name = "CustomDropPoint"
        marker.Shape = Enum.PartType.Ball
        marker.Size = Vector3.new(2.5, 2.5, 2.5)
        marker.Material = Enum.Material.Neon
        marker.Color = Color3.fromRGB(0, 255, 170)
        marker.Anchored = true
        marker.CanCollide = false
        marker.CFrame = root.CFrame - Vector3.new(0, 1.5, 0)
        marker.Parent = workspace

        table.insert(DeliveryPoints, marker)
        table.clear(TeleportedTracker)

        Fluent:Notify({ Title = "Punto Agregado", Content = "Bolitas en la red: " .. #DeliveryPoints, Duration = 2 })
    end
})

Tabs.Items:AddButton({
    Title = "Borrar Todas las Bolitas",
    Callback = function()
        for _, p in ipairs(DeliveryPoints) do
            if p and p.Parent then p:Destroy() end
        end
        table.clear(DeliveryPoints)
        table.clear(TeleportedTracker)
        Fluent:Notify({ Title = "Red Reiniciada", Content = "Bolitas eliminadas.", Duration = 2 })
    end
})

Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "Activar Teletransporte de Ítems",
    Default = false,
    Callback = function(Value)
        Config.AutoSendItems = Value
        if not Value then table.clear(TeleportedTracker) end
    end
})

Tabs.Items:AddToggle("OnlyScrapToggle", {
    Title = "Solo Teletransportar Chatarra (Scrap)",
    Default = true,
    Callback = function(Value) Config.OnlyScrap = Value end
})

Tabs.Items:AddToggle("ChainTeleportToggle", {
    Title = "Permitir Teletransporte Continuo",
    Default = true,
    Callback = function(Value) Config.ChainTeleport = Value end
})

Tabs.Items:AddSection("Protección del Generador")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Default = true,
    Callback = function(Value) Config.BasePrevent = Value end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio de Seguridad del Generador (Studs)",
    Default = 160,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(Value) Config.GeneratorSafeRadius = Value end
})

-- PESTAÑA 3: RUTA AMARILLA
Tabs.Patrol:AddSection("Patrullaje y Vuelo (+10 studs)")

Tabs.Patrol:AddToggle("PatrolToggle", {
    Title = "Iniciar Patrullaje en Bucle",
    Default = false,
    Callback = function(Value) Config.PatrolEnabled = Value end
})

Tabs.Patrol:AddToggle("FlyPatrolToggle", {
    Title = "Volar sobre la Ruta (+10 studs)",
    Default = false,
    Callback = function(Value) Config.FlyPatrol = Value end
})

Tabs.Patrol:AddSlider("WaitTimeSlider", {
    Title = "Tiempo de espera en cada punto (Segundos)",
    Default = 0,
    Min = 0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(Value) Config.WaypointWaitTime = Value end
})

Tabs.Patrol:AddButton({
    Title = "Crear Punto Amarillo Aquí (Tecla 'K')",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local wpPos = root.Position
            table.insert(Waypoints, wpPos)

            local marker = Instance.new("Part")
            marker.Name = "WaypointMarker_" .. #Waypoints
            marker.Shape = Enum.PartType.Ball
            marker.Size = Vector3.new(2, 2, 2)
            marker.Material = Enum.Material.Neon
            marker.Color = Color3.fromRGB(255, 230, 0)
            marker.Anchored = true
            marker.CanCollide = false
            marker.Position = wpPos - Vector3.new(0, 1.5, 0)
            marker.Parent = workspace

            table.insert(WaypointMarkers, marker)
            Fluent:Notify({ Title = "Punto Amarillo Creado", Content = "Punto #" .. #Waypoints .. " guardado.", Duration = 1.5 })
        end
    end
})

Tabs.Patrol:AddButton({
    Title = "Borrar Todos los Puntos Amarillos",
    Callback = function()
        for _, m in ipairs(WaypointMarkers) do
            if m and m.Parent then m:Destroy() end
        end
        table.clear(Waypoints)
        table.clear(WaypointMarkers)
        Fluent:Notify({ Title = "Ruta Borrada", Content = "Puntos amarillos eliminados.", Duration = 2 })
    end
})

-- PESTAÑA 4: REACTOR NUCLEAR (CALIBRACIÓN POR TRAZO DE 2 SEGUNDOS)
Tabs.Reactor:AddSection("Calibración por Trazo (Muerto/Vivo)")

Tabs.Reactor:AddButton({
    Title = "Grabar Trazo hacia la Puerta (2 seg)",
    Description = "Párate cerca, presiona el botón y avanza 2 seg hacia la puerta",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local pStart = root.Position
        Fluent:Notify({
            Title = "Grabando Dirección...",
            Content = "¡Avanza hacia la puerta ahora mismo! (2 segundos)",
            Duration = 2
        })

        task.delay(2.0, function()
            local cNow = lp.Character
            local rNow = cNow and cNow:FindFirstChild("HumanoidRootPart")
            if not rNow then return end

            local pEnd = rNow.Position
            local delta = (pEnd - pStart)
            local horizontalDir = Vector3.new(delta.X, 0, delta.Z)

            if horizontalDir.Magnitude < 0.5 then
                Fluent:Notify({
                    Title = "Movimiento insuficiente",
                    Content = "Debes moverte hacia la puerta para fijar la dirección.",
                    Duration = 3
                })
                return
            end

            ReactorForwardDir = horizontalDir.Unit
            local rightDir = ReactorForwardDir:Cross(Vector3.new(0, 1, 0)).Unit
            ReactorDoorPos = pEnd
            ReactorCenterPos = pEnd + (ReactorForwardDir * 46.6)

            -- Limpiar marcadores viejos
            for _, m in pairs(NuclearMarkers) do
                if m and m.Parent then m:Destroy() end
            end
            for _, m in ipairs(ChestMarkers) do
                if m and m.Parent then m:Destroy() end
            end
            table.clear(NuclearMarkers)
            table.clear(CalculatedChests)
            table.clear(ChestMarkers)

            -- Marcador en la puerta
            local dMarker = Instance.new("Part")
            dMarker.Name = "NuclearDoorMarker"
            dMarker.Shape = Enum.PartType.Ball
            dMarker.Size = Vector3.new(3, 3, 3)
            dMarker.Material = Enum.Material.Neon
            dMarker.Color = Color3.fromRGB(255, 120, 0)
            dMarker.Anchored = true
            dMarker.CanCollide = false
            dMarker.Position = ReactorDoorPos
            dMarker.Parent = workspace
            NuclearMarkers["Door"] = dMarker

            -- Marcador en el centro
            local cMarker = Instance.new("Part")
            cMarker.Name = "NuclearCenterMarker"
            cMarker.Shape = Enum.PartType.Ball
            cMarker.Size = Vector3.new(3, 3, 3)
            cMarker.Material = Enum.Material.Neon
            cMarker.Color = Color3.fromRGB(255, 80, 0)
            cMarker.Anchored = true
            cMarker.CanCollide = false
            cMarker.Position = ReactorCenterPos
            cMarker.Parent = workspace
            NuclearMarkers["Center"] = cMarker

            -- Calcular los 7 cofres subterráneos
            for i, offset in ipairs(LOCAL_CHEST_OFFSETS) do
                local worldPos = ReactorDoorPos + (rightDir * offset.X) + (ReactorForwardDir * offset.Z) + Vector3.new(0, offset.Y, 0)
                table.insert(CalculatedChests, worldPos)

                local marker = Instance.new("Part")
                marker.Name = "RotatedChestMarker_" .. i
                marker.Shape = Enum.PartType.Ball
                marker.Size = Vector3.new(2.2, 2.2, 2.2)
                marker.Material = Enum.Material.Neon
                marker.Color = Color3.fromRGB(0, 200, 255)
                marker.Anchored = true
                marker.CanCollide = false
                marker.Position = worldPos
                marker.Parent = workspace
                table.insert(ChestMarkers, marker)
            end

            Fluent:Notify({
                Title = "Reactor Calibrado",
                Content = "Trazo completado. Puerta, centro y 7 cofres fijados.",
                Duration = 4
            })
        end)
    end
end)

Tabs.Reactor:AddSection("Automatización")

Tabs.Reactor:AddToggle("NuclearFarmToggle", {
    Title = "Iniciar Saqueo Automático del Reactor",
    Default = false,
    Callback = function(Value) Config.ReactorFarmEnabled = Value end
})

Tabs.Reactor:AddToggle("LootChestsToggle", {
    Title = "Saquear 7 Cofres tras Limpiar",
    Default = true,
    Callback = function(Value) Config.LootChests = Value end
})

Tabs.Reactor:AddSlider("ChestWaitSlider", {
    Title = "Tiempo en cada cofre (Seg)",
    Default = 1.3,
    Min = 0.5,
    Max = 4.0,
    Rounding = 1,
    Callback = function(Value) Config.ChestWaitTime = Value end
})

Tabs.Reactor:AddSlider("NuclearWaitSlider", {
    Title = "Tiempo fuera del bioma (Seg)",
    Default = 10.0,
    Min = 5.0,
    Max = 60.0,
    Rounding = 0,
    Callback = function(Value) Config.ReactorResetWaitTime = Value end
})

-- PESTAÑA 5: UTILIDADES
Tabs.Misc:AddSection("Automatizaciones Ligeras")

Tabs.Misc:AddToggle("InstantGasToggle", {
    Title = "Surtidor Instantáneo (Cero Lag / Móvil)",
    Default = true,
    Callback = function(Value) Config.InstantGasStation = Value end
})

-- 2. BOTÓN FLOTANTE CÍRCULAR (DRAGGABLE CON POSICIÓN BAJA)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomHubFloatingBtn"
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
FloatBtn.Name = "DraggableToggle"
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
-- Ubicación predeterminada más abajo (Y = 0.40)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isDragging = false
local dragStart = nil
local startPos = nil

FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = true
        dragStart = input.Position
        startPos = FloatBtn.Position
    end
end)

FloatBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        FloatBtn.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- 3. NOCLIP CONSTANTE EN MODO REACTOR
RunService.Stepped:Connect(function()
    if Config.ReactorFarmEnabled then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

-- Vuelo reforzado anti-caídas (+10 studs fijos)
local function flyMoveTo(targetPos, speed, stopDistance, applyElevation)
    stopDistance = stopDistance or 3.5
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return false end

    -- Asegurar altura flotante constante
    local elevatedHeight = applyElevation and 10 or 0
    local finalDest = targetPos + Vector3.new(0, elevatedHeight, 0)
    local timeout = tick() + 25

    -- Ancla de fuerza física para eliminar la gravedad
    local bodyVel = root:FindFirstChild("HubFlyVelocity")
    if not bodyVel then
        bodyVel = Instance.new("BodyVelocity")
        bodyVel.Name = "HubFlyVelocity"
        bodyVel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bodyVel.Parent = root
    end

    while Config.ReactorFarmEnabled and tick() < timeout do
        RunService.Heartbeat:Wait()
        local currentPos = root.Position
        local diff = (finalDest - currentPos)
        local dist = diff.Magnitude

        if dist <= stopDistance then
            bodyVel.Velocity = Vector3.new(0, 0, 0)
            return true
        end

        local dir = diff.Unit
        bodyVel.Velocity = dir * speed
    end

    if bodyVel then bodyVel.Velocity = Vector3.new(0, 0, 0) end
    return false
end

local function cleanupFlyVelocity()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if root then
        local bodyVel = root:FindFirstChild("HubFlyVelocity")
        if bodyVel then bodyVel:Destroy() end
    end
end

local function getActivePhaser(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character then
            local name = entity.Name:lower()
            if name:find("phaser") or name:find("ghost") or name:find("fantasma") then
                local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
                local eHum = entity:FindFirstChildOfClass("Humanoid")
                if eRoot and (not eHum or eHum.Health > 0) then
                    local d = (eRoot.Position - centerPos).Magnitude
                    if d <= maxDist then return entity, eRoot end
                end
            end
        end
    end
    return nil, nil
end

local function countLivingZombiesInReactor(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local count = 0
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character then
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

-- 4. BUCLE MAESTRO: REACTOR Y RESET DE 420 STUDS
task.spawn(function()
    while true do
        task.wait(0.5)

        if Config.ReactorFarmEnabled then
            if not ReactorDoorPos or not ReactorCenterPos or not ReactorForwardDir then
                Fluent:Notify({ Title = "Sin Calibrar", Content = "Presiona 'Grabar Trazo hacia la Puerta' primero.", Duration = 3 })
                Config.ReactorFarmEnabled = false
            else
                -- 1. Puerta (a 10 studs de altura)
                flyMoveTo(ReactorDoorPos, 35, 4, true)
                task.wait(0.5)

                for _, prompt in ipairs(workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - ReactorDoorPos).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
                task.wait(1.5)

                -- 2. Centro (+10 studs suspendido)
                flyMoveTo(ReactorCenterPos, 40, 3, true)

                -- 3. Cacería de Phasers
                local inCombat = true
                local clearStreak = 0

                while Config.ReactorFarmEnabled and inCombat do
                    task.wait(0.3)
                    local phaserModel, phaserRoot = getActivePhaser(ReactorCenterPos, Config.ReactorDetectionRadius)

                    if phaserModel and phaserRoot then
                        clearStreak = 0
                        while Config.ReactorFarmEnabled and phaserModel.Parent and phaserRoot.Parent do
                            local eHum = phaserModel:FindFirstChildOfClass("Humanoid")
                            if eHum and eHum.Health <= 0 then break end
                            flyMoveTo(phaserRoot.Position, 38, 5, true)
                            task.wait(0.15)
                        end
                        flyMoveTo(ReactorCenterPos, 40, 3, true)
                    else
                        local remaining = countLivingZombiesInReactor(ReactorCenterPos, Config.ReactorDetectionRadius)
                        if remaining == 0 then
                            clearStreak = clearStreak + 1
                            if clearStreak >= 3 then inCombat = false end
                        else
                            clearStreak = 0
                        end
                    end
                end

                -- 4. Ruta de los 7 Cofres Subterráneos
                if Config.ReactorFarmEnabled and Config.LootChests and #CalculatedChests > 0 then
                    Fluent:Notify({ Title = "Reactor Despejado", Content = "Recorriendo los 7 cofres subterráneos...", Duration = 3 })
                    for _, cPos in ipairs(CalculatedChests) do
                        if not Config.ReactorFarmEnabled then break end
                        flyMoveTo(cPos, 38, 2.5, false)
                        task.wait(Config.ChestWaitTime)
                    end
                end

                -- 5. Salir 420 studs hacia afuera del bioma para reiniciar
                if Config.ReactorFarmEnabled then
                    Fluent:Notify({ Title = "Saqueo Completo", Content = "Alejándose 420 studs para descargar bioma...", Duration = 3 })
                    local resetPos = ReactorDoorPos - (ReactorForwardDir * 420) + Vector3.new(0, 15, 0)
                    flyMoveTo(resetPos, 60, 6, false)
                    task.wait(Config.ReactorResetWaitTime)
                end
            end
        else
            cleanupFlyVelocity()
        end
    end
end)

-- 5. BUCLE DE ATROPELLO FRONTAL CONSTANTE (SIN FRENOS)
RunService.Heartbeat:Connect(function()
    if not Config.AtropelloEnabled or not CurrentTarget or Config.ReactorFarmEnabled then return end

    local car, seat, mainPart = getCurrentVehicle()
    local controlledPart = mainPart or (lp.Character and lp.Character:FindFirstChild("HumanoidRootPart"))
    if not controlledPart then return end

    local targetPart = (CurrentTarget:IsA("BasePart") and CurrentTarget) or (CurrentTarget:IsA("Model") and (CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")))
    if not targetPart or not targetPart.Parent then return end

    local targetPos = targetPart.Position
    local myPos = controlledPart.Position
    local toZombie = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = toZombie.Magnitude

    local targetName = (CurrentTarget.Name):lower()
    local isBloater = targetName:find("bloater") or targetName:find("boom") or targetName:find("explo")
    if dist < 8 and isBloater and Config.AntiBloaterPush then
        targetPart.AssemblyLinearVelocity = Vector3.new(toZombie.Unit.X * 50, 85, toZombie.Unit.Z * 50)
    end

    if Config.AtropelloMode == "Embestida Frontal Continua" then
        if seat then
            seat.Throttle = 1
        end

        local moveDir = toZombie.Unit
        local vel = moveDir * Config.MoveSpeed
        controlledPart.AssemblyLinearVelocity = Vector3.new(vel.X, controlledPart.AssemblyLinearVelocity.Y, vel.Z)
    else
        local cf = targetPart.CFrame
        local side = (math.sin(tick() * 3) > 0) and 1 or -1
        local destination = targetPos + (cf.RightVector * (side * 14))
        local dir = (destination - myPos)
        local hDir = Vector3.new(dir.X, 0, dir.Z)

        if hDir.Magnitude > 1.5 then
            local vel = hDir.Unit * Config.MoveSpeed
            controlledPart.AssemblyLinearVelocity = Vector3.new(vel.X, controlledPart.AssemblyLinearVelocity.Y, vel.Z)
        end
    end
end)

-- 6. BUCLE DE TELETRANSPORTE OPTIMIZADO (CERO LAG)
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getGeneratorPosition()
    if CachedGeneratorPos then return CachedGeneratorPos end
    local gen = workspace:FindFirstChild("Generator") or workspace:FindFirstChild("Center")
    if gen then
        local p = (gen:IsA("Model") and (gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart"))) or gen
        if p then 
            CachedGeneratorPos = p.Position 
            return CachedGeneratorPos
        end
    end
    return nil
end

local function getNextBestDropPoint(itemPos)
    local genPos = getGeneratorPosition()
    local bestPoint = nil
    local currentDistToGen = genPos and (itemPos - genPos).Magnitude or math.huge
    local shortestDistToItem = math.huge

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local distItemToPoint = (itemPos - pt.Position).Magnitude
            if genPos and Config.ChainTeleport then
                local pointDistToGen = (pt.Position - genPos).Magnitude
                if pointDistToGen < currentDistToGen and distItemToPoint > 4 then
                    if distItemToPoint < shortestDistToItem then
                        shortestDistToItem = distItemToPoint
                        bestPoint = pt
                    end
                end
            else
                if distItemToPoint < shortestDistToItem and distItemToPoint > 4 then
                    shortestDistToItem = distItemToPoint
                    bestPoint = pt
                end
            end
        end
    end

    if not bestPoint and #DeliveryPoints > 0 then
        for _, pt in ipairs(DeliveryPoints) do
            if pt and pt.Parent and (itemPos - pt.Position).Magnitude > 4 then
                bestPoint = pt
                break
            end
        end
    end
    return bestPoint
end

task.spawn(function()
    while true do
        task.wait(0.35)
        if Config.AutoSendItems and #DeliveryPoints > 0 then
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                overlapParams.FilterDescendantsInstances = {char}
                local partsNearby = workspace:GetPartBoundsInRadius(root.Position, Config.CollectRadius, overlapParams)
                local processedCount = 0

                for _, hitPart in ipairs(partsNearby) do
                    if processedCount >= 4 then break end

                    if not hitPart.Anchored and not hitPart:FindFirstAncestorOfClass("Humanoid") then
                        local itemModel = hitPart:FindFirstAncestorOfClass("Model")
                        local targetEntity = (itemModel and itemModel.Parent ~= workspace.Characters and itemModel) or hitPart
                        local rootPos = (targetEntity:IsA("Model") and targetEntity:GetPivot().Position) or targetEntity.Position

                        local nameLower = (targetEntity.Name):lower()
                        local isScrap = nameLower:find("scrap") or nameLower:find("chatarra") or nameLower:find("metal") or nameLower:find("barrel")

                        if not Config.OnlyScrap or isScrap then
                            local genPos = getGeneratorPosition()
                            local insideBase = false
                            if Config.BasePrevent and genPos then
                                if (rootPos - genPos).Magnitude <= Config.GeneratorSafeRadius then
                                    insideBase = true
                                end
                            end

                            local canTeleport = not insideBase
                            if Config.SingleTeleportLimit and TeleportedTracker[targetEntity] then
                                canTeleport = false
                            end

                            if canTeleport then
                                local nextPoint = getNextBestDropPoint(rootPos)

                                if nextPoint then
                                    processedCount = processedCount + 1
                                    TeleportedTracker[targetEntity] = true

                                    local angle = math.random() * math.pi * 2
                                    local dist = math.random() * Config.SpreadRadius
                                    local destPos = nextPoint.Position + Vector3.new(math.cos(angle) * dist, 1.2, math.sin(angle) * dist)

                                    if targetEntity:IsA("Model") then
                                        targetEntity:PivotTo(CFrame.new(destPos))
                                    else
                                        targetEntity.CFrame = CFrame.new(destPos)
                                    end

                                    for _, p in ipairs(targetEntity:GetDescendants()) do
                                        if p:IsA("BasePart") then
                                            p.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
                                            p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                                        end
                                    end
                                    if targetEntity:IsA("BasePart") then
                                        targetEntity.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
                                        targetEntity.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
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

-- 7. BUCLE DE PATRULLA AMARILLA
task.spawn(function()
    while true do
        task.wait(0.2)
        if Config.PatrolEnabled and #Waypoints > 0 and not Config.ReactorFarmEnabled then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if hum and root and hum.Health > 0 then
                for _, targetPos in ipairs(Waypoints) do
                    if not Config.PatrolEnabled or Config.ReactorFarmEnabled then break end

                    local finalDestination = Config.FlyPatrol and (targetPos + Vector3.new(0, Config.FlyHeight, 0)) or targetPos
                    local reached = false
                    local timeout = tick() + 20

                    while Config.PatrolEnabled and not reached and tick() < timeout and not Config.ReactorFarmEnabled do
                        task.wait(0.05)

                        if Config.FlyPatrol then
                            local dir = (finalDestination - root.Position)
                            if dir.Magnitude <= 3.5 then
                                reached = true
                                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                            else
                                root.AssemblyLinearVelocity = dir.Unit * Config.MoveSpeed
                            end
                        else
                            hum:MoveTo(targetPos)
                            if (root.Position - targetPos).Magnitude <= 4 then reached = true end
                        end
                    end

                    if Config.PatrolEnabled and not Config.ReactorFarmEnabled then
                        if Config.FlyPatrol then root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
                        if Config.WaypointWaitTime > 0 then
                            task.wait(Config.WaypointWaitTime)
                        end
                    end
                end
            end
        end
    end
end)

-- 8. SURTIDOR INSTANTÁNEO
ProximityPromptService.PromptShown:Connect(function(prompt)
    if not Config.InstantGasStation then return end

    local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
        prompt.HoldDuration = 0
        fireproximityprompt(prompt)
    end
end)

-- 9. SELECCIÓN CON TECLAS
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.T then
        local target = mouse.Target
        if target then
            local model = target:FindFirstAncestorOfClass("Model")
            local chosen = (model and model ~= lp.Character and model ~= workspace and model) or target
            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)
                Fluent:Notify({ Title = "Objetivo Fijado", Content = "Fijado: " .. chosen.Name, Duration = 2 })
            end
        end
    end

    if input.KeyCode == Enum.KeyCode.Y then
        CurrentTarget = nil
        clearHighlight()
        Fluent:Notify({ Title = "Objetivo Cancelado", Content = "Se desmarcó el objetivo.", Duration = 2 })
    end

    if input.KeyCode == Enum.KeyCode.K then
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local wpPos = root.Position
            table.insert(Waypoints, wpPos)

            local marker = Instance.new("Part")
            marker.Name = "WaypointMarker_" .. #Waypoints
            marker.Shape = Enum.PartType.Ball
            marker.Size = Vector3.new(2, 2, 2)
            marker.Material = Enum.Material.Neon
            marker.Color = Color3.fromRGB(255, 230, 0)
            marker.Anchored = true
            marker.CanCollide = false
            marker.Position = wpPos - Vector3.new(0, 1.5, 0)
            marker.Parent = workspace

            table.insert(WaypointMarkers, marker)
            Fluent:Notify({ Title = "Punto Amarillo Creado", Content = "Punto #" .. #Waypoints .. " guardado.", Duration = 1.5 })
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB LISTO",
    Content = "Calibración por trazo de 2 seg y vuelo reforzado listos.",
    Duration = 4
})

Window:SelectTab(1)
