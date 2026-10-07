-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE (v3.2 AUTO-TRACK & HOVERCAR)
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
    -- Combate / Auto
    ZigZagEnabled = false,
    SwitchInterval = 1.0,
    LateralDist = 12,
    MoveSpeed = 55,
    VehicleHoverMode = false,   -- Truco de llantas y giro omnidireccional
    VehicleFrontRamMode = true,  -- Enfoque frontal y reversa para máximo daño

    -- Teletransporte Scrap
    AutoSendItems = false,
    CollectRadius = 24,
    OnlyScrap = true,
    ChainTeleport = true,
    SingleTeleportLimit = false,
    BasePrevent = true,
    GeneratorSafeRadius = 160,
    SpreadRadius = 4,

    -- Grabador Automático de Puntos
    AutoRecordScrap = false,
    ScrapStepDist = 35,          -- Distancia entre bolitas de chatarra
    AutoRecordPatrol = false,
    PatrolStepDist = 25,         -- Distancia entre puntos amarillos

    -- Ruta
    PatrolEnabled = false,
    FlyPatrol = false,
    FlyHeight = 10,
    WaypointWaitTime = 2.0,

    -- Reactor
    ReactorFarmEnabled = false,
    LootChests = true,
    ChestWaitTime = 1.3,
    ReactorResetWaitTime = 10.0,
    ReactorDetectionRadius = 130,

    -- Utilidades
    InstantGasStation = true
}

local CurrentTarget = nil
local TargetHighlight = nil
local DeliveryPoints = {}
local Waypoints = {}
local WaypointMarkers = {}
local TeleportedTracker = {}

-- Variables para auto-registro
local LastScrapRecordPos = nil
local LastPatrolRecordPos = nil

-- Variables del Reactor
local ReactorAnchorCF = nil
local NuclearMarker = nil
local CalculatedCenter = nil
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

-- Función para agregar punto de entrega de chatarra
local function addDeliveryPoint(pos)
    local marker = Instance.new("Part")
    marker.Name = "CustomDropPoint"
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(2.5, 2.5, 2.5)
    marker.Material = Enum.Material.Neon
    marker.Color = Color3.fromRGB(0, 255, 170)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Position = pos - Vector3.new(0, 1.5, 0)
    marker.Parent = workspace

    table.insert(DeliveryPoints, marker)
    table.clear(TeleportedTracker)
end

-- Función para agregar punto de patrulla amarillo
local function addPatrolPoint(pos)
    table.insert(Waypoints, pos)

    local marker = Instance.new("Part")
    marker.Name = "WaypointMarker_" .. #Waypoints
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(2, 2, 2)
    marker.Material = Enum.Material.Neon
    marker.Color = Color3.fromRGB(255, 230, 0)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Position = pos - Vector3.new(0, 1.5, 0)
    marker.Parent = workspace

    table.insert(WaypointMarkers, marker)
end

-- Cálculo de todo el reactor a partir de 1 solo punto con orientación
local function setReactorFromSinglePoint(cf)
    ReactorAnchorCF = cf
    local doorPos = cf.Position
    local forwardDir = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
    local rightDir = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z).Unit

    CalculatedCenter = doorPos + (forwardDir * 46.6)

    if NuclearMarker and NuclearMarker.Parent then NuclearMarker:Destroy() end
    for _, m in ipairs(ChestMarkers) do
        if m and m.Parent then m:Destroy() end
    end
    table.clear(CalculatedChests)
    table.clear(ChestMarkers)

    NuclearMarker = Instance.new("Part")
    NuclearMarker.Name = "NuclearDoorMarker"
    NuclearMarker.Size = Vector3.new(3, 1, 3)
    NuclearMarker.CFrame = cf
    NuclearMarker.Material = Enum.Material.Neon
    NuclearMarker.Color = Color3.fromRGB(255, 120, 0)
    NuclearMarker.Anchored = true
    NuclearMarker.CanCollide = false
    NuclearMarker.Parent = workspace

    for i, offset in ipairs(LOCAL_CHEST_OFFSETS) do
        local worldPos = doorPos + (rightDir * offset.X) + (forwardDir * offset.Z) + Vector3.new(0, offset.Y, 0)
        table.insert(CalculatedChests, worldPos)

        local m = Instance.new("Part")
        m.Name = "AutoChestMarker_" .. i
        m.Shape = Enum.PartType.Ball
        m.Size = Vector3.new(2.2, 2.2, 2.2)
        m.Material = Enum.Material.Neon
        m.Color = Color3.fromRGB(0, 200, 255)
        m.Anchored = true
        m.CanCollide = false
        m.Position = worldPos
        m.Parent = workspace
        table.insert(ChestMarkers, m)
    end
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
    Patrol = Window:AddTab({ Title = "Ruta y Mapa", Icon = "map-pin" }),
    Reactor = Window:AddTab({ Title = "Reactor Nuclear", Icon = "flame" }),
    Misc = Window:AddTab({ Title = "Utilidades", Icon = "wrench" })
}

