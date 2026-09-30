-- ==============================================================================
-- REACTOR NUCLEAR HUB - EXCLUSIVO Y LIGERO
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- Offsets locales relativos a la orientación (Derecha, Altura_Y, Adelante)
local LOCAL_CHEST_OFFSETS = {
    Vector3.new(57.3, -18.9, 43.1),   -- Cofre 1
    Vector3.new(60.3, -19.0, 67.2),   -- Cofres 2 y 3
    Vector3.new(60.3, -19.0, 67.2),   -- Cofres 4 y 5
    Vector3.new(-34.0, -38.7, 115.2), -- Cofre 6
    Vector3.new(-36.2, -38.7, 107.6)  -- Cofre 7
}

local State = {
    Running = false,
    Paused = false,
    LootChests = true,
    ChestWaitTime = 1.3,
    ResetWaitTime = 10.0,
    DetectionRadius = 130
}

-- Puntos de calibración
local Point1_Front = nil
local Point2_Door = nil
local CalculatedCenter = nil
local DoorForwardDir = nil

local Markers = {}
local CalculatedChests = {}
local ChestMarkers = {}

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "REACTOR HUB | NUCLEAR",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 480),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Controles", Icon = "play" }),
    Setup = Window:AddTab({ Title = "Calibración (2 Puntos)", Icon = "map-pin" }),
    Settings = Window:AddTab({ Title = "Tiempos / Ajustes", Icon = "settings" })
}

-- FUNCIONES DE FÍSICA Y LIMPIEZA
local function removeFly()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if root then
        local bv = root:FindFirstChild("ReactorFlyForce")
        if bv then bv:Destroy() end
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
end

local function restoreCollisions()
    local char = lp.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = true
            end
        end
    end
end

-- NOCLIP CONSTANTE (Solo cuando está corriendo y no pausado)
RunService.Stepped:Connect(function()
    if State.Running and not State.Paused then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = false
                end
            end
        end
    end
end)

-- VUELO REFORZADO (+10 STUDS FIJOS SIN CAÍDAS)
local function flyMoveTo(targetPos, speed, stopDistance, applyElevation)
    stopDistance = stopDistance or 3.5
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return false end

    local elevatedHeight = applyElevation and 10 or 0
    local finalDest = targetPos + Vector3.new(0, elevatedHeight, 0)
    local timeout = tick() + 25

    local bodyVel = root:FindFirstChild("ReactorFlyForce")
    if not bodyVel then
        bodyVel = Instance.new("BodyVelocity")
        bodyVel.Name = "ReactorFlyForce"
        bodyVel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bodyVel.Parent = root
    end

    while State.Running and tick() < timeout do
        RunService.Heartbeat:Wait()

        -- Manejo de pausa
        while State.Running and State.Paused do
            bodyVel.Velocity = Vector3.new(0, 0, 0)
            task.wait(0.2)
        end

        if not State.Running then break end

        local diff = (finalDest - root.Position)
        local dist = diff.Magnitude

        if dist <= stopDistance then
            bodyVel.Velocity = Vector3.new(0, 0, 0)
            return true
        end

        bodyVel.Velocity = diff.Unit * speed
    end

    if bodyVel then bodyVel.Velocity = Vector3.new(0, 0, 0) end
    return false
end

-- DETECCIÓN DE ENEMIGOS
local function getActivePhaser(centerPos, maxDist)
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character then
            local name = entity.Name:lower()
            if name:find("phaser") or name:find("ghost") or name:find("fantasma") then
                local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
                local eHum = entity:FindFirstChildOfClass("Humanoid")
                if eRoot and (not eHum or eHum.Health > 0) then
                    if (eRoot.Position - centerPos).Magnitude <= maxDist then
                        return entity, eRoot
                    end
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

-- CÁLCULO DE ORIENTACIÓN Y COFRES
local function recalculateReactor()
    if not Point1_Front or not Point2_Door then return end

    local delta = (Point2_Door - Point1_Front)
    local horizontalDir = Vector3.new(delta.X, 0, delta.Z)

    if horizontalDir.Magnitude < 0.5 then
        Fluent:Notify({ Title = "Puntos muy juntos", Content = "Separa un poco más el Punto 1 del Punto 2.", Duration = 3 })
        return
    end

    DoorForwardDir = horizontalDir.Unit
    local rightDir = DoorForwardDir:Cross(Vector3.new(0, 1, 0)).Unit

    -- Centro a 46.6 studs adelante de la puerta
    CalculatedCenter = Point2_Door + (DoorForwardDir * 46.6)

    -- Limpiar marcadores viejos de cofres
    for _, m in ipairs(ChestMarkers) do
        if m and m.Parent then m:Destroy() end
    end
    table.clear(CalculatedChests)
    table.clear(ChestMarkers)

    -- Calcular y mostrar los 7 cofres
    for i, offset in ipairs(LOCAL_CHEST_OFFSETS) do
        local worldPos = Point2_Door + (rightDir * offset.X) + (DoorForwardDir * offset.Z) + Vector3.new(0, offset.Y, 0)
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

    Fluent:Notify({ Title = "Cálculo Completo", Content = "Orientación y 7 cofres listos.", Duration = 3 })
