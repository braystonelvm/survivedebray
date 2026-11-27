-- ==============================================================================
-- PILOTO AÉREO PARABÓLICO V7.1 (CONFIGURACIÓN CAPTURA + REACTIVACIÓN 120s NOCHE)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local lp = Players.LocalPlayer

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local Config = {
    Active = false,
    Direction = "ESTE",         -- "NORTE", "SUR", "ESTE", "OESTE"
    Pattern = "Círculo",        -- "Círculo", "Cuadrado", "Zigzag", "Rombo", "I Invertida", "Solo Adelante"

    -- Distancias y Velocidades
    ForwardStuds = 34,
    PatternRadius = 26,
    VerticalDipStuds = 2.0,
    FlySpeed = 30.0,
    ReturnSpeed = 30.0,

    -- Física Parabólica (Valores de tu captura)
    JumpImpulseY = 53.0,
    JumpPulseInterval = 1.05,   -- Actual: Cada 1.05 segundos (Fuerza Y: 53)

    -- Modos Anti-Rubberband (Valores exactos de tu captura)
    AntiRubberMode = "WaitRubber", -- MODO: ESPERAR JALÓN Y REINICIAR DESDE TECHO
    MaxAirTimeBeforeReturn = 4.8,  -- Actual: 4.8 segundos en aire
    TouchRoofHoldTime = 1.2,       -- Actual: 1.2 segundos confirmando pisada
    RubberbandDetectDist = 12,
    PostRubberWaitTime = 0.5,      -- Actual: 0.5 segundos antes de volver a salir

    -- Radar Anti-Misiles / Ácido con Ráfaga Rápida
    AutoDodgeObjects = true,
    RadarHorizRadius = 22,
    RadarDownDepth = 50,
    DodgeTriggerDist = 22,
    DodgeBurstSpeed = 68,
    DodgeSideStuds = 15,
    DodgeUpStuds = 8,
    DodgeHoldSeconds = 1.6,

    -- Poder 5 ("Anulación del Sistema") vinculado al Reloj de Noche Larga
    AutoWeaponCycle = true,
    Power5Mode = "EternalNightStop", -- "EternalNightStop" o "TimerFixed"
    TimeCheckInterval = 1.5,
    TimeStopDelay = 15,              -- Actual: 15 segundos tras detenerse Survived
    Power5Interval = 120,            -- Actual: Cada 120 segundos (recarga del 5to poder)
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
    StatusText = "En espera (Detenido)",

    -- Radar
    DodgeOffset = Vector3.zero,
    DodgeUntil = 0,
    IsBurstDodging = false,
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
-- 1. RADAR ESPACIAL 0% LAG (RÁFAGA RÁPIDA CONTRA MISILES Y ÁCIDO)
-- ==============================================================================

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function isTeammateOrSelf(part)
    local char = lp.Character
    if char and part:IsDescendantOf(char) then return true end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and part:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

local function isHostileProjectileOrHazard(part)
    if not part or not part:IsA("BasePart") then return false end
    if part == State.RoofPart then return false end
    if isTeammateOrSelf(part) then return false end

    local maxDim = math.max(part.Size.X, part.Size.Y, part.Size.Z)
    if maxDim > 28 and part.Anchored and part.AssemblyLinearVelocity.Magnitude < 0.5 then
        return false
    end

    if not part.Anchored or part.AssemblyLinearVelocity.Magnitude > 1.5 then
        return true
    end

    local lowName = part.Name:lower()
    local parentName = part.Parent and part.Parent.Name:lower() or ""
    if lowName:find("acid") or lowName:find("missile") or lowName:find("rocket")
        or lowName:find("proj") or lowName:find("spit") or lowName:find("goo")
        or lowName:find("liquid") or lowName:find("hazard") or lowName:find("bomb")
        or parentName:find("projectiles") or parentName:find("effects") or parentName:find("debris") then
        return true
    end

    return false
end

task.spawn(function()
    while true do
        task.wait(0.07)
        if not Config.Active or not Config.AutoDodgeObjects then
            State.DodgeOffset = Vector3.zero
            State.IsBurstDodging = false
            State.DetectedBelowCount = 0
            continue
        end

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        local ignoreList = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then table.insert(ignoreList, plr.Character) end
        end
        if State.RoofPart then table.insert(ignoreList, State.RoofPart) end
        overlapParams.FilterDescendantsInstances = ignoreList

        local myPos = root.Position
        local maxHoriz = math.max(Config.RadarHorizRadius, Config.DodgeTriggerDist)
        local downDepth = Config.RadarDownDepth

        local boxSize = Vector3.new(maxHoriz * 2, downDepth + 14, maxHoriz * 2)
        local boxCenter = myPos - Vector3.new(0, (downDepth - 14) * 0.5, 0)
        local partsInBox = workspace:GetPartBoundsInBox(CFrame.new(boxCenter), boxSize, overlapParams)

        local closestThreatPos = nil
        local closestThreatVel = Vector3.zero
        local closestDist = math.huge
        local closestName = "Objeto"
        local belowAlerts = 0

        for _, part in ipairs(partsInBox) do
            if isHostileProjectileOrHazard(part) then
                local pPos = part.Position
                local dist = (pPos - myPos).Magnitude

                if pPos.Y < myPos.Y and (myPos.Y - pPos.Y) <= downDepth then
                    belowAlerts = belowAlerts + 1
                end

                if dist <= Config.DodgeTriggerDist and dist < closestDist then
                    closestDist = dist
                    closestThreatPos = pPos
                    closestThreatVel = part.AssemblyLinearVelocity
                    closestName = part.Name
                end
            end
        end

        State.DetectedBelowCount = belowAlerts

        if closestThreatPos then
            local awayVec = Vector3.new(myPos.X - closestThreatPos.X, 0, myPos.Z - closestThreatPos.Z)
            local sideDir
            if closestThreatVel.Magnitude > 2.0 then
                local velHoriz = Vector3.new(closestThreatVel.X, 0, closestThreatVel.Z)
                if velHoriz.Magnitude > 0.2 then
                    local perp = Vector3.new(-velHoriz.Z, 0, velHoriz.X).Unit
                    sideDir = (perp:Dot(awayVec) >= 0) and perp or -perp
                end
            end

            if not sideDir then
                sideDir = (awayVec.Magnitude > 0.2) and awayVec.Unit or Vector3.new(1, 0, 0)
            end

            State.DodgeOffset = (sideDir * Config.DodgeSideStuds) + Vector3.new(0, Config.DodgeUpStuds, 0)
            State.DodgeUntil = tick() + Config.DodgeHoldSeconds
            State.IsBurstDodging = true
            State.LastThreatName = string.format("%s (%.0fm)", closestName, closestDist)
        elseif tick() >= State.DodgeUntil then
            State.DodgeOffset = Vector3.zero
            State.IsBurstDodging = false
        end
    end
end)

-- ==============================================================================
-- 2. DETECCIÓN FÍSICA REAL DE SUELO SÓLIDO
-- ==============================================================================

local function detectFloorBelow(root)
    local char = lp.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {char}
    local charsFolder = workspace:FindFirstChild("Characters")
    if charsFolder then table.insert(ignore, charsFolder) end
    params.FilterDescendantsInstances = ignore

    local hit = workspace:Raycast(root.Position, Vector3.new(0, -18, 0), params)
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

    local char = lp.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {char}
    local charsFolder = workspace:FindFirstChild("Characters")
    if charsFolder then table.insert(ignore, charsFolder) end
    params.FilterDescendantsInstances = ignore

    local footHit = workspace:Raycast(root.Position, Vector3.new(0, -3.8, 0), params)
    if footHit and footHit.Instance and footHit.Instance:IsA("BasePart") and footHit.Instance.CanCollide then
        return true
    end

    return false
end

-- ==============================================================================
-- 3. GENERADOR DE COORDENADAS PRECALCULADAS (0% LAG)
-- ==============================================================================

local function buildPatternWaypoints(originPos)
    local fwd = DIRECTION_VECTORS[Config.Direction] or Vector3.new(1, 0, 0)
    local right = Vector3.new(-fwd.Z, 0, fwd.X)
    local center = originPos + (fwd * Config.ForwardStuds)
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
-- 4. LECTOR DEL RELOJ DE NOCHE LARGA + REACTIVACIÓN CADA 120s SI SIGUE DETENIDO
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

local function triggerSystemOverrideAndReturnSlot2()
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

    if Config.EquipSlot2Default then
        equipSlot2Only()
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
    local lastFixedTimerTick = 0

    while true do
        task.wait(Config.TimeCheckInterval)
        local curSec, labelStr = getSurvivalTimeSecondsAndLabel()
        State.DetectedHudTime = labelStr

        if not Config.Active or not Config.AutoWeaponCycle then
            lastSeconds = nil
            continue
        end

        if Config.Power5Mode == "EternalNightStop" then
            if not curSec then
                State.Power5StatusText = "Buscando reloj Survived..."
                continue
            end

            if lastSeconds then
                -- Detecta si el reloj de supervivencia (que va hacia adelante) se detuvo
                if math.abs(curSec - lastSeconds) < 0.01 then
                    -- 1. Esperar los 15s iniciales tras detenerse el reloj
                    local waitEnd = tick() + Config.TimeStopDelay
                    while tick() < waitEnd do
                        task.wait(0.25)
                        if not Config.Active or not Config.AutoWeaponCycle or Config.Power5Mode ~= "EternalNightStop" then
                            break
                        end
                        local checkNow = getSurvivalTimeSecondsAndLabel()
                        if checkNow and math.abs(checkNow - curSec) >= 0.01 then
                            break -- El reloj volvió a moverse
                        end
                        local rem = math.max(0, math.ceil(waitEnd - tick()))
                        State.Power5StatusText = string.format("Noche (%s): Activando en %ds", labelStr, rem)
                    end

                    -- 2. Bucle continuo: Mientras el reloj SIGA detenido, activar Poder 5 y esperar recarga (120s)
                    while Config.Active and Config.AutoWeaponCycle and Config.Power5Mode == "EternalNightStop" do
                        local checkSec = getSurvivalTimeSecondsAndLabel()
                        if not checkSec or math.abs(checkSec - curSec) >= 0.01 then
                            break -- Salió de la noche larga
                        end

                        State.Power5StatusText = "⚡ ¡Activando Anulación -> Arma 2!"
                        triggerSystemOverrideAndReturnSlot2()

                        -- Esperar los 120s de recarga del 5to poder verificando que el reloj siga quieto
                        local rechargeEnd = tick() + Config.Power5Interval
                        while tick() < rechargeEnd do
                            task.wait(0.5)
                            if not Config.Active or not Config.AutoWeaponCycle or Config.Power5Mode ~= "EternalNightStop" then
                                break
                            end
                            local stillFrozenSec = getSurvivalTimeSecondsAndLabel()
                            if not stillFrozenSec or math.abs(stillFrozenSec - curSec) >= 0.01 then
                                break -- El reloj volvió a avanzar durante la recarga
                            end
                            local remCd = math.max(0, math.ceil(rechargeEnd - tick()))
                            State.Power5StatusText = string.format("Noche (%s): Recarga 5to poder (%ds)", labelStr, remCd)
                        end
                    end
                elseif curSec > lastSeconds then
                    State.Power5StatusText = string.format("Reloj corriendo (%s)", labelStr)
                end
            end
            lastSeconds = curSec
        else
            local elapsed = tick() - lastFixedTimerTick
            if lastFixedTimerTick == 0 or elapsed >= Config.Power5Interval then
                lastFixedTimerTick = tick()
                State.Power5StatusText = "⚡ ¡Activando Anulación -> Arma 2!"
                triggerSystemOverrideAndReturnSlot2()
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
-- 5. FÍSICA PARABÓLICA (ARCO MANUAL AMPLIO + RÁFAGA EVASIVA DE MISILES)
-- ==============================================================================

local function resetPhysicsCompletely()
    State.Phase = "Idle"
    State.LastRealPos = nil
    State.GroundedConfirmedSince = nil
    State.DodgeOffset = Vector3.zero
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

    if hum then
        hum.PlatformStand = false
        hum.AutoRotate = true
    end
end

RunService.Heartbeat:Connect(function()
    if not Config.Active then return end

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    if not State.StartOrigin then
        State.StartOrigin = root.Position
        State.LastRealPos = root.Position
        detectFloorBelow(root)
        State.Phase = "Advancing"
        State.AirStartTime = tick()
        State.LastJumpPulse = 0
        buildPatternWaypoints(State.StartOrigin)
    end

    if hum.PlatformStand then
        hum.PlatformStand = false
    end

    local now = tick()
    local fwdDir = DIRECTION_VECTORS[Config.Direction] or Vector3.new(1, 0, 0)
    local advanceDest = State.StartOrigin + (fwdDir * Config.ForwardStuds)
    local mode = Config.AntiRubberMode

    -- MODO 1: PISANDO TECHO SÓLIDO
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
                State.StartOrigin = root.Position
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

    -- MODO 2: ESPERA TRAS DETECTAR RUBBERBAND
    if State.Phase == "RubberCooldown" then
        local rem = math.max(0, State.RubberWaitUntil - now)
        State.StatusText = string.format("⏳ Rubberband detectado: Reiniciando en %.2fs...", rem)
        if now >= State.RubberWaitUntil then
            State.StartOrigin = root.Position
            State.LastRealPos = root.Position
            State.Phase = "Advancing"
            State.AirStartTime = now
            State.LastJumpPulse = 0
            buildPatternWaypoints(State.StartOrigin)
        end
        return
    end

    -- Disparadores según modo elegido
    if State.Phase == "Advancing" or State.Phase == "Pattern" then
        if mode == "ReturnAndStep" then
            if (now - State.AirStartTime) >= Config.MaxAirTimeBeforeReturn then
                State.Phase = "ReturningToRoof"
            end

        elseif mode == "WaitRubber" then
            if State.LastRealPos then
                local jumpBackDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(State.LastRealPos.X, 0, State.LastRealPos.Z)).Magnitude
                if jumpBackDist >= Config.RubberbandDetectDist then
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
        State.StatusText = string.format("🦘 Avanzando al %s (%d studs)...", Config.Direction, Config.ForwardStuds)
        targetWp = advanceDest

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

        targetWp = (wps[State.CurrentWpIndex] or advanceDest) + State.DodgeOffset

        if State.IsBurstDodging then
            State.StatusText = string.format("🚨 ¡RÁFAGA EVASIVA: %s! | %s", State.LastThreatName, Config.Pattern)
        elseif mode == "ReturnAndStep" then
            local left = math.max(0, Config.MaxAirTimeBeforeReturn - (now - State.AirStartTime))
            State.StatusText = string.format("🌪️ %s (%d/%d) | Pisar techo en %.1fs", Config.Pattern, State.CurrentWpIndex, #wps, left)
        else
            State.StatusText = string.format("🌪️ %s (%d/%d) | Modo Esperar Jalón", Config.Pattern, State.CurrentWpIndex, #wps)
        end

        local horizDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetWp.X, 0, targetWp.Z)).Magnitude
        if horizDist <= 3.8 then
            State.CurrentWpIndex = (State.CurrentWpIndex % #wps) + 1
            targetWp = (wps[State.CurrentWpIndex] or advanceDest) + State.DodgeOffset
        end
    end

    local toTargetHoriz = Vector3.new(targetWp.X - root.Position.X, 0, targetWp.Z - root.Position.Z)
    local horizVel = Vector3.zero
    if toTargetHoriz.Magnitude > 0.15 then
        horizVel = toTargetHoriz.Unit * moveSpeed
    end

    local curVelY = root.AssemblyLinearVelocity.Y
    local desiredY = targetWp.Y

    if State.Phase == "ReturningToRoof" then
        if root.Position.Y < (State.StartOrigin.Y + 1.5) then
            curVelY = Config.JumpImpulseY
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    else
        if (now - State.LastJumpPulse) >= Config.JumpPulseInterval or root.Position.Y < (desiredY - 2.0) then
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
-- 6. INTERFAZ GRÁFICA NATIVA ROBLOX (3 PESTAÑAS + CONFIGURACIÓN POR DEFECTO)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("RoofAerialPilotGuiV71")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RoofAerialPilotGuiV71"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(20, 125, 175)
FloatBtn.Text = "✈️\nV7.1"
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
TitleBar.Text = "  ✈️ PILOTO PARABÓLICO V7.1 | RÁFAGA MISILES & RECARGA 120s"
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
RadarPage.CanvasSize = UDim2.new(0, 0, 0, 390)
RadarPage.ScrollBarThickness = 5
RadarPage.Visible = false
RadarPage.Parent = MainFrame

local ConfigPage = Instance.new("ScrollingFrame")
ConfigPage.Size = UDim2.new(1, 0, 1, -74)
ConfigPage.Position = UDim2.new(0, 0, 0, 74)
ConfigPage.BackgroundTransparency = 1
ConfigPage.BorderSizePixel = 0
ConfigPage.CanvasSize = UDim2.new(0, 0, 0, 740)
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
-- 7. PESTAÑA 1: CONTROL DE VUELO
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
    while true do
        task.wait(0.25)
        StatusLabel.Text = string.format(
            "Estado: %s\nSurvived: [%s] | Radar: %s (Abajo: %d)\nPoder 5: %s | Arma 2: %s",
            State.StatusText,
            State.DetectedHudTime,
            Config.AutoDodgeObjects and "ON" or "OFF",
            State.DetectedBelowCount,
            State.Power5StatusText,
            Config.AutoWeaponCycle and "ON" or "OFF"
        )
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
StopBtn.Text = "⏹️ DETENER"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.TextSize = 10
StopBtn.Font = Enum.Font.GothamBold
StopBtn.Parent = MainPage
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 8)

StartBtn.MouseButton1Click:Connect(function()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then
        State.StartOrigin = root.Position
        State.LastRealPos = root.Position
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
    State.StatusText = "Detenido (Físicas reiniciadas)"
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
-- 8. PESTAÑA 2: RADAR OBJETOS / MISILES / ÁCIDO
-- ==============================================================================

local RadarToggleBtn = Instance.new("TextButton")
RadarToggleBtn.Size = UDim2.new(1, -24, 0, 38)
RadarToggleBtn.Position = UDim2.new(0, 10, 0, 6)
RadarToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 155, 95)
RadarToggleBtn.Text = "🛡️ EVADIR MISILES Y ÁCIDO CON RÁFAGA (IGNORA COMPAÑEROS): ON"
RadarToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RadarToggleBtn.TextSize = 9
RadarToggleBtn.Font = Enum.Font.GothamBold
RadarToggleBtn.Parent = RadarPage
Instance.new("UICorner", RadarToggleBtn).CornerRadius = UDim.new(0, 8)

RadarToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoDodgeObjects = not Config.AutoDodgeObjects
    RadarToggleBtn.BackgroundColor3 = Config.AutoDodgeObjects and Color3.fromRGB(30, 155, 95) or Color3.fromRGB(65, 70, 85)
    RadarToggleBtn.Text = Config.AutoDodgeObjects and "🛡️ EVADIR MISILES Y ÁCIDO CON RÁFAGA (IGNORA COMPAÑEROS): ON" or "🛡️ EVADIR MISILES Y ÁCIDO: OFF"
    if not Config.AutoDodgeObjects then
        State.DodgeOffset = Vector3.zero
        State.IsBurstDodging = false
    end
end)