-- PESTAÑA 1: COMBATE Y AUTO
Tabs.Combat:AddSection("Físicas del Auto / Atropello Frontal")

Tabs.Combat:AddToggle("VehicleHoverToggle", {
    Title = "Modo Auto Deslizador (Físicas ZHUB)",
    Description = "Desactiva colisión de llantas y permite giro omnidireccional rápido",
    Default = false,
    Callback = function(Value)
        Config.VehicleHoverMode = Value
    end
})

Tabs.Combat:AddToggle("FrontRamToggle", {
    Title = "Enfoque de Impacto Frontal",
    Description = "Apunta siempre la parte delantera del auto hacia el zombie al embestir",
    Default = true,
    Callback = function(Value)
        Config.VehicleFrontRamMode = Value
    end
})

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Ataque / Atropello Continuo",
    Default = false,
    Callback = function(Value) Config.ZigZagEnabled = Value end
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación / embestida (Seg)",
    Default = 1.0,
    Min = 0.3,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value) Config.SwitchInterval = Value end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud lateral de barrido (Studs)",
    Default = 12,
    Min = 4,
    Max = 30,
    Rounding = 0,
    Callback = function(Value) Config.LateralDist = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Atropello",
    Default = 55,
    Min = 20,
    Max = 140,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

-- PESTAÑA 2: TELETRANSPORTE Y GRABADOR DE BOLITAS
Tabs.Items:AddSection("Grabador Automático de Chatarra")

Tabs.Items:AddToggle("AutoRecordScrapToggle", {
    Title = "Grabar Telaraña Caminando",
    Description = "Coloca bolitas de entrega automáticamente mientras te mueves",
    Default = false,
    Callback = function(Value)
        Config.AutoRecordScrap = Value
        LastScrapRecordPos = nil
    end
})

Tabs.Items:AddSlider("ScrapStepSlider", {
    Title = "Distancia entre Bolitas (Studs)",
    Default = 35,
    Min = 15,
    Max = 80,
    Rounding = 0,
    Callback = function(Value) Config.ScrapStepDist = Value end
})

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Manual Aquí",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            addDeliveryPoint(root.Position)
            Fluent:Notify({ Title = "Punto Agregado", Content = "Total en la red: " .. #DeliveryPoints, Duration = 2 })
        end
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

Tabs.Items:AddSection("Filtros de Recolección")

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

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Default = true,
    Callback = function(Value) Config.BasePrevent = Value end
})

-- PESTAÑA 3: RUTA Y MAPA
Tabs.Patrol:AddSection("Grabador Automático de Ruta Amarilla")

Tabs.Patrol:AddToggle("AutoRecordPatrolToggle", {
    Title = "Grabar Ruta Amarilla Caminando",
    Description = "Guarda los puntos amarillos automáticamente según la distancia recorrida",
    Default = false,
    Callback = function(Value)
        Config.AutoRecordPatrol = Value
        LastPatrolRecordPos = nil
    end
})

Tabs.Patrol:AddSlider("PatrolStepSlider", {
    Title = "Distancia entre Puntos Amarillos (Studs)",
    Default = 25,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.PatrolStepDist = Value end
})

