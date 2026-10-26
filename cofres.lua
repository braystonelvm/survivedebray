-- ==============================================================================
-- CHEST ROAMER 3D V2: EXPEDICIÓN ACTIVA + CARGA DINÁMICA DE STREAMING
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local State = {
    Running = false,
    Paused = false,
    NoclipEnabled = false,
    CurrentStatus = "Inactivo",
    FlySpeed = 160,              -- Velocidad de vuelo (configurable de 60 a 260)
    ChestWaitTime = 1.0,         -- Tiempo en cada cofre (1 segundo)
    MapBoundaryRadius = 1250,    -- Distancia máxima de patrulla hacia los bordes
    NearbyRadarRadius = 350,     -- Radio para desviar la ruta hacia cofres recién cargados
    LoopAll = true,              -- Repetir el recorrido de exploración infinitamente
    TotalLooted = 0,
    PatrolStep = 1
}

local KnownChests = {}           -- Lista de cofres cargados en memoria
local VisitedChests = {}         -- Cofres ya visitados en la ronda actual

-- ==============================================================================
-- 1. FÍSICAS DE VUELO 3D Y NOCLIP
-- ==============================================================================

local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function removePhysicsHelpers()
    local root = getRootPart()
    if root then
        local bp = root:FindFirstChild("ChestRoamBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("ChestRoamBG")
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
    local bodyPos = root:FindFirstChild("ChestRoamBP")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "ChestRoamBP"
        bodyPos.MaxForce = Vector3.new(1e6, math.huge, 1e6)
        bodyPos.P = 28000
        bodyPos.D = 900
        bodyPos.Position = initialPos or root.Position
        bodyPos.Parent = root
    end

    local bodyGyro = root:FindFirstChild("ChestRoamBG")
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "ChestRoamBG"
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

-- Vuelo 3D libre hacia cualquier coordenada X, Y, Z
local function flyMoveTo3D(targetPos, speed, stopDistance)
    stopDistance = stopDistance or 3.2
    local root = getRootPart()
    if not root then return false end

    local finalDest = targetPos + Vector3.new(0, 2.2, 0)
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
-- 2. DISCRIMINADOR Y ESCÁNER EN VIVO (CARGA POR PROXIMIDAD)
-- ==============================================================================

local function isChestModel(obj)
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end
    if obj == lp.Character or obj:IsDescendantOf(lp.Character) then return false end

    -- 1. Atributo oficial del servidor
    if obj:GetAttribute("Crate") == true then return true end

    -- 2. Si está dentro de la carpeta Crates
    if obj.Parent and obj.Parent.Name == "Crates" then return true end

    -- 3. Por ProximityPrompt de apertura
    local prompt = obj:FindFirstChildOfClass("ProximityPrompt") or obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
        if text:find("open") or text:find("abrir") or text:find("crate") or text:find("chest") then
            return true
        end
    end

    return false
end

local function registerChest(item)
    if not item or not item.Parent then return end
    if isChestModel(item) and not KnownChests[item] then
        local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
        if part then
            KnownChests[item] = {
                Instance = item,
                Part = part,
                Name = item.Name
            }
        end
    end
end

-- Detección reactiva instantánea cuando el mapa hace Streaming de un cofre
task.spawn(function()
    local mapFolder = workspace:FindFirstChild("Map")
    local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")

    if cratesFolder then
        cratesFolder.ChildAdded:Connect(registerChest)
        for _, c in ipairs(cratesFolder:GetChildren()) do registerChest(c) end
    end

    workspace.DescendantAdded:Connect(function(desc)
        if desc.Parent and desc.Parent.Name == "Crates" then
            registerChest(desc)
        elseif isChestModel(desc) then
            registerChest(desc)
        end
    end)
end)

-- Escaneo de proximidad constante (alrededor de 350 studs)
local function scanLoadedChestsAroundPlayer()
    local root = getRootPart()
    if not root then return end
    local myPos = root.Position

    local mapFolder = workspace:FindFirstChild("Map")
    local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")

    if cratesFolder then
        for _, c in ipairs(cratesFolder:GetChildren()) do registerChest(c) end
    end

    for _, container in ipairs({workspace:FindFirstChild("Structures"), mapFolder}) do
        if container then
            for _, desc in ipairs(container:GetChildren()) do
                if isChestModel(desc) then registerChest(desc) end
            end
        end
    end
end

-- ==============================================================================
-- 3. GENERADOR DE RUTA DE PATRULLA POR EL MAPA (STREAMING TRIGGER)
-- ==============================================================================

local function buildExplorationWaypoints(maxRadius)
    local gen = workspace:FindFirstChild("Generator") or workspace:FindFirstChild("Center")
    local center = (gen and gen:IsA("BasePart") and gen.Position) or BaseCenter
    local waypoints = {}
    local rOuter = maxRadius
    local rMid = maxRadius * 0.55

    -- Anillo exterior para cargar los bordes del mapa
    for angle = 0, 315, 45 do
        local rad = math.rad(angle)
        table.insert(waypoints, Vector3.new(center.X + math.cos(rad) * rOuter, 18, center.Z + math.sin(rad) * rOuter))
    end

    -- Anillo intermedio
    for angle = 22.5, 337.5, 45 do
        local rad = math.rad(angle)
        table.insert(waypoints, Vector3.new(center.X + math.cos(rad) * rMid, 18, center.Z + math.sin(rad) * rMid))
    end

    return waypoints
end

-- ==============================================================================
-- 4. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "CHEST ROAMER 3D | V2.0",
    SubTitle = "Expedición Activa + Streaming Radar",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 480),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main     = Window:AddTab({ Title = "Controles", Icon = "play" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" }),
    Coords   = Window:AddTab({ Title = "Coords", Icon = "clipboard" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Roamer",
    Content = "Inactivo. Presiona PLAY para iniciar el patrullaje exploratorio."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

-- PESTAÑA 1: CONTROLES
Tabs.Main:AddSection("Operación de Vuelo")

Tabs.Main:AddButton({
    Title = "▶ PLAY / INICIAR EXPEDICIÓN DE COFRES",
    Callback = function()
        if State.Running then return end

        State.Running = true
        State.Paused = false
        State.NoclipEnabled = false
        State.PatrolStep = 1
        table.clear(VisitedChests)

        updateStatus("Iniciando Fly seguro...")
        secureFlightStart()

        task.spawn(function()
            for s = 3, 1, -1 do
                if not State.Running then break end
                updateStatus(string.format("Fly activo. Esperando %ds para activar Noclip...", s))
                task.wait(1)
            end

            if State.Running then
                State.NoclipEnabled = true
                updateStatus("Noclip activo. Iniciando vuelo hacia los bordes del mapa para cargar cofres...")
            end
        end)
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
    Title = "⏹ STOP (CANCELAR Y RESTAURAR COLISIONES)",
    Callback = function()
        State.Running = false
        State.Paused = false
        State.NoclipEnabled = false
        removePhysicsHelpers()
        restoreCollisions()
        updateStatus("Detenido. Físicas y colisiones restauradas.")
    end
})

Tabs.Main:AddButton({
    Title = "🔄 REINICIAR LISTA DE COFRES VISITADOS",
    Callback = function()
        table.clear(VisitedChests)
        Fluent:Notify({ Title = "Lista Reiniciada", Content = "Todos los cofres del mapa podrán ser visitados nuevamente.", Duration = 2.5 })
    end
})

-- PESTAÑA 2: AJUSTES
Tabs.Settings:AddSection("Velocidad y Rango de Patrullaje")

Tabs.Settings:AddSlider("FlySpeedSlider", {
    Title = "Velocidad de Vuelo (Studs/seg)",
    Default = 160,
    Min = 60,
    Max = 260,
    Rounding = 0,
    Callback = function(v) State.FlySpeed = v end
})

Tabs.Settings:AddSlider("ChestWaitSlider", {
    Title = "Tiempo de Detención en Cada Cofre (Segundos)",
    Default = 1.0,
    Min = 0.2,
    Max = 5.0,
    Rounding = 1,
    Callback = function(v) State.ChestWaitTime = v end
})

Tabs.Settings:AddSlider("MapBoundarySlider", {
    Title = "Distancia de Patrullaje hacia los Bordes (Studs)",
    Description = "Hasta dónde vuela para obligar al juego a cargar cofres lejanos",
    Default = 1250,
    Min = 600,
    Max = 1600,
    Rounding = 0,
    Callback = function(v) State.MapBoundaryRadius = v end
})

Tabs.Settings:AddSlider("NearbyRadarSlider", {
    Title = "Radio de Desvío hacia Cofres Cargados (Studs)",
    Description = "Distancia a la redonda para detener la patrulla y saquear",
    Default = 350,
    Min = 150,
    Max = 600,
    Rounding = 0,
    Callback = function(v) State.NearbyRadarRadius = v end
})

Tabs.Settings:AddToggle("LoopAllToggle", {
    Title = "Repetir Patrulla en Bucle Infinito",
    Default = true,
    Callback = function(v) State.LoopAll = v end
})

-- PESTAÑA 3: COORDS
Tabs.Coords:AddSection("Posición en Vivo")

local LiveCoordsParagraph = Tabs.Coords:AddParagraph({
    Title = "Posición Actual",
    Content = "X: 0 | Y: 0 | Z: 0"
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
    Callback = function()
        local root = getRootPart()
        if root then
            local p = root.Position
            local str = string.format("Vector3.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
            if setclipboard then setclipboard(str) elseif toclipboard then toclipboard(str) end
            Fluent:Notify({ Title = "Coordenada Copiada", Content = str, Duration = 2.5 })
        end
    end
})

-- ==============================================================================
-- 5. BOTÓN FLOTANTE CIRCULAR (DELTA / MÓVIL)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChestRoamerFloatingGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 20)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- ==============================================================================
-- 6. BUCLE PRINCIPAL: EXPEDICIÓN ACTIVA + SAQUEO OPORTUNISTA
-- ==============================================================================

local function getNearestUnvisitedChestNearby(currentPos, maxDist)
    local best = nil
    local shortest = maxDist

    for inst, data in pairs(KnownChests) do
        if inst and inst.Parent and not VisitedChests[inst] then
            local part = data.Part
            if part and part.Parent then
                local d = (part.Position - currentPos).Magnitude
                if d <= shortest then
                    shortest = d
                    best = {
                        Instance = inst,
                        Part = part,
                        Pos = part.Position,
                        Name = data.Name,
                        Dist = d
                    }
                end
            else
                KnownChests[inst] = nil
            end
        end
    end

    return best
end

task.spawn(function()
    while true do
        task.wait(0.4)

        if State.Running and not State.Paused then
            if not State.NoclipEnabled then
                task.wait(0.3)
                continue
            end

            local root = getRootPart()
            local myPos = root and root.Position or BaseCenter

            -- 1. Actualizar el escáner de memoria
            scanLoadedChestsAroundPlayer()

            -- 2. PRIORIDAD MÁXIMA: Si hay cofres cargados alrededor, saquearlos primero
            local nearbyChest = getNearestUnvisitedChestNearby(myPos, State.NearbyRadarRadius)

            if nearbyChest then
                local cPos = nearbyChest.Pos
                local heightLabel = (cPos.Y > 15) and "Arriba" or ((cPos.Y < -5) and "Bajo Tierra" or "Superficie")

                updateStatus(string.format(
                    "📦 Cofre detectado a %d studs: '%s' [%s]\nVolando a saquear...",
                    math.floor(nearbyChest.Dist), nearbyChest.Name, heightLabel
                ))

                flyMoveTo3D(cPos, State.FlySpeed, 3.5)

                if State.Running and not State.Paused then
                    updateStatus(string.format("Rebuscando '%s' (Esperando %.1fs)...", nearbyChest.Name, State.ChestWaitTime))
                    task.wait(State.ChestWaitTime)
                    VisitedChests[nearbyChest.Instance] = true
                    State.TotalLooted = State.TotalLooted + 1
                end

            -- 3. MODO EXPEDICIÓN: Si no hay cofres cerca, continuar recorriendo el mapa para forzar la carga
            else
                local waypoints = buildExplorationWaypoints(State.MapBoundaryRadius)
                if #waypoints == 0 then continue end

                if State.PatrolStep > #waypoints then
                    if State.LoopAll then
                        State.PatrolStep = 1
                    else
                        updateStatus("✅ Expedición completa de todo el mapa terminada.")
                        State.Running = false
                        removePhysicsHelpers()
                        restoreCollisions()
                        continue
                    end
                end

                local targetWp = waypoints[State.PatrolStep]
                local distToWp = (Vector3.new(targetWp.X, 0, targetWp.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude

                updateStatus(string.format(
                    "🚀 Explorando mapa hacia Punto #%d/%d (Borde: %d studs)\nBuscando cofres ocultos en camino... [Visitados: %d]",
                    State.PatrolStep, #waypoints, math.floor(distToWp), State.TotalLooted
                ))

                -- Volar hacia el waypoint
                local reached = flyMoveTo3D(targetWp, State.FlySpeed, 25.0)
                if reached or distToWp <= 28.0 then
                    State.PatrolStep = State.PatrolStep + 1
                end
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Window:SelectTab(1)
