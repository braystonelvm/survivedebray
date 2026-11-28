-- ==============================================================================
-- PILOTO AÉREO PARABÓLICO V13.1 (ESCUDO TOTAL + ANTI-FILOS + CICLO PODER 5)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local lp = Players.LocalPlayer

-- Limpiar conexiones previas si se re-ejecuta en plena partida
if _G.PilotV13_RenderConn then _G.PilotV13_RenderConn:Disconnect() end
if _G.PilotV13_HeartConn then _G.PilotV13_HeartConn:Disconnect() end
_G.PilotV13_Running = false
task.wait(0.05)
_G.PilotV13_Running = true

_G.PilotV13_RenderConn = RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local Config = {
    Active = false,
    Direction = "ESTE",         -- "NORTE", "SUR", "ESTE", "OESTE"
    Pattern = "Círculo",        -- "Círculo", "Cuadrado", "Zigzag", "Rombo", "I Invertida", "Solo Adelante"

    -- Visualización del cuadrado del edificio (Tile_120 en ApartmentBroken)
    ShowApartmentBoxDefault = true,

    -- Distancias y Velocidades
    ForwardStuds = 34,          -- Studs hacia delante desde el techo
    PatternRadius = 35,         -- Radio / amplitud óptima para romper giro de misiles
    MinCruiseY = 115,           -- Techo máx de Spit es Y=92.6 -> Y>=115 te hace intocable por ácido aéreo
    VerticalDipStuds = 2.0,
    FlySpeed = 30.0,            -- Velocidad crucero segura (0% rollback)
    ReturnSpeed = 30.0,

    -- Física Parabólica
    JumpImpulseY = 53.0,        -- Fuerza Y
    JumpPulseInterval = 0.40,   -- Intervalo entre pulsos

    -- Escudo Anti-Pisada de otros techos y filos (0% lag)
    AvoidOtherRoofs = true,
    FloorClearanceStuds = 8.5,
    WallDetectStuds = 10.0,

    -- Modos Anti-Rubberband
    AntiRubberMode = "WaitRubber", -- "WaitRubber" o "ReturnAndStep"
    MaxAirTimeBeforeReturn = 4.8,
    TouchRoofHoldTime = 1.2,
    RubberbandDetectDist = 12,
    PostRubberWaitTime = 0.5,

    -- Radar Forense (Missile, Spit, BlightSpit, Boulder, AcidPool, StalkerSlash)
    AutoDodgeObjects = true,
    BossExtraHeight = 8,        -- Altura extra cuando Cyborg, Experiment o Tyrant están vivos
    RadarHorizRadius = 32,      -- Radio de vigilancia horizontal
    RadarDownDepth = 60,        -- Vigilancia hacia abajo (studs)
    DodgeTriggerDist = 30,      -- Distancia a la que dispara el corte evasivo
    DodgeBurstSpeed = 58,       -- Velocidad máxima segura anti-anticheat (evita triple rubberband)
    DodgeSideStuds = 18,        -- Corte lateral amplio
    DodgeUpStuds = 12,          -- Elevación rápida para superar nubes de Spit flotantes
    DodgeHoldSeconds = 1.4,     -- Duración de la maniobra evasiva

    -- Poder 5 ("Anulación del Sistema") vinculado al Reloj de Noche Larga
    AutoWeaponCycle = true,
    Power5Mode = "EternalNightStop", -- "EternalNightStop" o "TimerFixed"
    TimeCheckInterval = 1.0,
    TimeStopDelay = 15,
    Power5Interval = 120,
    Power5CastWait = 0.18,
    EquipSlot2Default = true
}

local State = {
    StartOrigin = nil,
    RoofPart = nil,
    Waypoints = {},
    CurrentWpIndex = 1,
    LastRealPos = nil,
    Phase = "Idle",
    AirStartTime = 0,
    LastJumpPulse = 0,
    GroundedConfirmedSince = nil,
    RubberWaitUntil = 0,
    RubberbandCount = 0,
    StatusText = "En espera (Detenido)",

    -- Escudo Techos / Paredes
    RoofAvoidJumpNeeded = false,
    WallSideDodge = Vector3.zero,

    -- Jefes Cyborg / Experiment / Tyrant bajo demanda
    HasBossActive = false,
    ActiveBossLabel = "Ninguno",

    -- Radar
    DodgeOffset = Vector3.zero,
    DodgeUntil = 0,
    IsBurstDodging = false,
    MissileJinkSign = 1,
    LastThreatName = "Ninguno",
    DetectedBelowCount = 0,

    -- Reloj Noche Larga & Poder 5
    DetectedHudTime = "Buscando...",
    Power5StatusText = "Esperando reloj detenido"
}

local DIRECTION_VECTORS = {
    NORTE = Vector3.new(0, 0, -1),
    SUR   = Vector3.new(0, 0, 1),
    ESTE  = Vector3.new(1, 0, 0),
    OESTE = Vector3.new(-1, 0, 0)
}

-- ==============================================================================
-- 1. VISUALIZADOR DEL CUADRADO DEL EDIFICIO (SOLO APARTMENTBROKEN.COLLISION.TILE_120)
-- ==============================================================================

local function setApartmentBoxesVisible(show)
    local tilesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Tiles")
    if not tilesFolder then return 0 end

    local count = 0
    for _, desc in ipairs(tilesFolder:GetDescendants()) do
        if desc:IsA("BasePart") then
            local isBuildingBox = (desc.Name == "Tile_120")
                and (desc.Parent and desc.Parent.Name == "Collision")
                and (desc.Parent.Parent and desc.Parent.Parent.Name == "ApartmentBroken")
                and (desc.Size.X >= 50 and desc.Size.Z >= 50)

            if isBuildingBox then
                if show then
                    desc.Transparency = 0.65
                    desc.Color = Color3.fromRGB(0, 235, 255)
                    desc.Material = Enum.Material.ForceField

                    if not desc:FindFirstChild("CollisionBoxOutline") then
                        local box = Instance.new("SelectionBox")
                        box.Name = "CollisionBoxOutline"
                        box.Adornee = desc
                        box.Color3 = Color3.fromRGB(0, 255, 190)
                        box.LineThickness = 0.05
                        box.Parent = desc
                    end
                else
                    local oldBox = desc:FindFirstChild("CollisionBoxOutline")
                    if oldBox then oldBox:Destroy() end
                    desc.Transparency = 1
                    desc.Material = Enum.Material.Concrete
                end
                count = count + 1
            else
                local stray = desc:FindFirstChild("CollisionBoxOutline") or desc:FindFirstChild("InvisibleBoxView")
                if stray then
                    stray:Destroy()
                    desc.Transparency = 1
                end
            end
        end
    end
    return count
end

if Config.ShowApartmentBoxDefault then
    task.spawn(function()
        task.wait(0.3)
        setApartmentBoxesVisible(true)
    end)
end

-- ==============================================================================
-- 2. FILTROS OPTIMIZADOS + BÚSQUEDA DE CENTRO DESPEJADO (CERO FILOS)
-- ==============================================================================

local envRayParams = RaycastParams.new()
envRayParams.FilterType = Enum.RaycastFilterType.Exclude
envRayParams.IgnoreWater = true

local function refreshStaticFilter()
    local ignore = {}
    if lp.Character then table.insert(ignore, lp.Character) end
    local charsFolder = workspace:FindFirstChild("Characters")
    if charsFolder then table.insert(ignore, charsFolder) end
    local holstered = workspace:FindFirstChild("HolsteredWeapons")
    if holstered then table.insert(ignore, holstered) end
    envRayParams.FilterDescendantsInstances = ignore
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshOverlapFilter()
    local ignore = {}
    if lp.Character then table.insert(ignore, lp.Character) end
    local charsFolder = workspace:FindFirstChild("Characters")
    if charsFolder then table.insert(ignore, charsFolder) end
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder then table.insert(ignore, mapFolder) end
    local droppedFolder = workspace:FindFirstChild("DroppedItems")
    if droppedFolder then table.insert(ignore, droppedFolder) end
    local holstered = workspace:FindFirstChild("HolsteredWeapons")
    if holstered then table.insert(ignore, holstered) end
    if State.RoofPart then table.insert(ignore, State.RoofPart) end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then table.insert(ignore, plr.Character) end
    end
    overlapParams.FilterDescendantsInstances = ignore
end

