-- ==============================================================================
-- SCRAP HIGHWAY CRUSHER & SPIDERWEB RELAY V2.0 (1200 STUDS / 0% LAG)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)
local MAX_MAP_RADIUS = 1200

local Config = {
    -- Auto-Conducción por Pistas
    AutoFarmRoads = false,
    VehicleSpeed = 125,
    RoadMaxHalfWidth = 14,      -- Límite lateral desde el centro de la pista (nunca sale a tierra)
    ScrapSearchRadius = 500,    -- Radio de detección de cúmulos a tu alrededor

    -- Red Telaraña de Teletransporte (1 por 1, pasos cortos)
    AutoSendItems = true,
    OnlyScrap = true,
    ChainTeleport = true,
    BasePrevent = true,
    GeneratorSafeRadius = 145,  -- Radio donde ya deja los materiales en la base
    CollectRadius = 85,         -- Tu presencia necesaria en studs para mover el ítem sin buguearlo
    WebStepDistance = 65,       -- Distancia corta de cada salto en la telaraña (studs)
    SpreadRadius = 2.5,         -- Pequeña dispersión para que no colisionen entre sí
    TeleportInterval = 0.28,    -- Pausa entre cada ítem (procesa 1 por 1, 0% lag)
    ShowWebVisuals = false      -- Mostrar/ocultar las bolitas de la red
}

local RoadNodes = {}            -- Nodos de todas las pistas cargadas hasta 1200 studs
local DeliveryPoints = {}       -- Bolitas de la telaraña (automáticas + manuales)
local RoadScrapList = {}        -- Cúmulos y autos chatarra validados dentro de la pista
local VisitedRoadHistory = {}   -- Memoria para recorrer las pistas sin quedarse atascado

local CachedGeneratorPos = nil
local CurrentScrapTarget = nil
local CurrentRoadTarget = nil

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. POSICIÓN DEL GENERADOR Y RED DE BOLITAS (TELARAÑA AUTOMÁTICA)
-- ==============================================================================

