-- ==============================================================================
-- ZOMBIE HUB MASTER V13: ZERO-LAG ENGINE + RUTEO DINÁMICO + WIDGET AUTO-PILOT
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local BaseCenter = Vector3.new(0, 0, 0)

-- COORDENADAS CALIBRADAS (+Z = NORTE, -Z = SUR)
local SECTOR_ROUTES = {
    NORTE = { Gate = Vector3.new(0, -1.9, 120.0), Combat = Vector3.new(0, 14.5, 180.0) },
    SUR   = { Gate = Vector3.new(0, -1.7, -120.0), Combat = Vector3.new(0, 14.5, -180.0) },
    ESTE  = { Gate = Vector3.new(120.0, -1.9, 0.0), Combat = Vector3.new(180.0, 14.5, 0.0) },
    OESTE = { Gate = Vector3.new(-120.0, -1.9, 0.0), Combat = Vector3.new(-180.0, 14.5, 0.0) }
}

-- RED DE PISTAS PERIMETRALES (T-SECTIONS Y CORNERS)
local PERIMETER_NODES = {
    { Name = "T_NORTE", Pos = Vector3.new(0, -1.9, 120.0),   Sector = "NORTE" },
    { Name = "C_NE",    Pos = Vector3.new(115.0, -1.9, 115.0), Sector = nil },
    { Name = "T_ESTE",  Pos = Vector3.new(120.0, -1.9, 0.0),    Sector = "ESTE" },
    { Name = "C_SE",    Pos = Vector3.new(115.0, -1.7, -115.0),Sector = nil },
    { Name = "T_SUR",   Pos = Vector3.new(0, -1.7, -120.0),  Sector = "SUR" },
    { Name = "C_SW",    Pos = Vector3.new(-115.0, -1.7, -115.0),Sector = nil },
    { Name = "T_OESTE", Pos = Vector3.new(-120.0, -1.9, 0.0),   Sector = "OESTE" },
    { Name = "C_NW",    Pos = Vector3.new(-115.0, -1.9, 115.0), Sector = nil }
}