-- Evita quedar atascado en filos de edificios tras un jalón de rubberband
local function findClearAirOrigin(originPos)
    refreshStaticFilter()
    local bestPos = Vector3.new(originPos.X, math.max(originPos.Y, Config.MinCruiseY), originPos.Z)
    local lowestObstacleY = math.huge

    for r = 0, 24, 8 do
        for a = 0, math.pi * 1.75, math.pi / 4 do
            local tx = originPos.X + math.cos(a) * r
            local tz = originPos.Z + math.sin(a) * r
            local hit = workspace:Raycast(Vector3.new(tx, math.max(originPos.Y + 10, Config.MinCruiseY), tz), Vector3.new(0, -140, 0), envRayParams)
            local hitY = hit and hit.Position.Y or 0
            if hitY < lowestObstacleY then
                lowestObstacleY = hitY
                bestPos = Vector3.new(tx, math.max(originPos.Y, Config.MinCruiseY), tz)
            end
        end
    end
    return bestPos
end

-- Clasifica amenazas reales (ignora armas enfundadas y basura del mapa)
local function classifyCapturedHazard(part)
    if not part or not part:IsA("BasePart") then return nil end
    if lp.Character and part:IsDescendantOf(lp.Character) then return nil end

    local pName = part.Name
    local parentName = part.Parent and part.Parent.Name or ""
    if parentName:find("HolsteredWeapons", 1, true) or pName:find("_Back", 1, true) then
        return nil
    end

    if pName == "Missile" or parentName == "Missile" then
        return "Missile"
    elseif pName == "Spit" or parentName == "Spit" or pName == "BlightSpit" or parentName == "BlightSpit" then
        return "Spit"
    elseif pName == "Boulder" or parentName == "Boulder" then
        return "Boulder"
    elseif pName == "AcidPool" or parentName == "AcidPool" then
        return "AcidPool"
    elseif pName == "StalkerSlash" or parentName == "StalkerSlash" then
        return "StalkerSlash"
    end

    return nil
end