createStepper(RadarPage, 52, "⚡ VELOCIDAD RÁFAGA EVASIVA (MISILES)",
    function() return string.format("Actual: %d studs/s al detectar proyectil", Config.DodgeBurstSpeed) end,
    function() Config.DodgeBurstSpeed = math.max(35, Config.DodgeBurstSpeed - 5) end,
    function() Config.DodgeBurstSpeed = math.min(120, Config.DodgeBurstSpeed + 5) end,
    false
)

createStepper(RadarPage, 106, "📡 RADIO VIGILANCIA ALREDEDOR (STUDS)",
    function() return string.format("Actual: %d studs alrededor de tu personaje", Config.RadarHorizRadius) end,
    function() Config.RadarHorizRadius = math.max(8, Config.RadarHorizRadius - 2) end,
    function() Config.RadarHorizRadius = math.min(60, Config.RadarHorizRadius + 2) end,
    false
)

createStepper(RadarPage, 160, "⬇️ VIGILANCIA CONSTANTE HACIA ABAJO (STUDS)",
    function() return string.format("Actual: %d studs debajo de ti", Config.RadarDownDepth) end,
    function() Config.RadarDownDepth = math.max(15, Config.RadarDownDepth - 5) end,
    function() Config.RadarDownDepth = math.min(120, Config.RadarDownDepth + 5) end,
    false
)

