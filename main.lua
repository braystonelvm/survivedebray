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

local LOCAL_CHEST_OFFSETS = {
    Vector3.new(57.3, -18.9, 43.1),
    Vector3.new(60.3, -19.0, 67.2),
    Vector3.new(60.3, -19.0, 67.2),
    Vector3.new(-34.0, -38.7, 115.2),
    Vector3.new(-36.2, -38.7, 107.6)
}

local Config = {
    -- Combate / Atropello
    AtropelloEnabled = false,
    AtropelloMode = "Embestida Frontal",
    CarFlyFrictionless = false,
    MoveSpeed = 65,
    ChargeOvershoot = 12,
    AntiBloaterPush = true,        -- Empujar bloaters lejos para evitar explosiones

    -- Reparación Ultrarrápida
    FastAutoRepair = true,
    RepairSpeed = 0.08,           -- Segundos por golpe (ultra rápido)
    RepairRange = 30,

    -- Teletransporte Scrap
    AutoSendItems = false,
    CollectRadius = 22,
    OnlyScrap = true,
    ChainTeleport = true,
    SingleTeleportLimit = false,
    BasePrevent = true,
    GeneratorSafeRadius = 160,
    SpreadRadius = 4,

    -- Auto-Grabado
    AutoRecordScrap = false,
    ScrapStepDist = 35,
    AutoRecordYellow = false,
    YellowStepDist = 25,

    -- Ruta
    PatrolEnabled = false,
    FlyPatrol = false,
    FlyHeight = 10,
    WaypointWaitTime = 2.0,

    -- Utilidades
    InstantGasStation = true,

    -- Reactor Autónomo
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

local LastScrapRecordPos = nil
local LastYellowRecordPos = nil

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

local function getCurrentVehicle()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model")
        return carModel, seat
    end
    return nil, nil
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(610, 530),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Repair = Window:AddTab({ Title = "Reparación", Icon = "hammer" }),
    Items = Window:AddTab({ Title = "Teletransporte", Icon = "box" }),
    Patrol = Window:AddTab({ Title = "Ruta y Mapa", Icon = "map-pin" }),
    Reactor = Window:AddTab({ Title = "Reactor Nuclear", Icon = "flame" }),
    Misc = Window:AddTab({ Title = "Utilidades", Icon = "wrench" })
}

-- PESTAÑA 1: COMBATE Y AUTO
Tabs.Combat:AddSection("Físicas del Auto (Modo ZHUB)")

Tabs.Combat:AddToggle("FrictionlessToggle", {
    Title = "Modo Auto Deslizante (Sin Fricción de Ruedas)",
    Description = "Elimina la resistencia de las llantas para acelerar y girar al instante",
    Default = false,
    Callback = function(Value)
        Config.CarFlyFrictionless = Value
        local car = getCurrentVehicle()
        if car then
            for _, p in ipairs(car:GetDescendants()) do
                if p:IsA("BasePart") and (p.Name:lower():find("wheel") or p.Name:lower():find("tire") or p.Name:lower():find("rueda") or p.Name:lower():find("llanta")) then
                    p.CanCollide = not Value
                    pcall(function()
                        p.CustomPhysicalProperties = Value and PhysicalProperties.new(0.01, 0, 0, 0, 0) or nil
                    end)
                end
            end
        end
    end
})

Tabs.Combat:AddSection("Atropello y Anti-Bloater")

Tabs.Combat:AddToggle("AtropelloToggle", {
    Title = "Activar Ataque de Atropello",
    Default = false,
    Callback = function(Value) Config.AtropelloEnabled = Value end
})

Tabs.Combat:AddToggle("AntiBloaterToggle", {
    Title = "Repeler Bloaters (Anti-Explosión)",
    Description = "Lanza a los zombies explosivos por el aire al atropellarlos para no recibir daño",
    Default = true,
    Callback = function(Value) Config.AntiBloaterPush = Value end
})