-- Rastreo por eventos de Cyborg, Experiment y Tyrant
local trackedBossModels = {}
local function refreshBossFlag()
    local foundCyborg, foundExp, foundTyrant = false, false, false
    for m, kind in pairs(trackedBossModels) do
        local hum = m and m.Parent and m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 and m:GetAttribute("Dead") ~= true then
            if kind == "Cyborg" then foundCyborg = true end
            if kind == "Experiment" then foundExp = true end
            if kind == "Tyrant" then foundTyrant = true end
        else
            trackedBossModels[m] = nil
        end
    end
    State.HasBossActive = (foundCyborg or foundExp or foundTyrant)
    local names = {}
    if foundCyborg then table.insert(names, "Cyborg") end
    if foundExp then table.insert(names, "Experiment") end
    if foundTyrant then table.insert(names, "Tyrant") end
    State.ActiveBossLabel = (#names > 0) and table.concat(names, "+") or "Ninguno"
end

task.spawn(function()
    local cFolder = workspace:FindFirstChild("Characters") or workspace
    local function checkModel(m)
        if m and m:IsA("Model") then
            local low = m.Name:lower()
            if low:find("cyborg", 1, true) then
                trackedBossModels[m] = "Cyborg"
                refreshBossFlag()
            elseif low:find("experiment", 1, true) then
                trackedBossModels[m] = "Experiment"
                refreshBossFlag()
            elseif low:find("tyrant", 1, true) then
                trackedBossModels[m] = "Tyrant"
                refreshBossFlag()
            end
        end
    end
    for _, ch in ipairs(cFolder:GetChildren()) do checkModel(ch) end
    cFolder.ChildAdded:Connect(checkModel)
    cFolder.ChildRemoved:Connect(function(ch)
        if trackedBossModels[ch] then
            trackedBossModels[ch] = nil
            refreshBossFlag()
        end
    end)
end)

-- Bucle ligero de Radar Forense (0.10s)
task.spawn(function()
    local filterTick = 0
    local jinkTick = 0
    local prevPositions = setmetatable({}, {__mode = "k"})

    while _G.PilotV13_Running do
        task.wait(0.10)
        if not Config.Active then
            State.DodgeOffset = Vector3.zero
            State.IsBurstDodging = false
            State.RoofAvoidJumpNeeded = false
            State.WallSideDodge = Vector3.zero
            State.DetectedBelowCount = 0
            continue
        end

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        local now = tick()
        if (now - filterTick) >= 2.0 then
            filterTick = now
            refreshStaticFilter()
            refreshOverlapFilter()
            refreshBossFlag()
        end

        local myPos = root.Position

        -- A. Escudo anti-pisada de techos vecinos y filos
        if Config.AvoidOtherRoofs and (State.Phase == "Advancing" or State.Phase == "Pattern") then
            local floorHit = workspace:Raycast(myPos, Vector3.new(0, -Config.FloorClearanceStuds, 0), envRayParams)
            State.RoofAvoidJumpNeeded = (floorHit ~= nil)

            local velH = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
            if velH.Magnitude > 2.0 then
                local fwdU = velH.Unit
                local wallHit = workspace:Raycast(myPos, fwdU * Config.WallDetectStuds, envRayParams)
                if wallHit then
                    State.RoofAvoidJumpNeeded = true
                    State.WallSideDodge = Vector3.new(-fwdU.Z, 0, fwdU.X) * 14
                else
                    State.WallSideDodge = Vector3.zero
                end
            else
                State.WallSideDodge = Vector3.zero
            end
        else
            State.RoofAvoidJumpNeeded = false
            State.WallSideDodge = Vector3.zero
        end

        -- B. Radar Forense de Proyectiles CFrame (incluye Spit estacionario Y=90 y Missile)
        if Config.AutoDodgeObjects then
            local maxHoriz = math.max(Config.RadarHorizRadius, Config.DodgeTriggerDist)
            local downDepth = Config.RadarDownDepth
            local boxSize = Vector3.new(maxHoriz * 2, downDepth + 22, maxHoriz * 2)
            local boxCenter = myPos - Vector3.new(0, (downDepth - 22) * 0.5, 0)
            local partsInBox = workspace:GetPartBoundsInBox(CFrame.new(boxCenter), boxSize, overlapParams)

            local closestThreatPos = nil
            local closestEstimatedVel = Vector3.zero
            local closestDist = math.huge
            local closestType = nil
            local belowAlerts = 0

            for _, part in ipairs(partsInBox) do
                local hazardType = classifyCapturedHazard(part)
                if hazardType then
                    local pPos = part.Position
                    local prevP = prevPositions[part]
                    prevPositions[part] = pPos

                    local estVel = prevP and ((pPos - prevP) / 0.10) or part.AssemblyLinearVelocity
                    local dist = (pPos - myPos).Magnitude

                    if pPos.Y < myPos.Y and (myPos.Y - pPos.Y) <= downDepth then
                        belowAlerts = belowAlerts + 1
                    end

                    local effectiveDist = (hazardType == "Missile") and (dist * 0.8) or dist
                    if dist <= Config.DodgeTriggerDist and effectiveDist < closestDist then
                        closestDist = effectiveDist
                        closestThreatPos = pPos
                        closestEstimatedVel = estVel
                        closestType = hazardType
                    end
                end
            end

            State.DetectedBelowCount = belowAlerts

            if closestThreatPos and closestType then
                local awayVec = Vector3.new(myPos.X - closestThreatPos.X, 0, myPos.Z - closestThreatPos.Z)
                local sideDir

                if closestEstimatedVel.Magnitude > 2.0 then
                    local velHoriz = Vector3.new(closestEstimatedVel.X, 0, closestEstimatedVel.Z)
                    if velHoriz.Magnitude > 0.2 then
                        local perp = Vector3.new(-velHoriz.Z, 0, velHoriz.X).Unit
                        if closestType == "Missile" then
                            if (now - jinkTick) >= 0.35 then
                                jinkTick = now
                                State.MissileJinkSign = -State.MissileJinkSign
                            end
                            sideDir = perp * State.MissileJinkSign
                        else
                            sideDir = (perp:Dot(awayVec) >= 0) and perp or -perp
                        end
                    end
                end

                if not sideDir then
                    sideDir = (awayVec.Magnitude > 0.2) and awayVec.Unit or Vector3.new(1, 0, 0)
                end

                local extraUp = (closestType == "Spit") and (Config.DodgeUpStuds + 6) or Config.DodgeUpStuds
                State.DodgeOffset = (sideDir * Config.DodgeSideStuds) + Vector3.new(0, extraUp, 0)
                State.DodgeUntil = now + Config.DodgeHoldSeconds
                State.IsBurstDodging = true
                State.LastThreatName = string.format("%s (%.0fm)", closestType, (closestThreatPos - myPos).Magnitude)
            elseif now >= State.DodgeUntil then
                State.DodgeOffset = Vector3.zero
                State.IsBurstDodging = false
            end
        else
            State.DodgeOffset = Vector3.zero
            State.IsBurstDodging = false
            State.DetectedBelowCount = 0
        end
    end
end)

-- ==============================================================================
-- 3. DETECCIÓN FÍSICA REAL DE SUELO SÓLIDO
-- ==============================================================================

local function detectFloorBelow(root)
    refreshStaticFilter()
    local hit = workspace:Raycast(root.Position, Vector3.new(0, -25, 0), envRayParams)
    if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
        State.RoofPart = hit.Instance
        return hit.Position
    end
    return nil
end

local function isActuallyStandingOnSolid(root, hum)
    if not root or not hum then return false end
    if hum.FloorMaterial ~= Enum.Material.Air then
        return true
    end

    local footHit = workspace:Raycast(root.Position, Vector3.new(0, -4.2, 0), envRayParams)
    if footHit and footHit.Instance and footHit.Instance:IsA("BasePart") and footHit.Instance.CanCollide then
        return true
    end

    return false
end

-- ==============================================================================
-- 4. GENERADOR DE COORDENADAS PRECALCULADAS EN ALTURA SEGURA (Y >= MinCruiseY)
-- ==============================================================================

local function buildPatternWaypoints(originPos)
    local fwd = DIRECTION_VECTORS[Config.Direction] or Vector3.new(1, 0, 0)
    local right = Vector3.new(-fwd.Z, 0, fwd.X)
    local baseY = math.max(originPos.Y, Config.MinCruiseY)
    local center = Vector3.new(originPos.X, baseY, originPos.Z) + (fwd * Config.ForwardStuds)
    local r = Config.PatternRadius
    local dip = Config.VerticalDipStuds
    local pts = {}

    if Config.Pattern == "Solo Adelante" then
        table.insert(pts, center + Vector3.new(0, -dip, 0))
        table.insert(pts, center)

    elseif Config.Pattern == "Círculo" then
        local segments = 12
        for i = 0, segments - 1 do
            local theta = (i / segments) * (math.pi * 2)
            local yOff = -math.abs(math.sin(theta)) * dip
            local p = center + (fwd * (math.cos(theta) * r)) + (right * (math.sin(theta) * r)) + Vector3.new(0, yOff, 0)
            table.insert(pts, p)
        end

    elseif Config.Pattern == "Cuadrado" then
        table.insert(pts, center + (fwd * r) + (right * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center + (fwd * r) - (right * r))
        table.insert(pts, center - (fwd * r) - (right * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center - (fwd * r) + (right * r))

    elseif Config.Pattern == "Zigzag" then
        local steps = 4
        for i = 0, steps do
            local t = (i / steps) * 2 - 1
            local side = ((i % 2 == 0) and 1 or -1) * r
            local yOff = ((i % 2 == 0) and -dip or 0)
            table.insert(pts, center + (fwd * (t * (r * 0.75))) + (right * side) + Vector3.new(0, yOff, 0))
        end
        for i = steps - 1, 1, -1 do
            local t = (i / steps) * 2 - 1
            local side = ((i % 2 == 0) and -1 or 1) * r
            table.insert(pts, center + (fwd * (t * (r * 0.75))) + (right * side))
        end

    elseif Config.Pattern == "Rombo" then
        table.insert(pts, center + (fwd * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center + (right * r))
        table.insert(pts, center - (fwd * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center - (right * r))

    elseif Config.Pattern == "I Invertida" then
        table.insert(pts, center)
        table.insert(pts, center + (right * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center)
        table.insert(pts, center - (right * r) + Vector3.new(0, -dip, 0))
    end

    State.Waypoints = pts
    State.CurrentWpIndex = 1
end

-- ==============================================================================
-- 5. CICLO ESTRICTO: ARMA 2 AL DETENERSE RELOJ -> PODER 5 -> REVISAR RELOJ / UNEQUIP
-- ==============================================================================

local function pressNumberKey(num)
    local kc = (num == 2 and Enum.KeyCode.Two) or (num == 5 and Enum.KeyCode.Five)
    if kc then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, kc, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, kc, false, game)
        end)
    end
end

local function simulateMouseClick()
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

local function findSystemOverrideTool()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")

    local slot5Frame = nil
    if bpg then
        local hotbar = bpg:FindFirstChild("Hotbar", true)
        local rootSearch = hotbar or bpg
        for _, child in ipairs(rootSearch:GetChildren()) do
            if child:IsA("GuiObject") and (child.Name == "5" or child.Name == "Slot5") then
                slot5Frame = child
                break
            end
        end
    end

    for _, container in ipairs({char, bp}) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") then
                    local low = item.Name:lower()
                    if low:find("anulaci", 1, true) or low:find("sistema", 1, true) or low:find("override", 1, true) then
                        return item
                    end
                end
            end
        end
    end

    if slot5Frame then
        for _, desc in ipairs(slot5Frame:GetDescendants()) do
            if desc:IsA("ObjectValue") and desc.Value and desc.Value:IsA("Tool") then
                return desc.Value
            elseif desc:IsA("TextLabel") and desc.Text ~= "" and desc.Text ~= "5" and not desc.Text:match("^[%d:%.s]+$") then
                local tName = desc.Text
                if char and char:FindFirstChild(tName) then return char[tName] end
                if bp and bp:FindFirstChild(tName) then return bp[tName] end
            end
        end
    end

    local all = {}
    if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then table.insert(all, t) end end end
    if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(all, t) end end end
    return all[5]
end

local function findSlot2Tool()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")

    if bpg then
        local hotbar = bpg:FindFirstChild("Hotbar", true)
        local rootSearch = hotbar or bpg
        for _, child in ipairs(rootSearch:GetChildren()) do
            if child:IsA("GuiObject") and (child.Name == "2" or child.Name == "Slot2") then
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("ObjectValue") and desc.Value and desc.Value:IsA("Tool") then
                        return desc.Value
                    elseif desc:IsA("TextLabel") and desc.Text ~= "" and desc.Text ~= "2" and not desc.Text:match("^[%d:%.s]+$") then
                        local tName = desc.Text
                        if char and char:FindFirstChild(tName) then return char[tName] end
                        if bp and bp:FindFirstChild(tName) then return bp[tName] end
                    end
                end
            end
        end
    end

    for _, container in ipairs({char, bp}) do
        if container and container:FindFirstChild("LMG") then
            return container.LMG
        end
    end

    local all = {}
    if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then table.insert(all, t) end end end
    if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(all, t) end end end
    return all[2]
end

local function equipSlot2Only()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return end

    local tool2 = findSlot2Tool()
    if tool2 then
        if char:FindFirstChildOfClass("Tool") ~= tool2 then
            hum:EquipTool(tool2)
        end
    else
        pressNumberKey(2)
    end
end

local function unequipSlot2OnceIfEquipped()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return end

    local equipped = char:FindFirstChildOfClass("Tool")
    local tool2 = findSlot2Tool()
    if equipped and (equipped == tool2 or equipped.Name:lower():find("lmg")) then
        pcall(function() hum:UnequipTools() end)
    end
end

local function activatePower5Only()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return end

    local tool5 = findSystemOverrideTool()
    if tool5 then
        hum:EquipTool(tool5)
        task.wait(0.08)
        pcall(function() tool5:Activate() end)
        simulateMouseClick()
        for _, desc in ipairs(tool5:GetDescendants()) do
            if desc:IsA("RemoteEvent") then
                pcall(function() desc:FireServer() end)
            elseif desc:IsA("RemoteFunction") then
                task.spawn(function() pcall(function() desc:InvokeServer() end) end)
            end
        end
        task.wait(Config.Power5CastWait)
    else
        pressNumberKey(5)
        task.wait(0.08)
        simulateMouseClick()
        task.wait(Config.Power5CastWait)
    end
end

local function getSurvivalTimeSecondsAndLabel()
    local attrSec = workspace:GetAttribute("EternalNightTime")
    local pg = lp:FindFirstChild("PlayerGui")
    local topUI = pg and pg:FindFirstChild("TopUI")
    local dayCounter = topUI and topUI:FindFirstChild("DayCounter")

    local displayStr = nil
    if dayCounter and dayCounter:IsA("TextLabel") and dayCounter.Text ~= "" then
        displayStr = dayCounter.Text:gsub("Survived:%s*", "")
    elseif type(attrSec) == "number" then
        local mins = math.floor(attrSec / 60)
        local secs = math.floor(attrSec % 60)
        displayStr = string.format("%02d:%02d", mins, secs)
    end

    if type(attrSec) == "number" then
        return attrSec, displayStr
    end

    if displayStr then
        local m, s = displayStr:match("(%d+):(%d+)")
        if m and s then
            return (tonumber(m) * 60) + tonumber(s), displayStr
        end
    end

    return nil, "N/A"
end

task.spawn(function()
    local lastSeconds = nil
    local didUnequipOnRunStart = false
    local lastFixedTimerTick = 0

    while _G.PilotV13_Running do
        task.wait(Config.TimeCheckInterval)
        local curSec, labelStr = getSurvivalTimeSecondsAndLabel()
        State.DetectedHudTime = labelStr

        if not Config.Active or not Config.AutoWeaponCycle then
            lastSeconds = nil
            didUnequipOnRunStart = false
            continue
        end

        if Config.Power5Mode == "EternalNightStop" then
            if not curSec then
                State.Power5StatusText = "Buscando reloj Survived..."
                continue
            end

            if lastSeconds then
                local isClockFrozen = (math.abs(curSec - lastSeconds) < 0.01)

                if isClockFrozen then
                    didUnequipOnRunStart = false

                    if Config.EquipSlot2Default then
                        equipSlot2Only()
                    end

                    local waitEnd = tick() + Config.TimeStopDelay
                    local abortedByClock = false
                    while tick() < waitEnd do
                        task.wait(0.25)
                        if not Config.Active or not Config.AutoWeaponCycle or Config.Power5Mode ~= "EternalNightStop" then
                            abortedByClock = true
                            break
                        end
                        if Config.EquipSlot2Default then
                            equipSlot2Only()
                        end
                        local nowSec = getSurvivalTimeSecondsAndLabel()
                        if nowSec and math.abs(nowSec - curSec) >= 0.01 then
                            abortedByClock = true
                            break
                        end
                        local rem = math.max(0, math.ceil(waitEnd - tick()))
                        State.Power5StatusText = string.format("Reloj quieto (%s): Poder 5 en %ds", labelStr, rem)
                    end

                    while not abortedByClock and Config.Active and Config.AutoWeaponCycle and Config.Power5Mode == "EternalNightStop" do
                        local checkBeforeCast = getSurvivalTimeSecondsAndLabel()
                        if not checkBeforeCast or math.abs(checkBeforeCast - curSec) >= 0.01 then
                            break
                        end

                        State.Power5StatusText = "⚡ Activando Poder 5..."
                        activatePower5Only()

                        local checkAfterCast = getSurvivalTimeSecondsAndLabel()
                        if checkAfterCast and math.abs(checkAfterCast - curSec) >= 0.01 then
                            unequipSlot2OnceIfEquipped()
                            didUnequipOnRunStart = true
                            State.Power5StatusText = "Reloj corriendo: Arma 2 liberada"
                            break
                        end

                        if Config.EquipSlot2Default then
                            equipSlot2Only()
                        end

                        local rechargeEnd = tick() + Config.Power5Interval
                        local clockStartedDuringCd = false
                        while tick() < rechargeEnd do
                            task.wait(0.5)
                            if not Config.Active or not Config.AutoWeaponCycle or Config.Power5Mode ~= "EternalNightStop" then
                                clockStartedDuringCd = true
                                break
                            end
                            local stillFrozen = getSurvivalTimeSecondsAndLabel()
                            if not stillFrozen or math.abs(stillFrozen - curSec) >= 0.01 then
                                clockStartedDuringCd = true
                                break
                            end
                            local remCd = math.max(0, math.ceil(rechargeEnd - tick()))
                            State.Power5StatusText = string.format("Noche (%s): Recarga 5to (%ds) -> Arma 2", labelStr, remCd)
                        end

                        if clockStartedDuringCd then
                            local nowClock = getSurvivalTimeSecondsAndLabel()
                            if nowClock and math.abs(nowClock - curSec) >= 0.01 then
                                unequipSlot2OnceIfEquipped()
                                didUnequipOnRunStart = true
                                State.Power5StatusText = "Reloj corriendo: Arma 2 liberada"
                            end
                            break
                        end
                    end
                else
                    if not didUnequipOnRunStart then
                        unequipSlot2OnceIfEquipped()
                        didUnequipOnRunStart = true
                    end
                    State.Power5StatusText = string.format("Tiempo corriendo (%s) - Libre", labelStr)
                end
            end

            lastSeconds = curSec
        else
            local elapsed = tick() - lastFixedTimerTick
            if lastFixedTimerTick == 0 or elapsed >= Config.Power5Interval then
                lastFixedTimerTick = tick()
                State.Power5StatusText = "⚡ Activando Poder 5 -> Arma 2"
                activatePower5Only()
                if Config.EquipSlot2Default then
                    equipSlot2Only()
                end
            else
                State.Power5StatusText = string.format("Timer fijo: %ds / %ds", math.floor(Config.Power5Interval - elapsed), Config.Power5Interval)
                if Config.EquipSlot2Default then
                    equipSlot2Only()
                end
            end
        end
    end
end)

-- ==============================================================================
-- 6. FÍSICA PARABÓLICA V13.1 (CERO FILOS + ANTI-RUBBERBAND + LIBERACIÓN AL STOP)
-- ==============================================================================

local function resetPhysicsCompletely()
    State.Phase = "Idle"
    State.LastRealPos = nil
    State.GroundedConfirmedSince = nil
    State.DodgeOffset = Vector3.zero
    State.RoofAvoidJumpNeeded = false
    State.WallSideDodge = Vector3.zero
    State.IsBurstDodging = false
    State.DodgeUntil = 0

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if root then
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = true
            end
        end
    end

    -- Restaura el control 100% manual y quita restricciones de altura/estado
    if hum then
        hum.PlatformStand = false
        hum.AutoRotate = true
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Freefall)
        end)
    end
end

_G.PilotV13_HeartConn = RunService.Heartbeat:Connect(function()
    if not Config.Active then return end

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    if not State.StartOrigin then
        State.StartOrigin = findClearAirOrigin(root.Position)
        State.LastRealPos = root.Position
        refreshStaticFilter()
        refreshOverlapFilter()
        refreshBossFlag()
        detectFloorBelow(root)
        State.Phase = "Advancing"
        State.AirStartTime = tick()
        State.LastJumpPulse = 0
        buildPatternWaypoints(State.StartOrigin)
    end

    if hum.PlatformStand then
        hum.PlatformStand = false
    end

    -- Evitar que el Humanoid entre en Freefall/FallingDown al rozar un borde
    local hState = hum:GetState()
    if hState == Enum.HumanoidStateType.FallingDown or hState == Enum.HumanoidStateType.Ragdoll then
        hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
    end

    local now = tick()
    local fwdDir = DIRECTION_VECTORS[Config.Direction] or Vector3.new(1, 0, 0)
    local advanceDest = State.StartOrigin + (fwdDir * Config.ForwardStuds)
    local mode = Config.AntiRubberMode

    if State.Phase == "SteppingOnRoof" then
        local onSolidGround = isActuallyStandingOnSolid(root, hum)
        if onSolidGround then
            root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)

            if not State.GroundedConfirmedSince then
                State.GroundedConfirmedSince = now
            end
            local heldFor = now - State.GroundedConfirmedSince
            State.StatusText = string.format("✅ Pisando techo sólido (%.2fs / %.2fs)...", heldFor, Config.TouchRoofHoldTime)

            if heldFor >= Config.TouchRoofHoldTime then
                State.StartOrigin = findClearAirOrigin(root.Position)
                State.LastRealPos = root.Position
                State.GroundedConfirmedSince = nil
                State.Phase = "Advancing"
                State.AirStartTime = now
                State.LastJumpPulse = 0
                buildPatternWaypoints(State.StartOrigin)
            end
        else
            State.GroundedConfirmedSince = nil
            State.StatusText = "⬇️ Cayendo hasta pisar el techo..."
            local floorCheck = detectFloorBelow(root)
            if not floorCheck then
                local backHoriz = Vector3.new(State.StartOrigin.X - root.Position.X, 0, State.StartOrigin.Z - root.Position.Z)
                if backHoriz.Magnitude > 1.0 then
                    local vel = backHoriz.Unit * math.min(Config.ReturnSpeed, 30.0)
                    root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)
                end
            else
                root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, -14), 0)
            end
        end
        return
    end

    if State.Phase == "RubberCooldown" then
        local rem = math.max(0, State.RubberWaitUntil - now)
        State.StatusText = string.format("⏳ Rubberband (#%d): Reiniciando en %.2fs...", State.RubberbandCount, rem)
        if now >= State.RubberWaitUntil then
            -- Re-centra lejos de filos para evitar bucle de 3 rubberbands seguidos
            State.StartOrigin = findClearAirOrigin(root.Position)
            State.LastRealPos = root.Position
            State.Phase = "Advancing"
            State.AirStartTime = now
            State.LastJumpPulse = 0
            buildPatternWaypoints(State.StartOrigin)
        end
        return
    end

    if State.Phase == "Advancing" or State.Phase == "Pattern" then
        if mode == "ReturnAndStep" then
            if (now - State.AirStartTime) >= Config.MaxAirTimeBeforeReturn then
                State.Phase = "ReturningToRoof"
            end
        elseif mode == "WaitRubber" then
            if State.LastRealPos then
                local jumpBackDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(State.LastRealPos.X, 0, State.LastRealPos.Z)).Magnitude
                if jumpBackDist >= Config.RubberbandDetectDist then
                    State.RubberbandCount = State.RubberbandCount + 1
                    root.AssemblyLinearVelocity = Vector3.zero
                    State.Phase = "RubberCooldown"
                    State.RubberWaitUntil = now + Config.PostRubberWaitTime
                    State.LastRealPos = root.Position
                    return
                end
            end
        end
    end

    State.LastRealPos = root.Position

    local targetWp = advanceDest
    local moveSpeed = State.IsBurstDodging and Config.DodgeBurstSpeed or Config.FlySpeed

    if State.Phase == "ReturningToRoof" then
        State.StatusText = "🔙 Volviendo al techo para pisar..."
        targetWp = State.StartOrigin + Vector3.new(0, 1.5, 0)
        moveSpeed = Config.ReturnSpeed

        local horizToRoof = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetWp.X, 0, targetWp.Z)).Magnitude
        if horizToRoof <= 2.5 then
            root.AssemblyLinearVelocity = Vector3.new(0, -14, 0)
            State.Phase = "SteppingOnRoof"
            State.GroundedConfirmedSince = nil
            return
        end

    elseif State.Phase == "Advancing" then
        State.StatusText = string.format("🦘 Avanzando al %s (%d studs) | Y:%.0f", Config.Direction, Config.ForwardStuds, root.Position.Y)
        targetWp = advanceDest + State.WallSideDodge + State.DodgeOffset

        local horizDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(advanceDest.X, 0, advanceDest.Z)).Magnitude
        if horizDist <= 3.0 then
            State.Phase = "Pattern"
            State.CurrentWpIndex = 1
        end

    elseif State.Phase == "Pattern" then
        local wps = State.Waypoints
        if #wps == 0 then
            buildPatternWaypoints(State.StartOrigin)
            wps = State.Waypoints
        end

        targetWp = (wps[State.CurrentWpIndex] or advanceDest) + State.DodgeOffset + State.WallSideDodge

        if State.IsBurstDodging then
            State.StatusText = string.format("🚨 ¡ESQUIVA %s! | %s", State.LastThreatName, Config.Pattern)
        elseif State.HasBossActive then
            State.StatusText = string.format("⚠️ %s activo (+%dm) | %s | Y:%.0f", State.ActiveBossLabel, Config.BossExtraHeight, Config.Pattern, root.Position.Y)
        elseif State.RoofAvoidJumpNeeded then
            State.StatusText = string.format("🛡️ Evitando filo/techo | %s", Config.Pattern)
        elseif mode == "ReturnAndStep" then
            local left = math.max(0, Config.MaxAirTimeBeforeReturn - (now - State.AirStartTime))
            State.StatusText = string.format("🌪️ %s (%d/%d) | Pisar en %.1fs", Config.Pattern, State.CurrentWpIndex, #wps, left)
        else
            State.StatusText = string.format("🌪️ %s (%d/%d) | Y:%.0f | RB:%d", Config.Pattern, State.CurrentWpIndex, #wps, root.Position.Y, State.RubberbandCount)
        end

        local horizDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetWp.X, 0, targetWp.Z)).Magnitude
        if horizDist <= 3.8 then
            State.CurrentWpIndex = (State.CurrentWpIndex % #wps) + 1
            targetWp = (wps[State.CurrentWpIndex] or advanceDest) + State.DodgeOffset + State.WallSideDodge
        end
    end

    local toTargetHoriz = Vector3.new(targetWp.X - root.Position.X, 0, targetWp.Z - root.Position.Z)
    local horizVel = Vector3.zero
    if toTargetHoriz.Magnitude > 0.15 then
        horizVel = toTargetHoriz.Unit * moveSpeed
    end

    local curVelY = root.AssemblyLinearVelocity.Y
    local bossBoost = State.HasBossActive and Config.BossExtraHeight or 0
    -- Garantiza altura >= MinCruiseY (115 studs) para evitar nubes de Spit en Y=90
    local desiredY = math.max(targetWp.Y + bossBoost, Config.MinCruiseY + bossBoost)

    if State.Phase == "ReturningToRoof" then
        if root.Position.Y < (State.StartOrigin.Y + 1.5) then
            curVelY = Config.JumpImpulseY
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    else
        local needJump = ((now - State.LastJumpPulse) >= Config.JumpPulseInterval)
            or (root.Position.Y < (desiredY - 1.5))
            or (State.RoofAvoidJumpNeeded and (now - State.LastJumpPulse) >= 0.30)

        if needJump then
            State.LastJumpPulse = now
            curVelY = Config.JumpImpulseY
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    root.AssemblyLinearVelocity = Vector3.new(horizVel.X, curVelY, horizVel.Z)

    if horizVel.Magnitude > 1.0 then
        root.CFrame = CFrame.lookAt(root.Position, root.Position + horizVel.Unit)
    end
end)