Tabs.Patrol:AddButton({
    Title = "Crear Punto Amarillo Aquí (Tecla 'K')",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            addPatrolPoint(root.Position)
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

Tabs.Patrol:AddSection("Patrullaje")

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
    Default = 2.0,
    Min = 0.5,
    Max = 15.0,
    Rounding = 1,
    Callback = function(Value) Config.WaypointWaitTime = Value end
})

Tabs.Patrol:AddButton({
    Title = "Importar Pings del Mapa como Ruta",
    Callback = function()
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BillboardGui") or obj.Name:find("Ping") or obj.Name:find("Waypoint") then
                local part = obj.Adornee or obj.Parent
                if part and part:IsA("BasePart") and not part:IsDescendantOf(lp.Character) then
                    addPatrolPoint(part.Position)
                    count = count + 1
                end
            end
        end
        Fluent:Notify({
            Title = "Pings Importados",
            Content = count > 0 and ("Se agregaron " .. count .. " puntos del mapa.") or "No se encontraron pings activos.",
            Duration = 3
        })
    end
})

-- PESTAÑA 4: REACTOR NUCLEAR
Tabs.Reactor:AddSection("Calibración del Reactor (1 Solo Paso)")

local function applySinglePointReactor()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        setReactorFromSinglePoint(root.CFrame)
        Fluent:Notify({
            Title = "Reactor Calibrado",
            Content = "Puerta, centro y los 7 cofres calculados según tu vista.",
            Duration = 4
        })
    end
end