createStepper(RadarPage, 214, "🚨 DISTANCIA DE ESQUIVA INMEDIATA (STUDS)",
    function() return string.format("Actual: Esquiva cuando el objeto esté a <%d studs", Config.DodgeTriggerDist) end,
    function() Config.DodgeTriggerDist = math.max(8, Config.DodgeTriggerDist - 2) end,
    function() Config.DodgeTriggerDist = math.min(45, Config.DodgeTriggerDist + 2) end,
    false
)

createStepper(RadarPage, 268, "↗️ DESPLAZAMIENTO AL ESQUIVAR (LADO / ARRIBA)",
    function() return string.format("Actual: %d studs lateral / +%d studs arriba", Config.DodgeSideStuds, Config.DodgeUpStuds) end,
    function()
        Config.DodgeSideStuds = math.max(6, Config.DodgeSideStuds - 2)
        Config.DodgeUpStuds = math.max(2, Config.DodgeUpStuds - 1)
    end,
    function()
        Config.DodgeSideStuds = math.min(35, Config.DodgeSideStuds + 2)
        Config.DodgeUpStuds = math.min(18, Config.DodgeUpStuds + 1)
    end,
    false
)

createStepper(RadarPage, 322, "⏱️ DURACIÓN DE ESQUIVA (PARA ÁCIDO DE 1.5s)",
    function() return string.format("Actual: Mantiene esquiva por %.1f segundos", Config.DodgeHoldSeconds) end,
    function() Config.DodgeHoldSeconds = math.max(0.6, Config.DodgeHoldSeconds - 0.2) end,
    function() Config.DodgeHoldSeconds = math.min(5.0, Config.DodgeHoldSeconds + 0.2) end,
    false
)

