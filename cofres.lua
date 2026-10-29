-- ==============================================================================
-- CHEST & LOOT ROAMER V5 (OMISIÓN DE BASE + STOP LIMPIO + FUEL CONFIGURABLE)
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)
local BASE_SAFE_RADIUS = 145 -- Radio de la base donde NO tocará nada (cofres, ítems ni gasolinas)

-- Eliminar desenfoques previos
pcall(function()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") then obj:Destroy() end
    end
end)

local State = {
    Running = false,
    Paused = false,
    NoclipEnabled = false,
    CurrentStatus = "Inactivo",
    FlySpeed = 160,
    ChestWaitTime = 1.0,
    MapBoundaryRadius = 1250,
    NearbyRadarRadius = 350,
    ItemRadarRadius = 180,
    CollectDroppedItems = true,
    LoopAll = true,
    TotalChestsLooted = 0,
    TotalItemsCollected = 0,
    PatrolStep = 1,
    ReturningToBase = false,

    -- MODO FUEL
    FuelOnlyMode = false,
    FuelScanRadius = 500
}

local KnownChests = {}
local VisitedChests = {}
local PassedItemsCooldown = {}

local PickUpRemote = nil
task.spawn(function()
    local rem = ReplicatedStorage:WaitForChild("Remotes", 5)
    local inter = rem and rem:WaitForChild("Interaction", 5)
    if inter then
        PickUpRemote = inter:WaitForChild("PickUpItem", 5)
    end
end)

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. FÍSICAS DE VUELO, NOCLIP Y LIMPIEZA TOTAL
-- ==============================================================================

local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function restoreCollisions()
    local char = lp.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

-- Limpieza exhaustiva de todas las modificaciones y restricciones de vuelo/altura
local function removeAllModifications()
    local root = getRootPart()
    local char = lp.Character

    -- 1. Destruir helpers de vuelo propios y de scripts anteriores
    if root then
        for _, obj in ipairs(root:GetChildren()) do
            if obj.Name:find("BP") or obj.Name:find("BG") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then
                obj:Destroy()
            end
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.Freefall)
        end
    end

    -- 2. Restaurar colisiones en todas las partes del personaje
    restoreCollisions()
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
-- 2. DETECCIÓN DE COFRES (OMITE ABIERTOS Y OMITE LA BASE)
-- ==============================================================================

local function isInsideBase(pos)
    local horiz = Vector3.new(pos.X - BaseCenter.X, 0, pos.Z - BaseCenter.Z)
    return horiz.Magnitude <= BASE_SAFE_RADIUS
end

