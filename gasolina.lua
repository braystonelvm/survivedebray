-- ==============================================================================
-- AUTO-FARM EXCLUSIVO DE GASOLINA (3 ESTACIONES, 0% LAG, SIN BLUR)
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer

-- Eliminar desenfoques
pcall(function()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") then obj:Destroy() end
    end
end)

-- 3 Gasolineras proporcionadas
local GAS_STATIONS = {
    Vector3.new(63.0, 2.1, -160.9),
    Vector3.new(176.6, 2.1, 161.5),
    Vector3.new(221.1, 2.3, 181.5)
}

local State = {
    Running = false,
    Paused = false,
    NoclipEnabled = false,
    CurrentStatus = "Inactivo",
    FlySpeed = 150,
    GasStationStop = 4.0,     -- Tiempo interactuando en el surtidor
    RetreatDistance = 18,     -- Retroceso para reiniciar activación
    CurrentIndex = 1,
    TotalFuelRuns = 0
}

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. FÍSICAS DE VUELO Y NOCLIP
-- ==============================================================================

local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function removePhysicsHelpers()
    local root = getRootPart()
    if root then
        local bp = root:FindFirstChild("GasFlyBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("GasFlyBG")
        if bg then bg:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
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
    if State.Running and not State.Paused and State.NoclipEnabled then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

local function getOrCreatePhysics(root, initialPos)
    local bodyPos = root:FindFirstChild("GasFlyBP")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "GasFlyBP"
        bodyPos.MaxForce = Vector3.new(1e6, math.huge, 1e6)
        bodyPos.P = 28000
        bodyPos.D = 900
        bodyPos.Position = initialPos or root.Position
        bodyPos.Parent = root
    end

    local bodyGyro = root:FindFirstChild("GasFlyBG")
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "GasFlyBG"
        bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bodyGyro.CFrame = root.CFrame
        bodyGyro.Parent = root
    end

    return bodyPos, bodyGyro
end

local function secureFlightStart()
    local root = getRootPart()
    if not root then return false end

    root.AssemblyLinearVelocity = Vector3.zero
    local bodyPos = getOrCreatePhysics(root, root.Position + Vector3.new(0, 3, 0))
    bodyPos.Position = root.Position + Vector3.new(0, 3, 0)
    task.wait(0.15)
    return true
end

local function flyMoveTo(targetPos, speed, stopDistance)
    stopDistance = stopDistance or 3.2
    local root = getRootPart()
    if not root then return false end

    local targetY = targetPos.Y + 2.5
    local finalDest = Vector3.new(targetPos.X, targetY, targetPos.Z)
    local bodyPos = getOrCreatePhysics(root, root.Position)
    local timeout = tick() + 25
    local lastPos = root.Position
    local stuckCounter = 0

    while State.Running and tick() < timeout do
        RunService.Heartbeat:Wait()

        while State.Running and State.Paused do
            bodyPos.Position = root.Position
            task.wait(0.2)
        end

        if not State.Running then break end

        local diff = finalDest - root.Position
        local dist = diff.Magnitude

        if dist <= stopDistance then
            bodyPos.Position = finalDest
            return true
        end

        if (root.Position - lastPos).Magnitude < 0.25 then
            stuckCounter = stuckCounter + 1
            if stuckCounter >= 25 then
                bodyPos.Position = root.Position + Vector3.new(0, 4, 0)
                stuckCounter = 0
            end
        else
            stuckCounter = 0
            lastPos = root.Position
        end

        local stepDir = diff.Unit
        local nextStep = root.Position + (stepDir * (speed * 0.1))
        bodyPos.Position = nextStep
    end

    if bodyPos then bodyPos.Position = finalDest end
    return false
end

-- ==============================================================================
-- 2. ACTIVACIÓN DIRECTA DE SURTIDOR
-- ==============================================================================

local function triggerGasPrompt(stationPos)
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local pPart = prompt.Parent
            local pos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition))

            if pos and (pos - stationPos).Magnitude <= 32 then
                prompt.HoldDuration = 0
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 60
                if fireproximityprompt then
                    pcall(function() fireproximityprompt(prompt) end)
                    pcall(function() fireproximityprompt(prompt, 0) end)
                end
            end
        end
    end
end

ProximityPromptService.PromptShown:Connect(function(prompt)
    if State.Running then
        local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
        if text:find("gasolina") or text:find("surtidor") or text:find("gas") or text:find("fuel") or text:find("usar") then
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false
            if fireproximityprompt then
                pcall(function() fireproximityprompt(prompt) end)
                pcall(function() fireproximityprompt(prompt, 0) end)
            end
        end
    end
end)

