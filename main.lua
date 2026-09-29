-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- Configuración general
local Config = {
    -- Combate / Zigzag
    ZigZagEnabled = false,
    SwitchInterval = 1.2,
    LateralDist = 14,
    MoveSpeed = 45,
    
    -- Teletransporte de Ítems
    AutoSendItems = false,
    CollectRadius = 25,
    BasePrevent = true,
    GeneratorSafeRadius = 180,
    SpreadRadius = 5,

    -- Recorrido con Puntos Amarillos
    PatrolEnabled = false,
    WaypointWaitTime = 2.0,

    -- Surtidor
    AutoGasStation = true
}

local CurrentTarget = nil
local TargetHighlight = nil

local DeliveryPoints = {}   -- Lista de bolitas verdes
local Waypoints = {}        -- Lista de bolitas amarillas
local WaypointMarkers = {}
local TeleportedTracker = {}

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

-- 1. VENTANA PRINCIPAL (Fluent UI)
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 480),
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

-- PESTAÑA 2: TELETRANSPORTE Y BASE PREVENT (GENERATOR)
Tabs.Items:AddSection("Red de Puntos de Entrega (Bolitas Verdes)")

Tabs.Items:AddButton({
    Title = "+ Agregar Punto de Destino Aquí",
    Description = "Coloca una bolita verde donde estés parado. Puedes poner varias.",
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
            Content = "Nuevo destino fijado. Total activos: " .. #DeliveryPoints,
            Duration = 3
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
        Fluent:Notify({ Title = "Puntos Borrados", Content = "Lista de destinos reiniciada.", Duration = 2 })
    end
})

Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "Enviar Ítems al Pasar Sobre Ellos",
    Default = false,
    Callback = function(Value)
        Config.AutoSendItems = Value
        if not Value then table.clear(TeleportedTracker) end
    end
})

Tabs.Items:AddSection("Protección del Generador (Base)")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Description = "No mueve ningún ítem si está cerca del Generador/Base",
    Default = true,
    Callback = function(Value)
        Config.BasePrevent = Value
    end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio de Seguridad del Generador (Studs)",
    Default = 180,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(Value)
        Config.GeneratorSafeRadius = Value
    end
})

-- PESTAÑA 3: RUTA CON PUNTOS AMARILLOS (WAYPOINTS)
Tabs.Patrol:AddSection("Configuración de Patrulla")

Tabs.Patrol:AddToggle("PatrolToggle", {
    Title = "Iniciar Patrullaje en Bucle",
    Default = false,
    Callback = function(Value)
        Config.PatrolEnabled = Value
    end
})

Tabs.Patrol:AddButton({
    Title = "Crear Punto Amarillo Aquí (Tecla 'K')",
    Description = "Guarda la posición actual para el circuito de caminata",
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

        Fluent:Notify({
            Title = "Punto Amarillo Creado",
            Content = "Punto #" .. #Waypoints .. " guardado.",
            Duration = 2
        })
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

-- PESTAÑA 4: UTILIDADES (SURTIDOR)
Tabs.Misc:AddSection("Automatizaciones")

Tabs.Misc:AddToggle("AutoGasToggle", {
    Title = "Auto-Activar Surtidor de Gasolina",
    Description = "Presiona E automáticamente al pasar cerca del surtidor",
    Default = true,
    Callback = function(Value)
        Config.AutoGasStation = Value
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

    -- Tecla K para colocar punto amarillo rápido
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

-- 5. BUCLE DE TELETRANSPORTE (MULTIPLE DROP POINTS + GENERATOR SAFE ZONE)
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

-- Encontrar la bolita verde más cercana a una posición
local function getClosestDeliveryPoint(pos)
    local bestPoint = nil
    local shortestDist = math.huge
    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local d = (pos - pt.Position).Magnitude
            if d < shortestDist then
                shortestDist = d
                bestPoint = pt
            end
        end
    end
    return bestPoint
end

-- Verificar si está cerca del Generador
local function isNearGenerator(pos)
    local generator = workspace:FindFirstChild("Generator", true) or workspace:FindFirstChild("Center", true)
    if generator then
        local gPart = (generator:IsA("Model") and (generator.PrimaryPart or generator:FindFirstChildWhichIsA("BasePart"))) or generator
        if gPart and (pos - gPart.Position).Magnitude <= Config.GeneratorSafeRadius then
            return true
        end
    end
    return false
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

                        -- No teletransportar si está dentro de la zona segura del Generador
                        local inSafeZone = Config.BasePrevent and isNearGenerator(rootPos)

                        if not inSafeZone and not TeleportedTracker[targetEntity] then
                            local targetDropPoint = getClosestDeliveryPoint(rootPos)

                            if targetDropPoint then
                                TeleportedTracker[targetEntity] = true

                                -- Dispersión aleatoria alrededor de la bolita verde más cercana
                                local angle = math.random() * math.pi * 2
                                local dist = math.random() * Config.SpreadRadius
                                local destPos = targetDropPoint.Position + Vector3.new(math.cos(angle) * dist, 1.2, math.sin(angle) * dist)

                                if targetEntity:IsA("Model") then
                                    targetEntity:PivotTo(CFrame.new(destPos))
                                else
                                    targetEntity.CFrame = CFrame.new(destPos)
                                end

                                -- Limpiar inercia y activar gravedad limpia
                                for _, p in ipairs(targetEntity:GetDescendants()) do
                                    if p:IsA("BasePart") then
                                        p.AssemblyLinearVelocity = Vector3.new(0, -4, 0)
                                        p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                                    end
                                end
                                if targetEntity:IsA("BasePart") then
                                    targetEntity.AssemblyLinearVelocity = Vector3.new(0, -4, 0)
                                    targetEntity.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- 6. BUCLE DE PATRULLA POR PUNTOS AMARILLOS (WAYPOINTS)
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

                    -- Caminar hacia el punto amarillo
                    hum:MoveTo(targetPos)

                    -- Esperar a llegar cerca del punto
                    local timeout = tick() + 15
                    while (root.Position - targetPos).Magnitude > 4 and Config.PatrolEnabled and tick() < timeout do
                        task.wait(0.1)
                    end

                    -- Esperar el tiempo configurado en el punto
                    if Config.PatrolEnabled then
                        task.wait(Config.WaypointWaitTime)
                    end
                end
            end
        end
    end
end)

-- 7. BUCLE DEL SURTIDOR DE GASOLINA (AUTO PROXIMITY PROMPT)
task.spawn(function()
    while true do
        task.wait(0.3)
        if Config.AutoGasStation then
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                -- Buscar prompts de gasolinera cerca
                for _, prompt in ipairs(workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local parentPart = prompt.Parent
                        if parentPart and parentPart:IsA("BasePart") then
                            local dist = (parentPart.Position - root.Position).Magnitude
                            if dist <= prompt.MaxActivationDistance + 4 then
                                -- Si dice Surtidor o Gasolina
                                local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
                                if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") then
                                    fireproximityprompt(prompt)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB COMPLETO",
    Content = "Múltiples destinos, Patrulla (K) y Auto-Surtidor listos.",
    Duration = 5
})

Window:SelectTab(1)
