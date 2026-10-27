-- ==============================================================================
-- CHEST ROAMER 3D V4: COFRES CERRADOS + MODO FUEL BASE + APAGADO TOTAL EN BASE
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

-- ELIMINAR CUALQUIER EFECTO DE DESENFOQUE / BLUR PREVIO
pcall(function()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") then
            obj:Destroy()
        end
    end
end)

local State = {
    Running = false,
    Paused = false,
    NoclipEnabled = false,
    CurrentStatus = "Inactivo",
    FlySpeed = 160,              -- Velocidad de vuelo (configurable de 60 a 260)
    ChestWaitTime = 1.0,         -- Exactamente 1 segundo en cofres
    MapBoundaryRadius = 1250,    -- Base de patrulla (se expande automáticamente)
    AutoDetectMapExpansion = true,
    NearbyRadarRadius = 350,     -- Radio para desviar la ruta hacia cofres
    ItemRadarRadius = 180,       -- Radio para pasar recogiendo ítems al vuelo
    CollectDroppedItems = true,  -- Recoger ítems pasando por encima
    LoopAll = true,              -- Bucle infinito de exploración
    TotalChestsLooted = 0,
    TotalItemsCollected = 0,
    PatrolStep = 1,
    ReturningToBase = false,

    -- MODO EXCLUSIVO DE COMBUSTIBLE EN BASE
    FuelOnlyMode = false,
    FuelScanRadius = 500         -- Rango alrededor de la base (configurable)
}

local KnownChests = {}           -- Lista de cofres cargados
local VisitedChests = {}         -- Cofres ya visitados en la ronda
local PassedItemsCooldown = {}   -- Evita atascarse si la mochila se llena

local PickUpRemote = nil
task.spawn(function()
    local rem = ReplicatedStorage:WaitForChild("Remotes", 5)
    local inter = rem and rem:WaitForChild("Interaction", 5)
    if inter then
        PickUpRemote = inter:WaitForChild("PickUpItem", 5)
    end
end)

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

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
-- 2. DETECCIÓN DE COFRES (OMITE COFRES ABIERTOS)
-- ==============================================================================

local function isChestModel(obj)
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end
    if obj == lp.Character or obj:IsDescendantOf(lp.Character) then return false end

    -- 1. FILTRO: DESCARTAR COFRES YA ABIERTOS O SAQUEADOS
    if obj:GetAttribute("Open") == true 
       or obj:GetAttribute("Opened") == true 
       or obj:GetAttribute("Looted") == true 
       or obj:GetAttribute("Empty") == true then
        return false
    end

    -- 2. VERIFICACIÓN DEL PROMPT
    local prompt = obj:FindFirstChildOfClass("ProximityPrompt") or obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        -- Si el prompt está deshabilitado, el cofre ya fue abierto
        if not prompt.Enabled then
            return false
        end
        local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
        if text:find("open") or text:find("abrir") or text:find("crate") or text:find("chest") then
            return true
        end
    end

    -- 3. POR ATRIBUTO O CARPETA
    if obj:GetAttribute("Crate") == true then return true end
    if obj.Parent and obj.Parent.Name == "Crates" then return true end

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

local function scanLoadedChestsAroundPlayer()
    local root = getRootPart()
    if not root then return end

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
-- 3. DETECCIÓN DE ÍTEMS Y GALONES DE GASOLINA
-- ==============================================================================

local function isCollectableDroppedItem(item)
    if not item or not item.Parent then return false end
    if item == lp.Character or item:IsDescendantOf(lp.Character) then return false end

    local n = item.Name:lower()
    local itemType = tostring(item:GetAttribute("ItemType") or ""):lower()
    local toolType = tostring(item:GetAttribute("ToolType") or ""):lower()

    if itemType == "food" or n:find("carrot") then
        return false
    end

    if item:GetAttribute("CanPickUp") ~= nil 
       or item:GetAttribute("ToolLoaded") == true 
       or item:GetAttribute("Tier") ~= nil 
       or item:IsA("Tool") 
       or itemType == "ammo" 
       or toolType ~= "" 
       or n:find("ammo") 
       or n:find("medkit") 
       or n:find("bandage") 
       or n:find("turret") 
       or n:find("wire") 
       or n:find("gun") 
       or n:find("shotgun") 
       or n:find("rifle") 
       or n:find("gas") 
       or n:find("grenade") 
       or n:find("molotov") then
        return true
    end

    return false