local Config = {
    ZigZagEnabled = false,
    AttackMode = "Stalker",
    SwitchInterval = 0.5,
    LateralDist = 25,
    MoveSpeed = 150,              -- 150 studs/s por defecto
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true,

    -- LÍMITES STALKER
    StalkerBaseOvershoot = 5.0,    -- 5 studs hacia la base
    StalkerFarOvershoot = 25.0,    -- 25 studs hacia la horda

    -- RETIRADA TÁCTICA TERRESTRE
    RetreatEnabled = true,
    LowHealthThreshold = 0.20,     -- 20% activa retirada
    FullHealthThreshold = 0.70,    -- 70% reanuda combate
    RetreatDistance = 30.0,        -- 30 studs de retroceso
    RetreatSpeed = 110,

    -- RESCATE PEATONAL
    AutoRemountEnabled = true,
    SprintSpeed = 34,
    BunnyHop = true,
    MaxCarSearchDist = 300
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local CurrentActiveSector = "NORTE"

-- CACHÉS LIGERAS PARA EVITAR CONSUMO DE CPU
local CachedCombatRoads = {} -- [Sector] = Instance
local CachedBloaterDangers = {}
local CachedHordeClusterOffset = 0
local LastDrivenVehicle = nil
local IsInContingency = false

local DefenseState = {
    IsRetreating = false,
    CurrentHP = 2500,
    MaxHP = 2500,
    HPRatio = 1.0
}

local TransitState = {
    Active = false,
    Waypoints = {},
    Index = 1,
    TargetSector = "NORTE"
}

-- ==============================================================================
-- 1. DETECCIÓN LIGERA DE VEHÍCULO Y SALUD (CERO LAG)
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getCurrentVehicle()
    local _, _, hum = getCharacterParts()
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local model = seat:FindFirstAncestorOfClass("Model")
        if model and model.Parent ~= workspace then
            local higher = model:FindFirstAncestorOfClass("Model")
            if higher then model = higher end
        end
        LastDrivenVehicle = model
        return model, seat
    end
    return nil, nil
end

-- Consulta directa en memoria sin escanear descendientes
local function getTruckHealth(truck)
    if not truck then return 2500, 2500, 1.0 end

    local cfg = truck:FindFirstChild("Configuration")
    local hp = cfg and cfg:GetAttribute("Health") or truck:GetAttribute("Health")
    local maxHp = cfg and cfg:GetAttribute("MaxHealth") or truck:GetAttribute("MaxHealth") or 2500

    if not hp then
        local v = cfg and cfg:FindFirstChild("Health")
        if v and v:IsA("ValueBase") then hp = v.Value end
    end

    hp = hp or maxHp
    local ratio = (maxHp > 0) and (hp / maxHp) or 1.0
    return hp, maxHp, ratio
end

-- ==============================================================================
-- 2. CACHÉ INICIAL DE PISTAS FRONTALES (ESCANEO ÚNICO AL ENTRAR)
-- ==============================================================================

local function clearHighlight()
    if TargetHighlight then TargetHighlight:Destroy(); TargetHighlight = nil end
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

-- Mapea las carreteras una sola vez en segundo plano sin congelar el juego
task.spawn(function()
    task.wait(1.0)
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("Tiles") or workspace

    for secName, routeData in pairs(SECTOR_ROUTES) do
        local cPos = routeData.Combat
        local best, shortest = nil, 90

        for _, obj in ipairs(mapFolder:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local n = obj.Name:lower()
                if (n:find("straight") or n:find("road") or n:find("pista")) and not n:find("corner") and not n:find("tsection") and not n:find("section") then
                    local p = obj:IsA("Model") and select(1, obj:GetBoundingBox()).Position or obj.Position
                    local dist = (p - cPos).Magnitude
                    if dist < shortest and (p - BaseCenter).Magnitude >= 135 then
                        shortest = dist
                        best = obj
                    end
                end
            end
        end
        CachedCombatRoads[secName] = best
    end
end)

local function getCombatStraightRoad(secName)
    if CachedCombatRoads[secName] and CachedCombatRoads[secName].Parent then
        return CachedCombatRoads[secName]
    end
    return nil
end

-- ==============================================================================
-- 3. ENCAMINAMIENTO POR LA PISTA MÁS CERCANA (ANILLO PERIMETRAL)
-- ==============================================================================

local function calculateDynamicRoadPath(currentPos, targetSector)
    local targetGateIdx = 1
    for idx, node in ipairs(PERIMETER_NODES) do
        if node.Sector == targetSector then
            targetGateIdx = idx
            break
        end
    end

    -- Nodo perimetral más próximo a la posición actual
    local closestIdx = 1
    local minDist = math.huge
    for idx, node in ipairs(PERIMETER_NODES) do
        local d = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(node.Pos.X, 0, node.Pos.Z)).Magnitude
        if d < minDist then
            minDist = d
            closestIdx = idx
        end
    end

    local wps = {}
    table.insert(wps, PERIMETER_NODES[closestIdx].Pos)

    if closestIdx ~= targetGateIdx then
        local total = #PERIMETER_NODES
        local fSteps = (targetGateIdx - closestIdx) % total
        local bSteps = (closestIdx - targetGateIdx) % total
        local dir = (fSteps <= bSteps) and 1 or -1
        local cur = closestIdx

        while cur ~= targetGateIdx do
            cur = cur + dir
            if cur > total then cur = 1 end
            if cur < 1 then cur = total end
            table.insert(wps, PERIMETER_NODES[cur].Pos)
        end
    end

    table.insert(wps, SECTOR_ROUTES[targetSector].Combat)
    return wps
end

local function startDynamicSectorTransition(newSector)
    local _, root = getCharacterParts()
    local carPos = root and root.Position or BaseCenter

    local wps = calculateDynamicRoadPath(carPos, newSector)
    TransitState.Active = true
    TransitState.Waypoints = wps
    TransitState.Index = 1
    TransitState.TargetSector = newSector
    CurrentTarget = nil
    clearHighlight()

    Fluent:Notify({
        Title = "🚗 ENRUTANDO: " .. newSector,
        Content = string.format("Tomando pista perimetral (%d tramos)...", #wps),
        Duration = 3
    })
end

-- ==============================================================================
-- 4. PARSER ULTRA-LIGERO DE INCOMINGPOSITION (0ms LAG)
-- ==============================================================================

local function parseSectorFromAttribute(val)
    local vec = nil
    if typeof(val) == "Vector3" then
        vec = val
    elseif type(val) == "string" then
        local x, y, z = val:match("([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)")
        if x and y and z then
            vec = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
        end
    end

    if not vec then return "DESCONOCIDO" end
    -- +Z = NORTE, -Z = SUR
    if math.abs(vec.Z) > math.abs(vec.X) then
        return (vec.Z > 0) and "NORTE" or "SUR"
    else
        return (vec.X > 0) and "ESTE" or "OESTE"
    end
end

workspace:GetAttributeChangedSignal("IncomingPosition"):Connect(function()
    local rawVal = workspace:GetAttribute("IncomingPosition")
    if rawVal then
        local sec = parseSectorFromAttribute(rawVal)
        if sec ~= "DESCONOCIDO" and sec ~= CurrentActiveSector then
            if Config.AutoRouteToWave and Config.ZigZagEnabled then
                startDynamicSectorTransition(sec)
            else
                CurrentActiveSector = sec
            end
        end
    end
end)

-- ==============================================================================
-- 5. RESCATE PEATONAL Y DESMONTE LIMPIO
-- ==============================================================================

local function applyBrake(duration)
    duration = duration or 1.0
    task.spawn(function()
        local endTime = tick() + duration
        while tick() < endTime do
            local carModel, seat = getCurrentVehicle()
            local primary = carModel and (carModel.PrimaryPart or seat)
            if primary then
                primary.AssemblyLinearVelocity = Vector3.new(0, primary.AssemblyLinearVelocity.Y, 0)
                primary.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- Baja al personaje y lo coloca seguro al costado
local function forceDismountVehicle()
    local _, root, hum = getCharacterParts()
    if hum and hum.SeatPart then
        hum.Sit = false
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        task.wait(0.05)
        if root then
            root.CFrame = root.CFrame * CFrame.new(6.0, 1.2, 0)
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end
end

local function locateTargetCar()
    local _, root = getCharacterParts()
    if not root then return nil, nil end

    if LastDrivenVehicle and LastDrivenVehicle.Parent then
        local seat = LastDrivenVehicle:FindFirstChild("DriveSeat") or LastDrivenVehicle:FindFirstChildWhichIsA("VehicleSeat")
        if seat then return LastDrivenVehicle, seat end
    end

    local myPos = root.Position
    local bestSeat, bestModel = nil, nil
    local shortestDist = Config.MaxCarSearchDist

    local container = workspace:FindFirstChild("Structures") or workspace
    for _, model in ipairs(container:GetChildren()) do
        if model:IsA("Model") then
            local seat = model:FindFirstChild("DriveSeat") or model:FindFirstChildWhichIsA("VehicleSeat")
            if seat then
                local dist = (seat.Position - myPos).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    bestSeat = seat
                    bestModel = model
                end
            end
        end
    end
    return bestModel, bestSeat
end

local function executeGroundRescue(onBoardCallback)
    if IsInContingency then return end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end

    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        if onBoardCallback then onBoardCallback() end
        return
    end

    local carModel, seat = locateTargetCar()
    if not carModel or not seat then return end

    IsInContingency = true
    LastDrivenVehicle = carModel

    local runTimeout = tick() + 8.0
    local lastJumpTime = 0

    while IsInContingency and tick() < runTimeout do
        RunService.Heartbeat:Wait()
        if not hum or hum.Health <= 0 then break end
        if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then break end

        local hoodPos = (seat.CFrame * CFrame.new(0, 0, -6.5)).Position
        local diff = hoodPos - root.Position
        local horiz = Vector3.new(diff.X, 0, diff.Z)
        local dist = horiz.Magnitude

        if dist <= 6.5 then
            -- Reparación si está muerto
            if carModel:GetAttribute("Dead") == true then
                local p = carModel:FindFirstChildWhichIsA("ProximityPrompt", true)
                if p and fireproximityprompt then
                    pcall(function() fireproximityprompt(p) end)
                    pcall(function() fireproximityprompt(p, 0) end)
                end
                task.wait(0.2)
            end

            -- Montaje inmediato
            local sitP = seat:FindFirstChild("SitPrompt") or seat:FindFirstChildOfClass("ProximityPrompt")
            if sitP and fireproximityprompt then
                pcall(function() fireproximityprompt(sitP) end)
                pcall(function() fireproximityprompt(sitP, 0) end)
            end
            hum:ChangeState(Enum.HumanoidStateType.Seated)
            pcall(function() seat:Sit(hum) end)
            task.wait(0.2)
            break
        end

        local runDir = horiz.Unit
        root.AssemblyLinearVelocity = Vector3.new(runDir.X * Config.SprintSpeed, root.AssemblyLinearVelocity.Y, runDir.Z * Config.SprintSpeed)
        hum:MoveTo(root.Position + runDir * 10)

        if Config.BunnyHop and tick() - lastJumpTime >= 0.35 then
            hum.Jump = true
            lastJumpTime = tick()
        end
    end

    IsInContingency = false
    if onBoardCallback then onBoardCallback() end
end

-- ==============================================================================
-- 6. GUARDIÁN DE SALUD (INTERVALO 0.35s SIN GASTO DE CPU)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.35)
        local truck = getCurrentVehicle()

        if truck then
            local hp, maxHp, ratio = getTruckHealth(truck)
            DefenseState.CurrentHP = hp
            DefenseState.MaxHP = maxHp
            DefenseState.HPRatio = ratio

            if Config.RetreatEnabled then
                if not DefenseState.IsRetreating and ratio <= Config.LowHealthThreshold then
                    DefenseState.IsRetreating = true
                    Fluent:Notify({
                        Title = "🛡️ RETIRADA TÁCTICA",
                        Content = string.format("Vida al %.0f%%. Retrocediendo 30 studs.", ratio * 100),
                        Duration = 2.5
                    })
                elseif DefenseState.IsRetreating and ratio >= Config.FullHealthThreshold then
                    DefenseState.IsRetreating = false
                    Fluent:Notify({
                        Title = "⚔️ SALUD RECUPERADA",
                        Content = "Reanudando embestida Stalker al 100%.",
                        Duration = 2.5
                    })
                end
            else
                DefenseState.IsRetreating = false
            end
        else
            DefenseState.IsRetreating = false
            if Config.AutoRemountEnabled and Config.ZigZagEnabled and not IsInContingency then
                local _, _, hum = getCharacterParts()
                if hum and hum.Health > 0 and (not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat")) then
                    task.spawn(executeGroundRescue)
                end
            end
        end
    end
end)

-- BUCLE DE BLOATERS LIGERO (0.5s)
task.spawn(function()
    while true do
        task.wait(0.5)
        if Config.EvadeBloaters and not IsInContingency then
            local _, root = getCharacterParts()
            local myPos = root and root.Position or BaseCenter
            local list = {}
            local folder = workspace:FindFirstChild("Characters")

            if folder then
                for _, ent in ipairs(folder:GetChildren()) do
                    if ent:IsA("Model") and ent ~= lp.Character then
                        local n = ent.Name:lower()
                        if n:find("bloat") or n:find("boom") then
                            local r = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                            if r and (r.Position - myPos).Magnitude <= 75 then
                                local h = ent:FindFirstChildOfClass("Humanoid")
                                if (h and h.Health <= 50) or ent:GetAttribute("Dead") == true then
                                    table.insert(list, r.Position)
                                end
                            end
                        end
                    end
                end
            end
            CachedBloaterDangers = list
        else
            table.clear(CachedBloaterDangers)
        end
    end
end)

-- ==============================================================================
-- 7. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V13",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 520),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate", Icon = "crosshair" }),
    Defense = Window:AddTab({ Title = "Defensa & Esquive", Icon = "shield" }),
    Rescue = Window:AddTab({ Title = "Auto-Rescate", Icon = "user-check" }),
    Horde = Window:AddTab({ Title = "Radar", Icon = "radar" })
}