-- ==============================================================================
-- 3. INTERFAZ LIMPIA Y LIGERA (SIN FLUENT, CERO DESENFOQUES)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GasFarmMasterGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 420, 0, 310)
MainFrame.Position = UDim2.new(0.5, -210, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "  ⛽ FARM DE GASOLINA PURO (3 ESTACIONES)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 75)
StatusBox.Position = UDim2.new(0, 10, 0, 44)
StatusBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
StatusBox.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusBox.TextSize = 10
StatusBox.Font = Enum.Font.Code
StatusBox.TextXAlignment = Enum.TextXAlignment.Left
StatusBox.TextYAlignment = Enum.TextYAlignment.Top
StatusBox.Text = "Presiona INICIAR para farmear gasolina..."
StatusBox.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusBox

local function createBtn(text, color, pos, size, callback)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- Botón 1: Play
createBtn("▶ INICIAR FARM GASOLINA", Color3.fromRGB(30, 150, 70), UDim2.new(0, 10, 0, 128), UDim2.new(0.48, -5, 0, 38), function()
    if State.Running then return end
    State.Running = true
    State.Paused = false
    State.NoclipEnabled = false
    State.CurrentIndex = 1

    State.CurrentStatus = "Iniciando vuelo seguro..."
    secureFlightStart()

    task.spawn(function()
        for s = 3, 1, -1 do
            if not State.Running then break end
            State.CurrentStatus = string.format("Fly activo. Noclip en %ds...", s)
            task.wait(1)
        end
        if State.Running then
            State.NoclipEnabled = true
            State.CurrentStatus = "Noclip activo. Recorriendo estaciones..."
        end
    end)
end)

-- Botón 2: Stop
createBtn("⏹ DETENER Y RESTAURAR", Color3.fromRGB(180, 40, 50), UDim2.new(0.52, 0, 0, 128), UDim2.new(0.48, -10, 0, 38), function()
    State.Running = false
    State.Paused = false
    State.NoclipEnabled = false
    removePhysicsHelpers()
    restoreCollisions()
    State.CurrentStatus = "Detenido. Físicas y colisiones normales."
end)

-- Botón 3: Pausa
createBtn("⏸ PAUSA / REANUDAR", Color3.fromRGB(50, 55, 70), UDim2.new(0, 10, 0, 174), UDim2.new(0.48, -5, 0, 32), function()
    if State.Running then
        State.Paused = not State.Paused
        State.CurrentStatus = State.Paused and "Pausado" or "Reanudado"
    end
end)

-- Botón 4: Ajustar Parada
local TimeBtn
TimeBtn = createBtn("⏱ TIEMPO SURTIDOR: 4s", Color3.fromRGB(40, 90, 140), UDim2.new(0.52, 0, 0, 174), UDim2.new(0.48, -10, 0, 32), function()
    State.GasStationStop = (State.GasStationStop == 4.0) and 6.0 or ((State.GasStationStop == 6.0) and 2.5 or 4.0)
    TimeBtn.Text = string.format("⏱ TIEMPO SURTIDOR: %.1fs", State.GasStationStop)
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "⛽\nGAS"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==============================================================================
-- 4. BUCLE DE FARMEAO CONTINUO DE GASOLINA
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.3)

        if State.Running and not State.Paused then
            if not State.NoclipEnabled then
                task.wait(0.3)
                continue
            end

            for idx = 1, #GAS_STATIONS do
                if not State.Running or State.Paused then break end
                local gasPos = GAS_STATIONS[idx]

                local rootBefore = getRootPart()
                local approachPos = rootBefore and rootBefore.Position or gasPos

                -- 1. VUELO A LA ESTACIÓN
                State.CurrentStatus = string.format("Vuelo a Estación %d/3...", idx)
                flyMoveTo(gasPos, State.FlySpeed, 3.2)
                task.wait(0.15)

                -- 2. ACTIVACIÓN #1
                State.CurrentStatus = string.format("Extrayendo combustible en Estación %d/3...", idx)
                local t1 = tick()
                while State.Running and not State.Paused and (tick() - t1 < State.GasStationStop) do
                    triggerGasPrompt(gasPos)
                    task.wait(0.5)
                end

                if not State.Running or State.Paused then break end

                -- 3. RETROCESO CORTO (18 STUDS) PARA REINICIAR PROMPT
                local dirAway = (approachPos - gasPos).Unit
                if dirAway.Magnitude == 0 or dirAway ~= dirAway then
                    dirAway = Vector3.new(0, 0, 1)
                end
                local retreatPos = Vector3.new(gasPos.X + dirAway.X * State.RetreatDistance, gasPos.Y + 2.5, gasPos.Z + dirAway.Z * State.RetreatDistance)
                flyMoveTo(retreatPos, State.FlySpeed, 2.5)
                task.wait(0.2)

                if not State.Running or State.Paused then break end

                -- 4. SEGUNDO CONTACTO
                State.CurrentStatus = string.format("Reingreso Estación %d/3 (Doble extracción)...", idx)
                flyMoveTo(gasPos, State.FlySpeed, 3.2)
                task.wait(0.15)

                local t2 = tick()
                while State.Running and not State.Paused and (tick() - t2 < State.GasStationStop) do
                    triggerGasPrompt(gasPos)
                    task.wait(0.5)
                end

                State.TotalFuelRuns = State.TotalFuelRuns + 1
            end
        else
            removePhysicsHelpers()
        end
    end
end)

-- Monitor visual
task.spawn(function()
    while true do
        task.wait(0.3)
        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Estaciones Activas: %d\n" ..
            "Extracciones Realizadas: %d\n" ..
            "Velocidad de Vuelo: %d studs/s",
            State.CurrentStatus,
            #GAS_STATIONS,
            State.TotalFuelRuns,
            State.FlySpeed
        )
    end
end)
