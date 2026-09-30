-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE (VERSION COMPLETA)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- Coordenadas fijas del Reactor
local DOOR_POS = Vector3.new(312.1, 3.2, 1200.0)
local CENTER_POS = Vector3.new(360.2, 2.7, 1181.3)
local FORWARD_DIR = Vector3.new(CENTER_POS.X - DOOR_POS.X, 0, CENTER_POS.Z - DOOR_POS.Z).Unit

local CHEST_COORDS = {
    Vector3.new(371.4, -16.2, 1242.2),
    Vector3.new(398.4, -16.3, 1234.3),
    Vector3.new(413.4, -16.3, 1207.3),
    Vector3.new(413.7, -36.0, 1138.6),
    Vector3.new(402.9, -35.5, 1133.7)
}

local GAS_STATION_1 = Vector3.new(246.3, 3.9, 235.4)
local GAS_STATION_2 = Vector3.new(610.9, 4.1, 409.6)

local Config = {
    -- Combate / Atropello Constante
    AtropelloEnabled = false,
    AtropelloMode = "Embestida Frontal Continua",
    MoveSpeed = 160,
    ChargeDistance = 25,
    AntiBloaterPush = true,

    -- Reparación
    FastAutoRepair = true,
    RepairSpeed = 0.08,
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
    YellowStepDist = 40,

    -- Ruta Amarilla
    PatrolEnabled = false,
    FlyPatrol = false,
    FlyHeight = 10,
    WaypointWaitTime = 0,

    -- Utilidades
    InstantGasStation = true,

    -- Reactor Autónomo
    ReactorFarmEnabled = false,
    LootChests = true,
    ChestWaitTime = 1.3,
    BaseNuclearWait = 900,
    GasCycleInterval = 180,
    DetectionRadius = 270
}

local CurrentTarget = nil
local TargetHighlight = nil
local DeliveryPoints = {}
local Waypoints = {}
local WaypointMarkers = {}
local TeleportedTracker = {}

local LastScrapRecordPos = nil
local LastYellowRecordPos = nil
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

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | COMPLETO",
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
    Coords = Window:AddTab({ Title = "Coords", Icon = "clipboard" }),
    Misc = Window:AddTab({ Title = "Utilidades", Icon = "wrench" })
}

-- PESTAÑA 1: COMBATE Y ATROPELLO
Tabs.Combat:AddSection("Atropello Constante")