Tabs.Combat:AddSection("Controles de Embestida (Stalker 150)")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(v) Config.ZigZagEnabled = v end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 150,
    Min = 20,
    Max = 220,
    Rounding = 0,
    Callback = function(v) Config.MoveSpeed = v end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud Lateral Zigzag (Studs)",
    Default = 25,
    Min = 2,
    Max = 70,
    Rounding = 0,
    Callback = function(v) Config.LateralDist = v end
})

Tabs.Combat:AddSlider("StalkerFarSlider", {
    Title = "Rebase Hacia Afuera / Horda (Studs)",
    Default = 25,
    Min = 0,
    Max = 60,
    Rounding = 0,
    Callback = function(v) Config.StalkerFarOvershoot = v end
})

Tabs.Combat:AddSlider("StalkerBaseSlider", {
    Title = "Rebase Hacia la Base (Studs)",
    Default = 5,
    Min = 0,
    Max = 40,
    Rounding = 0,
    Callback = function(v) Config.StalkerBaseOvershoot = v end
})

Tabs.Combat:AddToggle("AutoRouteToggle", {
    Title = "🚗 Auto-Ruta Dinámica por Pistas",
    Default = true,
    Callback = function(v) Config.AutoRouteToWave = v end
})

Tabs.Defense:AddSection("Retirada Táctica por Daño")

