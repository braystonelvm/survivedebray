-- ==============================================================================
-- REACTOR NUCLEAR HUB - INTELIGENTE, ANTI-TRABAS Y SIN LAG
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

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
    CurrentStatus = "Inactivo",
    LootChests = true,
    ChestWaitTime = 1.3,
    BaseNuclearWait = 900, -- 15 minutos en segundos
    DetectionRadius = 130
}

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

-- Párrafo de Estado
local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Bot",
    Content = "Inactivo. Presiona PLAY para iniciar."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

local function copyToClipboard(text, label)
    if setclipboard then
        setclipboard(text)
    end
    print("\n[COORDS] " .. label .. ":\n" .. text .. "\n")
    Fluent:Notify({
        Title = "Copiado al Portapapeles",
        Content = label .. " listo para usar.",
        Duration = 3
    })
end

-- CONTROL DE FÍSICA Y FLOTACIÓN ANCLADA
local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

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
            if p:IsA("BasePart") then
                p.CanCollide = true
            end
        end
    end
end

-- NOCLIP CONSTANTE ACTIVO
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

-- VUELO RÍGIDO CON ANTI-TRABAS
local function flyMoveTo(targetPos, speed, stopDistance, applyElevation)
    stopDistance = stopDistance or 3.5
    local root = getRootPart()
    if not root then return false end

    local fixedHeight = applyElevation and 10 or 0
    local finalDest = targetPos + Vector3.new(0, fixedHeight, 0)
    local timeout = tick() + 20 -- 20 segundos máximo para evitar atascos permanentes

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

    while State.Running and tick() < timeout do
        RunService.Heartbeat:Wait()

        while State.Running and State.Paused do
            bodyPos.Position = root.Position
            task.wait(0.2)
        end

        if not State.Running then break end

        local dist = (finalDest - root.Position).Magnitude
        if dist <= stopDistance then
            bodyPos.Position = finalDest
            return true
        end

        -- Lógica Anti-Trabas: Si no avanza en 1 segundo, da un micro-impulso hacia arriba
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

-- LECTURA SEGURA DEL COOLDOWN DE LA PUERTA (SIN LAG)
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

-- DETECCIÓN DE ENEMIGOS EN EL REACTOR
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

-- CALIBRACIÓN
local function recalculateReactor()
    if not Point1_Front or not Point2_Door then return end

    local delta = (Point2_Door - Point1_Front)
    local horizontalDir = Vector3.new(delta.X, 0, delta.Z)

    if horizontalDir.Magnitude < 0.5 then
        Fluent:Notify({ Title = "Puntos muy juntos", Content = "Separa un poco más los 2 puntos.", Duration = 3 })
        return
    end

    DoorForwardDir = horizontalDir.Unit
    local rightDir = DoorForwardDir:Cross(Vector3.new(0, 1, 0)).Unit

    CalculatedCenter = Point2_Door + (DoorForwardDir * 46.6)

    for _, m in ipairs(ChestMarkers) do
        if m and m.Parent then m:Destroy() end
    end
    table.clear(CalculatedChests)
    table.clear(ChestMarkers)

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

    Fluent:Notify({ Title = "Calibración Completa", Content = "Orientación y 7 cofres listos.", Duration = 3 })
end

-- PESTAÑA 1: CONTROLES
Tabs.Main:AddSection("Operación")

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
        updateStatus("Iniciado. Evaluando puerta...")
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
    Callback = function()
        State.Running = false
        State.Paused = false
        removePhysicsHelpers()
        restoreCollisions()
        updateStatus("Detenido. Físicas restauradas.")
    end
})

-- PESTAÑA 2: CALIBRACIÓN
Tabs.Setup:AddSection("2 Puntos en la Entrada")

Tabs.Setup:AddButton({
    Title = "1. Fijar Punto 1 (Frente a la Puerta)",
    Callback = function()
        local root = getRootPart()
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

            Fluent:Notify({ Title = "Punto 1 Guardado", Content = "Pégate a la puerta para el Punto 2.", Duration = 2 })
            recalculateReactor()
        end
    end
})

Tabs.Setup:AddButton({
    Title = "2. Fijar Punto 2 (Pegado a la Puerta)",
    Callback = function()
        local root = getRootPart()
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

            Fluent:Notify({ Title = "Punto 2 Guardado", Content = "Puerta fijada.", Duration = 2 })
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
        for _, m in pairs(Markers) do if m and m.Parent then m:Destroy() end end
        for _, m in ipairs(ChestMarkers) do if m and m.Parent then m:Destroy() end end
        table.clear(Markers)
        table.clear(CalculatedChests)
        table.clear(ChestMarkers)
        updateStatus("Calibración reiniciada.")
    end
})

-- PESTAÑA 3: COPIADOR DE COORDENADAS
Tabs.Coords:AddSection("Extraer Posición Actual")

