-- ==============================================================================
-- REACTOR NUCLEAR HUB - COORDENADAS PREDEFINIDAS Y TOTALMENTE MODIFICABLES
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- Coordenadas predefinidas por defecto
local DEFAULT_DOOR = Vector3.new(312.1, 3.2, 1200.0)
local DEFAULT_CENTER = Vector3.new(360.2, 2.7, 1181.3)
local DEFAULT_CHESTS = {
    Vector3.new(371.4, -16.2, 1242.2), -- Cofre 1
    Vector3.new(398.4, -16.3, 1234.3), -- Cofre 2
    Vector3.new(413.4, -16.3, 1207.3), -- Cofre 3
    Vector3.new(413.7, -36.0, 1138.6), -- Cofre 4
    Vector3.new(402.9, -35.5, 1133.7)  -- Cofre 5
}

local GAS_STATION_1 = Vector3.new(246.3, 3.9, 235.4)
local GAS_STATION_2 = Vector3.new(610.9, 4.1, 409.6)

local State = {
    Running = false,
    Paused = false,
    CurrentStatus = "Inactivo",
    LootChests = false,
    ChestWaitTime = 1.3,
    BaseNuclearWait = 900,
    GasCycleInterval = 180,
    DetectionRadius = 270
}

-- Puntos activos (inician con los valores predeterminados)
local Point1_Front = nil
local Point2_Door = DEFAULT_DOOR
local CalculatedCenter = DEFAULT_CENTER
local DoorForwardDir = Vector3.new(DEFAULT_CENTER.X - DEFAULT_DOOR.X, 0, DEFAULT_CENTER.Z - DEFAULT_DOOR.Z).Unit

local Markers = {}
local CalculatedChests = {}
local ChestMarkers = {}

for _, cPos in ipairs(DEFAULT_CHESTS) do
    table.insert(CalculatedChests, cPos)
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "REACTOR HUB | NUCLEAR",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 520),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Controles", Icon = "play" }),
    Death = Window:AddTab({ Title = "Auto-Kill / Vuelo", Icon = "skull" }),
    Setup = Window:AddTab({ Title = "Calibración", Icon = "map-pin" }),
    Coords = Window:AddTab({ Title = "Coords", Icon = "clipboard" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Bot",
    Content = "Listo con coordenadas predefinidas. Presiona PLAY."
})