-- ==============================================================================
-- 9. PESTAÑA 3: CONFIGURACIÓN DE VUELO (VALORES DE CAPTURA POR DEFECTO)
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

-- TIEMPO 1: 15 segundos tras detenerse Survived
createStepper(ConfigPage, 52, "⏱️ ESPERA TRAS DETENERSE RELOJ NOCHE (PODER 5)",
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

-- TIEMPO 2: 0.5 segundos tras jalón rubberband
createStepper(ConfigPage, 106, "⏳ ESPERA TRAS JALÓN RUBBERBAND (MODO ESPERAR)",
    function() return string.format("Actual: %.1f segundos antes de volver a salir", Config.PostRubberWaitTime) end,
    function() Config.PostRubberWaitTime = math.max(0.1, Config.PostRubberWaitTime - 0.1) end,
    function() Config.PostRubberWaitTime = math.min(4.0, Config.PostRubberWaitTime + 0.1) end,
    false
)

-- TIEMPO 3: 4.8 segundos máximo en aire
createStepper(ConfigPage, 160, "⏱️ TIEMPO MÁX. EN EL AIRE (MODO RETORNAR TECHO)",
    function() return string.format("Actual: %.1f segundos en aire (límite ~6.2s)", Config.MaxAirTimeBeforeReturn) end,
    function() Config.MaxAirTimeBeforeReturn = math.max(1.5, Config.MaxAirTimeBeforeReturn - 0.2) end,
    function() Config.MaxAirTimeBeforeReturn = math.min(6.2, Config.MaxAirTimeBeforeReturn + 0.2) end,
    false
)

-- TIEMPO 4: 1.2 segundos pisando techo sólido
createStepper(ConfigPage, 214, "👣 TIEMPO PISANDO EL TECHO SÓLIDO (MODO RETORNAR)",
    function() return string.format("Actual: %.1f segundos confirmando pisada", Config.TouchRoofHoldTime) end,
    function() Config.TouchRoofHoldTime = math.max(0.2, Config.TouchRoofHoldTime - 0.1) end,
    function() Config.TouchRoofHoldTime = math.min(5.0, Config.TouchRoofHoldTime + 0.1) end,
    false
)

-- TIEMPO 5: 1.05 segundos entre impulsos de salto
createStepper(ConfigPage, 268, "🦘 INTERVALO ENTRE IMPULSOS DE SALTO (ARCO)",
    function() return string.format("Actual: Cada %.2f segundos (Fuerza Y: %.0f)", Config.JumpPulseInterval, Config.JumpImpulseY) end,
    function() Config.JumpPulseInterval = math.max(0.40, Config.JumpPulseInterval - 0.05) end,
    function() Config.JumpPulseInterval = math.min(1.60, Config.JumpPulseInterval + 0.05) end,
    false
)

-- TIEMPO 6: 120 segundos de recarga del Poder 5 (reactiva en noche o modo fijo)
createStepper(ConfigPage, 322, "⚡ RECARGA / TEMPORIZADOR PODER 5 (SEGUNDOS)",
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

-- TIEMPO 7: Pausa activación Anulación del Sistema
createStepper(ConfigPage, 376, "⏳ PAUSA ACTIVACIÓN 'ANULACIÓN DEL SISTEMA' (SEG)",
    function() return string.format("Actual: %.2f segundos antes de equipar Arma 2", Config.Power5CastWait) end,
    function() Config.Power5CastWait = math.max(0.05, Config.Power5CastWait - 0.05) end,
    function() Config.Power5CastWait = math.min(1.50, Config.Power5CastWait + 0.05) end,
    false
)

-- DISTANCIAS Y VELOCIDADES
createStepper(ConfigPage, 430, "➡️ DISTANCIA AVANCE INICIAL (STUDS)",
    function() return string.format("Actual: %d studs hacia delante", Config.ForwardStuds) end,
    function() Config.ForwardStuds = math.max(5, Config.ForwardStuds - 5) end,
    function() Config.ForwardStuds = math.min(120, Config.ForwardStuds + 5) end,
    true
)

createStepper(ConfigPage, 484, "🔄 AMPLITUD DE FORMA (CÍRCULO / I INVERTIDA / ETC.)",
    function() return string.format("Actual: %d studs de radio / amplitud", Config.PatternRadius) end,
    function() Config.PatternRadius = math.max(8, Config.PatternRadius - 2) end,
    function() Config.PatternRadius = math.min(60, Config.PatternRadius + 2) end,
    true
)

createStepper(ConfigPage, 538, "✈️ VELOCIDAD HORIZONTAL CRUCERO (STUDS/S)",
    function() return string.format("Actual: %.1f studs/s (30.0 = límite sin jalón previo)", Config.FlySpeed) end,
    function() Config.FlySpeed = math.max(15.0, Config.FlySpeed - 1.5) end,
    function() Config.FlySpeed = math.min(60.0, Config.FlySpeed + 1.5) end,
    false
)

createStepper(ConfigPage, 592, "📏 UMBRAL DETECCIÓN TIRÓN RUBBERBAND (STUDS)",
    function() return string.format("Actual: >%d studs de retroceso repentino", Config.RubberbandDetectDist) end,
    function() Config.RubberbandDetectDist = math.max(4, Config.RubberbandDetectDist - 2) end,
    function() Config.RubberbandDetectDist = math.min(40, Config.RubberbandDetectDist + 2) end,
    false
)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