local function getGeneratorPosition()
    if CachedGeneratorPos then return CachedGeneratorPos end
    local gen = workspace:FindFirstChild("Generator") or workspace:FindFirstChild("Center")
    if gen then
        local p = (gen:IsA("Model") and (gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart"))) or gen
        if p and p:IsA("BasePart") then
            CachedGeneratorPos = p.Position
            return CachedGeneratorPos
        end
    end
    return BaseCenter
end

local function createWebMarker(pos, isManual)
    local marker = Instance.new("Part")
    marker.Name = isManual and "CustomDropPoint" or "AutoWebNode"
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(2.2, 2.2, 2.2)
    marker.Material = Enum.Material.Neon
    marker.Color = isManual and Color3.fromRGB(0, 255, 170) or Color3.fromRGB(0, 180, 255)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Transparency = Config.ShowWebVisuals and 0.2 or 1
    marker.Position = pos + Vector3.new(0, 1.2, 0)
    marker.Parent = workspace

    table.insert(DeliveryPoints, marker)
    return marker
end

-- Si la pista nueva está lejos de otra bolita, le planta un nodo de telaraña automáticamente
local function tryAddWebNodeAtRoad(roadPos)
    local genPos = getGeneratorPosition()
    if (roadPos - genPos).Magnitude <= (Config.GeneratorSafeRadius - 15) then return end

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            if (pt.Position - roadPos).Magnitude < (Config.WebStepDistance * 0.85) then
                return
            end
        end
    end
    createWebMarker(roadPos, false)
end

-- ==============================================================================
-- 2. MAPEO PROGRESIVO DE PISTAS (HASTA 1200 STUDS SIN LAG)
-- ==============================================================================

local function isRoadObject(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    if n:find("straight") or n:find("road") or n:find("pista") or n:find("corner") or n:find("tsection") then
        if not n:find("sign") and not n:find("light") and not n:find("lamp") and not n:find("railing") then
            return true
        end
    end
    return false
end

local function registerRoadPiece(obj)
    local pos = nil
    if obj:IsA("Model") then
        local cf = select(1, obj:GetBoundingBox())
        pos = cf.Position
    else
        pos = obj.Position
    end

    -- Ignorar lo que supere los 1200 studs desde la base
    local distFromCenter = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
    if distFromCenter > MAX_MAP_RADIUS or distFromCenter < 95 then return end

    for _, node in ipairs(RoadNodes) do
        if (node.Pos - pos).Magnitude < 18 then
            return
        end
    end

    local newNode = {
        Pos = Vector3.new(pos.X, 1.5, pos.Z),
        Instance = obj,
        LastVisited = 0
    }
    table.insert(RoadNodes, newNode)

    -- Tejer nodo de la telaraña sobre esta pista
    tryAddWebNodeAtRoad(newNode.Pos)
end

-- Escaneo inicial suave por lotes (0% congelamiento al ejecutar)
task.spawn(function()
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("Tiles") or workspace
    local descendants = mapFolder:GetDescendants()
    for i, desc in ipairs(descendants) do
        if isRoadObject(desc) then
            registerRoadPiece(desc)
        end
        if i % 250 == 0 then task.wait() end
    end
end)

-- A medida que el auto sale y explora hasta 1200 studs, registra las nuevas pistas automáticamente
workspace.DescendantAdded:Connect(function(desc)
    if isRoadObject(desc) then
        task.wait(0.15)
        registerRoadPiece(desc)
    end
end)

local function getClosestRoadNode(pos)
    local bestNode = nil
    local shortest = math.huge
    for _, node in ipairs(RoadNodes) do
        local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(node.Pos.X, 0, node.Pos.Z)).Magnitude
        if d < shortest then
            shortest = d
            bestNode = node
        end
    end
    return bestNode, shortest
end

-- ==============================================================================
-- 3. ESCÁNER DE SCRAP PILE Y CRASHED CAR (SOLO DENTRO DE LAS PISTAS)
-- ==============================================================================

local function isValidScrapTarget(model)
    if not model or not model.Parent or not model:IsA("Model") then return false end
    if model:GetAttribute("Dead") == true then return false end

    local n = model.Name:lower()
    if n:find("scrap pile") or n:find("crashed car") then
        return true
    end
    return false
end

local function scanRoadScrapTargets()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return end

    local myPos = root.Position
    local structFolder = workspace:FindFirstChild("Structures") or workspace
    local validTargets = {}

    for _, item in ipairs(structFolder:GetChildren()) do
        if isValidScrapTarget(item) then
            local part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
            if part then
                local sPos = part.Position
                local distToBase = (Vector3.new(sPos.X, 0, sPos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude

                if distToBase <= MAX_MAP_RADIUS and distToBase >= 100 then
                    local distToMe = (sPos - myPos).Magnitude
                    if distToMe <= Config.ScrapSearchRadius then
                        -- Filtro estricto: comprobar que esté sobre una pista (máximo 18 studs del eje central de la pista)
                        local roadNode, distToRoadCenter = getClosestRoadNode(sPos)
                        if roadNode and distToRoadCenter <= 18 then
                            table.insert(validTargets, {
                                Model = item,
                                Part = part,
                                Pos = sPos,
                                RoadCenter = roadNode.Pos,
                                Dist = distToMe
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(validTargets, function(a, b)
        return a.Dist < b.Dist
    end)

    RoadScrapList = validTargets
end

-- ==============================================================================
-- 4. BUCLE DE TELETRANSPORTE EN TELARAÑA (1 POR 1, SALTOS CORTOS, CERO LAG)
-- ==============================================================================

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function getNextSpiderwebPoint(itemPos)
    local genPos = getGeneratorPosition()
    local currentDistToGen = (itemPos - genPos).Magnitude
    local bestPoint = nil
    local shortestStep = math.huge

    for _, pt in ipairs(DeliveryPoints) do
        if pt and pt.Parent then
            local ptPos = pt.Position
            local stepDist = (itemPos - ptPos).Magnitude
            local pointDistToGen = (ptPos - genPos).Magnitude

            if Config.ChainTeleport then
                -- El siguiente punto debe acercar el objeto al generador en un tramo corto (entre 6 y WebStepDistance + 35 studs)
                if pointDistToGen < (currentDistToGen - 5) and stepDist > 5 and stepDist <= (Config.WebStepDistance + 40) then
                    if stepDist < shortestStep then
                        shortestStep = stepDist
                        bestPoint = pt
                    end
                end
            else
                if stepDist < shortestStep and stepDist > 5 then
                    shortestStep = stepDist
                    bestPoint = pt
                end
            end
        end
    end

    -- Si no hay nodo intermedio en ese radio, busca cualquier nodo que esté más cerca de la base
    if not bestPoint then
        for _, pt in ipairs(DeliveryPoints) do
            if pt and pt.Parent then
                local ptPos = pt.Position
                local stepDist = (itemPos - ptPos).Magnitude
                local pointDistToGen = (ptPos - genPos).Magnitude
                if pointDistToGen < (currentDistToGen - 8) and stepDist < shortestStep then
                    shortestStep = stepDist
                    bestPoint = pt
                end
            end
        end
    end

    return bestPoint
end

task.spawn(function()
    while true do
        task.wait(Config.TeleportInterval)
        if Config.AutoSendItems and #DeliveryPoints > 0 then
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            if root then
                overlapParams.FilterDescendantsInstances = {char}
                local partsNearby = workspace:GetPartBoundsInRadius(root.Position, Config.CollectRadius, overlapParams)
                local processedOne = false

                for _, hitPart in ipairs(partsNearby) do
                    if processedOne then break end -- Estrictamente 1 por 1 para evitar lag y bugs físicos

                    if not hitPart.Anchored and not hitPart:FindFirstAncestorOfClass("Humanoid") then
                        local itemModel = hitPart:FindFirstAncestorOfClass("Model")
                        local isVehicle = itemModel and (itemModel:FindFirstChild("DriveSeat") or itemModel:FindFirstChildWhichIsA("VehicleSeat"))

                        if not isVehicle then
                            local targetEntity = (itemModel and itemModel.Parent ~= workspace:FindFirstChild("Characters") and itemModel) or hitPart
                            local rootPos = (targetEntity:IsA("Model") and targetEntity:GetPivot().Position) or targetEntity.Position

                            local nameLower = targetEntity.Name:lower()
                            local isScrap = nameLower:find("scrap") or nameLower:find("chatarra") or nameLower:find("metal") or nameLower:find("barrel") or nameLower:find("sheet") or targetEntity:GetAttribute("ItemType") == "Resource"

                            if not Config.OnlyScrap or isScrap then
                                local genPos = getGeneratorPosition()
                                local insideBase = false
                                if Config.BasePrevent and genPos then
                                    if (rootPos - genPos).Magnitude <= Config.GeneratorSafeRadius then
                                        insideBase = true
                                    end
                                end

                                if not insideBase then
                                    local nextPoint = getNextSpiderwebPoint(rootPos)
                                    if nextPoint then
                                        processedOne = true

                                        local angle = math.random() * math.pi * 2
                                        local rDist = math.random() * Config.SpreadRadius
                                        local destPos = nextPoint.Position + Vector3.new(math.cos(angle) * rDist, 1.2, math.sin(angle) * rDist)

                                        if targetEntity:IsA("Model") then
                                            targetEntity:PivotTo(CFrame.new(destPos))
                                            for _, p in ipairs(targetEntity:GetDescendants()) do
                                                if p:IsA("BasePart") then
                                                    p.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
                                                    p.AssemblyAngularVelocity = Vector3.zero
                                                end
                                            end
                                        else
                                            targetEntity.CFrame = CFrame.new(destPos)
                                            targetEntity.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
                                            targetEntity.AssemblyAngularVelocity = Vector3.zero
                                        end
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

-- ==============================================================================
-- 5. MOTOR DE CONDUCCIÓN INTELIGENTE SOBRE PISTAS (SIN SALIRSE JAMÁS)
-- ==============================================================================

local function getCurrentCar()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local car = seat:FindFirstAncestorOfClass("Model")
        return car, seat
    end
    return nil, nil
end

-- Elige el siguiente tramo de pista conectado para seguir avanzando sin repetir
local function getNextExplorationRoadNode(myPos)
    local bestNode = nil
    local bestScore = math.huge
    local now = tick()

    for _, node in ipairs(RoadNodes) do
        local dist = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(node.Pos.X, 0, node.Pos.Z)).Magnitude
        -- Buscar el siguiente segmento de pista consecutivo (entre 25 y 140 studs)
        if dist >= 22 and dist <= 150 then
            local timeSinceVisit = now - node.LastVisited
            -- Penalizar pistas recién visitadas para que recorra todo el mapa hasta 1200 studs
            local score = dist - math.min(timeSinceVisit * 2, 120)
            if score < bestScore then
                bestScore = score
                bestNode = node
            end
        end
    end

    if not bestNode then
        bestNode = getClosestRoadNode(myPos)
    end
    return bestNode
end

RunService.Heartbeat:Connect(function()
    if not Config.AutoFarmRoads then return end

    local car, seat = getCurrentCar()
    local root = car and (car.PrimaryPart or seat)
    if not root then return end

    local myPos = root.Position
    local closestRoad, distToRoad = getClosestRoadNode(myPos)

    -- 1. PROTECCIÓN ANTI-SALIDA DE PISTA: Si el auto se sale de la calzada (> 18 studs), regresa inmediatamente a la pista más cercana
    if closestRoad and distToRoad > 18 then
        local recoverDiff = closestRoad.Pos - myPos
        local recoverDir = Vector3.new(recoverDiff.X, 0, recoverDiff.Z).Unit
        root.AssemblyLinearVelocity = Vector3.new(
            recoverDir.X * Config.VehicleSpeed,
            root.AssemblyLinearVelocity.Y,
            recoverDir.Z * Config.VehicleSpeed
        )
        return
    end

    if closestRoad and distToRoad <= 20 then
        closestRoad.LastVisited = tick()
    end

    -- 2. BUSCAR CÚMULO DE CHATARRA O AUTO CHATARRA EN LA PISTA
    local activeScrap = nil
    for _, sc in ipairs(RoadScrapList) do
        if sc.Model and sc.Model.Parent and sc.Model:GetAttribute("Dead") ~= true then
            activeScrap = sc
            break
        end
    end

    local targetDestination = nil

    if activeScrap then
        CurrentScrapTarget = activeScrap.Model
        -- Limitar la posición del impacto dentro del margen seguro de la pista para no pisar tierra
        local offsetFromRoadCenter = activeScrap.Pos - activeScrap.RoadCenter
        local safeOffset = Vector3.new(
            math.clamp(offsetFromRoadCenter.X, -Config.RoadMaxHalfWidth, Config.RoadMaxHalfWidth),
            0,
            math.clamp(offsetFromRoadCenter.Z, -Config.RoadMaxHalfWidth, Config.RoadMaxHalfWidth)
        )
        targetDestination = activeScrap.RoadCenter + safeOffset
    else
        CurrentScrapTarget = nil
        -- Si no hay chatarra en este tramo, avanza por la pista hacia el siguiente segmento
        if not CurrentRoadTarget or (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(CurrentRoadTarget.Pos.X, 0, CurrentRoadTarget.Pos.Z)).Magnitude < 22 then
            CurrentRoadTarget = getNextExplorationRoadNode(myPos)
        end
        if CurrentRoadTarget then
            targetDestination = CurrentRoadTarget.Pos
        end
    end

    -- 3. APLICAR MOVIMIENTO SUAVE SOBRE EL ASFALTO
    if targetDestination then
        local diff = targetDestination - myPos
        local horiz = Vector3.new(diff.X, 0, diff.Z)
        if horiz.Magnitude > 2.0 then
            local dir = horiz.Unit
            root.AssemblyLinearVelocity = Vector3.new(
                dir.X * Config.VehicleSpeed,
                root.AssemblyLinearVelocity.Y,
                dir.Z * Config.VehicleSpeed
            )
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.6)
        if Config.AutoFarmRoads then
            scanRoadScrapTargets()
        end
    end
end)

-- ==============================================================================
-- 6. INTERFAZ FLUENT + WIDGETS FLOTANTES
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "SCRAP HIGHWAY & WEB RELAY V2.0",
    SubTitle = "Auto-Pistas (1200m) + Telaraña 1x1",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 480),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    RoadFarm = Window:AddTab({ Title = "Auto-Pistas", Icon = "truck" }),
    Items    = Window:AddTab({ Title = "Red Telaraña", Icon = "share-2" })
}

-- PESTAÑA 1: AUTO-PISTAS
Tabs.RoadFarm:AddSection("Atropello de Chatarra en Pistas (1200 Studs)")

local AutoFarmToggle = Tabs.RoadFarm:AddToggle("AutoFarmToggle", {
    Title = "🚜 Activar Auto-Atropello en Pistas",
    Default = false,
    Callback = function(v)
        Config.AutoFarmRoads = v
        if v then scanRoadScrapTargets() end
    end
})

local StatusParagraph = Tabs.RoadFarm:AddParagraph({
    Title = "Monitor de Pistas y Chatarra",
    Content = "Cargando red vial..."
})

Tabs.RoadFarm:AddSlider("CarSpeedSlider", {
    Title = "Velocidad del Auto en Pista",
    Default = 125,
    Min = 60,
    Max = 190,
    Rounding = 0,
    Callback = function(v) Config.VehicleSpeed = v end
})

Tabs.RoadFarm:AddSlider("RoadWidthSlider", {
    Title = "Ancho Máximo de Carril (Studs)",
    Description = "Mantiene el auto dentro de la pista sin pisar tierra",
    Default = 14,
    Min = 6,
    Max = 18,
    Rounding = 0,
    Callback = function(v) Config.RoadMaxHalfWidth = v end
})

-- PESTAÑA 2: TELETRANSPORTE EN TELARAÑA (BASADO EN TU LÓGICA DE BOLITAS)
Tabs.Items:AddSection("Red de Puntos de Entrega (Telaraña Automática + Manual)")

Tabs.Items:AddButton({
    Title = "+ Agregar Bolita Manual Aquí",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        createWebMarker(root.Position - Vector3.new(0, 1.5, 0), true)
        Fluent:Notify({ Title = "Punto Agregado", Content = "Nodos totales en la red: " .. #DeliveryPoints, Duration = 2 })
    end
})

Tabs.Items:AddToggle("ShowBallsToggle", {
    Title = "👁️ Mostrar Bolitas de la Telaraña en el Mapa",
    Default = false,
    Callback = function(v)
        Config.ShowWebVisuals = v
        for _, pt in ipairs(DeliveryPoints) do
            if pt and pt.Parent then
                pt.Transparency = v and 0.2 or 1
            end
        end
    end
})

Tabs.Items:AddButton({
    Title = "Borrar y Regenerar Telaraña",
    Callback = function()
        for _, p in ipairs(DeliveryPoints) do
            if p and p.Parent then p:Destroy() end
        end
        table.clear(DeliveryPoints)
        for _, rNode in ipairs(RoadNodes) do
            tryAddWebNodeAtRoad(rNode.Pos)
        end
        Fluent:Notify({ Title = "Red Reiniciada", Content = "Telaraña reconstruida en pistas: " .. #DeliveryPoints .. " nodos.", Duration = 2 })
    end
})

Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "🕸️ Activar Teletransporte de Ítems (1 por 1)",
    Default = true,
    Callback = function(v) Config.AutoSendItems = v end
})

Tabs.Items:AddToggle("OnlyScrapToggle", {
    Title = "Solo Teletransportar Chatarra (Scrap)",
    Default = true,
    Callback = function(v) Config.OnlyScrap = v end
})

Tabs.Items:AddToggle("ChainTeleportToggle", {
    Title = "Permitir Teletransporte Continuo en Saltos Cortos",
    Default = true,
    Callback = function(v) Config.ChainTeleport = v end
})

Tabs.Items:AddSlider("PresenceSlider", {
    Title = "Distancia de Tu Presencia (Studs)",
    Description = "Solo mueve chatarra cerca de ti para que el juego la detecte bien",
    Default = 85,
    Min = 35,
    Max = 160,
    Rounding = 0,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Items:AddSlider("StepDistSlider", {
    Title = "Distancia Corta de Cada Salto (Studs)",
    Default = 65,
    Min = 35,
    Max = 110,
    Rounding = 0,
    Callback = function(v) Config.WebStepDistance = v end
})

Tabs.Items:AddSection("Protección del Generador")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Generator Prevent",
    Default = true,
    Callback = function(v) Config.BasePrevent = v end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio de Seguridad del Generador (Studs)",
    Default = 145,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(v) Config.GeneratorSafeRadius = v end
})

-- ==============================================================================
-- 7. WIDGETS FLOTANTES (MENÚ + BOTÓN ON/OFF RÁPIDO)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local FloatGui = Instance.new("ScreenGui")
FloatGui.Name = "ScrapWebMasterFloatGui"
FloatGui.ResetOnSpawn = false
FloatGui.Parent = GuiParent

-- Widget 1: Abrir / Ocultar Menú
local MenuBtn = Instance.new("ImageButton")
MenuBtn.Size = UDim2.new(0, 48, 0, 48)
MenuBtn.Position = UDim2.new(0.04, 0, 0.58, 0)
MenuBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
MenuBtn.Image = "rbxassetid://10723415903"
MenuBtn.Active = true
MenuBtn.Draggable = true
MenuBtn.Parent = FloatGui

local MenuCorner = Instance.new("UICorner")
MenuCorner.CornerRadius = UDim.new(1, 0)
MenuCorner.Parent = MenuBtn

local isMenuVisible = true
MenuBtn.MouseButton1Click:Connect(function()
    isMenuVisible = not isMenuVisible
    Window.Root.Visible = isMenuVisible
end)

-- Widget 2: Encender / Apagar Auto-Farm Vial
local DriveBtn = Instance.new("TextButton")
DriveBtn.Size = UDim2.new(0, 48, 0, 48)
DriveBtn.Position = UDim2.new(0.04, 0, 0.48, 0)
DriveBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
DriveBtn.Text = "🚜\nOFF"
DriveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DriveBtn.TextSize = 11
DriveBtn.Font = Enum.Font.GothamBold
DriveBtn.Active = true
DriveBtn.Draggable = true
DriveBtn.Parent = FloatGui

local DriveCorner = Instance.new("UICorner")
DriveCorner.CornerRadius = UDim.new(1, 0)
DriveCorner.Parent = DriveBtn

DriveBtn.MouseButton1Click:Connect(function()
    Config.AutoFarmRoads = not Config.AutoFarmRoads
    pcall(function() AutoFarmToggle:SetValue(Config.AutoFarmRoads) end)
    if Config.AutoFarmRoads then
        DriveBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 65)
        DriveBtn.Text = "🚜\nON"
    else
        DriveBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
        DriveBtn.Text = "🚜\nOFF"
    end
end)

-- Actualización del monitor cada 0.6s
task.spawn(function()
    while true do
        task.wait(0.6)
        local targetText = CurrentScrapTarget and CurrentScrapTarget.Name or "Recorriendo red vial"
        StatusParagraph:SetDesc(string.format(
            "Pistas registradas (hasta 1200m): %d\nNodos de Telaraña activos: %d\nCúmulos en pista detectados: %d\nAcción actual: %s",
            #RoadNodes,
            #DeliveryPoints,
            #RoadScrapList,
            targetText
        ))
    end
end)

Window:SelectTab(1)