end

local function getNearestLootItem(currentPos, maxDist)
    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local best = nil
    local shortest = maxDist
    local now = tick()

    for _, item in ipairs(dropped:GetChildren()) do
        if not (PassedItemsCooldown[item] and now < PassedItemsCooldown[item]) then
            if isCollectableDroppedItem(item) then
                local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                if part then
                    local d = (part.Position - currentPos).Magnitude
                    if d < shortest then
                        shortest = d
                        best = {
                            Instance = item,
                            Part = part,
                            Pos = part.Position,
                            Name = item.Name,
                            Dist = d
                        }
                    end
                end
            end
        end
    end

    return best
end

-- Selector exclusivo para galones de gasolina en radio de base
local function getNearestBaseFuelCan(currentPos)
    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local best = nil
    local shortest = math.huge
    local now = tick()

    for _, item in ipairs(dropped:GetChildren()) do
        if not (PassedItemsCooldown[item] and now < PassedItemsCooldown[item]) then
            local n = item.Name:lower()
            local isFuel = (n == "fuel" or n == "refined fuel" or n:find("fuel") or n:find("gas") or n:find("jerry")) and not n:find("mask")
            if isFuel then
                local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                if part then
                    local distFromBase = (Vector3.new(part.Position.X, 0, part.Position.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
                    if distFromBase <= State.FuelScanRadius then
                        local d = (part.Position - currentPos).Magnitude
                        if d < shortest then
                            shortest = d
                            best = {
                                Instance = item,
                                Part = part,
                                Pos = part.Position,
                                Name = item.Name,
                                Dist = d
                            }
                        end
                    end
                end
            end
        end
    end

    return best
end

-- ==============================================================================
-- 4. ADAPTACIÓN AUTOMÁTICA AL TAMAÑO DEL MAPA (AMPLIACIONES)
-- ==============================================================================

local function getEffectiveMapRadius()
    if not State.AutoDetectMapExpansion then
        return State.MapBoundaryRadius
    end

    local rawRadius = workspace:GetAttribute("MapRadius") or workspace:GetAttribute("WorldRadius")
    if rawRadius and type(rawRadius) == "number" then
        if rawRadius < 100 then
            return math.clamp(rawRadius * 32, 700, 2200)
        else
            return math.clamp(rawRadius, 700, 2500)
        end
    end

    return State.MapBoundaryRadius
end

local function buildExplorationWaypoints()
    local maxRadius = getEffectiveMapRadius()
    local gen = workspace:FindFirstChild("Generator") or workspace:FindFirstChild("Center")
    local center = (gen and gen:IsA("BasePart") and gen.Position) or BaseCenter
    local waypoints = {}
    local rOuter = maxRadius
    local rMid = maxRadius * 0.55

    for angle = 0, 315, 45 do
        local rad = math.rad(angle)
        table.insert(waypoints, Vector3.new(center.X + math.cos(rad) * rOuter, 18, center.Z + math.sin(rad) * rOuter))
    end

    for angle = 22.5, 337.5, 45 do
        local rad = math.rad(angle)
        table.insert(waypoints, Vector3.new(center.X + math.cos(rad) * rMid, 18, center.Z + math.sin(rad) * rMid))
    end

    return waypoints
end

-- ==============================================================================
-- 5. ACCIÓN: VOLVER A LA BASE Y APAGAR TODO
-- ==============================================================================

local function executeReturnToBaseAndShutdown()
    if not State.Running then
        State.Running = true
        secureFlightStart()
        State.NoclipEnabled = true
    end

    State.ReturningToBase = true
    State.CurrentStatus = "🚀 Volviendo a la Base..."

    flyMoveTo3D(BaseCenter + Vector3.new(0, 4.0, 0), State.FlySpeed, 4.0)

    -- APAGAR TOTALMENTE TODAS LAS MODIFICACIONES AL LLEGAR
    State.Running = false
    State.Paused = false
    State.NoclipEnabled = false
    State.ReturningToBase = false

    removePhysicsHelpers()
    restoreCollisions()

    State.CurrentStatus = "🟢 En Base: Todas las modificaciones apagadas."
    Fluent:Notify({ Title = "Llegada Exitosa", Content = "En la base. Físicas normales restauradas y bot apagado.", Duration = 3 })
end

-- ==============================================================================
-- 6. INTERFAZ FLUENT (ACRYLIC = FALSE / CERO DIFUMINACIÓN)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "CHEST & LOOT ROAMER | V4.0",
    SubTitle = "Cofres Cerrados + Fuel Base + Salida Limpia",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 500),
    Acrylic = false,
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
    Content = "Inactivo. Presiona PLAY para iniciar."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

-- PESTAÑA 1: CONTROLES
Tabs.Main:AddSection("Operación de Vuelo")

Tabs.Main:AddButton({
    Title = "▶ PLAY / INICIAR EXPEDICIÓN",
    Callback = function()
        if State.Running then return end

        State.Running = true
        State.Paused = false
        State.NoclipEnabled = false
        State.ReturningToBase = false
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
                updateStatus(State.FuelOnlyMode and "Modo Fuel Base activo..." or "Noclip activo. Explorando mapa...")
            end
        end)
    end
})