Tabs.Defense:AddToggle("RetreatToggle", {
    Title = "🛡️ Activar Retirada y Esquive (Baja Vida)",
    Default = true,
    Callback = function(v) Config.RetreatEnabled = v end
})

local DefenseStatusParagraph = Tabs.Defense:AddParagraph({
    Title = "Estado del Vehículo",
    Content = "Monitoreando salud..."
})

Tabs.Defense:AddSlider("LowHPSlider", {
    Title = "Umbral de Retirada (% Vida)",
    Default = 20,
    Min = 10,
    Max = 40,
    Rounding = 0,
    Callback = function(v) Config.LowHealthThreshold = v / 100 end
})

Tabs.Defense:AddSlider("FullHPSlider", {
    Title = "Umbral de Reanudación (% Vida)",
    Default = 70,
    Min = 50,
    Max = 95,
    Rounding = 0,
    Callback = function(v) Config.FullHealthThreshold = v / 100 end
})

Tabs.Rescue:AddSection("Rescate Terrestre de Personaje")

Tabs.Rescue:AddToggle("AutoRemountToggle", {
    Title = "🛡️ Auto-Rescate en Eyección",
    Default = true,
    Callback = function(v) Config.AutoRemountEnabled = v end
})

Tabs.Rescue:AddSlider("SprintSpeedSlider", {
    Title = "Velocidad de Carrera al Auto",
    Default = 34,
    Min = 20,
    Max = 55,
    Rounding = 0,
    Callback = function(v) Config.SprintSpeed = v end
})