local FlyDiagnosticsParagraph = Tabs.Main:AddParagraph({
    Title = "Diagnóstico Dead-Fly (ZHUB)",
    Content = "Verificando físicas..."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

-- GENERAR MARCADORES VISUALES EN EL MAPA
local function refreshVisualMarkers()
    for _, m in pairs(Markers) do if m and m.Parent then m:Destroy() end end
    for _, m in ipairs(ChestMarkers) do if m and m.Parent then m:Destroy() end end
    table.clear(Markers)
    table.clear(ChestMarkers)

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

    for i, pos in ipairs(CalculatedChests) do
        local marker = Instance.new("Part")
        marker.Name = "ChestMarker_" .. i
        marker.Shape = Enum.PartType.Ball
        marker.Size = Vector3.new(2.2, 2.2, 2.2)
        marker.Material = Enum.Material.Neon
        marker.Color = Color3.fromRGB(0, 200, 255)
        marker.Anchored = true
        marker.CanCollide = false
        marker.Position = pos
        marker.Parent = workspace
        table.insert(ChestMarkers, marker)
    end
end

refreshVisualMarkers()

-- MOTOR DEAD-FLY: OBTENER PIEZA DE TRACCIÓN
local function getBestFlightPart()
    local char = lp.Character
    if not char then return nil end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local isDowned = (hum and hum.Health <= 0) or char:FindFirstChild("ReviveProgress") or char:FindFirstChild("Downed")

    if isDowned and torso then
        return torso
    end
    return hrp or torso
end

local function breakGroundWelds()
    local char = lp.Character
    if char then
        for _, obj in ipairs(char:GetDescendants()) do
            if obj:IsA("Weld") or obj:IsA("WeldConstraint") or obj:IsA("Snap") then
                if obj.Part0 and not obj.Part0:IsDescendantOf(char) then
                    obj:Destroy()
                elseif obj.Part1 and not obj.Part1:IsDescendantOf(char) then
                    obj:Destroy()
                end
            end
        end
    end
end

local function executeAirAutoKill()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = getBestFlightPart()

    if not char or not hum or not root then
        Fluent:Notify({ Title = "Error", Content = "Personaje no detectado.", Duration = 2 })
        return
    end

    if hum.Health <= 0 then
        Fluent:Notify({ Title = "Ya estás abatido", Content = "Liberando restricciones de suelo...", Duration = 2 })
        breakGroundWelds()
        root.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
        return
    end

    root.AssemblyLinearVelocity = Vector3.new(0, 45, 0)
    task.wait(0.08)

    pcall(function()
        hum.Health = 0
    end)

    task.wait(0.1)
    breakGroundWelds()

    Fluent:Notify({
        Title = "Auto-Kill Ejecutado",
        Content = "Cuerpo en el aire sin restricciones de suelo.",
        Duration = 3
    })
end

-- DIAGNÓSTICO EN TIEMPO REAL
task.spawn(function()
    while true do
        task.wait(0.3)
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local part = getBestFlightPart()

        if not char or not part then
            FlyDiagnosticsParagraph:SetDesc("🔴 SIN PERSONAJE (Esperando spawn)")
        elseif hum and hum.Health > 0 then
            FlyDiagnosticsParagraph:SetDesc("🟢 PERSONAJE VIVO | Físicas normales (Vuelo al 100%)")
        else
            breakGroundWelds()
            local canFly = not part.Anchored
            if canFly then
                FlyDiagnosticsParagraph:SetDesc(string.format("🟡 ABATIDO LIBRE | Pieza: %s (Vuelo desbloqueado)", part.Name))
            else
                FlyDiagnosticsParagraph:SetDesc("🔴 ABATIDO Y ANCLADO | Servidor bloqueó la pieza")
            end
        end
    end
end)

local function copyCurrentCoords()
    local root = getBestFlightPart()
    if root then
        local p = root.Position
        local str = string.format("Vector3.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
        if setclipboard then setclipboard(str) elseif toclipboard then toclipboard(str) end
        print("\n[COORDS]: " .. str .. "\n")
        Fluent:Notify({ Title = "Coordenada Copiada", Content = str, Duration = 3 })
    end
end

-- CONTROL DE FÍSICA CON FUERZA INFINITA EN Y
local function getOrCreatePhysics(part)
    local bodyPos = part:FindFirstChild("ReactorFloatBP")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "ReactorFloatBP"
        bodyPos.MaxForce = Vector3.new(1e6, math.huge, 1e6)
        bodyPos.P = 35000
        bodyPos.D = 600
        bodyPos.Parent = part
    end

    local bodyGyro = part:FindFirstChild("ReactorFloatBG")
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "ReactorFloatBG"
        bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bodyGyro.CFrame = part.CFrame
        bodyGyro.Parent = part
    end

    return bodyPos, bodyGyro
end

local function removePhysicsHelpers()
    local char = lp.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local bp = part:FindFirstChild("ReactorFloatBP")
                if bp then bp:Destroy() end
                local bg = part:FindFirstChild("ReactorFloatBG")
                if bg then bg:Destroy() end
                part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end
        end
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

-- VUELO CON ALTITUD BLINDADA
local function flyMoveTo(targetPos, speed, stopDistance, lockAltitudeToDoor)
    stopDistance = stopDistance or 3.5
    local root = getBestFlightPart()
    if not root then return false end

    breakGroundWelds()

    local safeY = (lockAltitudeToDoor and Point2_Door) and (Point2_Door.Y + 10) or targetPos.Y
    local finalDest = Vector3.new(targetPos.X, safeY, targetPos.Z)
    local timeout = tick() + 20

    local bodyPos = getOrCreatePhysics(root)
    bodyPos.Position = Vector3.new(root.Position.X, safeY, root.Position.Z)

    local lastPos = root.Position
    local stuckCounter = 0

    while State.Running and tick() < timeout do
        RunService.Heartbeat:Wait()

        local currentRoot = getBestFlightPart()
        if currentRoot and currentRoot ~= root then
            removePhysicsHelpers()
            root = currentRoot
            bodyPos = getOrCreatePhysics(root)
        end

        while State.Running and State.Paused do
            bodyPos.Position = Vector3.new(root.Position.X, safeY, root.Position.Z)
            task.wait(0.2)
        end

        if not State.Running then break end

        local horizontalDist = (Vector3.new(finalDest.X, 0, finalDest.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
        if horizontalDist <= stopDistance then
            bodyPos.Position = finalDest
            return true
        end

        local movedHorizontal = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude
        if movedHorizontal < 0.2 then
            stuckCounter = stuckCounter + 1
            if stuckCounter >= 25 then
                bodyPos.Position = Vector3.new(root.Position.X, safeY + 4, root.Position.Z)
                breakGroundWelds()
                stuckCounter = 0
            end
        else
            stuckCounter = 0
            lastPos = root.Position
        end

        local hDir = (Vector3.new(finalDest.X, 0, finalDest.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Unit
        local nextStepX = root.Position.X + (hDir.X * (speed * 0.1))
        local nextStepZ = root.Position.Z + (hDir.Z * (speed * 0.1))
        bodyPos.Position = Vector3.new(nextStepX, safeY, nextStepZ)
    end

    bodyPos.Position = finalDest
    return false
end

-- ÓRBITAS TÁCTICAS
local function orbitTarget(targetRoot, radius, duration, speed)
    local root = getBestFlightPart()
    if not root or not targetRoot or not targetRoot.Parent or not Point2_Door then return end

    local safeY = Point2_Door.Y + 10
    local endTime = tick() + duration
    local angle = 0
    local bodyPos = getOrCreatePhysics(root)

    while State.Running and not State.Paused and targetRoot.Parent and tick() < endTime do
        RunService.Heartbeat:Wait()
        angle = angle + (speed * 0.05)
        local tPos = targetRoot.Position
        bodyPos.Position = Vector3.new(
            tPos.X + math.cos(angle) * radius,
            safeY,
            tPos.Z + math.sin(angle) * radius
        )
    end
end

-- COFRES SEGUROS
local function lootChestSafe(chestWorldPos, waitTime)
    local root = getBestFlightPart()
    if not root or not Point2_Door then return end

    local safeY = Point2_Door.Y + 10

    flyMoveTo(chestWorldPos, 38, 3, true)
    task.wait(0.2)

    flyMoveTo(chestWorldPos, 25, 2.5, false)
    task.wait(waitTime)

    local returnSky = Vector3.new(chestWorldPos.X, safeY, chestWorldPos.Z)
    flyMoveTo(returnSky, 30, 2.5, false)
    task.wait(0.2)
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

-- PESTAÑA 1: CONTROLES
Tabs.Main:AddSection("Operación")

Tabs.Main:AddButton({
    Title = "▶ PLAY / INICIAR",
    Callback = function()
        if not Point2_Door or not CalculatedCenter then
            Fluent:Notify({ Title = "Sin Coordenadas", Content = "Falta fijar la puerta o el centro.", Duration = 3 })
            return
        end
        State.Running = true
        State.Paused = false
        updateStatus("Iniciado. Evaluando situación...")
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

Tabs.Main:AddToggle("LootChestsQuickToggle", {
    Title = "Saquear Cofres tras Limpiar",
    Default = false,
    Callback = function(Value) State.LootChests = Value end
})

-- PESTAÑA 2: AUTO-KILL / CONDICIONES DE VUELO
Tabs.Death:AddSection("Muerte Asistida para Desbloquear Vuelo")

Tabs.Death:AddButton({
    Title = "💀 Morir en el Aire (Salto + Kill)",
    Description = "Salta y muere en el aire para que el torso nunca se pegue al suelo",
    Callback = function()
        executeAirAutoKill()
    end
})

Tabs.Death:AddButton({
    Title = "🔓 Romper Soldaduras de Suelo Manualmente",
    Description = "Destruye uniones si tu cadáver quedó trabado contra el suelo",
    Callback = function()
        breakGroundWelds()
        local root = getBestFlightPart()
        if root then
            root.AssemblyLinearVelocity = Vector3.new(0, 25, 0)
        end
        Fluent:Notify({ Title = "Soldaduras Eliminadas", Content = "Impulso vertical aplicado.", Duration = 2 })
    end
})

-- PESTAÑA 3: CALIBRACIÓN Y PERSONALIZACIÓN DE COORDENADAS
Tabs.Setup:AddSection("Sobrescribir Puntos en Vivo")

Tabs.Setup:AddButton({
    Title = "Fijar Puerta en Mi Posición Actual",
    Callback = function()
        local root = getBestFlightPart()
        if root then
            Point2_Door = root.Position
            DoorForwardDir = Vector3.new(CalculatedCenter.X - Point2_Door.X, 0, CalculatedCenter.Z - Point2_Door.Z).Unit
            refreshVisualMarkers()
            Fluent:Notify({ Title = "Puerta Actualizada", Content = "Nueva coordenada guardada.", Duration = 2 })
        end
    end
})

Tabs.Setup:AddButton({
    Title = "Fijar Centro en Mi Posición Actual",
    Callback = function()
        local root = getBestFlightPart()
        if root then
            CalculatedCenter = root.Position
            DoorForwardDir = Vector3.new(CalculatedCenter.X - Point2_Door.X, 0, CalculatedCenter.Z - Point2_Door.Z).Unit
            refreshVisualMarkers()
            Fluent:Notify({ Title = "Centro Actualizado", Content = "Nueva coordenada guardada.", Duration = 2 })
        end
    end
})

Tabs.Setup:AddButton({
    Title = "Restaurar Coordenadas Predeterminadas",
    Callback = function()
        Point2_Door = DEFAULT_DOOR
        CalculatedCenter = DEFAULT_CENTER
        DoorForwardDir = Vector3.new(DEFAULT_CENTER.X - DEFAULT_DOOR.X, 0, DEFAULT_CENTER.Z - DEFAULT_DOOR.Z).Unit
        table.clear(CalculatedChests)
        for _, cPos in ipairs(DEFAULT_CHESTS) do
            table.insert(CalculatedChests, cPos)
        end
        refreshVisualMarkers()
        Fluent:Notify({ Title = "Restaurado", Content = "Valores iniciales fijados.", Duration = 2 })
    end
})

-- PESTAÑA 4: COORDS
Tabs.Coords:AddSection("Extraer Coordenadas")

local LiveCoordsParagraph = Tabs.Coords:AddParagraph({
    Title = "Posición en Vivo",
    Content = "X: 0, Y: 0, Z: 0"
})

task.spawn(function()
    while true do
        task.wait(0.3)
        local root = getBestFlightPart()
        if root then
            local p = root.Position
            LiveCoordsParagraph:SetDesc(string.format("X: %.1f | Y: %.1f | Z: %.1f", p.X, p.Y, p.Z))
        end
    end
end)

Tabs.Coords:AddButton({
    Title = "📋 Copiar Mi Posición Actual",
    Callback = function() copyCurrentCoords() end
})

-- PESTAÑA 5: AJUSTES
Tabs.Settings:AddSection("Tiempos")

Tabs.Settings:AddSlider("BaseWaitSlider", {
    Title = "Tiempo de espera en Base (Minutos)",
    Default = 15,
    Min = 5,
    Max = 30,
    Rounding = 0,
    Callback = function(Value) State.BaseNuclearWait = Value * 60 end
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

UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.C then
        copyCurrentCoords()
    end
end)

-- MÁQUINA DE ESTADOS - EJECUCIÓN AUTÓNOMA
task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            if not Point2_Door or not CalculatedCenter or not DoorForwardDir then
                updateStatus("Error: Coordenadas incompletas.")
                State.Running = false
            else
                local root = getBestFlightPart()
                local distToCenter = root and (root.Position - CalculatedCenter).Magnitude or 999
                local alreadyInside = distToCenter < 140

                if not alreadyInside then
                    updateStatus("[1/5] Verificando Puerta...")
                    flyMoveTo(Point2_Door, 35, 4, true)
                    task.wait(0.5)

                    local cd = getDoorCooldownRemaining(Point2_Door)
                    while State.Running and not State.Paused and cd do
                        updateStatus("Puerta Bloqueada. Tiempo: " .. cd)
                        task.wait(2)
                        cd = getDoorCooldownRemaining(Point2_Door)
                    end

                    if not State.Running then break end

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
                end

                flyMoveTo(CalculatedCenter, 40, 3, true)

                -- ESTADO 3: CACERÍA Y BARRIDO CON ÓRBITAS
                updateStatus("[3/5] Barriendo reactor (270 studs) con órbitas...")
                local inCombat = true
                local clearStreak = 0

                while State.Running and not State.Paused and inCombat do
                    task.wait(0.2)
                    local targetModel, targetRoot = getAnyTargetZombie(CalculatedCenter, State.DetectionRadius)

                    if targetModel and targetRoot then
                        clearStreak = 0
                        local name = targetModel.Name
                        updateStatus("Rodeando a " .. name .. " para el dron...")

                        flyMoveTo(targetRoot.Position, 42, 6, true)
                        orbitTarget(targetRoot, 7, 1.8, 4)

                        if targetModel.Parent and targetRoot.Parent then
                            orbitTarget(targetRoot, 15, 2.2, 3)
                        end

                        flyMoveTo(CalculatedCenter, 40, 3, true)
                    else
                        local remaining = countLivingZombiesInReactor(CalculatedCenter, State.DetectionRadius)
                        updateStatus("Verificando sala (270 studs)... Restantes: " .. remaining)
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
                    updateStatus("[4/5] Saqueando los 5 cofres predefinidos...")
                    for _, cPos in ipairs(CalculatedChests) do
                        if not State.Running or State.Paused then break end
                        lootChestSafe(cPos, State.ChestWaitTime)
                    end
                    flyMoveTo(CalculatedCenter, 40, 3, true)
                end

                -- ESTADO 5: RECORRIDO DE GASOLINERAS CADA 3 MINUTOS
                if State.Running and not State.Paused then
                    local cooldownStart = tick()

                    while State.Running and not State.Paused and (tick() - cooldownStart < State.BaseNuclearWait) do
                        local roundStart = tick()

                        updateStatus("[5/5] Viajando a Gasolinera 1...")
                        flyMoveTo(GAS_STATION_1, 55, 4, false)
                        task.wait(0.5)
                        interactWithGasPump(GAS_STATION_1)
                        task.wait(1.5)

                        if not State.Running or State.Paused then break end
                        updateStatus("[5/5] Viajando a Gasolinera 2...")
                        flyMoveTo(GAS_STATION_2, 55, 4, false)
                        task.wait(0.5)
                        interactWithGasPump(GAS_STATION_2)
                        task.wait(1.5)

                        if not State.Running or State.Paused then break end
                        updateStatus("[5/5] En la puerta del Reactor...")
                        flyMoveTo(Point2_Door, 55, 4, true)

                        while State.Running and not State.Paused and (tick() - roundStart < State.GasCycleInterval) do
                            local totalLeft = math.floor(State.BaseNuclearWait - (tick() - cooldownStart))
                            if totalLeft <= 0 then break end

                            local nextGas = math.floor(State.GasCycleInterval - (tick() - roundStart))
                            local mins = math.floor(totalLeft / 60)
                            local secs = totalLeft % 60
                            updateStatus(string.format("Nuclear: %02dm %02ds | Próximo Gas en: %ds", mins, secs, math.max(0, nextGas)))
                            task.wait(1)
                        end
                    end

                    updateStatus("Cooldown terminado. Reiniciando reactor...")
                    task.wait(1)
                end
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Fluent:Notify({
    Title = "REACTOR HUB LISTO",
    Content = "Puerta, centro y 5 cofres predefinidos cargados.",
    Duration = 4
})

Window:SelectTab(1)