Tabs.Main:AddButton({
    Title = "🏠 VOLVER A LA BASE Y APAGAR TODO",
    Description = "Vuela al centro, desactiva Fly/Noclip y restaura físicas",
    Callback = executeReturnToBaseAndShutdown
})

Tabs.Main:AddToggle("FuelOnlyToggle", {
    Title = "⛽ MODO EXCLUSIVO: Solo Recolectar Fuel en Base",
    Description = "Omite patrulla y va únicamente a galones de gasolina cerca de la base",
    Default = false,
    Callback = function(v) State.FuelOnlyMode = v end
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
        State.ReturningToBase = false
        removePhysicsHelpers()
        restoreCollisions()
        updateStatus("Detenido. Físicas y colisiones restauradas.")
    end
})

Tabs.Main:AddButton({
    Title = "🔄 REINICIAR LISTA DE COFRES VISITADOS",
    Callback = function()
        table.clear(VisitedChests)
        table.clear(PassedItemsCooldown)
        Fluent:Notify({ Title = "Ruta Reiniciada", Content = "Todos los cofres cerrados podrán visitarse nuevamente.", Duration = 2.5 })
    end
})

-- PESTAÑA 2: AJUSTES
Tabs.Settings:AddSection("Ajustes de Combustible y Velocidad")

Tabs.Settings:AddSlider("FuelRadiusSlider", {
    Title = "Radio para Recolectar Fuel en Base (Studs)",
    Description = "Por defecto 500 studs alrededor del centro",
    Default = 500,
    Min = 150,
    Max = 1200,
    Rounding = 0,
    Callback = function(v) State.FuelScanRadius = v end
})

Tabs.Settings:AddSlider("FlySpeedSlider", {
    Title = "Velocidad de Vuelo (Studs/seg)",
    Default = 160,
    Min = 60,
    Max = 260,
    Rounding = 0,
    Callback = function(v) State.FlySpeed = v end
})

Tabs.Settings:AddSlider("ChestWaitSlider", {
    Title = "Tiempo de Espera SOLO en Cofres (Segundos)",
    Description = "Los ítems sueltos se recogen en 0 segundos (al vuelo)",
    Default = 1.0,
    Min = 0.2,
    Max = 5.0,
    Rounding = 1,
    Callback = function(v) State.ChestWaitTime = v end
})