Tabs.Rescue:AddButton({
    Title = "🏃 Forzar Carrera y Montaje (Tecla 'V')",
    Callback = function() executeGroundRescue() end
})

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente Dominante",
    Content = "Escaneando..."
})

-- ==============================================================================
-- 8. WIDGETS FLOTANTES: MENU HUB + AUTO-PILOTO (ON / OFF)
-- ==============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZombieHubMasterFloat"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

-- BOTÓN MENÚ (Y = 0.72)
local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.72, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
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

-- WIDGET AUTO-PILOTO (Y = 0.64)
local AutoPilotBtn = Instance.new("TextButton")
AutoPilotBtn.Size = UDim2.new(0, 48, 0, 48)
AutoPilotBtn.Position = UDim2.new(0.04, 0, 0.64, 0)
AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
AutoPilotBtn.Text = "⚡\nOFF"
AutoPilotBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoPilotBtn.TextSize = 11
AutoPilotBtn.Font = Enum.Font.GothamBold
AutoPilotBtn.Active = true
AutoPilotBtn.Draggable = true
AutoPilotBtn.Parent = ScreenGui

local AutoPilotCorner = Instance.new("UICorner")
AutoPilotCorner.CornerRadius = UDim.new(1, 0)
AutoPilotCorner.Parent = AutoPilotBtn