-- ==============================================================================
-- 7. INTERFAZ GRÁFICA NATIVA ROBLOX (3 PESTAÑAS + ESCUDO FORENSE COMPLETO)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
for _, oldName in ipairs({"RoofAerialPilotGuiV11", "RoofAerialPilotGuiV13"}) do
    local existing = GuiParent:FindFirstChild(oldName)
    if existing then existing:Destroy() end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RoofAerialPilotGuiV13"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(20, 125, 175)
FloatBtn.Text = "✈️\nV13.1"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 540, 0, 465)
MainFrame.Position = UDim2.new(0.5, -270, 0.5, -232)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 19, 26)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 29, 40)
TitleBar.Text = "  ✈️ PILOTO PARABÓLICO V13.1 | CERO FILOS + ESCUDO SPIT/MISSILE"
TitleBar.TextColor3 = Color3.fromRGB(0, 235, 255)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TabMainBtn = Instance.new("TextButton")
TabMainBtn.Size = UDim2.new(0.34, -8, 0, 28)
TabMainBtn.Position = UDim2.new(0, 10, 0, 40)
TabMainBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 170)
TabMainBtn.Text = "🎮 CONTROL VUELO"
TabMainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TabMainBtn.TextSize = 9
TabMainBtn.Font = Enum.Font.GothamBold
TabMainBtn.Parent = MainFrame
Instance.new("UICorner", TabMainBtn).CornerRadius = UDim.new(0, 6)