Tabs.Settings:AddToggle("CollectItemsToggle", {
    Title = "Recoger Ítems Sueltos al Vuelo (Armas/Balas/Medkits)",
    Default = true,
    Callback = function(v) State.CollectDroppedItems = v end
})

Tabs.Settings:AddSlider("NearbyRadarSlider", {
    Title = "Radio para Desviar hacia Cofres (Studs)",
    Default = 350,
    Min = 150,
    Max = 600,
    Rounding = 0,
    Callback = function(v) State.NearbyRadarRadius = v end
})

Tabs.Settings:AddSlider("ItemRadarSlider", {
    Title = "Radio de Detección de Ítems Cercanos (Studs)",
    Default = 180,
    Min = 80,
    Max = 400,
    Rounding = 0,
    Callback = function(v) State.ItemRadarRadius = v end
})

Tabs.Settings:AddToggle("AutoMapRadiusToggle", {
    Title = "Adaptar Radio Automático según Ampliación del Mapa",
    Default = true,
    Callback = function(v) State.AutoDetectMapExpansion = v end
})

Tabs.Settings:AddSlider("MapBoundarySlider", {
    Title = "Límite Máximo Manual de Borde (Studs)",
    Default = 1250,
    Min = 600,
    Max = 2000,
    Rounding = 0,
    Callback = function(v) State.MapBoundaryRadius = v end
})

Tabs.Settings:AddToggle("LoopAllToggle", {
    Title = "Bucle Infinito de Patrulla",
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
end)

-- ==============================================================================
-- 7. BOTONES FLOTANTES CIRCULARES (DELTA / MÓVIL)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChestRoamerFloatingGuiV4"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón 1: Menú
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

-- Botón 2: Volver a la Base y Apagar Todo
local BaseBtn = Instance.new("TextButton")
BaseBtn.Size = UDim2.new(0, 48, 0, 48)
BaseBtn.Position = UDim2.new(0.04, 0, 0.49, 0)
BaseBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 70)
BaseBtn.Text = "🏠\nBASE"
BaseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BaseBtn.TextSize = 10
BaseBtn.Font = Enum.Font.GothamBold
BaseBtn.Active = true
BaseBtn.Draggable = true
BaseBtn.Parent = ScreenGui

local BaseCorner = Instance.new("UICorner")
BaseCorner.CornerRadius = UDim.new(1, 0)
BaseCorner.Parent = BaseBtn

BaseBtn.MouseButton1Click:Connect(executeReturnToBaseAndShutdown)

-- ==============================================================================
-- 8. BUCLE PRINCIPAL DE NAVEGACIÓN
-- ==============================================================================

local function getNearestUnvisitedChestNearby(currentPos, maxDist)
    local best = nil
    local shortest = maxDist

    for inst, data in pairs(KnownChests) do
        if inst and inst.Parent and not VisitedChests[inst] then
            -- Omitir si se abrió mientras estábamos en camino
            if isChestModel(inst) then
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
            else
                VisitedChests[inst] = true
            end
        end
    end

    return best
end