Tabs.Coords:AddButton({
    Title = "Copiar Mi Posición Actual (Tecla 'C')",
    Description = "Copia tu Vector3 exacto al portapapeles listo para usar",
    Callback = function()
        local root = getRootPart()
        if root then
            local pos = root.Position
            local str = string.format("Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z)
            copyToClipboard(str, "Posición Actual")
        end
    end
})

-- PESTAÑA 4: AJUSTES
Tabs.Settings:AddSection("Tiempos")

Tabs.Settings:AddSlider("BaseWaitSlider", {
    Title = "Tiempo de espera en Base (Minutos)",
    Default = 15,
    Min = 5,
    Max = 30,
    Rounding = 0,
    Callback = function(Value)
        State.BaseNuclearWait = Value * 60
    end
})

Tabs.Settings:AddSlider("ChestWaitSlider", {
    Title = "Tiempo en cada cofre (Segundos)",
    Default = 1.3,
    Min = 0.5,
    Max = 4.0,
    Rounding = 1,
    Callback = function(Value) State.ChestWaitTime = Value end
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

-- TECLA C PARA COPIAR COORDENADAS
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.C then
        local root = getRootPart()
        if root then
            local pos = root.Position
            local str = string.format("Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z)
            copyToClipboard(str, "Posición Actual")
        end
    end
end)

-- MÁQUINA DE ESTADOS Y EJECUCIÓN AUTÓNOMA INTELIGENTE
task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            if not Point2_Door or not CalculatedCenter or not DoorForwardDir then
                updateStatus("Error: Calibra los 2 puntos primero.")
                State.Running = false
            else
                -- ESTADO 1: VERIFICAR COOLDOWN DE PUERTA
                updateStatus("[1/5] Verificando Puerta...")
                flyMoveTo(Point2_Door, 35, 4, true)
                task.wait(0.5)

                local cd = getDoorCooldownRemaining(Point2_Door)
                while State.Running and not State.Paused and cd do
                    updateStatus("Puerta Bloqueada. Esperando tiempo: " .. cd)
                    task.wait(2)
                    cd = getDoorCooldownRemaining(Point2_Door)
                end

                if not State.Running then break end

                -- ESTADO 2: ABRIR E INGRESAR AL REACTOR
                updateStatus("[2/5] Accediendo al reactor...")
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

                flyMoveTo(CalculatedCenter, 40, 3, true)

                -- ESTADO 3: CACERÍA Y ESPERA DE PHASERS (ANTI-TRABAS)
                updateStatus("[3/5] Vigilando Reactor / Esperando Dron...")
                local inCombat = true
                local clearStreak = 0

                while State.Running and not State.Paused and inCombat do
                    task.wait(0.3)
                    local phaserModel, phaserRoot = getActivePhaser(CalculatedCenter, State.DetectionRadius)

                    if phaserModel and phaserRoot then
                        clearStreak = 0
                        updateStatus("Persiguiendo Phaser para el dron...")
                        local chaseTimeout = tick() + 15

                        while State.Running and not State.Paused and phaserModel.Parent and phaserRoot.Parent and tick() < chaseTimeout do
                            local eHum = phaserModel:FindFirstChildOfClass("Humanoid")
                            if eHum and eHum.Health <= 0 then break end
                            flyMoveTo(phaserRoot.Position, 38, 5, true)
                            task.wait(0.15)
                        end
                        flyMoveTo(CalculatedCenter, 40, 3, true)
                    else
                        local remaining = countLivingZombiesInReactor(CalculatedCenter, State.DetectionRadius)
                        updateStatus("Limpieza en curso. Zombies restantes: " .. remaining)
                        if remaining == 0 then
                            clearStreak = clearStreak + 1
                            if clearStreak >= 3 then inCombat = false end
                        else
                            clearStreak = 0
                        end
                    end
                end

                -- ESTADO 4: SAQUEO DE COFRES
                if State.Running and not State.Paused and State.LootChests and #CalculatedChests > 0 then
                    updateStatus("[4/5] Saqueando los 7 cofres subterráneos...")
                    for _, cPos in ipairs(CalculatedChests) do
                        if not State.Running or State.Paused then break end
                        flyMoveTo(cPos, 38, 2.5, false)
                        task.wait(State.ChestWaitTime)
                    end
                end

                -- ESTADO 5: ESPERAR 15 MINUTOS EN LA BASE Y RESETEAR BIOMA
                if State.Running and not State.Paused then
                    flyMoveTo(CalculatedCenter, 40, 3, true)
                    local waitStart = tick()

                    while State.Running and not State.Paused and (tick() - waitStart < State.BaseNuclearWait) do
                        local left = math.floor(State.BaseNuclearWait - (tick() - waitStart))
                        local mins = math.floor(left / 60)
                        local secs = left % 60
                        updateStatus(string.format("[5/5] En base. Esperando recarga: %02dm %02ds", mins, secs))
                        task.wait(1)
                    end

                    updateStatus("Descargando bioma (420 studs)...")
                    local resetPos = Point2_Door - (DoorForwardDir * 420) + Vector3.new(0, 15, 0)
                    flyMoveTo(resetPos, 60, 6, false)
                    task.wait(3)
                end
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Fluent:Notify({
    Title = "REACTOR HUB LISTO",
    Content = "Sistema Anti-Trabas y Copiador de Coords activos.",
    Duration = 4
})

Window:SelectTab(1)