local TabRadarBtn = Instance.new("TextButton")
TabRadarBtn.Size = UDim2.new(0.33, -8, 0, 28)
TabRadarBtn.Position = UDim2.new(0.34, 4, 0, 40)
TabRadarBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabRadarBtn.Text = "🛡️ RADAR OBJETOS"
TabRadarBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabRadarBtn.TextSize = 9
TabRadarBtn.Font = Enum.Font.GothamBold
TabRadarBtn.Parent = MainFrame
Instance.new("UICorner", TabRadarBtn).CornerRadius = UDim.new(0, 6)

local TabConfigBtn = Instance.new("TextButton")
TabConfigBtn.Size = UDim2.new(0.33, -8, 0, 28)
TabConfigBtn.Position = UDim2.new(0.67, 0, 0, 40)
TabConfigBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabConfigBtn.Text = "⚙️ CONFIG VUELO"
TabConfigBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabConfigBtn.TextSize = 9
TabConfigBtn.Font = Enum.Font.GothamBold
TabConfigBtn.Parent = MainFrame
Instance.new("UICorner", TabConfigBtn).CornerRadius = UDim.new(0, 6)

local MainPage = Instance.new("Frame")
MainPage.Size = UDim2.new(1, 0, 1, -74)
MainPage.Position = UDim2.new(0, 0, 0, 74)
MainPage.BackgroundTransparency = 1
MainPage.Visible = true
MainPage.Parent = MainFrame

local RadarPage = Instance.new("ScrollingFrame")
RadarPage.Size = UDim2.new(1, 0, 1, -74)
RadarPage.Position = UDim2.new(0, 0, 0, 74)
RadarPage.BackgroundTransparency = 1
RadarPage.BorderSizePixel = 0
RadarPage.CanvasSize = UDim2.new(0, 0, 0, 460)
RadarPage.ScrollBarThickness = 5
RadarPage.Visible = false
RadarPage.Parent = MainFrame