end

-- PESTAÑA 1: CONTROLES (PLAY / PAUSA / STOP)
Tabs.Main:AddSection("Estado del Auto-Farm")

Tabs.Main:AddButton({
    Title = "▶ PLAY / INICIAR",
    Description = "Inicia o reanuda la rutina de farmeo",
    Callback = function()
        if not Point2_Door or not CalculatedCenter then
            Fluent:Notify({ Title = "Sin Calibrar", Content = "Fija los 2 puntos de la puerta primero.", Duration = 3 })
            return
        end
        State.Running = true
        State.Paused = false
        Fluent:Notify({ Title = "Reactor Iniciado", Content = "Rutina en marcha.", Duration = 2 })
    end
})

Tabs.Main:AddButton({
    Title = "⏸ PAUSA",
    Description = "Congela temporalmente el movimiento donde estés",
    Callback = function()
        if State.Running then
            State.Paused = not State.Paused
            Fluent:Notify({
                Title = State.Paused and "Pausado" or "Reanudado",
                Content = State.Paused and "Movimiento congelado." or "Continuando rutina...",
                Duration = 2
            })
        end
    end
})

Tabs.Main:AddButton({
    Title = "⏹ STOP (CANCELAR TODO)",
    Description = "Apaga la rutina, quita el noclip y desactiva el vuelo",
    Callback = function()
        State.Running = false
        State.Paused = false
        removeFly()
        restoreCollisions()
        Fluent:Notify({ Title = "Detenido", Content = "Noclip y Vuelo desactivados por completo.", Duration = 3 })
    end
})

-- PESTAÑA 2: CALIBRACIÓN DE LOS 2 PUNTOS
Tabs.Setup:AddSection("Calibración en la Puerta")

Tabs.Setup:AddButton({
    Title = "1. Fijar Punto 1 (Frente a la Puerta)",
    Description = "Párate a unos 3 o 5 metros frente a la puerta",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            Point1_Front = root.Position

            if Markers["P1"] and Markers["P1"].Parent then Markers["P1"]:Destroy() end
            local m = Instance.new("Part")
            m.Shape = Enum.PartType.Ball
            m.Size = Vector3.new(2.5, 2.5, 2.5)
            m.Material = Enum.Material.Neon
            m.Color = Color3.fromRGB(255, 170, 0)
            m.Anchored = true
            m.CanCollide = false
            m.Position = root.Position
            m.Parent = workspace
            Markers["P1"] = m

            Fluent:Notify({ Title = "Punto 1 Guardado", Content = "Ahora avanza y pégate a la puerta.", Duration = 2.5 })
            recalculateReactor()
        end
    end
})

Tabs.Setup:AddButton({
    Title = "2. Fijar Punto 2 (Pegado a la Puerta)",
    Description = "Pégate a la puerta/consola del reactor",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            Point2_Door = root.Position

            if Markers["P2"] and Markers["P2"].Parent then Markers["P2"]:Destroy() end
            local m = Instance.new("Part")
            m.Shape = Enum.PartType.Ball
            m.Size = Vector3.new(2.5, 2.5, 2.5)
            m.Material = Enum.Material.Neon
            m.Color = Color3.fromRGB(255, 60, 0)
            m.Anchored = true
            m.CanCollide = false
            m.Position = root.Position
            m.Parent = workspace
            Markers["P2"] = m

            Fluent:Notify({ Title = "Punto 2 Guardado", Content = "Puerta fijada.", Duration = 2.5 })
            recalculateReactor()
        end
    end
})

