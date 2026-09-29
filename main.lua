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

-- ==============================================================================
-- COORDENADAS PREDEFINIDAS DEL REACTOR (Pega aquí tus datos una vez obtenidos)
-- ==============================================================================
local HARDCODED_REACTOR = {
    Door = nil,       -- Ej: Vector3.new(120.5, 4.2, -350.1)
    Center = nil,     -- Ej: Vector3.new(145.2, 3.8, -380.0)
    Outside = nil,    -- Ej: Vector3.new(50.0, 10.0, -100.0)
    Chests = {
        -- Ej: Vector3.new(150.1, -12.4, -390.2),
        -- Ej: Vector3.new(160.8, -12.4, -385.0),
    }
}

-- Variables de configuración
local Config = {
    -- Combate / Zigzag
    ZigZagEnabled = false,
    SwitchInterval = 1.2,
    LateralDist = 14,
    MoveSpeed = 45,

    -- Teletransporte de Ítems (Telaraña)
    AutoSendItems = false,
    CollectRadius = 25,
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
    WaypointWaitTime = 2.0,

    -- Utilidades
    InstantGasStation = true,

    -- Reactor Nuclear
    ReactorFarmEnabled = false,
    LootChests = true,
    ChestWaitTime = 1.2,
    ReactorResetWaitTime = 10.0,
    ReactorDetectionRadius = 130
}

local CurrentTarget = nil
local TargetHighlight = nil
local DeliveryPoints = {}   -- Bolitas de entrega
local Waypoints = {}        -- Puntos amarillos
local WaypointMarkers = {}
local TeleportedTracker = {}

-- Puntos del Reactor (Carga los predefinidos si existen)
local NuclearPoints = {
    Door = HARDCODED_REACTOR.Door,
    Center = HARDCODED_REACTOR.Center,
    Outside = HARDCODED_REACTOR.Outside
}
local NuclearMarkers = {}
local ChestPoints = HARDCODED_REACTOR.Chests or {}
local ChestMarkers = {}

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

-- Función para copiar texto al portapapeles y notificar
local function copyToClipboard(text, label)
    if setclipboard then
        setclipboard(text)
    end
    print("\n--- [ZOMBIE HUB: " .. label .. "] ---\n" .. text .. "\n----------------------------------")
    Fluent:Notify({
        Title = "Copiado al Portapapeles",
        Content = label .. " listo para pegar en GitHub o consola (F9).",
        Duration = 3.5
    })
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
    Coords = Window:AddTab({ Title = "Config / Coords", Icon = "clipboard" }),
    Misc = Window:AddTab({ Title = "Utilidades", Icon = "wrench" })
}

-- PESTAÑA 1: COMBATE
Tabs.Combat:AddSection("Controles de Zigzag / Atropello")

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento / Atropello Automático",
    Default = false,
    Callback = function(Value) Config.ZigZagEnabled = Value end
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación (Segundos)",
    Default = 1.2,
    Min = 0.3,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value) Config.SwitchInterval = Value end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Ancho de Atropello (Studs)",
    Default = 14,
    Min = 4,
    Max = 35,
    Rounding = 0,
    Callback = function(Value) Config.LateralDist = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Movimiento",
    Default = 45,
    Min = 16,
    Max = 120,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

-- PESTAÑA 2: TELETRANSPORTE Y TELARAÑA
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
    Default = 2.0,
    Min = 0.5,
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

-- PESTAÑA 4: REACTOR NUCLEAR
Tabs.Reactor:AddSection("Fijar los 3 Puntos Naranjas")

local function spawnOrangeMarker(pos, name)
    if NuclearMarkers[name] and NuclearMarkers[name].Parent then
        NuclearMarkers[name]:Destroy()
    end
    local marker = Instance.new("Part")
    marker.Name = "NuclearMarker_" .. name
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(2.8, 2.8, 2.8)
    marker.Material = Enum.Material.Neon
    marker.Color = Color3.fromRGB(255, 120, 0)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Position = pos
    marker.Parent = workspace
    NuclearMarkers[name] = marker