local ConfigPage = Instance.new("ScrollingFrame")
ConfigPage.Size = UDim2.new(1, 0, 1, -74)
ConfigPage.Position = UDim2.new(0, 0, 0, 74)
ConfigPage.BackgroundTransparency = 1
ConfigPage.BorderSizePixel = 0
ConfigPage.CanvasSize = UDim2.new(0, 0, 0, 880)
ConfigPage.ScrollBarThickness = 5
ConfigPage.Visible = false
ConfigPage.Parent = MainFrame

local function switchTab(activeBtn, activePage)
    MainPage.Visible   = (activePage == MainPage)
    RadarPage.Visible  = (activePage == RadarPage)
    ConfigPage.Visible = (activePage == ConfigPage)

    for _, btn in ipairs({TabMainBtn, TabRadarBtn, TabConfigBtn}) do
        if btn == activeBtn then
            btn.BackgroundColor3 = Color3.fromRGB(0, 130, 170)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            btn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
            btn.TextColor3 = Color3.fromRGB(200, 200, 200)
        end
    end
end

TabMainBtn.MouseButton1Click:Connect(function() switchTab(TabMainBtn, MainPage) end)
TabRadarBtn.MouseButton1Click:Connect(function() switchTab(TabRadarBtn, RadarPage) end)
TabConfigBtn.MouseButton1Click:Connect(function() switchTab(TabConfigBtn, ConfigPage) end)

local function createStepper(parent, yPos, title, getSubText, onMinus, onPlus, rebuildOnEdit)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 48)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, -10, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title .. "\n" .. getSubText()
    lbl.TextColor3 = Color3.fromRGB(235, 240, 250)
    lbl.TextSize = 9
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local minusBtn = Instance.new("TextButton")
    minusBtn.Size = UDim2.new(0, 46, 0, 32)
    minusBtn.Position = UDim2.new(1, -106, 0, 8)
    minusBtn.BackgroundColor3 = Color3.fromRGB(165, 45, 55)
    minusBtn.Text = "➖"
    minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minusBtn.TextSize = 12
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.Parent = row
    Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

    local plusBtn = Instance.new("TextButton")
    plusBtn.Size = UDim2.new(0, 46, 0, 32)
    plusBtn.Position = UDim2.new(1, -54, 0, 8)
    plusBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
    plusBtn.Text = "➕"
    plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    plusBtn.TextSize = 12
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.Parent = row
    Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

    minusBtn.MouseButton1Click:Connect(function()
        onMinus()
        if rebuildOnEdit and State.StartOrigin then buildPatternWaypoints(State.StartOrigin) end
        lbl.Text = title .. "\n" .. getSubText()
    end)

    plusBtn.MouseButton1Click:Connect(function()
        onPlus()
        if rebuildOnEdit and State.StartOrigin then buildPatternWaypoints(State.StartOrigin) end
        lbl.Text = title .. "\n" .. getSubText()
    end)
end

-- ==============================================================================
-- 8. PESTAÑA 1: CONTROL DE VUELO
-- ==============================================================================

local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, -20, 0, 68)
StatusCard.Position = UDim2.new(0, 10, 0, 4)
StatusCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
StatusCard.Parent = MainPage
Instance.new("UICorner", StatusCard).CornerRadius = UDim.new(0, 6)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -12, 1, -8)
StatusLabel.Position = UDim2.new(0, 6, 0, 4)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Estado: En espera (Detenido)"
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 180)
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextWrapped = true
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.Parent = StatusCard

task.spawn(function()
    while _G.PilotV13_Running do
        task.wait(0.35)
        if MainFrame.Visible and MainPage.Visible then
            StatusLabel.Text = string.format(
                "Estado: %s\nSurvived: [%s] | Jefes: %s | Radar: %s\nPoder 5: %s | Arma 2: %s",
                State.StatusText,
                State.DetectedHudTime,
                State.ActiveBossLabel,
                Config.AutoDodgeObjects and "ON" or "OFF",
                State.Power5StatusText,
                Config.AutoWeaponCycle and "ON" or "OFF"
            )
        end
    end
end)

local StartBtn = Instance.new("TextButton")
StartBtn.Size = UDim2.new(0.5, -12, 0, 40)
StartBtn.Position = UDim2.new(0, 10, 0, 80)
StartBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
StartBtn.Text = "▶️ INICIAR SALTO AÉREO"
StartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StartBtn.TextSize = 11
StartBtn.Font = Enum.Font.GothamBold
StartBtn.Parent = MainPage
Instance.new("UICorner", StartBtn).CornerRadius = UDim.new(0, 8)

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(0.5, -12, 0, 40)
StopBtn.Position = UDim2.new(0.5, 2, 0, 80)
StopBtn.BackgroundColor3 = Color3.fromRGB(195, 45, 55)
StopBtn.Text = "⏹️ DETENER (LIBERAR)"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.TextSize = 10
StopBtn.Font = Enum.Font.GothamBold
StopBtn.Parent = MainPage
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 8)

StartBtn.MouseButton1Click:Connect(function()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then
        State.StartOrigin = findClearAirOrigin(root.Position)
        State.LastRealPos = root.Position
        refreshStaticFilter()
        refreshOverlapFilter()
        refreshBossFlag()
        detectFloorBelow(root)
        State.Phase = "Advancing"
        State.AirStartTime = tick()
        State.LastJumpPulse = 0
        State.GroundedConfirmedSince = nil
        buildPatternWaypoints(State.StartOrigin)
        Config.Active = true
        if Config.EquipSlot2Default then
            equipSlot2Only()
        end
    end
end)

StopBtn.MouseButton1Click:Connect(function()
    Config.Active = false
    State.StartOrigin = nil
    State.StatusText = "Detenido (Control 100% libre)"
    resetPhysicsCompletely()
end)

local DirTitle = Instance.new("TextLabel")
DirTitle.Size = UDim2.new(1, -20, 0, 18)
DirTitle.Position = UDim2.new(0, 10, 0, 128)
DirTitle.BackgroundTransparency = 1
DirTitle.Text = "🧭 DIRECCIÓN DE AVANCE INICIAL:"
DirTitle.TextColor3 = Color3.fromRGB(180, 200, 220)
DirTitle.TextSize = 10
DirTitle.Font = Enum.Font.GothamBold
DirTitle.TextXAlignment = Enum.TextXAlignment.Left
DirTitle.Parent = MainPage

local dirButtons = {}
local dirs = {"NORTE", "SUR", "ESTE", "OESTE"}
for i, dName in ipairs(dirs) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.25, -7, 0, 32)
    b.Position = UDim2.new((i - 1) * 0.25, 10 - ((i - 1) * 2), 0, 148)
    b.BackgroundColor3 = (Config.Direction == dName) and Color3.fromRGB(0, 145, 215) or Color3.fromRGB(30, 35, 48)
    b.Text = dName
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 10
    b.Font = Enum.Font.GothamBold
    b.Parent = MainPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    dirButtons[dName] = b

    b.MouseButton1Click:Connect(function()
        Config.Direction = dName
        if State.StartOrigin then
            buildPatternWaypoints(State.StartOrigin)
            if Config.Active then State.Phase = "Advancing" end
        end
        for k, btn in pairs(dirButtons) do
            btn.BackgroundColor3 = (k == dName) and Color3.fromRGB(0, 145, 215) or Color3.fromRGB(30, 35, 48)
        end
    end)
end

local PatTitle = Instance.new("TextLabel")
PatTitle.Size = UDim2.new(1, -20, 0, 18)
PatTitle.Position = UDim2.new(0, 10, 0, 188)
PatTitle.BackgroundTransparency = 1
PatTitle.Text = "🌪️ FORMA EN EL AIRE (WAYPOINTS PRECALCULADOS):"
PatTitle.TextColor3 = Color3.fromRGB(180, 200, 220)
PatTitle.TextSize = 10
PatTitle.Font = Enum.Font.GothamBold
PatTitle.TextXAlignment = Enum.TextXAlignment.Left
PatTitle.Parent = MainPage

local patButtons = {}
local patterns = {"Círculo", "Cuadrado", "Zigzag", "Rombo", "I Invertida", "Solo Adelante"}
for i, pName in ipairs(patterns) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.333, -9, 0, 28)
    b.Position = UDim2.new(col * 0.333, 10 - (col * 2), 0, 208 + (row * 32))
    b.BackgroundColor3 = (Config.Pattern == pName) and Color3.fromRGB(125, 65, 185) or Color3.fromRGB(30, 35, 48)
    b.Text = pName
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 9
    b.Font = Enum.Font.GothamBold
    b.Parent = MainPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    patButtons[pName] = b

    b.MouseButton1Click:Connect(function()
        Config.Pattern = pName
        if State.StartOrigin then
            buildPatternWaypoints(State.StartOrigin)
        end
        for k, btn in pairs(patButtons) do
            btn.BackgroundColor3 = (k == pName) and Color3.fromRGB(125, 65, 185) or Color3.fromRGB(30, 35, 48)
        end
    end)
