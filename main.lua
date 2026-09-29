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
    OnlyScrap = true,             -- Solo teletransporta chatarra
    ChainTeleport = true,         -- Permite saltar entre bolitas hacia la base
    SingleTeleportLimit = false,  -- Desactivado: se pueden teletransportar cuantas veces quieras
    BasePrevent = true,
    GeneratorSafeRadius = 160,
    SpreadRadius = 4,

    -- Ruta Amarilla / Vuelo
    PatrolEnabled = false,
    FlyPatrol = false,            -- Vuela 10 studs sobre el suelo
    FlyHeight = 10,
    WaypointWaitTime = 2.0,

    -- Utilidades / Surtidor
    InstantGasStation = true      -- Instant prompt sin lag
}

local CurrentTarget = nil
local TargetHighlight = nil
local DeliveryPoints = {}   -- Bolitas verdes
local Waypoints = {}        -- Puntos amarillos
local WaypointMarkers = {}
local TeleportedTracker = {}

-- Respaldo de gravedad/física para vuelo
local FloatAttachment = nil
local FloatVelocity = nil

-- Funciones de Highlight
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

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 490),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Items = Window:AddTab({ Title = "Teletransporte", Icon = "box" }),
    Patrol = Window:AddTab({ Title = "Ruta Amarilla", Icon = "map-pin" }),
    Misc = Window:AddTab({ Title = "Utilidades", Icon = "wrench" })
}

-- PESTAÑA 1: COMBATE
Tabs.Combat:AddSection("Controles de Zigzag / Atropello")

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento / Atropello Automático",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

Tabs.Combat:AddParagraph({
    Title = "Teclas de Selector",
    Content = "• Presiona 'T' apuntando a un Zombie o Zona para fijarlo.\n• Presiona 'Y' para desmarcar el objetivo."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación (Segundos)",
    Default = 1.2,
    Min = 0.3,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value)
        Config.SwitchInterval = Value
    end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Ancho de Atropello (Studs)",
    Default = 14,
    Min = 4,
    Max = 35,
    Rounding = 0,
    Callback = function(Value)
        Config.LateralDist = Value
    end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Movimiento",
    Default = 45,
    Min = 16,
    Max = 120,
    Rounding = 0,
    Callback = function(Value)
        Config.MoveSpeed = Value
    end
})

-- PESTAÑA 2: TELETRANSPORTE Y TELARAÑA DE BOLITAS
Tabs.Items:AddSection("Red de Puntos de Entrega (Bolitas Verdes)")

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Verde Aquí",
    Description = "Coloca una bolita verde. Los ítems saltarán de bolita en bolita hacia la base.",
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

        Fluent:Notify({
            Title = "Punto Agregado",
            Content = "Bolita agregada. Total en la red: " .. #DeliveryPoints,
            Duration = 2.5
        })
    end
})

Tabs.Items:AddButton({
    Title = "Borrar Todas las Bolitas Verdes",
    Callback = function()
        for _, p in ipairs(DeliveryPoints) do
            if p and p.Parent then p:Destroy() end
        end
        table.clear(DeliveryPoints)
        table.clear(TeleportedTracker)
        Fluent:Notify({ Title = "Red Reiniciada", Content = "Bolitas verdes eliminadas.", Duration = 2 })
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
    Description = "Ignora bidones, herramientas y pilas para evitar bugs físicos",
    Default = true,
    Callback = function(Value)
        Config.OnlyScrap = Value
    end
})

Tabs.Items:AddToggle("ChainTeleportToggle", {
    Title = "Permitir Teletransporte Continuo",
    Description = "Permite que los ítems salten múltiples veces entre bolitas",
    Default = true,
    Callback = function(Value)
        Config.ChainTeleport = Value
    end
})

Tabs.Items:AddSection("Protección del Generador")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Description = "No mueve ningún recurso que ya esté cerca del Generador",
    Default = true,
    Callback = function(Value)
        Config.BasePrevent = Value
    end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio de Seguridad del Generador (Studs)",
    Default = 160,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(Value)
        Config.GeneratorSafeRadius = Value
    end
})

-- PESTAÑA 3: RUTA AMARILLA Y VUELO
Tabs.Patrol:AddSection("Patrullaje y Vuelo (+10 studs)")

Tabs.Patrol:AddToggle("PatrolToggle", {
    Title = "Iniciar Patrullaje en Bucle",
    Default = false,
    Callback = function(Value)
        Config.PatrolEnabled = Value
    end
})

Tabs.Patrol:AddToggle("FlyPatrolToggle", {
    Title = "Volar sobre la Ruta (+10 studs)",
    Description = "Te eleva 10 studs sobre el suelo y vuela directo entre puntos",
    Default = false,
    Callback = function(Value)
        Config.FlyPatrol = Value
    end
})

Tabs.Patrol:AddSlider("WaitTimeSlider", {
    Title = "Tiempo de espera en cada punto (Segundos)",
    Default = 2.0,
    Min = 0.5,
    Max = 15.0,
    Rounding = 1,
    Callback = function(Value)
        Config.WaypointWaitTime = Value
    end
})