local function toggleAutoPilot()
    if Config.ZigZagEnabled then
        -- DESACTIVAR: FRENAR Y EXPULSAR PERSONAJE
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        TransitState.Active = false
        applyBrake(1.0)
        forceDismountVehicle()

        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
        AutoPilotBtn.Text = "⚡\nOFF"

        Fluent:Notify({
            Title = "⏹ AUTO-PILOTO OFF",
            Content = "Auto detenido y personaje bajado con éxito.",
            Duration = 2
        })
    else
        -- ACTIVAR: MONTAR Y ATACAR
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 70)
        AutoPilotBtn.Text = "⚡\nON"

        executeGroundRescue(function()
            Config.ZigZagEnabled = true
            pcall(function() ZigZagToggleInstance:SetValue(true) end)
            startDynamicSectorTransition(CurrentActiveSector)
        end)
    end
end

AutoPilotBtn.MouseButton1Click:Connect(toggleAutoPilot)
Tabs.Combat:AddButton({ Title = "⚡ TOGGLE AUTO-PILOTO (SUBIR / BAJAR)", Callback = toggleAutoPilot })

-- CONTROLES DE TECLADO ('T', '9', '0', 'V')
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end

    if input.KeyCode == Enum.KeyCode.T then
        local raw = mouse.Target
        if raw then
            local chosen = getCompleteObject(raw)
            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)
                Config.ZigZagEnabled = true
                pcall(function() ZigZagToggleInstance:SetValue(true) end)
                AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 70)
                AutoPilotBtn.Text = "⚡\nON"
            end
        end
    end

    if input.KeyCode == Enum.KeyCode.Nine or input.KeyCode == Enum.KeyCode.KeypadNine then
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
        AutoPilotBtn.Text = "⚡\nOFF"
        applyBrake(1.0)
    end

    if input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.KeypadZero then
        CurrentTarget = nil
        clearHighlight()
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(160, 25, 35)
        AutoPilotBtn.Text = "⚡\nOFF"
        applyBrake(1.0)
    end

    if input.KeyCode == Enum.KeyCode.V then
        executeGroundRescue()
    end
end)

-- ACTUALIZACIÓN DE TEXTOS EN INTERFAZ
task.spawn(function()
    while true do
        task.wait(0.5)
        DefenseStatusParagraph:SetDesc(string.format(
            "Vida Vehículo: %.0f / %.0f (%.0f%%)\nRetirada Automática: %s\nModo Actual: %s",
            DefenseState.CurrentHP, DefenseState.MaxHP, DefenseState.HPRatio * 100,
            Config.RetreatEnabled and "🟢 ACTIVA" or "🔴 OFF",
            DefenseState.IsRetreating and "🛡️ Retirada (-30 studs)" or (TransitState.Active and "🚗 Enrutando Pistas" or "⚔️ Stalker Activo")
        ))

        HordeStatusParagraph:SetDesc(string.format(
            "Frente Dominante: %s\nIncomingPosition: %s\nZombies Restantes: %d",
            CurrentActiveSector,
            tostring(workspace:GetAttribute("IncomingPosition") or "N/A"),
            workspace:GetAttribute("RemainingMobs") or 0
        ))
    end
end)

-- ==============================================================================
-- 9. MOTOR CINÉTICO ZERO-LAG (HEARTBEAT DIRECTO)
-- ==============================================================================