end

local WeaponToggleBtn = Instance.new("TextButton")
WeaponToggleBtn.Size = UDim2.new(1, -20, 0, 32)
WeaponToggleBtn.Position = UDim2.new(0, 10, 0, 280)
WeaponToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
WeaponToggleBtn.Text = "🔫 AUTO 'ANULACIÓN DEL SISTEMA' (5) + ARMA 2: ON"
WeaponToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
WeaponToggleBtn.TextSize = 9
WeaponToggleBtn.Font = Enum.Font.GothamBold
WeaponToggleBtn.Parent = MainPage
Instance.new("UICorner", WeaponToggleBtn).CornerRadius = UDim.new(0, 6)

WeaponToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoWeaponCycle = not Config.AutoWeaponCycle
    WeaponToggleBtn.BackgroundColor3 = Config.AutoWeaponCycle and Color3.fromRGB(30, 145, 80) or Color3.fromRGB(65, 70, 85)
    WeaponToggleBtn.Text = Config.AutoWeaponCycle and "🔫 AUTO 'ANULACIÓN DEL SISTEMA' (5) + ARMA 2: ON" or "🔫 AUTO PODER 5 + ARMA 2: OFF"
end)

local Power5ModeBtn = Instance.new("TextButton")
Power5ModeBtn.Size = UDim2.new(1, -20, 0, 32)
Power5ModeBtn.Position = UDim2.new(0, 10, 0, 318)
Power5ModeBtn.BackgroundColor3 = Color3.fromRGB(0, 125, 185)
Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: NOCHE DETENIDA (%ds + RECARGA %ds)", Config.TimeStopDelay, Config.Power5Interval)
Power5ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
Power5ModeBtn.TextSize = 9
Power5ModeBtn.Font = Enum.Font.GothamBold
Power5ModeBtn.Parent = MainPage
Instance.new("UICorner", Power5ModeBtn).CornerRadius = UDim.new(0, 6)

Power5ModeBtn.MouseButton1Click:Connect(function()
    if Config.Power5Mode == "EternalNightStop" then
        Config.Power5Mode = "TimerFixed"
        Power5ModeBtn.BackgroundColor3 = Color3.fromRGB(175, 105, 25)
        Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: TEMPORIZADOR FIJO (CADA %ds)", Config.Power5Interval)
    else
        Config.Power5Mode = "EternalNightStop"
        Power5ModeBtn.BackgroundColor3 = Color3.fromRGB(0, 125, 185)
        Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: NOCHE DETENIDA (%ds + RECARGA %ds)", Config.TimeStopDelay, Config.Power5Interval)
    end
end)

-- ==============================================================================
-- 9. PESTAÑA 2: RADAR FORENSE (MISSILE / SPIT / BLIGHTSPIT / BOULDER / ACIDPOOL)
-- ==============================================================================

local RadarToggleBtn = Instance.new("TextButton")
RadarToggleBtn.Size = UDim2.new(1, -24, 0, 38)
RadarToggleBtn.Position = UDim2.new(0, 10, 0, 6)
RadarToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 155, 95)
RadarToggleBtn.Text = "🛡️ ESCUDO MISSILE (CYBORG), SPIT Y BOULDER (0% LAG): ON"
RadarToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RadarToggleBtn.TextSize = 9
RadarToggleBtn.Font = Enum.Font.GothamBold
RadarToggleBtn.Parent = RadarPage
Instance.new("UICorner", RadarToggleBtn).CornerRadius = UDim.new(0, 8)

RadarToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoDodgeObjects = not Config.AutoDodgeObjects
    RadarToggleBtn.BackgroundColor3 = Config.AutoDodgeObjects and Color3.fromRGB(30, 155, 95) or Color3.fromRGB(65, 70, 85)
    RadarToggleBtn.Text = Config.AutoDodgeObjects and "🛡️ ESCUDO MISSILE (CYBORG), SPIT Y BOULDER (0% LAG): ON" or "🛡️ ESCUDO PROYECTILES: OFF"
    if not Config.AutoDodgeObjects then
        State.DodgeOffset = Vector3.zero
        State.IsBurstDodging = false
    end
end)

createStepper(RadarPage, 52, "⬆️ ALTURA EXTRA AL DETECTAR CYBORG / EXPERIMENT",
    function() return string.format("Actual: +%d studs extra en el aire", Config.BossExtraHeight) end,
    function() Config.BossExtraHeight = math.max(0, Config.BossExtraHeight - 2) end,
    function() Config.BossExtraHeight = math.min(25, Config.BossExtraHeight + 2) end,
    false
)

createStepper(RadarPage, 106, "⚡ VELOCIDAD RÁFAGA EVASIVA (ANTI-RUBBERBAND)",
    function() return string.format("Actual: %d studs/s al detectar proyectil (58 = seguro)", Config.DodgeBurstSpeed) end,
    function() Config.DodgeBurstSpeed = math.max(35, Config.DodgeBurstSpeed - 4) end,
    function() Config.DodgeBurstSpeed = math.min(100, Config.DodgeBurstSpeed + 4) end,
    false
)

createStepper(RadarPage, 160, "📡 RADIO VIGILANCIA ALREDEDOR (STUDS)",
    function() return string.format("Actual: %d studs alrededor de tu personaje", Config.RadarHorizRadius) end,
    function() Config.RadarHorizRadius = math.max(10, Config.RadarHorizRadius - 2) end,
    function() Config.RadarHorizRadius = math.min(60, Config.RadarHorizRadius + 2) end,
    false
)

createStepper(RadarPage, 214, "⬇️ VIGILANCIA CONSTANTE HACIA ABAJO (STUDS)",
    function() return string.format("Actual: %d studs debajo de ti", Config.RadarDownDepth) end,
    function() Config.RadarDownDepth = math.max(15, Config.RadarDownDepth - 5) end,
    function() Config.RadarDownDepth = math.min(120, Config.RadarDownDepth + 5) end,
    false
)

createStepper(RadarPage, 268, "🚨 DISTANCIA DE ESQUIVA INMEDIATA (STUDS)",
    function() return string.format("Actual: Esquiva cuando el misil/ácido esté a <%d studs", Config.DodgeTriggerDist) end,
    function() Config.DodgeTriggerDist = math.max(10, Config.DodgeTriggerDist - 2) end,
    function() Config.DodgeTriggerDist = math.min(50, Config.DodgeTriggerDist + 2) end,
    false
)

createStepper(RadarPage, 322, "↗️ DESPLAZAMIENTO AL ESQUIVAR (LADO / ARRIBA)",
    function() return string.format("Actual: %d studs lateral / +%d studs arriba", Config.DodgeSideStuds, Config.DodgeUpStuds) end,
    function()
        Config.DodgeSideStuds = math.max(8, Config.DodgeSideStuds - 2)
        Config.DodgeUpStuds = math.max(2, Config.DodgeUpStuds - 1)
    end,
    function()
        Config.DodgeSideStuds = math.min(40, Config.DodgeSideStuds + 2)
        Config.DodgeUpStuds = math.min(20, Config.DodgeUpStuds + 1)
    end,
    false
)

createStepper(RadarPage, 376, "⏱️ DURACIÓN DE ESQUIVA (SEGUNDOS)",
    function() return string.format("Actual: Mantiene esquiva por %.1f segundos", Config.DodgeHoldSeconds) end,
    function() Config.DodgeHoldSeconds = math.max(0.6, Config.DodgeHoldSeconds - 0.2) end,
    function() Config.DodgeHoldSeconds = math.min(5.0, Config.DodgeHoldSeconds + 0.2) end,
    false
)

-- ==============================================================================
-- 10. PESTAÑA 3: CONFIGURACIÓN DE VUELO
-- ==============================================================================

local AntiRubberModes = {
    { Id = "WaitRubber",    Label = "🛡️ MODO: ESPERAR JALÓN Y REINICIAR DESDE TECHO",    Color = Color3.fromRGB(0, 130, 185) },
    { Id = "ReturnAndStep", Label = "🛡️ MODO: RETORNAR Y PISAR TECHO ANTES DEL JALÓN",    Color = Color3.fromRGB(30, 150, 95) }
}
local curRubberIdx = 1

local AntiRubberBtn = Instance.new("TextButton")
AntiRubberBtn.Size = UDim2.new(1, -24, 0, 38)
AntiRubberBtn.Position = UDim2.new(0, 10, 0, 6)
AntiRubberBtn.BackgroundColor3 = AntiRubberModes[1].Color
AntiRubberBtn.Text = AntiRubberModes[1].Label
AntiRubberBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AntiRubberBtn.TextSize = 10
AntiRubberBtn.Font = Enum.Font.GothamBold
AntiRubberBtn.Parent = ConfigPage
Instance.new("UICorner", AntiRubberBtn).CornerRadius = UDim.new(0, 8)