Tabs.Setup:AddButton({
    Title = "Borrar Calibración",
    Callback = function()
        Point1_Front = nil
        Point2_Door = nil
        CalculatedCenter = nil
        DoorForwardDir = nil
        for _, m in pairs(Markers) do
            if m and m.Parent then m:Destroy() end
        end
        for _, m in ipairs(ChestMarkers) do
            if m and m.Parent then m:Destroy() end
        end
        table.clear(Markers)
        table.clear(CalculatedChests)
        table.clear(ChestMarkers)
        Fluent:Notify({ Title = "Calibración Borrada", Content = "Puntos reiniciados.", Duration = 2 })
    end
})

-- PESTAÑA 3: TIEMPOS Y AJUSTES
Tabs.Settings:AddSection("Ajustes del Saqueo")

Tabs.Settings:AddToggle("LootChestsToggle", {
    Title = "Saquear 7 Cofres tras Limpiar",
    Default = true,
    Callback = function(Value) State.LootChests = Value end
})

Tabs.Settings:AddSlider("ChestWaitSlider", {
    Title = "Tiempo en cada cofre (Segundos)",
    Default = 1.3,
    Min = 0.5,
    Max = 4.0,
    Rounding = 1,
    Callback = function(Value) State.ChestWaitTime = Value end
})

Tabs.Settings:AddSlider("ResetWaitSlider", {
    Title = "Tiempo fuera del bioma para reiniciar (Seg)",
    Default = 10.0,
    Min = 5.0,
    Max = 60.0,
    Rounding = 0,
    Callback = function(Value) State.ResetWaitTime = Value end
})

-- BOTÓN FLOTANTE CÍRCULAR (MÁS ABAJO: Y = 0.40)
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

-- BUCLE MAESTRO: EJECUCIÓN AUTÓNOMA DEL REACTOR
task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            if not Point2_Door or not CalculatedCenter or not DoorForwardDir then
                Fluent:Notify({ Title = "Sin Calibrar", Content = "Falta fijar los puntos de la puerta.", Duration = 3 })
                State.Running = false
            else
                -- 1. Ir a la Puerta (+10 studs suspendido)
                flyMoveTo(Point2_Door, 35, 4, true)
                task.wait(0.5)

                -- Activar ProximityPrompt de la puerta
                for _, prompt in ipairs(workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - Point2_Door).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
                task.wait(1.5)

                -- 2. Entrar al Centro (+10 studs fijos)
                flyMoveTo(CalculatedCenter, 40, 3, true)

                -- 3. Cacería de Phasers y vigilancia
                local inCombat = true
                local clearStreak = 0

                while State.Running and not State.Paused and inCombat do
                    task.wait(0.3)
                    local phaserModel, phaserRoot = getActivePhaser(CalculatedCenter, State.DetectionRadius)

                    if phaserModel and phaserRoot then
                        clearStreak = 0
                        while State.Running and not State.Paused and phaserModel.Parent and phaserRoot.Parent do
                            local eHum = phaserModel:FindFirstChildOfClass("Humanoid")
                            if eHum and eHum.Health <= 0 then break end
                            flyMoveTo(phaserRoot.Position, 38, 5, true)
                            task.wait(0.15)
                        end
                        flyMoveTo(CalculatedCenter, 40, 3, true)
                    else
                        local remaining = countLivingZombiesInReactor(CalculatedCenter, State.DetectionRadius)
                        if remaining == 0 then
                            clearStreak = clearStreak + 1
                            if clearStreak >= 3 then inCombat = false end
                        else
                            clearStreak = 0
                        end
                    end
                end

                -- 4. Ruta de los 7 Cofres Subterráneos
                if State.Running and not State.Paused and State.LootChests and #CalculatedChests > 0 then
                    Fluent:Notify({ Title = "Reactor Despejado", Content = "Recorriendo los 7 cofres subterráneos...", Duration = 3 })
                    for _, cPos in ipairs(CalculatedChests) do
                        if not State.Running or State.Paused then break end
                        flyMoveTo(cPos, 38, 2.5, false)
                        task.wait(State.ChestWaitTime)
                    end
                end

                -- 5. Salir 420 studs en reversa para descargar el bioma
                if State.Running and not State.Paused then
                    Fluent:Notify({ Title = "Saqueo Completo", Content = "Alejándose 420 studs para reiniciar bioma...", Duration = 3 })
                    local resetPos = Point2_Door - (DoorForwardDir * 420) + Vector3.new(0, 15, 0)
                    flyMoveTo(resetPos, 60, 6, false)
                    task.wait(State.ResetWaitTime)
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "REACTOR HUB LISTO",
    Content = "Menú exclusivo de Reactor cargado.",
    Duration = 4
})

Window:SelectTab(1)