local stalkerDir = 1
local lastStalkerSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or IsInContingency then return end

    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end
    if not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then return end

    -- FASE 1: TRÁNSITO POR PISTAS DINÁMICAS
    if TransitState.Active then
        local wp = TransitState.Waypoints[TransitState.Index]
        if wp then
            local diff = wp - root.Position
            local horiz = Vector3.new(diff.X, 0, diff.Z)

            if horiz.Magnitude <= 22.0 then
                TransitState.Index = TransitState.Index + 1
                if TransitState.Index > #TransitState.Waypoints then
                    TransitState.Active = false
                    CurrentActiveSector = TransitState.TargetSector

                    local road = getCombatStraightRoad(CurrentActiveSector)
                    if road then
                        CurrentTarget = road
                        applyHighlight(road)
                    end
                end
            else
                local mDir = horiz.Unit
                root.AssemblyLinearVelocity = Vector3.new(mDir.X * Config.MoveSpeed, root.AssemblyLinearVelocity.Y, mDir.Z * Config.MoveSpeed)
            end
        else
            TransitState.Active = false
        end
        return
    end

    -- FASE 2: ATAQUE STALKER & RETIRADA
    local targetPos = nil
    local targetSize = Vector3.new(60, 10, 60)

    if CurrentTarget then
        targetPos = CurrentTarget:IsA("BasePart") and CurrentTarget.Position or select(1, CurrentTarget:GetBoundingBox()).Position
        targetSize = CurrentTarget:IsA("BasePart") and CurrentTarget.Size or select(2, CurrentTarget:GetBoundingBox())
    elseif SECTOR_ROUTES[CurrentActiveSector] then
        targetPos = SECTOR_ROUTES[CurrentActiveSector].Combat
    end

    if targetPos then
        local destination = targetPos
        local d = Config.LateralDist
        local speed = Config.MoveSpeed

        local toRoad = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
        local roadLen = toRoad.Magnitude > 0 and toRoad.Unit or Vector3.new(0, 0, 1)
        local roadWid = Vector3.new(-roadLen.Z, 0, roadLen.X)

        if DefenseState.IsRetreating then
            speed = Config.RetreatSpeed
            local hLen = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local anchor = targetPos - (roadLen * (hLen + Config.RetreatDistance))
            destination = anchor + (roadWid * (math.sin(tick() * 4.0) * d))
        else
            local hLen = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local reachAway = hLen + Config.StalkerFarOvershoot
            local reachBase = hLen + Config.StalkerBaseOvershoot

            local carAlong = (root.Position - targetPos):Dot(roadLen)

            if stalkerDir == 1 and carAlong >= (reachAway - 3.5) then
                stalkerDir = -1
                lastStalkerSwitch = tick()
            elseif stalkerDir == -1 and carAlong <= -(reachBase - 3.5) then
                stalkerDir = 1
                lastStalkerSwitch = tick()
            end

            if tick() - lastStalkerSwitch >= 3.2 then
                stalkerDir = -stalkerDir
                lastStalkerSwitch = tick()
            end

            local tDist = (stalkerDir == 1) and reachAway or -reachBase
            destination = targetPos + (roadLen * tDist) + (roadWid * (math.sin(tick() * 5.5) * d))
        end

        -- EVASIÓN DE BLOATERS RÁPIDA
        if Config.EvadeBloaters and #CachedBloaterDangers > 0 then
            for _, bPos in ipairs(CachedBloaterDangers) do
                if (root.Position - bPos).Magnitude <= Config.BloaterDangerDist then
                    local aDir = (root.Position - bPos).Unit
                    destination = destination + Vector3.new(aDir.X, 0, aDir.Z) * 26
                end
            end
        end

        local dir = (destination - root.Position)
        local hDir = Vector3.new(dir.X, 0, dir.Z)

        if hDir.Magnitude > 1.2 then
            local vel = hDir.Unit * speed
            root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB MASTER V13",
    Content = "Zero-Lag Engine activo. 60 FPS estables.",
    Duration = 3
})

Window:SelectTab(1)