AntiRubberBtn.MouseButton1Click:Connect(function()
    curRubberIdx = (curRubberIdx % #AntiRubberModes) + 1
    local m = AntiRubberModes[curRubberIdx]
    Config.AntiRubberMode = m.Id
    AntiRubberBtn.Text = m.Label
    AntiRubberBtn.BackgroundColor3 = m.Color
    State.AirStartTime = tick()
    State.Phase = "Advancing"
end)

local AptBoxBtn = Instance.new("TextButton")
AptBoxBtn.Size = UDim2.new(1, -24, 0, 34)
AptBoxBtn.Position = UDim2.new(0, 10, 0, 50)
AptBoxBtn.BackgroundColor3 = Color3.fromRGB(0, 145, 165)
AptBoxBtn.Text = "🏢 VER CUADRADO DE EDIFICIO (APARTMENTBROKEN): ON"
AptBoxBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AptBoxBtn.TextSize = 9
AptBoxBtn.Font = Enum.Font.GothamBold
AptBoxBtn.Parent = ConfigPage
Instance.new("UICorner", AptBoxBtn).CornerRadius = UDim.new(0, 8)

AptBoxBtn.MouseButton1Click:Connect(function()
    Config.ShowApartmentBoxDefault = not Config.ShowApartmentBoxDefault
    setApartmentBoxesVisible(Config.ShowApartmentBoxDefault)
    AptBoxBtn.BackgroundColor3 = Config.ShowApartmentBoxDefault and Color3.fromRGB(0, 145, 165) or Color3.fromRGB(65, 70, 85)
    AptBoxBtn.Text = Config.ShowApartmentBoxDefault and "🏢 VER CUADRADO DE EDIFICIO (APARTMENTBROKEN): ON" or "🏢 VER CUADRADO DE EDIFICIO (APARTMENTBROKEN): OFF"
end)

createStepper(ConfigPage, 92, "🛫 ALTURA MÍNIMA DE SEGURIDAD (ANTI-SPIT Y=90)",
    function() return string.format("Actual: Y >= %d studs (Techo máx de Spit es 92.6)", Config.MinCruiseY) end,
    function() Config.MinCruiseY = math.max(60, Config.MinCruiseY - 5) end,
    function() Config.MinCruiseY = math.min(180, Config.MinCruiseY + 5) end,
    true
)

createStepper(ConfigPage, 146, "⏱️ ESPERA TRAS DETENERSE RELOJ NOCHE (PODER 5)",
    function() return string.format("Actual: %d segundos tras detenerse Survived", Config.TimeStopDelay) end,
    function()
        Config.TimeStopDelay = math.max(5, Config.TimeStopDelay - 5)
        if Config.Power5Mode == "EternalNightStop" then
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: NOCHE DETENIDA (%ds + RECARGA %ds)", Config.TimeStopDelay, Config.Power5Interval)
        end
    end,
    function()
        Config.TimeStopDelay = math.min(90, Config.TimeStopDelay + 5)
        if Config.Power5Mode == "EternalNightStop" then
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: NOCHE DETENIDA (%ds + RECARGA %ds)", Config.TimeStopDelay, Config.Power5Interval)
        end
    end,
    false
)

createStepper(ConfigPage, 200, "⏳ ESPERA TRAS JALÓN RUBBERBAND (MODO ESPERAR)",
    function() return string.format("Actual: %.1f segundos antes de volver a salir", Config.PostRubberWaitTime) end,
    function() Config.PostRubberWaitTime = math.max(0.1, Config.PostRubberWaitTime - 0.1) end,
    function() Config.PostRubberWaitTime = math.min(4.0, Config.PostRubberWaitTime + 0.1) end,
    false
)

createStepper(ConfigPage, 254, "⏱️ TIEMPO MÁX. EN EL AIRE (MODO RETORNAR TECHO)",
    function() return string.format("Actual: %.1f segundos en aire (límite ~6.2s)", Config.MaxAirTimeBeforeReturn) end,
    function() Config.MaxAirTimeBeforeReturn = math.max(1.5, Config.MaxAirTimeBeforeReturn - 0.2) end,
    function() Config.MaxAirTimeBeforeReturn = math.min(6.2, Config.MaxAirTimeBeforeReturn + 0.2) end,
    false
)

createStepper(ConfigPage, 308, "👣 TIEMPO PISANDO EL TECHO SÓLIDO (MODO RETORNAR)",
    function() return string.format("Actual: %.1f segundos confirmando pisada", Config.TouchRoofHoldTime) end,
    function() Config.TouchRoofHoldTime = math.max(0.2, Config.TouchRoofHoldTime - 0.1) end,
    function() Config.TouchRoofHoldTime = math.min(5.0, Config.TouchRoofHoldTime + 0.1) end,
    false
)

createStepper(ConfigPage, 362, "🦘 INTERVALO ENTRE IMPULSOS DE SALTO (ARCO)",
    function() return string.format("Actual: Cada %.2f segundos (Fuerza Y: %.0f)", Config.JumpPulseInterval, Config.JumpImpulseY) end,
    function() Config.JumpPulseInterval = math.max(0.40, Config.JumpPulseInterval - 0.05) end,
    function() Config.JumpPulseInterval = math.min(1.60, Config.JumpPulseInterval + 0.05) end,
    false
)

createStepper(ConfigPage, 416, "⚡ RECARGA / TEMPORIZADOR PODER 5 (SEGUNDOS)",
    function() return string.format("Actual: Cada %d segundos", Config.Power5Interval) end,
    function()
        Config.Power5Interval = math.max(10, Config.Power5Interval - 10)
        if Config.Power5Mode == "TimerFixed" then
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: TEMPORIZADOR FIJO (CADA %ds)", Config.Power5Interval)
        else
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: NOCHE DETENIDA (%ds + RECARGA %ds)", Config.TimeStopDelay, Config.Power5Interval)
        end
    end,
    function()
        Config.Power5Interval = math.min(300, Config.Power5Interval + 10)
        if Config.Power5Mode == "TimerFixed" then
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: TEMPORIZADOR FIJO (CADA %ds)", Config.Power5Interval)
        else
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: NOCHE DETENIDA (%ds + RECARGA %ds)", Config.TimeStopDelay, Config.Power5Interval)
        end
    end,
    false
)

createStepper(ConfigPage, 470, "⏳ PAUSA ACTIVACIÓN 'ANULACIÓN DEL SISTEMA' (SEG)",
    function() return string.format("Actual: %.2f segundos antes de equipar Arma 2", Config.Power5CastWait) end,
    function() Config.Power5CastWait = math.max(0.05, Config.Power5CastWait - 0.05) end,
    function() Config.Power5CastWait = math.min(1.50, Config.Power5CastWait + 0.05) end,
    false
)

createStepper(ConfigPage, 524, "➡️ DISTANCIA AVANCE INICIAL (STUDS)",
    function() return string.format("Actual: %d studs hacia delante", Config.ForwardStuds) end,
    function() Config.ForwardStuds = math.max(5, Config.ForwardStuds - 5) end,
    function() Config.ForwardStuds = math.min(120, Config.ForwardStuds + 5) end,
    true
)

createStepper(ConfigPage, 578, "🔄 AMPLITUD DE FORMA (CÍRCULO / I INVERTIDA / ETC.)",
    function() return string.format("Actual: %d studs de radio / amplitud", Config.PatternRadius) end,
    function() Config.PatternRadius = math.max(8, Config.PatternRadius - 2) end,
    function() Config.PatternRadius = math.min(60, Config.PatternRadius + 2) end,
    true
)

createStepper(ConfigPage, 632, "✈️ VELOCIDAD HORIZONTAL CRUCERO (STUDS/S)",
    function() return string.format("Actual: %.1f studs/s (30.0 = límite sin jalón previo)", Config.FlySpeed) end,
    function() Config.FlySpeed = math.max(15.0, Config.FlySpeed - 1.5) end,
    function() Config.FlySpeed = math.min(60.0, Config.FlySpeed + 1.5) end,
    false
)

createStepper(ConfigPage, 686, "📏 UMBRAL DETECCIÓN TIRÓN RUBBERBAND (STUDS)",
    function() return string.format("Actual: >%d studs de retroceso repentino", Config.RubberbandDetectDist) end,
    function() Config.RubberbandDetectDist = math.max(4, Config.RubberbandDetectDist - 2) end,
    function() Config.RubberbandDetectDist = math.min(40, Config.RubberbandDetectDist + 2) end,
    false
)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