Tabs.Combat:AddDropdown("AtropelloModeSelect", {
    Title = "Patrón de Ataque",
    Values = {"Embestida Frontal", "Zigzag Lateral"},
    Default = "Embestida Frontal",
    Callback = function(Value) Config.AtropelloMode = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 65,
    Min = 20,
    Max = 150,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

-- PESTAÑA 2: REPARACIÓN RÁPIDA
Tabs.Repair:AddSection("Auto-Reparación con Martillo")

Tabs.Repair:AddToggle("FastRepairToggle", {
    Title = "Reparación Ultrarrápida Activa",
    Description = "Repara tu auto (incluso estando adentro) y vallas dañadas al instante",
    Default = true,
    Callback = function(Value) Config.FastAutoRepair = Value end
})

Tabs.Repair:AddSlider("RepairSpeedSlider", {
    Title = "Velocidad de Martillazo (Segundos)",
    Description = "Menor valor = reparación mucho más rápida",
    Default = 0.08,
    Min = 0.03,
    Max = 0.4,
    Rounding = 2,
    Callback = function(Value) Config.RepairSpeed = Value end
})

Tabs.Repair:AddSlider("RepairRadiusSlider", {
    Title = "Radio de Reparación (Studs)",
    Default = 30,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.RepairRange = Value end
})

-- PESTAÑA 3: TELETRANSPORTE Y AUTO-GRABACIÓN
Tabs.Items:AddSection("Auto-Grabado de Bolitas (Al Conducir/Caminar)")

Tabs.Items:AddToggle("AutoRecordScrapToggle", {
    Title = "Auto-Colocar Bolitas al Moverse",
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
    Max = 70,
    Rounding = 0,
    Callback = function(Value) Config.ScrapStepDist = Value end
})

Tabs.Items:AddSection("Gestión Manual")

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Aquí Manualmente",
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
        Fluent:Notify({ Title = "Punto Agregado", Content = "Bolitas activas: " .. #DeliveryPoints, Duration = 2 })
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

Tabs.Items:AddSection("Protección del Generador")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Default = true,
    Callback = function(Value) Config.BasePrevent = Value end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio Seguro del Generador (Studs)",
    Default = 160,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(Value) Config.GeneratorSafeRadius = Value end
})

-- PESTAÑA 4: RUTA Y MAPA
Tabs.Patrol:AddSection("Auto-Grabado de Ruta Amarilla")

Tabs.Patrol:AddToggle("AutoRecordYellowToggle", {
    Title = "Auto-Grabar Ruta al Caminar",
    Default = false,
    Callback = function(Value)
        Config.AutoRecordYellow = Value
        LastYellowRecordPos = nil
    end
})

Tabs.Patrol:AddSlider("YellowStepSlider", {
    Title = "Distancia entre Puntos Amarillos (Studs)",
    Default = 25,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.YellowStepDist = Value end
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
                    table.insert(Waypoints, part.Position)
                    count = count + 1

                    local marker = Instance.new("Part")
                    marker.Name = "MapPingMarker_" .. #Waypoints
                    marker.Shape = Enum.PartType.Ball
                    marker.Size = Vector3.new(2, 2, 2)
                    marker.Material = Enum.Material.Neon
                    marker.Color = Color3.fromRGB(255, 230, 0)
                    marker.Anchored = true
                    marker.CanCollide = false
                    marker.Position = part.Position
                    marker.Parent = workspace
                    table.insert(WaypointMarkers, marker)
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

-- PESTAÑA 5: REACTOR NUCLEAR
Tabs.Reactor:AddSection("Calibración del Reactor (1 Solo Paso)")

local allowReactorOverride = false

local function applySinglePointReactor()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        ReactorAnchorCF = root.CFrame
        local doorPos = root.Position
        local forwardDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
        local rightDir = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z).Unit

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
        NuclearMarker.CFrame = root.CFrame
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

        Fluent:Notify({ Title = "Reactor Calibrado", Content = "Puerta, centro y 7 cofres calculados.", Duration = 4 })
    end
end

Tabs.Reactor:AddToggle("AllowOverrideToggle", {
    Title = "Desbloquear Sobrescritura de Posición",
    Default = false,
    Callback = function(Value) allowReactorOverride = Value end
})

Tabs.Reactor:AddButton({
    Title = "Fijar Frente a la Puerta (Mirando adentro)",
    Callback = function()
        if ReactorAnchorCF and not allowReactorOverride then
            Fluent:Notify({
                Title = "Punto Protegido",
                Content = "Activa 'Desbloquear Sobrescritura' arriba para cambiarlo.",
                Duration = 4
            })
        else
            applySinglePointReactor()
        end
    end
})

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

-- PESTAÑA 6: UTILIDADES
Tabs.Misc:AddSection("Automatizaciones Ligeras")

Tabs.Misc:AddToggle("InstantGasToggle", {
    Title = "Surtidor Instantáneo (Cero Lag / Móvil)",
    Default = true,
    Callback = function(Value) Config.InstantGasStation = Value end
})

-- BOTÓN FLOTANTE CÍRCULAR
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

-- BUCLE DE REPARACIÓN ULTRARRÁPIDA (DESDE ADENTRO DEL AUTO)
task.spawn(function()
    while true do
        task.wait(Config.RepairSpeed)
        if Config.FastAutoRepair then
            local char = lp.Character
            local backpack = lp:FindFirstChild("Backpack")
            local hammer = (char and char:FindFirstChildWhichIsA("Tool")) or (backpack and backpack:FindFirstChildWhichIsA("Tool"))

            -- Verificar si es un martillo de reparación
            if hammer and (hammer.Name:lower():find("hammer") or hammer.Name:lower():find("martillo") or hammer.Name:lower():find("repair")) then
                -- Si está guardado en mochila, equiparlo temporalmente
                if hammer.Parent == backpack and char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum:EquipTool(hammer) end
                end

                -- 1. Reparar auto si estamos montados
                local car = getCurrentVehicle()
                if car then
                    pcall(function()
                        hammer:Activate()
                    end)
                else
                    -- 2. Si estamos a pie, buscar vallas o piezas dañadas alrededor
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if root then
                        pcall(function()
                            hammer:Activate()
                        end)
                    end
                end
            end
        end
    end
end)

-- BUCLE DE AUTO-GRABACIÓN AL MOVERSE
task.spawn(function()
    while true do
        task.wait(0.3)
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local currentPos = root.Position

            if Config.AutoRecordScrap then
                if not LastScrapRecordPos or (currentPos - LastScrapRecordPos).Magnitude >= Config.ScrapStepDist then
                    LastScrapRecordPos = currentPos

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
                end
            end

            if Config.AutoRecordYellow then
                if not LastYellowRecordPos or (currentPos - LastYellowRecordPos).Magnitude >= Config.YellowStepDist then
                    LastYellowRecordPos = currentPos
                    table.insert(Waypoints, currentPos)

                    local marker = Instance.new("Part")
                    marker.Name = "WaypointMarker_" .. #Waypoints
                    marker.Shape = Enum.PartType.Ball
                    marker.Size = Vector3.new(2, 2, 2)
                    marker.Material = Enum.Material.Neon
                    marker.Color = Color3.fromRGB(255, 230, 0)
                    marker.Anchored = true
                    marker.CanCollide = false
                    marker.Position = currentPos - Vector3.new(0, 1.5, 0)
                    marker.Parent = workspace
                    table.insert(WaypointMarkers, marker)
                end
            end
        end
    end
end)

-- BUCLE DE ATROPELLO Y ANTI-BLOATER
local chargeState = "charge"
local stateSwitchTime = tick()

RunService.Heartbeat:Connect(function()
    local car, seat = getCurrentVehicle()
    local controlledPart = seat or (lp.Character and lp.Character:FindFirstChild("HumanoidRootPart"))
    if not controlledPart then return end

    if Config.CarFlyFrictionless and car then
        for _, p in ipairs(car:GetDescendants()) do
            if p:IsA("BasePart") and (p.Name:lower():find("wheel") or p.Name:lower():find("tire") or p.Name:lower():find("rueda") or p.Name:lower():find("llanta")) then
                p.CanCollide = false
            end
        end
    end

    if not Config.AtropelloEnabled or not CurrentTarget or Config.ReactorFarmEnabled then return end

    local targetPart = (CurrentTarget:IsA("BasePart") and CurrentTarget) or (CurrentTarget:IsA("Model") and (CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")))
    if not targetPart or not targetPart.Parent then return end

    local targetPos = targetPart.Position
    local myPos = controlledPart.Position
    local targetName = (CurrentTarget.Name):lower()
    local isBloater = targetName:find("bloater") or targetName:find("boom") or targetName:find("explo")

    if Config.AtropelloMode == "Embestida Frontal" then
        local toZombie = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
        local dist = toZombie.Magnitude

        -- Si es un bloater y chocamos, repelerlo por el aire lejos del auto
        if dist < 6 and isBloater and Config.AntiBloaterPush then
            targetPart.AssemblyLinearVelocity = Vector3.new(toZombie.Unit.X * 40, 75, toZombie.Unit.Z * 40)
        end

        if chargeState == "charge" and dist < 4.0 then
            chargeState = "reverse"
            stateSwitchTime = tick()
        elseif chargeState == "reverse" and (tick() - stateSwitchTime >= 0.8 or dist >= Config.ChargeOvershoot) then
            chargeState = "charge"
        end

        local moveDir = toZombie.Unit
        if chargeState == "reverse" then
            moveDir = -moveDir
        end

        if car then
            car:PivotTo(CFrame.new(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z)))
        end

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

-- BUCLE DE TELETRANSPORTE SCRAP
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
                                            pcall(function()
                                                firetouchinterest(root, rootPart, 0)
                                                firetouchinterest(root, rootPart, 1)
                                            end)
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

-- BUCLE REACTOR NUCLEAR
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

                flyMoveTo(CalculatedCenter, 40, 3, true)

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

                if Config.ReactorFarmEnabled and Config.LootChests and #CalculatedChests > 0 then
                    Fluent:Notify({ Title = "Reactor Despejado", Content = "Recorriendo los 7 cofres subterráneos...", Duration = 3 })
                    for _, cPos in ipairs(CalculatedChests) do
                        if not Config.ReactorFarmEnabled then break end
                        flyMoveTo(cPos, 38, 2.5, false)
                        task.wait(Config.ChestWaitTime)
                    end
                end

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

-- BUCLE PATRULLAJE
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

-- SURTIDOR INSTANTÁNEO
ProximityPromptService.PromptShown:Connect(function(prompt)
    if not Config.InstantGasStation then return end

    local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
        prompt.HoldDuration = 0
        fireproximityprompt(prompt)
    end
end)

-- SELECCIÓN CON TECLAS
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
            Fluent:Notify({ Title = "Punto Creado", Content = "Punto #" .. #Waypoints .. " guardado.", Duration = 1.5 })
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB LISTO",
    Content = "Reparación ultrarrápida y Anti-Bloater agregados.",
    Duration = 4
})

Window:SelectTab(1)