end

Tabs.Reactor:AddButton({
    Title = "1. Fijar Punto Puerta",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            NuclearPoints.Door = root.Position
            spawnOrangeMarker(root.Position, "Door")
            Fluent:Notify({ Title = "Punto 1 Guardado", Content = "Punto de la puerta fijado.", Duration = 2 })
        end
    end
})

Tabs.Reactor:AddButton({
    Title = "2. Fijar Punto Centro",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            NuclearPoints.Center = root.Position
            spawnOrangeMarker(root.Position, "Center")
            Fluent:Notify({ Title = "Punto 2 Guardado", Content = "Centro del reactor fijado.", Duration = 2 })
        end
    end
})

Tabs.Reactor:AddButton({
    Title = "3. Fijar Punto Lejos",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            NuclearPoints.Outside = root.Position
            spawnOrangeMarker(root.Position, "Outside")
            Fluent:Notify({ Title = "Punto 3 Guardado", Content = "Punto lejano de salida fijado.", Duration = 2 })
        end
    end
})

Tabs.Reactor:AddSection("Ruta de Cofres Subterráneos")

Tabs.Reactor:AddToggle("LootChestsToggle", {
    Title = "Hacer Ruta de Cofres tras Limpiar",
    Default = true,
    Callback = function(Value) Config.LootChests = Value end
})

Tabs.Reactor:AddSlider("ChestWaitSlider", {
    Title = "Tiempo de espera en cada cofre (Seg)",
    Default = 1.2,
    Min = 0.5,
    Max = 4.0,
    Rounding = 1,
    Callback = function(Value) Config.ChestWaitTime = Value end
})

