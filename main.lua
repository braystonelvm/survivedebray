-- ==============================================================================
-- REACTOR NUCLEAR HUB - SISTEMA ORIGINAL ESTABLE CON COFRES FIJOS
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- Coordenadas fijas
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

local State = {
    Running = false,
    Paused = false,
    CurrentStatus = "Inactivo",
    LootChests = true,
    ChestWaitTime = 1.3,
    BaseNuclearWait = 900,
    GasCycleInterval = 180,
    DetectionRadius = 270
}

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
    Coords = Window:AddTab({ Title = "Coords", Icon = "clipboard" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Bot",
    Content = "Inactivo. Presiona PLAY para iniciar."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
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

-- CONTROL DE FÍSICA Y FLOTACIÓN ANCLADA
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
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

RunService.Stepped:Connect(function()
    if State.Running and not State.Paused then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

-- VUELO RÍGIDO (SISTEMA QUE FUNCIONA)
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

-- LECTURA DEL COOLDOWN DE LA PUERTA
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

-- DETECCIÓN GENERAL DE ZOMBIES
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

Tabs.Main:AddToggle("LootChestsToggle", {
    Title = "Saquear Cofres tras Limpiar",
    Default = true,
    Callback = function(Value) State.LootChests = Value end
})

-- PESTAÑA 2: COORDS
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
    Title = "📋 Copiar Mi Posición Actual",
    Callback = function() copyCurrentCoords() end
})

-- PESTAÑA 3: AJUSTES
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

-- MÁQUINA DE ESTADOS AUTÓNOMA
task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            local root = getRootPart()
            local distToCenter = root and (root.Position - CENTER_POS).Magnitude or 999
            local alreadyInside = distToCenter < 140

            if not alreadyInside then
                updateStatus("[1/5] Verificando Puerta...")
                flyMoveTo(DOOR_POS, 35, 4, true)
                task.wait(0.5)

                local cd = getDoorCooldownRemaining(DOOR_POS)
                while State.Running and not State.Paused and cd do
                    updateStatus("Puerta Bloqueada. Tiempo: " .. cd)
                    task.wait(2)
                    cd = getDoorCooldownRemaining(DOOR_POS)
                end

                if not State.Running then break end

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

            while State.Running and not State.Paused and inCombat do
                task.wait(0.2)
                local targetModel, targetRoot = getAnyTargetZombie(CENTER_POS, State.DetectionRadius)

                if targetModel and targetRoot then
                    clearStreak = 0
                    local name = targetModel.Name
                    updateStatus("Cazando: " .. name .. "...")
                    local chaseTimeout = tick() + 12

                    while State.Running and not State.Paused and targetModel.Parent and targetRoot.Parent and tick() < chaseTimeout do
                        local eHum = targetModel:FindFirstChildOfClass("Humanoid")
                        if eHum and eHum.Health <= 0 then break end
                        -- Vuela flotando sobre el zombie a +10 studs sin descender
                        flyMoveTo(targetRoot.Position, 42, 4, true)
                        task.wait(0.15)
                    end
                    flyMoveTo(CENTER_POS, 40, 3, true)
                else
                    local remaining = countLivingZombiesInReactor(CENTER_POS, State.DetectionRadius)
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
            if State.Running and not State.Paused and State.LootChests then
                updateStatus("[4/5] Todos muertos. Saqueando los 5 cofres...")
                for _, cPos in ipairs(CHEST_COORDS) do
                    if not State.Running or State.Paused then break end
                    -- 1. Viaja por el aire justo encima del cofre
                    flyMoveTo(cPos, 38, 3, true)
                    task.wait(0.15)
                    -- 2. Desciende verticalmente a la coordenada del cofre
                    flyMoveTo(cPos, 25, 2.5, false)
                    task.wait(State.ChestWaitTime)
                    -- 3. Sube inmediatamente al aire antes de ir al siguiente
                    flyMoveTo(cPos, 30, 2.5, true)
                end
                flyMoveTo(CENTER_POS, 40, 3, true)
            end

            -- ESTADO 5: RECORRIDO DE GASOLINERAS CADA 3 MINUTOS (DURANTE LOS 15 MINUTOS)
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
                    flyMoveTo(DOOR_POS, 55, 4, true)

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

                updateStatus("Cooldown completado. Reiniciando bucle...")
                task.wait(1)
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Fluent:Notify({
    Title = "REACTOR HUB LISTO",
    Content = "Sistema funcional restaurado con coordenadas exactas.",
    Duration = 4
})

Window:SelectTab(1)