Tabs.Reactor:AddButton({
    Title = "Fijar Frente a la Puerta (Mirando adentro)",
    Description = "Párate mirando hacia la puerta y presiona aquí.",
    Callback = function()
        if ReactorAnchorCF then
            Window:Dialog({
                Title = "Confirmar Cambio de Posición",
                Content = "¿Estás seguro de que deseas sobrescribir el punto de referencia del Reactor?",
                Buttons = {
                    {
                        Title = "Confirmar",
                        Callback = function() applySinglePointReactor() end
                    },
                    {
                        Title = "Cancelar",
                        Callback = function()
                            Fluent:Notify({ Title = "Cancelado", Content = "Se conservó la referencia anterior.", Duration = 2 })
                        end
                    }
                }
            })
        else
            applySinglePointReactor()
        end
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

-- 2. BOTÓN FLOTANTE CÍRCULAR
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
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.22, 0)
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

-- 3. BUCLE DEL GRABADOR AUTOMÁTICO DE PUNTOS
task.spawn(function()
    while true do
        task.wait(0.3)
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")

        if root then
            local currentPos = root.Position

            -- Grabar bolitas de chatarra si recorrió la distancia
            if Config.AutoRecordScrap then
                if not LastScrapRecordPos or (currentPos - LastScrapRecordPos).Magnitude >= Config.ScrapStepDist then
                    LastScrapRecordPos = currentPos
                    addDeliveryPoint(currentPos)
                end
            end

            -- Grabar puntos amarillos si recorrió la distancia
            if Config.AutoRecordPatrol then
                if not LastPatrolRecordPos or (currentPos - LastPatrolRecordPos).Magnitude >= Config.PatrolStepDist then
                    LastPatrolRecordPos = currentPos
                    addPatrolPoint(currentPos)
                end
            end
        end
    end
end)

-- 4. BUCLE DE CONTROL DE FÍSICAS DEL AUTO (HOVER / DESLIZADOR SIN FRICCIÓN)
RunService.Heartbeat:Connect(function()
    if not Config.VehicleHoverMode then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart

    if seat and seat:IsA("VehicleSeat") then
        local carModel = seat:FindFirstAncestorOfClass("Model")
        if carModel then
            -- Quitar colisión a las llantas para deslizamiento omnidireccional
            for _, part in ipairs(carModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    local pName = part.Name:lower()
                    if pName:find("wheel") or pName:find("tire") or pName:find("llanta") or pName:find("rueda") then
                        part.CanCollide = false
                    end
                end
            end
        end
    end
end)

-- 5. BUCLE DE ATROPELLO FRONTAL / ZIGZAG EN VEHÍCULO O A PIE
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or not CurrentTarget or Config.ReactorFarmEnabled then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    -- Detectar si estamos manejando un auto
    local seat = hum.SeatPart
    local vehicleRoot = (seat and seat:IsA("VehicleSeat") and (seat.AssemblyRootPart or seat)) or root

    local targetPart = (CurrentTarget:IsA("BasePart") and CurrentTarget) or (CurrentTarget:IsA("Model") and (CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")))

    if targetPart and targetPart.Parent then
        if tick() - lastSwitch >= Config.SwitchInterval then
            side = -side
            lastSwitch = tick()
        end

        local cf = targetPart.CFrame
        -- Embestida frontal-trasera u oscilante
        local lateralOffset = cf.RightVector * (side * Config.LateralDist)
        local forwardOffset = cf.LookVector * (side * 6)
        local destination = targetPart.Position + lateralOffset + forwardOffset

        local direction = (destination - vehicleRoot.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.5 then
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            vehicleRoot.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, vehicleRoot.AssemblyLinearVelocity.Y, targetVelocity.Z)

            -- Orientar la trompa del auto hacia el zombie para daño frontal máximo
            if Config.VehicleFrontRamMode and seat and seat:IsA("VehicleSeat") then
                local lookAtZombie = CFrame.lookAt(vehicleRoot.Position, Vector3.new(targetPart.Position.X, vehicleRoot.Position.Y, targetPart.Position.Z))
                vehicleRoot.CFrame = vehicleRoot.CFrame:Lerp(lookAtZombie, 0.2)
            end
        end
    end
end)

-- 6. NOCLIP CONSTANTE EN MODO REACTOR
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

local function flyMoveTo(targetPos, speed, stopDistance, applyElevation)
    stopDistance = stopDistance or 3.5
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return false end

    local finalDest = applyElevation and (targetPos + Vector3.new(0, 5, 0)) or targetPos
    local timeout = tick() + 25

    while Config.ReactorFarmEnabled and tick() < timeout do
        RunService.Heartbeat:Wait()
        local dist = (finalDest - root.Position).Magnitude
        if dist <= stopDistance then
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            return true
        end
        local dir = (finalDest - root.Position).Unit
        root.AssemblyLinearVelocity = dir * speed
    end
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    return false
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

-- 7. BUCLE MAESTRO: REACTOR Y RESET DE 420 STUDS
task.spawn(function()
    while true do
        task.wait(0.5)

        if Config.ReactorFarmEnabled then
            if not ReactorAnchorCF or not CalculatedCenter then
                Fluent:Notify({ Title = "Sin Calibrar", Content = "Fija el punto frente a la puerta primero.", Duration = 3 })
                Config.ReactorFarmEnabled = false
            else
                local doorPos = ReactorAnchorCF.Position
                local forwardDir = Vector3.new(ReactorAnchorCF.LookVector.X, 0, ReactorAnchorCF.LookVector.Z).Unit

                -- 1. Puerta
                flyMoveTo(doorPos, 35, 4, true)
                task.wait(0.5)

                for _, prompt in ipairs(workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - doorPos).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
                task.wait(1.5)

                -- 2. Entrar al Centro
                flyMoveTo(CalculatedCenter, 40, 3, true)

                -- 3. Cacería de Phasers
                local inCombat = true
                local clearStreak = 0

                while Config.ReactorFarmEnabled and inCombat do
                    task.wait(0.3)
                    local phaserModel, phaserRoot = getActivePhaser(CalculatedCenter, Config.ReactorDetectionRadius)

                    if phaserModel and phaserRoot then
                        clearStreak = 0
                        while Config.ReactorFarmEnabled and phaserModel.Parent and phaserRoot.Parent do
                            local eHum = phaserModel:FindFirstChildOfClass("Humanoid")
                            if eHum and eHum.Health <= 0 then break end
                            flyMoveTo(phaserRoot.Position, 38, 5, true)
                            task.wait(0.15)
                        end
                        flyMoveTo(CalculatedCenter, 40, 3, true)
                    else
                        local remaining = countLivingZombiesInReactor(CalculatedCenter, Config.ReactorDetectionRadius)
                        if remaining == 0 then
                            clearStreak = clearStreak + 1
                            if clearStreak >= 3 then inCombat = false end
                        else
                            clearStreak = 0
                        end
                    end
                end

                -- 4. Ruta de los 7 Cofres
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
                    local resetPos = doorPos - (forwardDir * 420) + Vector3.new(0, 15, 0)
                    flyMoveTo(resetPos, 60, 6, false)
                    task.wait(Config.ReactorResetWaitTime)
                end
            end
        end
    end
end)

-- 8. BUCLE DE TELETRANSPORTE SCRAP (RED SINCRONIZADA / CERO DESYNC)
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
    return bestPoint
end

task.spawn(function()
    while true do
        task.wait(0.4)
        if Config.AutoSendItems and #DeliveryPoints > 0 then
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                overlapParams.FilterDescendantsInstances = {char}
                local partsNearby = workspace:GetPartBoundsInRadius(root.Position, Config.CollectRadius, overlapParams)
                local processedCount = 0

                for _, hitPart in ipairs(partsNearby) do
                    if processedCount >= 2 then break end

                    if not hitPart.Anchored and not hitPart:FindFirstAncestorOfClass("Humanoid") then
                        local itemModel = hitPart:FindFirstAncestorOfClass("Model")
                        local targetEntity = (itemModel and itemModel.Parent ~= workspace.Characters and itemModel) or hitPart
                        local rootPart = (targetEntity:IsA("Model") and (targetEntity.PrimaryPart or targetEntity:FindFirstChildWhichIsA("BasePart"))) or targetEntity

                        if rootPart then
                            local nameLower = (targetEntity.Name):lower()
                            local isScrap = nameLower:find("scrap") or nameLower:find("chatarra") or nameLower:find("metal") or nameLower:find("barrel")

                            if not Config.OnlyScrap or isScrap then
                                local genPos = getGeneratorPosition()
                                local insideBase = false
                                if Config.BasePrevent and genPos then
                                    if (rootPart.Position - genPos).Magnitude <= Config.GeneratorSafeRadius then
                                        insideBase = true
                                    end
                                end

                                local canTeleport = not insideBase
                                if Config.SingleTeleportLimit and TeleportedTracker[targetEntity] then
                                    canTeleport = false
                                end

                                if canTeleport then
                                    local nextPoint = getNextBestDropPoint(rootPart.Position)

                                    if nextPoint then
                                        processedCount = processedCount + 1
                                        TeleportedTracker[targetEntity] = true

                                        if firetouchinterest then
                                            firetouchinterest(root, rootPart, 0)
                                            firetouchinterest(root, rootPart, 1)
                                        end

                                        local angle = math.random() * math.pi * 2
                                        local dist = math.random() * Config.SpreadRadius
                                        local destPos = nextPoint.Position + Vector3.new(math.cos(angle) * dist, 1.5, math.sin(angle) * dist)

                                        if targetEntity:IsA("Model") then
                                            targetEntity:PivotTo(CFrame.new(destPos))
                                        else
                                            targetEntity.CFrame = CFrame.new(destPos)
                                        end

                                        rootPart.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
                                        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
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

-- 9. BUCLE DE PATRULLA AMARILLA
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
                        task.wait(Config.WaypointWaitTime)
                    end
                end
            end
        end
    end
end)

-- 10. SURTIDOR INSTANTÁNEO
ProximityPromptService.PromptShown:Connect(function(prompt)
    if not Config.InstantGasStation then return end

    local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
        prompt.HoldDuration = 0
        fireproximityprompt(prompt)
    end
end)

-- 11. CONTROLES POR TECLADO
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
            addPatrolPoint(root.Position)
            Fluent:Notify({ Title = "Punto Amarillo Creado", Content = "Punto #" .. #Waypoints .. " guardado.", Duration = 1.5 })
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB LISTO",
    Content = "Auto-Record y Modo Deslizador integrados.",
    Duration = 4
})

Window:SelectTab(1)