Tabs.Patrol:AddButton({
    Title = "Crear Punto Amarillo Aquí (Tecla 'K')",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

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

-- PESTAÑA 4: UTILIDADES (SURTIDOR INSTANTÁNEO CERO LAG)
Tabs.Misc:AddSection("Automatizaciones Ligeras")

Tabs.Misc:AddToggle("InstantGasToggle", {
    Title = "Surtidor Instantáneo (Cero Lag / Móvil)",
    Description = "Activa el surtidor de inmediato al acercarte sin mantener presionado",
    Default = true,
    Callback = function(Value)
        Config.InstantGasStation = Value
    end
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

-- 3. DETECCIÓN DE TECLAS (T: Fijar, Y: Desmarcar, K: Punto Amarillo)
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

                local displayName = chosen.Name
                if displayName == "Mesh" or displayName == "MeshPart" then
                    if chosen.Parent and chosen.Parent ~= workspace then
                        displayName = chosen.Parent.Name
                    end
                end

                Fluent:Notify({ Title = "Objetivo Fijado", Content = "Fijado: " .. displayName, Duration = 2.5 })
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

-- 4. BUCLE DE MOVIMIENTO EN ZIGZAG (COMBATE / ATROPELLO)
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or not CurrentTarget then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    local targetPart = nil
    if CurrentTarget:IsA("BasePart") then
        targetPart = CurrentTarget
    elseif CurrentTarget:IsA("Model") then
        targetPart = CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")
    end

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

-- 5. BUCLE DE TELETRANSPORTE Y TELARAÑA (CADENA HACIA EL GENERADOR)
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

-- Busca la mejor bolita verde hacia donde hacer avanzar el ítem
local function getNextBestDropPoint(itemPos)
    local genPos = getGeneratorPosition()
    local bestPoint = nil
    local currentDistToGen = genPos and (itemPos - genPos).Magnitude or math.huge
    local shortestDistToItem = math.huge

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local distItemToPoint = (itemPos - pt.Position).Magnitude

            -- Si tenemos el generador como referencia, buscar bolitas más cercanas al generador que el ítem
            if genPos and Config.ChainTeleport then
                local pointDistToGen = (pt.Position - genPos).Magnitude
                if pointDistToGen < currentDistToGen and distItemToPoint > 4 then
                    if distItemToPoint < shortestDistToItem then
                        shortestDistToItem = distItemToPoint
                        bestPoint = pt
                    end
                end
            else
                -- Modo normal: la bolita verde más cercana
                if distItemToPoint < shortestDistToItem and distItemToPoint > 4 then
                    shortestDistToItem = distItemToPoint
                    bestPoint = pt
                end
            end
        end
    end

    -- Respaldo si no hay ninguna más cerca del generador: usar la más cercana absoluta
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

                        -- 1. Filtro Only Scrap
                        local nameLower = (targetEntity.Name):lower()
                        local isScrap = nameLower:find("scrap") or nameLower:find("chatarra") or nameLower:find("metal") or nameLower:find("barrel")

                        if not Config.OnlyScrap or isScrap then
                            -- 2. Base Prevent (Generator)
                            local genPos = getGeneratorPosition()
                            local insideBase = false
                            if Config.BasePrevent and genPos then
                                if (rootPos - genPos).Magnitude <= Config.GeneratorSafeRadius then
                                    insideBase = true
                                end
                            end

                            -- 3. Teletransportar a través de la red
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

                                    -- Limpieza física suave
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

-- 6. BUCLE DE PATRULLAJE CON OPCIÓN DE VUELO (+10 STUDS)
task.spawn(function()
    while true do
        task.wait(0.2)
        if Config.PatrolEnabled and #Waypoints > 0 then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if hum and root and hum.Health > 0 then
                for i, targetPos in ipairs(Waypoints) do
                    if not Config.PatrolEnabled then break end

                    local finalDestination = targetPos
                    if Config.FlyPatrol then
                        finalDestination = targetPos + Vector3.new(0, Config.FlyHeight, 0)
                    end

                    local reached = false
                    local timeout = tick() + 20

                    while Config.PatrolEnabled and not reached and tick() < timeout do
                        task.wait(0.05)

                        if Config.FlyPatrol then
                            -- Volar directo hacia el punto elevado
                            local dir = (finalDestination - root.Position)
                            if dir.Magnitude <= 3.5 then
                                reached = true
                                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                            else
                                root.AssemblyLinearVelocity = dir.Unit * Config.MoveSpeed
                            end
                        else
                            -- Caminar normal por tierra
                            hum:MoveTo(targetPos)
                            if (root.Position - targetPos).Magnitude <= 4 then
                                reached = true
                            end
                        end
                    end

                    -- Esperar en el punto
                    if Config.PatrolEnabled then
                        if Config.FlyPatrol then
                            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        end
                        task.wait(Config.WaypointWaitTime)
                    end
                end
            end
        end
    end
end)

-- 7. SURTIDOR INSTANTÁNEO POR EVENTO NATIVO (CERO LAG / COMPATIBLE CON MÓVIL)
ProximityPromptService.PromptShown:Connect(function(prompt)
    if not Config.InstantGasStation then return end

    local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
    if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
        -- Vuelve la interacción instantánea (sin mantener pulsado)
        prompt.HoldDuration = 0
        fireproximityprompt(prompt)
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB LISTO",
    Content = "Cadena de bolitas, Modo Vuelo y Surtidor Instantáneo activos.",
    Duration = 5
})

Window:SelectTab(1)