local function isChestModel(obj)
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end
    if obj == lp.Character or obj:IsDescendantOf(lp.Character) then return false end

    -- 1. FILTRO: DESCARTAR COFRES DENTRO DE LA BASE
    local part = obj:IsA("BasePart") and obj or (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart"))
    if part and isInsideBase(part.Position) then
        return false
    end

    -- 2. FILTRO: DESCARTAR COFRES YA ABIERTOS O SAQUEADOS
    if obj:GetAttribute("Open") == true 
       or obj:GetAttribute("Opened") == true 
       or obj:GetAttribute("Looted") == true 
       or obj:GetAttribute("Empty") == true then
        return false
    end

    local prompt = obj:FindFirstChildOfClass("ProximityPrompt") or obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        if not prompt.Enabled then return false end
        local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
        if text:find("open") or text:find("abrir") or text:find("crate") or text:find("chest") then
            return true
        end
    end

    if obj:GetAttribute("Crate") == true then return true end
    if obj.Parent and obj.Parent.Name == "Crates" then return true end

    return false
end

local function registerChest(item)
    if not item or not item.Parent then return end
    if isChestModel(item) and not KnownChests[item] then
        local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
        if part and not isInsideBase(part.Position) then
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
-- 3. DETECCIÓN DE ÍTEMS Y GALONES (OMITE LA BASE)
-- ==============================================================================

local function isCollectableDroppedItem(item)
    if not item or not item.Parent then return false end
    if item == lp.Character or item:IsDescendantOf(lp.Character) then return false end

    local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
    if not part or isInsideBase(part.Position) then
        return false
    end

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
                if part and not isInsideBase(part.Position) then
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

-- Selector de galones: entre el límite de la base y el radio configurado
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

                    -- Excluir los que ya están dentro de la base (<= 145 studs) y respetar el límite exterior configurado
                    if distFromBase > BASE_SAFE_RADIUS and distFromBase <= State.FuelScanRadius then
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
-- 4. WAYPOINTS DE PATRULLA
-- ==============================================================================

local function getEffectiveMapRadius()
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
    local rMid = math.max(BASE_SAFE_RADIUS + 80, maxRadius * 0.55)

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
-- 5. ACCIONES DE APAGADO Y RETORNO
-- ==============================================================================

-- 1. Detener en seco y dejar el personaje como nuevo
local function executeImmediateStopAndClean()
    State.Running = false
    State.Paused = false
    State.NoclipEnabled = false
    State.ReturningToBase = false

    removeAllModifications()
    State.CurrentStatus = "Detenido. Modificaciones eliminadas (Personaje normal)."
end

-- 2. Ir a la base primero y luego apagar absolutamente todo
local function executeReturnToBaseAndShutdown()
    if not State.Running then
        State.Running = true
        secureFlightStart()
        State.NoclipEnabled = true
    end

    State.ReturningToBase = true
    State.CurrentStatus = "🚀 Volviendo a la Base..."

    flyMoveTo3D(BaseCenter + Vector3.new(0, 3.5, 0), State.FlySpeed, 4.0)

    -- APAGAR TOTALMENTE AL LLEGAR
    executeImmediateStopAndClean()
    State.CurrentStatus = "🟢 En Base: Todas las modificaciones apagadas."
end

-- ==============================================================================
-- 6. INTERFAZ NATIVA (0% LAG - SIN DEPENDENCIAS EXTERNAS)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChestRoamerCleanGuiV5"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 440, 0, 360)
MainFrame.Position = UDim2.new(0.5, -220, 0.5, -180)
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
TitleBar.Text = "  📦 CHEST & LOOT ROAMER V5 (BASE EXCLUIDA)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 80)
StatusBox.Position = UDim2.new(0, 10, 0, 44)
StatusBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
StatusBox.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusBox.TextSize = 10
StatusBox.Font = Enum.Font.Code
StatusBox.TextXAlignment = Enum.TextXAlignment.Left
StatusBox.TextYAlignment = Enum.TextYAlignment.Top
StatusBox.Text = "Iniciando sistema..."
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

-- Botón 1: Iniciar
createBtn("▶ INICIAR EXPEDICIÓN", Color3.fromRGB(30, 150, 70), UDim2.new(0, 10, 0, 134), UDim2.new(0.48, -5, 0, 38), function()
    if State.Running then return end
    State.Running = true
    State.Paused = false
    State.NoclipEnabled = false
    State.ReturningToBase = false
    State.PatrolStep = 1
    table.clear(VisitedChests)

    State.CurrentStatus = "Iniciando Fly seguro..."
    secureFlightStart()

    task.spawn(function()
        for s = 3, 1, -1 do
            if not State.Running then break end
            State.CurrentStatus = string.format("Fly activo. Noclip en %ds...", s)
            task.wait(1)
        end
        if State.Running then
            State.NoclipEnabled = true
            State.CurrentStatus = State.FuelOnlyMode and "Modo Fuel Base activo..." or "Explorando mapa (Base excluida)..."
        end
    end)
end)

-- Botón 2: Volver a Base y Apagar
createBtn("🏠 BASE Y APAGAR", Color3.fromRGB(40, 130, 80), UDim2.new(0.52, 0, 0, 134), UDim2.new(0.48, -10, 0, 38), executeReturnToBaseAndShutdown)

-- Botón 3: Toggle Fuel Fuera de Base
local FuelBtn
FuelBtn = createBtn("⛽ SOLO FUEL (EXTERIOR): OFF", Color3.fromRGB(45, 50, 65), UDim2.new(0, 10, 0, 180), UDim2.new(1, -20, 0, 34), function()
    State.FuelOnlyMode = not State.FuelOnlyMode
    if State.FuelOnlyMode then
        FuelBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
        FuelBtn.Text = string.format("⛽ SOLO FUEL: ON (%d-%d STUDS)", BASE_SAFE_RADIUS, State.FuelScanRadius)
    else
        FuelBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
        FuelBtn.Text = "⛽ SOLO FUEL (EXTERIOR): OFF"
    end
end)

-- Botón 4: STOP Y LIMPIAR TODO
createBtn("⏹ STOP Y LIMPIAR TODO", Color3.fromRGB(180, 40, 50), UDim2.new(0, 10, 0, 222), UDim2.new(0.48, -5, 0, 32), executeImmediateStopAndClean)

-- Botón 5: Pausa
createBtn("⏸ PAUSA / REANUDAR", Color3.fromRGB(60, 65, 80), UDim2.new(0.52, 0, 0, 222), UDim2.new(0.48, -10, 0, 32), function()
    if State.Running then
        State.Paused = not State.Paused
        State.CurrentStatus = State.Paused and "Pausado manualmente" or "Reanudado"
    end
end)

-- Botón 6: Configurar Radio de Fuel (+/- 100)
createBtn("➖ RADIO FUEL (-100)", Color3.fromRGB(35, 40, 50), UDim2.new(0, 10, 0, 262), UDim2.new(0.48, -5, 0, 28), function()
    State.FuelScanRadius = math.max(BASE_SAFE_RADIUS + 50, State.FuelScanRadius - 100)
    if State.FuelOnlyMode then
        FuelBtn.Text = string.format("⛽ SOLO FUEL: ON (%d-%d STUDS)", BASE_SAFE_RADIUS, State.FuelScanRadius)
    end
end)

createBtn("➕ RADIO FUEL (+100)", Color3.fromRGB(35, 40, 50), UDim2.new(0.52, 0, 0, 262), UDim2.new(0.48, -10, 0, 28), function()
    State.FuelScanRadius = math.min(1500, State.FuelScanRadius + 100)
    if State.FuelOnlyMode then
        FuelBtn.Text = string.format("⛽ SOLO FUEL: ON (%d-%d STUDS)", BASE_SAFE_RADIUS, State.FuelScanRadius)
    end
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "📦\nROAM"
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

-- Botón Flotante Rápido: Volver a Base y Apagar
local QuickBaseBtn = Instance.new("TextButton")
QuickBaseBtn.Size = UDim2.new(0, 48, 0, 48)
QuickBaseBtn.Position = UDim2.new(0.04, 0, 0.49, 0)
QuickBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 70)
QuickBaseBtn.Text = "🏠\nBASE"
QuickBaseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
QuickBaseBtn.TextSize = 10
QuickBaseBtn.Font = Enum.Font.GothamBold
QuickBaseBtn.Active = true
QuickBaseBtn.Draggable = true
QuickBaseBtn.Parent = ScreenGui

local QuickBaseCorner = Instance.new("UICorner")
QuickBaseCorner.CornerRadius = UDim.new(1, 0)
QuickBaseCorner.Parent = QuickBaseBtn

QuickBaseBtn.MouseButton1Click:Connect(executeReturnToBaseAndShutdown)

-- ==============================================================================
-- 7. BUCLE PRINCIPAL DE NAVEGACIÓN
-- ==============================================================================

local function getNearestUnvisitedChestNearby(currentPos, maxDist)
    local best = nil
    local shortest = maxDist

    for inst, data in pairs(KnownChests) do
        if inst and inst.Parent and not VisitedChests[inst] then
            if isChestModel(inst) then
                local part = data.Part
                if part and part.Parent and not isInsideBase(part.Position) then
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

            -- MODO FUEL
            if State.FuelOnlyMode then
                local fuelTarget = getNearestBaseFuelCan(myPos)
                if fuelTarget then
                    State.CurrentStatus = string.format("⛽ Yendo a galón (%d studs)...", math.floor(fuelTarget.Dist))
                    flyMoveTo3D(fuelTarget.Pos, State.FlySpeed, 2.8)

                    if PickUpRemote and fuelTarget.Instance and fuelTarget.Instance.Parent then
                        pcall(function() PickUpRemote:FireServer(fuelTarget.Instance) end)
                    end

                    PassedItemsCooldown[fuelTarget.Instance] = tick() + 10
                    State.TotalItemsCollected = State.TotalItemsCollected + 1
                else
                    State.CurrentStatus = string.format("⛽ Sin galones en radio exterior (%d studs).", State.FuelScanRadius)
                    task.wait(1.0)
                end

            -- MODO EXPEDICIÓN
            else
                scanLoadedChestsAroundPlayer()

                local nearbyChest = getNearestUnvisitedChestNearby(myPos, State.NearbyRadarRadius)

                if nearbyChest then
                    State.CurrentStatus = string.format("📦 Cofre CERRADO a %d studs: '%s'", math.floor(nearbyChest.Dist), nearbyChest.Name)
                    flyMoveTo3D(nearbyChest.Pos, State.FlySpeed, 3.5)

                    if State.Running and not State.Paused and not State.ReturningToBase then
                        State.CurrentStatus = string.format("Rebuscando '%s' (1s)...", nearbyChest.Name)
                        task.wait(State.ChestWaitTime)
                        VisitedChests[nearbyChest.Instance] = true
                        State.TotalChestsLooted = State.TotalChestsLooted + 1
                    end

                elseif State.CollectDroppedItems and getNearestLootItem(myPos, State.ItemRadarRadius) then
                    local loot = getNearestLootItem(myPos, State.ItemRadarRadius)
                    if loot then
                        State.CurrentStatus = string.format("⚡ Pasando por: '%s' (0s)...", loot.Name)
                        flyMoveTo3D(loot.Pos, State.FlySpeed, 2.8)

                        if PickUpRemote and loot.Instance and loot.Instance.Parent then
                            pcall(function() PickUpRemote:FireServer(loot.Instance) end)
                        end

                        PassedItemsCooldown[loot.Instance] = tick() + 15
                        State.TotalItemsCollected = State.TotalItemsCollected + 1
                    end

                else
                    local waypoints = buildExplorationWaypoints()
                    if #waypoints > 0 then
                        if State.PatrolStep > #waypoints then
                            if State.LoopAll then
                                State.PatrolStep = 1
                            else
                                executeReturnToBaseAndShutdown()
                                continue
                            end
                        end

                        local targetWp = waypoints[State.PatrolStep]
                        local distToWp = (Vector3.new(targetWp.X, 0, targetWp.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude

                        State.CurrentStatus = string.format("🚀 Explorando hacia Punto #%d/%d (%d studs)...", State.PatrolStep, #waypoints, math.floor(distToWp))
                        local reached = flyMoveTo3D(targetWp, State.FlySpeed, 25.0)
                        if reached or distToWp <= 28.0 then
                            State.PatrolStep = State.PatrolStep + 1
                        end
                    end
                end
            end
        elseif not State.Running then
            removeAllModifications()
        end
    end
end)

-- Monitor visual de estado
task.spawn(function()
    while true do
        task.wait(0.3)
        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Modo Fuel Exterior: %s (%d-%d studs)\n" ..
            "Base Protegida (Omitida): %d studs del centro\n" ..
            "Cofres Cerrados Saqueados: %d | Ítems: %d",
            State.CurrentStatus,
            State.FuelOnlyMode and "ACTIVADO" or "DESACTIVADO",
            BASE_SAFE_RADIUS,
            State.FuelScanRadius,
            BASE_SAFE_RADIUS,
            State.TotalChestsLooted,
            State.TotalItemsCollected
        )
    end
end)