task.spawn(function()
    while true do
        task.wait(0.3)

        if State.Running and not State.Paused and not State.ReturningToBase then
            if not State.NoclipEnabled then
                task.wait(0.3)
                continue
            end

            local root = getRootPart()
            local myPos = root and root.Position or BaseCenter

            -- ==================================================================
            -- MODO EXCLUSIVO: SOLO RECOLECTAR FUEL EN EL RADIO DE LA BASE
            -- ==================================================================
            if State.FuelOnlyMode then
                local fuelTarget = getNearestBaseFuelCan(myPos)
                if fuelTarget then
                    updateStatus(string.format("⛽ Yendo a galón de combustible (%d studs de ti)...", math.floor(fuelTarget.Dist)))

                    flyMoveTo3D(fuelTarget.Pos, State.FlySpeed, 2.8)

                    if PickUpRemote and fuelTarget.Instance and fuelTarget.Instance.Parent then
                        pcall(function() PickUpRemote:FireServer(fuelTarget.Instance) end)
                    end

                    PassedItemsCooldown[fuelTarget.Instance] = tick() + 10
                    State.TotalItemsCollected = State.TotalItemsCollected + 1
                else
                    updateStatus(string.format("⛽ Sin más galones dentro de %d studs de la base.", State.FuelScanRadius))
                    task.wait(1.0)
                end

            -- ==================================================================
            -- MODO EXPEDICIÓN NORMAL (COFRES CERRADOS + ÍTEMS AL VUELO)
            -- ==================================================================
            else
                scanLoadedChestsAroundPlayer()

                -- 1. PRIORIDAD MÁXIMA: Cofre cerrado cercano (Espera 1 segundo)
                local nearbyChest = getNearestUnvisitedChestNearby(myPos, State.NearbyRadarRadius)

                if nearbyChest then
                    local cPos = nearbyChest.Pos
                    local heightLabel = (cPos.Y > 15) and "Arriba" or ((cPos.Y < -5) and "Bajo Tierra" or "Superficie")

                    updateStatus(string.format(
                        "📦 Cofre CERRADO a %d studs: '%s' [%s]\nVolando a saquear...",
                        math.floor(nearbyChest.Dist), nearbyChest.Name, heightLabel
                    ))

                    flyMoveTo3D(cPos, State.FlySpeed, 3.5)

                    if State.Running and not State.Paused and not State.ReturningToBase then
                        updateStatus(string.format("Rebuscando '%s' (Esperando %.1fs)...", nearbyChest.Name, State.ChestWaitTime))
                        task.wait(State.ChestWaitTime)
                        VisitedChests[nearbyChest.Instance] = true
                        State.TotalChestsLooted = State.TotalChestsLooted + 1
                    end

                -- 2. PRIORIDAD MEDIA: Ítem del suelo cerca (Pasa volando por él a 0s de espera)
                elseif State.CollectDroppedItems and getNearestLootItem(myPos, State.ItemRadarRadius) then
                    local loot = getNearestLootItem(myPos, State.ItemRadarRadius)
                    if loot then
                        updateStatus(string.format("⚡ Pasando por: '%s' (0s espera)...", loot.Name))

                        flyMoveTo3D(loot.Pos, State.FlySpeed, 2.8)

                        if PickUpRemote and loot.Instance and loot.Instance.Parent then
                            pcall(function() PickUpRemote:FireServer(loot.Instance) end)
                        end

                        PassedItemsCooldown[loot.Instance] = tick() + 15
                        State.TotalItemsCollected = State.TotalItemsCollected + 1
                    end

                -- 3. MODO PATRULLA: Recorrer el mapa para forzar Streaming de zonas nuevas
                else
                    local waypoints = buildExplorationWaypoints()
                    if #waypoints == 0 then continue end

                    if State.PatrolStep > #waypoints then
                        if State.LoopAll then
                            State.PatrolStep = 1
                        else
                            updateStatus("✅ Expedición del mapa completada.")
                            State.Running = false
                            removePhysicsHelpers()
                            restoreCollisions()
                            continue
                        end
                    end

                    local targetWp = waypoints[State.PatrolStep]
                    local distToWp = (Vector3.new(targetWp.X, 0, targetWp.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                    local currentRad = getEffectiveMapRadius()

                    updateStatus(string.format(
                        "🚀 Patrulla hacia Punto #%d/%d (Borde: %d studs)\nCofres: %d | Ítems recogidos: %d",
                        State.PatrolStep, #waypoints, math.floor(currentRad),
                        State.TotalChestsLooted, State.TotalItemsCollected
                    ))

                    local reached = flyMoveTo3D(targetWp, State.FlySpeed, 25.0)
                    if reached or distToWp <= 28.0 then
                        State.PatrolStep = State.PatrolStep + 1
                    end
                end
            end
        elseif not State.Running then
            removePhysicsHelpers()
        end
    end
end)

Window:SelectTab(1)