Tabs.Combat:AddToggle("AtropelloToggle", {
    Title = "Activar Ataque de Atropello",
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

-- PESTAÑA 2: REPARACIÓN RÁPIDA
Tabs.Repair:AddSection("Auto-Reparación con Martillo")

Tabs.Repair:AddToggle("FastRepairToggle", {
    Title = "Reparación Ultrarrápida Activa",
    Default = true,
    Callback = function(Value) Config.FastAutoRepair = Value end
})

Tabs.Repair:AddSlider("RepairSpeedSlider", {
    Title = "Velocidad de Martillazo (Segundos)",
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
Tabs.Items:AddSection("Auto-Grabado de Bolitas")

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
        local root = getRootPart()
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
    Default = 40,
    Min = 15,
    Max = 80,
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
    Default = 0,
    Min = 0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(Value) Config.WaypointWaitTime = Value end
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
Tabs.Reactor:AddSection("Operación Autónoma")

local ReactorStatusParagraph = Tabs.Reactor:AddParagraph({
    Title = "Estado del Reactor",
    Content = "Inactivo. Presiona el botón de abajo para iniciar."
})

local function updateStatus(text)
    ReactorStatusParagraph:SetDesc(text)
end

Tabs.Reactor:AddToggle("NuclearFarmToggle", {
    Title = "Activar Farm del Reactor",
    Default = false,
    Callback = function(Value)
        Config.ReactorFarmEnabled = Value
        if not Value then
            local root = getRootPart()
            if root then
                local bp = root:FindFirstChild("ReactorFloatBP")
                if bp then bp:Destroy() end
                local bg = root:FindFirstChild("ReactorFloatBG")
                if bg then bg:Destroy() end
            end
            local char = lp.Character
            if char then
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = true end
                end
            end
            updateStatus("Desactivado. Físicas normales.")
        else
            updateStatus("Iniciado. Evaluando situación...")
        end
    end
})

Tabs.Reactor:AddToggle("LootChestsToggle", {
    Title = "Saquear 5 Cofres al Terminar",
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

-- PESTAÑA 6: COORDS
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

-- PESTAÑA 7: UTILIDADES
Tabs.Misc:AddSection("Automatizaciones Ligeras")

Tabs.Misc:AddToggle("InstantGasToggle", {
    Title = "Surtidor Instantáneo (Cero Lag / Móvil)",
    Default = true,
    Callback = function(Value) Config.InstantGasStation = Value end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
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

-- SISTEMA DE VUELO RIGIDO (MANTIENE LA ALTURA A +10 STUDS EN COMBATE)
local function flyMoveTo(targetPos, speed, stopDistance, applyElevation)
    stopDistance = stopDistance or 3.5
    local root = getRootPart()
    if not root then return false end

    local fixedHeight = applyElevation and 10 or 0
    local finalDest = targetPos + Vector3.new(0, fixedHeight, 0)
    local timeout = tick() + 20

    local bodyPos = root:FindFirstChild("ReactorFloatBP")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "ReactorFloatBP"
        bodyPos.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bodyPos.P = 15000
        bodyPos.D = 800
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

    local lastPos = root.Position
    local stuckCounter = 0

    while Config.ReactorFarmEnabled and tick() < timeout do
        RunService.Heartbeat:Wait()

        local dist = (finalDest - root.Position).Magnitude
        if dist <= stopDistance then
            bodyPos.Position = finalDest
            return true
        end

        if (root.Position - lastPos).Magnitude < 0.2 then
            stuckCounter = stuckCounter + 1
            if stuckCounter >= 25 then
                bodyPos.Position = root.Position + Vector3.new(0, 6, 0)
                stuckCounter = 0
            end
        else
            stuckCounter = 0
            lastPos = root.Position
        end

        local stepDir = (finalDest - root.Position).Unit
        bodyPos.Position = root.Position + (stepDir * (speed * 0.1))
    end

    if bodyPos then bodyPos.Position = finalDest end
    return false
end

-- NOCLIP ACTIVO EN EL REACTOR
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

-- BUCLE DE REPARACIÓN
task.spawn(function()
    while true do
        task.wait(Config.RepairSpeed)
        if Config.FastAutoRepair then
            local char = lp.Character
            local backpack = lp:FindFirstChild("Backpack")
            local hammer = (char and char:FindFirstChildWhichIsA("Tool")) or (backpack and backpack:FindFirstChildWhichIsA("Tool"))

            if hammer and (hammer.Name:lower():find("hammer") or hammer.Name:lower():find("martillo") or hammer.Name:lower():find("repair")) then
                if hammer.Parent == backpack and char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum:EquipTool(hammer) end
                end

                local car = getCurrentVehicle()
                if car then
                    pcall(function() hammer:Activate() end)
                else
                    local root = getRootPart()
                    if root then
                        pcall(function() hammer:Activate() end)
                    end
                end
            end
        end
    end
end)

-- BUCLE DE AUTO-GRABADO
task.spawn(function()
    while true do
        task.wait(0.3)
        local root = getRootPart()
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

-- BUCLE DE ATROPELLO
RunService.Heartbeat:Connect(function()
    if not Config.AtropelloEnabled or not CurrentTarget or Config.ReactorFarmEnabled then return end

    local car, seat, mainPart = getCurrentVehicle()
    local controlledPart = mainPart or getRootPart()
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
        if seat then seat.Throttle = 1 end
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

-- BUCLE DE TELETRANSPORTE SCRAP
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getGeneratorPosition()
    if CachedGeneratorPos then return CachedGeneratorPos end
    local gen = workspace:FindFirstChild("Generator") or workspace:FindFirstChild("Center")
    if gen then
        local p = (gen:IsA("Model") and (gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart"))) or gen
        if p then CachedGeneratorPos = p.Position return CachedGeneratorPos end
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
            local root = getRootPart()
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

-- PATRULLAJE AMARILLO
task.spawn(function()
    while true do
        task.wait(0.2)
        if Config.PatrolEnabled and #Waypoints > 0 and not Config.ReactorFarmEnabled then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = getRootPart()

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

-- DETECCIÓN DEL COOLDOWN DE LA PUERTA
local function getDoorCooldownRemaining(doorPos)
    for _, gui in ipairs(workspace:GetChildren()) do
        if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
            local adornee = gui.Adornee or gui.Parent
            if adornee and adornee:IsA("BasePart") and (adornee.Position - doorPos).Magnitude <= 20 then
                for _, lbl in ipairs(gui:GetChildren()) do
                    if lbl:IsA("TextLabel") and lbl.Visible then
                        local txt = lbl.Text:lower()
                        if txt:find("m") and txt:find("s") and not txt:find("revivir") then
                            return txt
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function interactWithGasPump(stationPos)
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local pPart = prompt.Parent
            if pPart and pPart:IsA("BasePart") and (pPart.Position - stationPos).Magnitude <= 18 then
                prompt.HoldDuration = 0
                fireproximityprompt(prompt)
            end
        end
    end
end

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

    if priorityPhaser then return priorityPhaser, priorityRoot end
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

-- BUCLE AUTÓNOMO DEL REACTOR CON VUELO SEGURO Y COFRES TRAS MATARLOS
task.spawn(function()
    while true do
        task.wait(0.5)

        if Config.ReactorFarmEnabled then
            local root = getRootPart()
            local distToCenter = root and (root.Position - CENTER_POS).Magnitude or 999
            local alreadyInside = distToCenter < 140

            if not alreadyInside then
                updateStatus("[1/5] Verificando Puerta...")
                flyMoveTo(DOOR_POS, 35, 4, true)
                task.wait(0.5)

                local cd = getDoorCooldownRemaining(DOOR_POS)
                while Config.ReactorFarmEnabled and cd do
                    updateStatus("Puerta Bloqueada. Tiempo: " .. cd)
                    task.wait(2)
                    cd = getDoorCooldownRemaining(DOOR_POS)
                end

                if not Config.ReactorFarmEnabled then break end

                updateStatus("[2/5] Accediendo al reactor...")
                for _, prompt in ipairs(workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - DOOR_POS).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
                task.wait(1.5)
            end

            -- Entrar al Centro flotando a +10 studs
            flyMoveTo(CENTER_POS, 40, 3, true)

            -- ESTADO 3: CACERÍA Y BARRIDO EN EL AIRE (SIN BAJAR NUNCA)
            updateStatus("[3/5] Barriendo reactor y cazando zombies...")
            local inCombat = true
            local clearStreak = 0

            while Config.ReactorFarmEnabled and inCombat do
                task.wait(0.2)
                local targetModel, targetRoot = getAnyTargetZombie(CENTER_POS, Config.DetectionRadius)

                if targetModel and targetRoot then
                    clearStreak = 0
                    local name = targetModel.Name
                    updateStatus("Cazando: " .. name .. "...")
                    local chaseTimeout = tick() + 12

                    while Config.ReactorFarmEnabled and targetModel.Parent and targetRoot.Parent and tick() < chaseTimeout do
                        local eHum = targetModel:FindFirstChildOfClass("Humanoid")
                        if eHum and eHum.Health <= 0 then break end
                        -- Vuela flotando sobre el zombie a +10 studs fijos sin descender
                        flyMoveTo(targetRoot.Position, 42, 4, true)
                        task.wait(0.15)
                    end
                    flyMoveTo(CENTER_POS, 40, 3, true)
                else
                    local remaining = countLivingZombiesInReactor(CENTER_POS, Config.DetectionRadius)
                    updateStatus("Verificando sala... Restantes: " .. remaining)
                    if remaining == 0 then
                        clearStreak = clearStreak + 1
                        if clearStreak >= 3 then inCombat = false end
                    else
                        clearStreak = 0
                    end
                end
            end

            -- ESTADO 4: SOLO AHORA DESCIENDE A LOS COFRES (ALINEACIÓN AÉREA + BAJADA VERTICAL)
            if Config.ReactorFarmEnabled and Config.LootChests then
                updateStatus("[4/5] Todos muertos. Saqueando los 5 cofres...")
                for _, cPos in ipairs(CHEST_COORDS) do
                    if not Config.ReactorFarmEnabled then break end
                    -- 1. Viaja por el aire justo encima del cofre (+10 studs)
                    flyMoveTo(cPos, 38, 3, true)
                    task.wait(0.15)
                    -- 2. Desciende verticalmente a la coordenada del cofre
                    flyMoveTo(cPos, 25, 2.5, false)
                    task.wait(Config.ChestWaitTime)
                    -- 3. Sube inmediatamente al aire antes de ir al siguiente
                    flyMoveTo(cPos, 30, 2.5, true)
                end
                flyMoveTo(CENTER_POS, 40, 3, true)
            end

            -- ESTADO 5: RECORRIDO DE GASOLINERAS CADA 3 MINUTOS (DURANTE LOS 15 MINUTOS)
            if Config.ReactorFarmEnabled then
                local cooldownStart = tick()

                while Config.ReactorFarmEnabled and (tick() - cooldownStart < Config.BaseNuclearWait) do
                    local roundStart = tick()

                    updateStatus("[5/5] Viajando a Gasolinera 1...")
                    flyMoveTo(GAS_STATION_1, 55, 4, false)
                    task.wait(0.5)
                    interactWithGasPump(GAS_STATION_1)
                    task.wait(1.5)

                    if not Config.ReactorFarmEnabled then break end
                    updateStatus("[5/5] Viajando a Gasolinera 2...")
                    flyMoveTo(GAS_STATION_2, 55, 4, false)
                    task.wait(0.5)
                    interactWithGasPump(GAS_STATION_2)
                    task.wait(1.5)

                    if not Config.ReactorFarmEnabled then break end
                    updateStatus("[5/5] En la puerta del Reactor...")
                    flyMoveTo(DOOR_POS, 55, 4, true)

                    while Config.ReactorFarmEnabled and (tick() - roundStart < Config.GasCycleInterval) do
                        local totalLeft = math.floor(Config.BaseNuclearWait - (tick() - cooldownStart))
                        if totalLeft <= 0 then break end

                        local nextGas = math.floor(Config.GasCycleInterval - (tick() - roundStart))
                        local mins = math.floor(totalLeft / 60)
                        local secs = totalLeft % 60
                        updateStatus(string.format("Nuclear: %02dm %02ds | Próximo Gas en: %ds", mins, secs, math.max(0, nextGas)))
                        task.wait(1)
                    end
                end

                updateStatus("Cooldown completado. Reiniciando bucle...")
                task.wait(1)
            end
        end
    end
end)

-- SURTIDOR INSTANTÁNEO MANUAL
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
        local root = getRootPart()
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
    Content = "Todas las funciones y vuelo blindado restaurados.",
    Duration = 4
})

Window:SelectTab(1)