Tabs.Reactor:AddButton({
    Title = "+ Agregar Posición de Cofre Aquí",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            table.insert(ChestPoints, root.Position)

            local marker = Instance.new("Part")
            marker.Name = "ChestMarker_" .. #ChestPoints
            marker.Shape = Enum.PartType.Ball
            marker.Size = Vector3.new(2.2, 2.2, 2.2)
            marker.Material = Enum.Material.Neon
            marker.Color = Color3.fromRGB(0, 200, 255)
            marker.Anchored = true
            marker.CanCollide = false
            marker.Position = root.Position
            marker.Parent = workspace

            table.insert(ChestMarkers, marker)
            Fluent:Notify({ Title = "Cofre Guardado", Content = "Cofre #" .. #ChestPoints .. " registrado.", Duration = 2 })
        end
    end
})

Tabs.Reactor:AddButton({
    Title = "Borrar Ruta de Cofres",
    Callback = function()
        for _, m in ipairs(ChestMarkers) do
            if m and m.Parent then m:Destroy() end
        end
        table.clear(ChestPoints)
        table.clear(ChestMarkers)
        Fluent:Notify({ Title = "Cofres Eliminados", Content = "Lista de cofres reiniciada.", Duration = 2 })
    end
})

Tabs.Reactor:AddSection("Automatización")

Tabs.Reactor:AddToggle("NuclearFarmToggle", {
    Title = "Iniciar Saqueo Automático del Reactor",
    Default = false,
    Callback = function(Value) Config.ReactorFarmEnabled = Value end
})

Tabs.Reactor:AddSlider("NuclearWaitSlider", {
    Title = "Tiempo fuera del bioma (Seg)",
    Default = 10.0,
    Min = 5.0,
    Max = 60.0,
    Rounding = 0,
    Callback = function(Value) Config.ReactorResetWaitTime = Value end
})

-- PESTAÑA 5: EXPORTADOR Y COPIADOR DE COORDENADAS
Tabs.Coords:AddSection("Copiador Rápido (Alternativa 1)")

Tabs.Coords:AddButton({
    Title = "Copiar Mi Posición Actual (Tecla 'C')",
    Description = "Copia tu Vector3 exacto al portapapeles listo para GitHub",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local pos = root.Position
            local coordStr = string.format("Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z)
            copyToClipboard(coordStr, "Posición Actual")
        end
    end
})

Tabs.Coords:AddSection("Exportar Datos de la Partida")

Tabs.Coords:AddButton({
    Title = "Copiar Todos los Puntos del Reactor",
    Description = "Genera el bloque HARDCODED_REACTOR completo de puerta, centro, salida y cofres",
    Callback = function()
        local doorStr = NuclearPoints.Door and string.format("Vector3.new(%.1f, %.1f, %.1f)", NuclearPoints.Door.X, NuclearPoints.Door.Y, NuclearPoints.Door.Z) or "nil"
        local centerStr = NuclearPoints.Center and string.format("Vector3.new(%.1f, %.1f, %.1f)", NuclearPoints.Center.X, NuclearPoints.Center.Y, NuclearPoints.Center.Z) or "nil"
        local outStr = NuclearPoints.Outside and string.format("Vector3.new(%.1f, %.1f, %.1f)", NuclearPoints.Outside.X, NuclearPoints.Outside.Y, NuclearPoints.Outside.Z) or "nil"
        
        local chestList = "{\n"
        for _, cp in ipairs(ChestPoints) do
            chestList = chestList .. string.format("        Vector3.new(%.1f, %.1f, %.1f),\n", cp.X, cp.Y, cp.Z)
        end
        chestList = chestList .. "    }"

        local output = string.format("local HARDCODED_REACTOR = {\n    Door = %s,\n    Center = %s,\n    Outside = %s,\n    Chests = %s\n}", doorStr, centerStr, outStr, chestList)
        copyToClipboard(output, "Datos del Reactor")
    end
})

Tabs.Coords:AddButton({
    Title = "Copiar Toda la Red de Bolitas de Chatarra",
    Description = "Copia la lista de bolitas verdes/azules que colocaste en este mapa",
    Callback = function()
        if #DeliveryPoints == 0 then
            Fluent:Notify({ Title = "Sin Bolitas", Content = "No hay bolitas activas para exportar.", Duration = 2 })
            return
        end
        local listStr = "{\n"
        for _, pt in ipairs(DeliveryPoints) do
            if pt and pt.Parent then
                local p = pt.Position
                listStr = listStr .. string.format("    Vector3.new(%.1f, %.1f, %.1f),\n", p.X, p.Y, p.Z)
            end
        end
        listStr = listStr .. "}"
        copyToClipboard(listStr, "Telaraña de Chatarra")
    end
})

Tabs.Coords:AddButton({
    Title = "Copiar Toda la Ruta Amarilla",
    Description = "Copia la lista completa de puntos de patrulla",
    Callback = function()
        if #Waypoints == 0 then
            Fluent:Notify({ Title = "Sin Ruta", Content = "No hay puntos amarillos creados.", Duration = 2 })
            return
        end
        local listStr = "{\n"
        for _, wp in ipairs(Waypoints) do
            listStr = listStr .. string.format("    Vector3.new(%.1f, %.1f, %.1f),\n", wp.X, wp.Y, wp.Z)
        end
        listStr = listStr .. "}"
        copyToClipboard(listStr, "Ruta Amarilla")
    end
})

-- PESTAÑA 6: UTILIDADES
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

-- 4. BUCLE MAESTRO: SAQUEO DEL REACTOR Y RUTA DE COFRES
task.spawn(function()
    while true do
        task.wait(0.5)

        if Config.ReactorFarmEnabled then
            if not NuclearPoints.Door or not NuclearPoints.Center or not NuclearPoints.Outside then
                Fluent:Notify({ Title = "Puntos Incompletos", Content = "Fija los 3 puntos naranjas primero.", Duration = 3 })
                Config.ReactorFarmEnabled = false
            else
                -- 1. Puerta
                flyMoveTo(NuclearPoints.Door, 35, 4, true)
                task.wait(0.5)

                for _, prompt in ipairs(workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - NuclearPoints.Door).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
                task.wait(1.5)

                -- 2. Centro
                flyMoveTo(NuclearPoints.Center, 40, 3, true)

                -- 3. Cacería de Phasers
                local inCombat = true
                local clearStreak = 0

                while Config.ReactorFarmEnabled and inCombat do
                    task.wait(0.3)
                    local phaserModel, phaserRoot = getActivePhaser(NuclearPoints.Center, Config.ReactorDetectionRadius)

                    if phaserModel and phaserRoot then
                        clearStreak = 0
                        while Config.ReactorFarmEnabled and phaserModel.Parent and phaserRoot.Parent do
                            local eHum = phaserModel:FindFirstChildOfClass("Humanoid")
                            if eHum and eHum.Health <= 0 then break end
                            flyMoveTo(phaserRoot.Position, 38, 5, true)
                            task.wait(0.15)
                        end
                        flyMoveTo(NuclearPoints.Center, 40, 3, true)
                    else
                        local remaining = countLivingZombiesInReactor(NuclearPoints.Center, Config.ReactorDetectionRadius)
                        if remaining == 0 then
                            clearStreak = clearStreak + 1
                            if clearStreak >= 3 then inCombat = false end
                        else
                            clearStreak = 0
                        end
                    end
                end

                -- 4. Ruta de Cofres
                if Config.ReactorFarmEnabled and Config.LootChests and #ChestPoints > 0 then
                    Fluent:Notify({ Title = "Sala Limpia", Content = "Recorriendo ruta de cofres...", Duration = 2.5 })
                    for _, cPos in ipairs(ChestPoints) do
                        if not Config.ReactorFarmEnabled then break end
                        flyMoveTo(cPos, 36, 2.5, false)
                        task.wait(Config.ChestWaitTime)
                    end
                end

                -- 5. Salir al punto lejano
                if Config.ReactorFarmEnabled then
                    Fluent:Notify({ Title = "Saqueo Completo", Content = "Saliendo a descargar el bioma...", Duration = 3 })
                    flyMoveTo(NuclearPoints.Outside, 55, 5, true)
                    task.wait(Config.ReactorResetWaitTime)
                end
            end
        end
    end
end)

-- 5. BUCLE DE MOVIMIENTO EN ZIGZAG
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or not CurrentTarget or Config.ReactorFarmEnabled then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    local targetPart = (CurrentTarget:IsA("BasePart") and CurrentTarget) or (CurrentTarget:IsA("Model") and (CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")))

    if targetPart and targetPart.Parent then
        if tick() - lastSwitch >= Config.SwitchInterval then
            side = -side
            lastSwitch = tick()
        end

        local cf = targetPart.CFrame
        local lateralOffset = cf.RightVector * (side * Config.LateralDist)
        local destination = targetPart.Position + lateralOffset

        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.5 then
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

-- 6. BUCLE DE TELETRANSPORTE Y TELARAÑA
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getGeneratorPosition()
    local gen = workspace:FindFirstChild("Generator", true) or workspace:FindFirstChild("Center", true)
    if gen then
        local p = (gen:IsA("Model") and (gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart"))) or gen
        if p then return p.Position end
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
        task.wait(0.2)
        if Config.AutoSendItems and #DeliveryPoints > 0 then
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                overlapParams.FilterDescendantsInstances = {char}
                local partsNearby = workspace:GetPartBoundsInRadius(root.Position, Config.CollectRadius, overlapParams)

                for _, hitPart in ipairs(partsNearby) do
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
                        task.wait(Config.WaypointWaitTime)
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

-- 9. SELECCIÓN CON TECLAS (T: Fijar, Y: Desmarcar, K: Punto Amarillo, C: Copiar Coords)
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

    -- Tecla C para copiar posición actual instantánea
    if input.KeyCode == Enum.KeyCode.C then
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local pos = root.Position
            local coordStr = string.format("Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z)
            copyToClipboard(coordStr, "Posición Actual")
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB LISTO",
    Content = "Copiador de Coordenadas y Exportador integrados.",
    Duration = 4
})

Window:SelectTab(1)
