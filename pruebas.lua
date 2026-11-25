-- ==============================================================================
-- EXPLORADOR FORENSE DE TERRENO V11.0 (ANTI-SPITTER/HAZMAT + ÓRBITA EN ROCA)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local Config = {
    Mode = "UnderSkin",         -- "UnderSkin" (Bajo piel) o "Bunker" (Dentro sobre suelo real)
    KeepFly = true,             -- TRUE: Mantiene Fly al llegar
    LockPositionBP = true,      -- FALSE: No te jala de vuelta si te mueves con otro script
    GoToDeepestEdge = false,    -- FALSE: Baja recto (sin irse de lado)
    FlySpeed = 95,
    WalkSpeed = 24,
    SkinOffset = 1.2,
    HoldSeconds = 1.0,
    WalkFirst = true,

    -- Anti-Bloater Diagonal
    AutoEvadeBloaters = true,
    BloaterThreshold = 1,
    BloaterPreDelay = 0.0,
    BloaterSideStuds = 16,
    BloaterDropStuds = 14,
    BloaterHoldDown = 3.0,
    BloaterScanRadius = 55,

    -- Anti-Spitter y Hazmat (Evasión rápida en diagonal hacia el lado opuesto)
    AutoEvadeToxic = true,
    ToxicScanRadius = 65,
    ToxicSideStuds = 18,
    ToxicDropStuds = 14,
    ToxicHoldDown = 2.8,

    -- Órbita lenta alrededor de la piel baja de la roca + Evasión de Jefes
    AutoRockOrbit = true,       -- Rodea la parte baja de la roca continuamente
    OrbitAngularSpeed = 0.45,   -- Velocidad de giro (radianes/seg - medio lento por defecto)
    OrbitRadiusRatio = 0.35,    -- Qué tanto abarca del tamaño de la roca (35% del radio)
    AutoEvadeBosses = true,     -- Hunde y aleja la órbita al lado contrario de los jefes
    BossMinMaxHP = 4500,
    BossScanRadius = 110,
    BossExtraDepth = 10,

    -- 5to Poder con EternalNightTime / TopUI.DayCounter ("Survived: 12:00")
    AutoPower5OnTimeStop = true,
    TimeCheckInterval = 2.0,
    TimeStopDelay = 30,

    -- Zanahorias Inteligentes
    AutoCarrotDash = false,
    CarrotHungerThreshold = 20,
    CarrotMaxZombies = 5,
    CarrotZombieRadius = 35,
    CarrotMaxDist = 80,
    AutoEquipSlot2 = true
}

local State = {
    ClickInspect = false,
    SelectedPart = nil,
    HighlightMap = {},
    ExtraHighlight = nil,
    FilteredObjects = {},

    -- Control de movimiento y cancelación global
    EmergencyCancelId = 0,
    IsWalkingToTarget = false,
    IsFlying = false,
    IsNoclip = false,
    IsDodgingThreat = false,  -- Bloquea temporalmente la órbita mientras esquiva Bloater o Spitter/Hazmat
    IsEvadingBoss = false,
    IsDashingCarrot = false,
    GhostRocks = {},

    -- Ancla base bajo la roca para orbitar alrededor
    AnchorRockPart = nil,
    BaseAnchorPos = nil,

    -- Línea guía (Beam)
    BeamObj = nil,
    Att0 = nil,
    Att1 = nil,

    -- Telemetría
    DetectedHudTime = "Buscando...",
    ActiveBossCount = 0
}

local UIRefs = {}

local COLOR_YELLOW = Color3.fromRGB(255, 220, 0)
local COLOR_BLUE   = Color3.fromRGB(0, 145, 255)

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
-- 1. GESTIÓN DE ARMAS (SLOT 2 PRINCIPAL Y SLOT 5 PODER INSTANTÁNEO)
-- ==============================================================================

local function getToolInstanceForSlot(slotNum)
    local slotStr = tostring(slotNum)
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")
    local toolNameFound = nil

    if bpg then
        for _, desc in ipairs(bpg:GetDescendants()) do
            if (desc.Name == slotStr or desc.Name == "Slot" .. slotStr) and desc:IsA("GuiObject") then
                for _, child in ipairs(desc:GetChildren()) do
                    if child:IsA("ObjectValue") and child.Value and child.Value:IsA("Tool") then
                        return child.Value
                    elseif child:IsA("TextLabel") and child.Text ~= "" and child.Text ~= slotStr and not child.Text:match("^%d+$") then
                        toolNameFound = child.Text
                        break
                    end
                end
            end
            if toolNameFound then break end
        end
    end

    if not toolNameFound and slotNum == 2 then
        toolNameFound = "LMG"
    end

    if toolNameFound then
        local char = lp.Character
        if char then
            local t = char:FindFirstChild(toolNameFound)
            if t and t:IsA("Tool") then return t end
        end
        local bp = lp:FindFirstChild("Backpack")
        if bp then
            local t = bp:FindFirstChild(toolNameFound)
            if t and t:IsA("Tool") then return t end
        end
    end

    return nil
end

local function equipSlotWeapon(slotNum)
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return nil end

    local targetTool = getToolInstanceForSlot(slotNum)
    if not targetTool then return nil end

    local currentTool = char:FindFirstChildOfClass("Tool")
    if currentTool == targetTool then return targetTool end

    if currentTool and currentTool ~= targetTool then
        hum:UnequipTools()
        task.wait(0.03)
    end
    hum:EquipTool(targetTool)
    return targetTool
end

local function activatePowerSlot5()
    local tool5 = equipSlotWeapon(5)
    if tool5 then
        task.wait(0.06)
        pcall(function() tool5:Activate() end)
        for _, child in ipairs(tool5:GetChildren()) do
            if child:IsA("RemoteEvent") then
                local n = child.Name:lower()
                if n:find("use") or n:find("mount") or n:find("cast") or n:find("ability") then
                    pcall(function() child:FireServer() end)
                end
            end
        end
        task.wait(0.12)
    end
    if Config.AutoEquipSlot2 then
        equipSlotWeapon(2)
    end
end

-- ==============================================================================
-- 2. DETECCIÓN DE SACIEDAD, ZOMBIES Y PUNTOS DE DESCENSO
-- ==============================================================================

local function getHungerPercent()
    local char = lp.Character
    local hunger = (char and char:GetAttribute("Hunger")) or lp:GetAttribute("Hunger")
    local maxHunger = (char and char:GetAttribute("MaxHunger")) or lp:GetAttribute("MaxHunger") or 100

    if type(hunger) == "number" then
        return math.floor((hunger / math.max(maxHunger, 1)) * 100)
    end

    local hVal = (char and char:FindFirstChild("Hunger")) or lp:FindFirstChild("Hunger")
    if hVal and (hVal:IsA("NumberValue") or hVal:IsA("IntValue")) then
        local maxHVal = (char and char:FindFirstChild("MaxHunger")) or lp:FindFirstChild("MaxHunger")
        local maxV = (maxHVal and maxHVal.Value) or 100
        return math.floor((hVal.Value / math.max(maxV, 1)) * 100)
    end

    return 100
end

local function countZombiesInRadius(originPos, radius)
    local count = 0
    local char = lp.Character
    local folder = workspace:FindFirstChild("Characters") or workspace

    for _, ent in ipairs(folder:GetChildren()) do
        if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
            local eHum = ent:FindFirstChildOfClass("Humanoid")
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
            if eHum and eHum.Health > 0 and ent:GetAttribute("Dead") ~= true and eRoot then
                local dist = (Vector3.new(eRoot.Position.X, 0, eRoot.Position.Z) - Vector3.new(originPos.X, 0, originPos.Z)).Magnitude
                if dist <= radius then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function getLowestCornerXZ(part)
    local cf = part.CFrame
    local half = part.Size * 0.5
    local lowestPoint = part.Position - Vector3.new(0, half.Y, 0)
    local minY = math.huge

    for _, sx in ipairs({-1, 1}) do
        for _, sy in ipairs({-1, 1}) do
            for _, sz in ipairs({-1, 1}) do
                local worldCorner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
                if worldCorner.Y < minY then
                    minY = worldCorner.Y
                    lowestPoint = worldCorner
                end
            end
        end
    end

    return Vector3.new(
        lowestPoint.X * 0.65 + part.Position.X * 0.35,
        lowestPoint.Y,
        lowestPoint.Z * 0.65 + part.Position.Z * 0.35
    ), minY
end

local function getTargetHorizontalPos(part, currentRootPos)
    if Config.GoToDeepestEdge then
        local cornerPos, _ = getLowestCornerXZ(part)
        return Vector3.new(cornerPos.X, part.Position.Y, cornerPos.Z)
    else
        if currentRootPos then
            local checkParams = RaycastParams.new()
            checkParams.FilterType = Enum.RaycastFilterType.Include
            checkParams.FilterDescendantsInstances = {part}
            local downHit = workspace:Raycast(
                Vector3.new(currentRootPos.X, part.Position.Y + part.Size.Y + 10, currentRootPos.Z),
                Vector3.new(0, -(part.Size.Y * 2 + 20), 0),
                checkParams
            )
            if downHit then
                return Vector3.new(currentRootPos.X, part.Position.Y, currentRootPos.Z)
            end
        end
        return Vector3.new(part.Position.X, part.Position.Y, part.Position.Z)
    end
end

local function getExactUndersideSkinPoint(part, customXZ)
    local _, bboxMinY = getLowestCornerXZ(part)
    local targetXZ = customXZ or getTargetHorizontalPos(part, nil)

    local includeParams = RaycastParams.new()
    includeParams.FilterType = Enum.RaycastFilterType.Include
    includeParams.FilterDescendantsInstances = {part}

    local rayOrigin = Vector3.new(targetXZ.X, bboxMinY - 15, targetXZ.Z)
    local rayDir = Vector3.new(0, part.Size.Y + 35, 0)
    local hit = workspace:Raycast(rayOrigin, rayDir, includeParams)
    if hit then return hit.Position end

    local centerOrigin = Vector3.new(part.Position.X, bboxMinY - 15, part.Position.Z)
    local centerHit = workspace:Raycast(centerOrigin, Vector3.new(0, part.Size.Y + 35, 0), includeParams)
    if centerHit then return centerHit.Position end

    return Vector3.new(targetXZ.X, bboxMinY, targetXZ.Z)
end

local function getRealGroundInsideRock(part, customXZ)
    local targetXZ = customXZ or Vector3.new(part.Position.X, part.Position.Y, part.Position.Z)
    local excludeParams = RaycastParams.new()
    excludeParams.FilterType = Enum.RaycastFilterType.Exclude
    local ignoreList = {part}
    if lp.Character then table.insert(ignoreList, lp.Character) end
    excludeParams.FilterDescendantsInstances = ignoreList

    local origin = Vector3.new(targetXZ.X, part.Position.Y + (part.Size.Y * 0.5) + 10, targetXZ.Z)
    local hit = workspace:Raycast(origin, Vector3.new(0, -(part.Size.Y + 50), 0), excludeParams)

    if hit then
        return Vector3.new(targetXZ.X, hit.Position.Y + 3.0, targetXZ.Z)
    end
    return Vector3.new(targetXZ.X, part.Position.Y + 2, targetXZ.Z)
end

local function getPartBottomDepth(part)
    local _, minY = getLowestCornerXZ(part)
    return minY
end

-- ==============================================================================
-- 3. GESTIÓN DE HIGHLIGHTS Y LÍNEA GUÍA (BEAM 0% LAG)
-- ==============================================================================

local function clearGuideBeam()
    if State.BeamObj then State.BeamObj:Destroy(); State.BeamObj = nil end
    if State.Att0 then State.Att0:Destroy(); State.Att0 = nil end
    if State.Att1 then State.Att1:Destroy(); State.Att1 = nil end
end

local function updateGuideBeam(targetPart)
    clearGuideBeam()
    if not targetPart or not targetPart:IsA("BasePart") or not targetPart.Parent then return end

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local att0 = Instance.new("Attachment")
    att0.Name = "ForensicGuideAtt0"
    att0.Parent = root

    local att1 = Instance.new("Attachment")
    att1.Name = "ForensicGuideAtt1"
    att1.Parent = targetPart

    local beam = Instance.new("Beam")
    beam.Name = "ForensicGuideBeam"
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    beam.Width0 = 0.14
    beam.Width1 = 0.14
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.Transparency = NumberSequence.new(0.15)
    beam.Color = ColorSequence.new(COLOR_BLUE)
    beam.Parent = root

    State.Att0 = att0
    State.Att1 = att1
    State.BeamObj = beam
end

lp.CharacterAdded:Connect(function()
    task.wait(0.8)
    if State.SelectedPart and State.SelectedPart.Parent then
        updateGuideBeam(State.SelectedPart)
    end
    if Config.AutoEquipSlot2 then
        equipSlotWeapon(2)
    end
end)

local function clearAllHighlights()
    for _, hl in pairs(State.HighlightMap) do
        if hl and hl.Parent then hl:Destroy() end
    end
    State.HighlightMap = {}

    if State.ExtraHighlight and State.ExtraHighlight.Parent then
        State.ExtraHighlight:Destroy()
        State.ExtraHighlight = nil
    end
end

local function applyHighlightStyle(hl, isSelected)
    if not hl then return end
    if isSelected then
        hl.FillColor = COLOR_BLUE
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.25
    else
        hl.FillColor = COLOR_YELLOW
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
    end
end

local function selectTargetPart(targetPart)
    if State.SelectedPart then
        local prevHl = State.HighlightMap[State.SelectedPart]
        if prevHl then applyHighlightStyle(prevHl, false) end
    end
    if State.ExtraHighlight then
        State.ExtraHighlight:Destroy()
        State.ExtraHighlight = nil
    end

    State.SelectedPart = targetPart

    if targetPart and targetPart:IsA("BasePart") then
        local existingHl = State.HighlightMap[targetPart]
        if existingHl then
            applyHighlightStyle(existingHl, true)
        else
            local hl = Instance.new("Highlight")
            hl.Name = "SelectedExtraHighlight"
            hl.Adornee = targetPart
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            applyHighlightStyle(hl, true)
            hl.Parent = CoreGui
            State.ExtraHighlight = hl
        end
        updateGuideBeam(targetPart)
    else
        clearGuideBeam()
    end
end

-- ==============================================================================
-- 4. CONTROL DE FÍSICAS, FLY, NOCLIP, PARADA TOTAL Y REACTIVACIÓN AL BAJAR
-- ==============================================================================

RunService.Stepped:Connect(function()
    if State.IsNoclip then
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

local function setCharacterCollide(enabled)
    local char = lp.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = enabled
            end
        end
    end
end

local function restoreGhostRocks()
    for part, origCollide in pairs(State.GhostRocks) do
        if part and part.Parent then
            part.CanCollide = origCollide
        end
    end
    State.GhostRocks = {}
end

local function clearFlightForcesOnly(root)
    if not root then return end
    for _, obj in ipairs(root:GetChildren()) do
        if obj.Name == "DescentBP" or obj.Name == "DescentBG" or obj.Name == "TempDodgeBP" or obj.Name == "TempBossBP" then
            obj:Destroy()
        end
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function stopFlyAndNoclipImmediate()
    State.EmergencyCancelId = State.EmergencyCancelId + 1

    State.IsWalkingToTarget = false
    State.IsNoclip = false
    State.IsFlying = false
    State.IsDodgingThreat = false
    State.IsEvadingBoss = false
    State.IsDashingCarrot = false
    State.AnchorRockPart = nil
    State.BaseAnchorPos = nil

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if root then
        root.Anchored = false
        clearFlightForcesOnly(root)
    end

    setCharacterCollide(true)

    if hum then
        hum.PlatformStand = false
    end
end

local function reactivateDefaultProtections()
    Config.AutoEvadeBloaters = true
    Config.AutoEvadeToxic = true
    Config.AutoRockOrbit = true
    Config.AutoEvadeBosses = true
    Config.AutoPower5OnTimeStop = true

    if UIRefs.BloaterBtn then
        UIRefs.BloaterBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
        UIRefs.BloaterBtn.Text = "💣 ANTI-BLOATER DIAGONAL (SI DESAPARECE 1): ON"
    end
    if UIRefs.ToxicBtn then
        UIRefs.ToxicBtn.BackgroundColor3 = Color3.fromRGB(40, 155, 115)
        UIRefs.ToxicBtn.Text = "☣️ ANTI-SPITTER / HAZMAT (DIAGONAL): ON"
    end
    if UIRefs.OrbitBtn then
        UIRefs.OrbitBtn.BackgroundColor3 = Color3.fromRGB(0, 135, 195)
        UIRefs.OrbitBtn.Text = "🔄 RODEAR BAJO PIEL DE ROCA + JEFES: ON"
    end
    if UIRefs.Power5Btn then
        UIRefs.Power5Btn.BackgroundColor3 = Color3.fromRGB(115, 55, 175)
        UIRefs.Power5Btn.Text = "⏱️ PODER 5 SI RELOJ SURVIVED SE DETIENE (30s): ON"
    end
end

local function fullEmergencyResetAll()
    stopFlyAndNoclipImmediate()
    restoreGhostRocks()

    Config.AutoEvadeBloaters = false
    Config.AutoEvadeToxic = false
    Config.AutoRockOrbit = false
    Config.AutoEvadeBosses = false
    Config.AutoPower5OnTimeStop = false
    Config.AutoCarrotDash = false
    State.ClickInspect = false
    State.ActiveBossCount = 0

    if UIRefs.BloaterBtn then
        UIRefs.BloaterBtn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.BloaterBtn.Text = "💣 ANTI-BLOATER: OFF"
    end
    if UIRefs.ToxicBtn then
        UIRefs.ToxicBtn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.ToxicBtn.Text = "☣️ ANTI-SPITTER / HAZMAT: OFF"
    end
    if UIRefs.OrbitBtn then
        UIRefs.OrbitBtn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.OrbitBtn.Text = "🔄 RODEAR BAJO PIEL DE ROCA + JEFES: OFF"
    end
    if UIRefs.Power5Btn then
        UIRefs.Power5Btn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.Power5Btn.Text = "⏱️ PODER 5 EN RELOJ SURVIVED: OFF"
    end
    if UIRefs.CarrotBtn then
        UIRefs.CarrotBtn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.CarrotBtn.Text = "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): OFF"
    end
    if UIRefs.AnchorBtn then
        UIRefs.AnchorBtn.BackgroundColor3 = Color3.fromRGB(45, 85, 155)
        UIRefs.AnchorBtn.Text = "⚓ ANCLAR AFK AQUÍ (SIN JALÓN + ARMA 2): OFF"
    end
    if UIRefs.ClickBtn then
        UIRefs.ClickBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
        UIRefs.ClickBtn.Text = "🎯 CLICK: OFF"
    end
end

local function ascendAndReleaseAll(statusCallback)
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    stopFlyAndNoclipImmediate()
    restoreGhostRocks()

    local myOpId = State.EmergencyCancelId
    State.IsNoclip = true
    State.IsFlying = true
    hum.PlatformStand = true

    local bp = Instance.new("BodyPosition")
    bp.Name = "DescentBP"
    bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bp.P = 35000
    bp.D = 900
    bp.Position = root.Position
    bp.Parent = root

    local bg = Instance.new("BodyGyro")
    bg.Name = "DescentBG"
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.CFrame = root.CFrame
    bg.Parent = root

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {char}

    local skyOrigin = Vector3.new(root.Position.X, root.Position.Y + 120, root.Position.Z)
    local surfaceHit = workspace:Raycast(skyOrigin, Vector3.new(0, -180, 0), rayParams)

    local targetY = root.Position.Y + 15.0
    if surfaceHit and surfaceHit.Position.Y > (root.Position.Y - 2.0) then
        targetY = surfaceHit.Position.Y + 3.5
    end

    local destPos = Vector3.new(root.Position.X, targetY, root.Position.Z)

    if statusCallback then
        statusCallback(string.format("⬆️ Subiendo a la superficie (Y: %.1f)...", targetY))
    end

    local reached = false
    local timeout = tick() + 12.0

    while State.IsFlying and State.EmergencyCancelId == myOpId and tick() < timeout do
        local dt = RunService.Heartbeat:Wait()
        if not root or not root.Parent then break end
        local diff = destPos - root.Position
        local dist = diff.Magnitude
        if dist <= 1.2 then
            bp.Position = destPos
            reached = true
            break
        end
        bp.Position = root.Position + (diff.Unit * math.min(dist, Config.FlySpeed * dt))
    end

    if State.EmergencyCancelId == myOpId then
        stopFlyAndNoclipImmediate()
        restoreGhostRocks()
        if statusCallback then
            statusCallback(reached and "✅ Superficie alcanzada: Todo suelto." or "🛑 Ascenso finalizado.")
        end
    end
end

local function executeRefugeEntry(targetPart, statusCallback, skipWalk)
    if not targetPart or not targetPart.Parent then return end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    stopFlyAndNoclipImmediate()
    restoreGhostRocks()
    reactivateDefaultProtections()

    local myOpId = State.EmergencyCancelId
    local approachPos = getTargetHorizontalPos(targetPart, root.Position)

    if Config.WalkFirst and not skipWalk then
        local initialHoriz = Vector3.new(approachPos.X - root.Position.X, 0, approachPos.Z - root.Position.Z).Magnitude
        if initialHoriz > 5.0 then
            State.IsWalkingToTarget = true
            local originalWalkSpeed = hum.WalkSpeed
            hum.WalkSpeed = math.max(originalWalkSpeed, Config.WalkSpeed)

            if statusCallback then statusCallback("🚶 Caminando hacia la posición de bajada...") end

            local walkTimeout = tick() + 18.0
            local lastJump = 0
            while State.IsWalkingToTarget and State.EmergencyCancelId == myOpId and tick() < walkTimeout do
                RunService.Heartbeat:Wait()
                if not targetPart or not targetPart.Parent or not root or not root.Parent or hum.Health <= 0 then break end
                approachPos = getTargetHorizontalPos(targetPart, root.Position)
                local horizDiff = Vector3.new(approachPos.X - root.Position.X, 0, approachPos.Z - root.Position.Z)
                if horizDiff.Magnitude <= 5.0 then break end
                hum:MoveTo(Vector3.new(approachPos.X, root.Position.Y, approachPos.Z))
                if (tick() - lastJump) >= 0.7 and root.AssemblyLinearVelocity.Magnitude < (hum.WalkSpeed * 0.35) then
                    hum.Jump = true
                    lastJump = tick()
                end
            end

            hum.WalkSpeed = originalWalkSpeed
            if not State.IsWalkingToTarget or State.EmergencyCancelId ~= myOpId then return end
            State.IsWalkingToTarget = false
        end
    end

    local finalXZ = getTargetHorizontalPos(targetPart, root.Position)
    local targetDest = nil

    if Config.Mode == "Bunker" then
        State.GhostRocks[targetPart] = targetPart.CanCollide
        targetPart.CanCollide = false
        targetDest = getRealGroundInsideRock(targetPart, finalXZ)
    else
        local skinPoint = getExactUndersideSkinPoint(targetPart, finalXZ)
        targetDest = Vector3.new(skinPoint.X, skinPoint.Y - Config.SkinOffset, skinPoint.Z)
    end

    State.IsNoclip = true
    State.IsFlying = true
    hum.PlatformStand = true

    local bp = Instance.new("BodyPosition")
    bp.Name = "DescentBP"
    bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bp.P = 35000
    bp.D = 900
    bp.Position = root.Position
    bp.Parent = root

    local bg = Instance.new("BodyGyro")
    bg.Name = "DescentBG"
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.CFrame = root.CFrame
    bg.Parent = root

    if statusCallback then
        statusCallback(string.format("⬇️ Bajando a Y: %.1f (Defensas ON)...", targetDest.Y))
    end

    local reachedTarget = false
    while State.IsFlying and State.EmergencyCancelId == myOpId do
        local dt = RunService.Heartbeat:Wait()
        if not targetPart or not targetPart.Parent or not root or not root.Parent then break end
        local diff = targetDest - root.Position
        local dist = diff.Magnitude
        if dist <= 1.0 then
            bp.Position = targetDest
            reachedTarget = true
            break
        end
        bp.Position = root.Position + (diff.Unit * math.min(dist, Config.FlySpeed * dt))
    end

    if State.EmergencyCancelId ~= myOpId then return end

    if reachedTarget and State.IsFlying then
        State.IsNoclip = false
        setCharacterCollide(true)

        -- Guardar la roca y el punto base para que la órbita rodee su piel inferior
        State.AnchorRockPart = targetPart
        State.BaseAnchorPos = targetDest

        if Config.KeepFly and Config.LockPositionBP then
            bp.Position = targetDest
            if statusCallback then statusCallback("🔒 Bajo roca: Órbita lenta y Defensas activas.") end
        elseif Config.KeepFly and not Config.LockPositionBP then
            clearFlightForcesOnly(root)
            root.Anchored = true
            if statusCallback then statusCallback("⚓ Posición anclada + Defensas activas.") end
        else
            if statusCallback then statusCallback(string.format("🛑 Noclip OFF. Soltando Fly en %.1fs...", Config.HoldSeconds)) end
            task.wait(Config.HoldSeconds)
            if State.EmergencyCancelId ~= myOpId then return end
            stopFlyAndNoclipImmediate()
            if statusCallback then statusCallback("✅ Posición alcanzada (Fly OFF).") end
        end

        if Config.AutoEquipSlot2 then
            equipSlotWeapon(2)
        end
    else
        stopFlyAndNoclipImmediate()
    end
end

local function descendBelowFeetObject(statusCallback)
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {char}

    local hit = workspace:Raycast(root.Position, Vector3.new(0, -60, 0), rayParams)
    if hit and hit.Instance and hit.Instance:IsA("BasePart") then
        local floorPart = hit.Instance
        selectTargetPart(floorPart)
        if statusCallback then statusCallback(string.format("👣 Bajo tus pies: '%s'. Bajando...", floorPart.Name)) end
        executeRefugeEntry(floorPart, statusCallback, true)
    else
        if statusCallback then statusCallback("⚠️ No se detectó nada sólido debajo de tus pies.") end
    end
end

-- ==============================================================================
-- 5. EVASIÓN DIAGONAL RÁPIDA (BLOATERS + SPITTER / HAZMAT)
-- ==============================================================================

local StatusDisplayCallback = nil

-- Función unificada de evasión rápida en diagonal opuesta (Bloater, Spitter y Hazmat)
local function triggerFastDiagonalDodge(threatPos, labelName, sideStuds, dropStuds, holdTime, preDelay)
    if State.IsDodgingThreat then return end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local myCancelId = State.EmergencyCancelId
    State.IsDodgingThreat = true

    if preDelay and preDelay > 0 then
        local preEnd = tick() + preDelay
        while tick() < preEnd do
            task.wait(0.05)
            if State.EmergencyCancelId ~= myCancelId then
                State.IsDodgingThreat = false
                return
            end
        end
        if not root or not root.Parent then
            State.IsDodgingThreat = false
            return
        end
    end

    local savedCF = root.CFrame
    local wasAnchored = root.Anchored
    local existingBP = root:FindFirstChild("DescentBP")
    local returnPos = State.BaseAnchorPos or (existingBP and existingBP.Position) or savedCF.Position

    local awayHoriz = Vector3.new(returnPos.X - threatPos.X, 0, returnPos.Z - threatPos.Z)
    if awayHoriz.Magnitude < 0.2 then
        awayHoriz = Vector3.new(1, 0, 1)
    end
    local awayDir = awayHoriz.Unit

    local diagonalDest = returnPos + (awayDir * sideStuds) - Vector3.new(0, dropStuds, 0)

    if StatusDisplayCallback then
        StatusDisplayCallback(string.format("⚠️ ¡%s! Esquive diagonal (%dm lado / -%dm)...", labelName, sideStuds, dropStuds))
    end

    State.IsNoclip = true
    setCharacterCollide(false)
    root.Anchored = false
    root.AssemblyLinearVelocity = Vector3.zero

    local tempBP = existingBP
    if not tempBP then
        tempBP = Instance.new("BodyPosition")
        tempBP.Name = "TempDodgeBP"
        tempBP.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        tempBP.P = 45000
        tempBP.D = 900
        tempBP.Parent = root
    end
    tempBP.Position = diagonalDest

    local holdEnd = tick() + holdTime
    while tick() < holdEnd do
        task.wait(0.05)
        if State.EmergencyCancelId ~= myCancelId then
            if tempBP and tempBP ~= existingBP and tempBP.Parent then tempBP:Destroy() end
            State.IsDodgingThreat = false
            return
        end
    end

    -- Regresar al refugio
    if root and root.Parent and State.EmergencyCancelId == myCancelId then
        root.AssemblyLinearVelocity = Vector3.zero
        if existingBP and existingBP.Parent then
            existingBP.Position = returnPos
            task.wait(0.30)
        else
            if tempBP and tempBP.Parent then tempBP:Destroy() end
            root.CFrame = savedCF
            root.Anchored = wasAnchored
        end
    end

    if State.EmergencyCancelId == myCancelId then
        State.IsNoclip = false
        setCharacterCollide(true)
        if StatusDisplayCallback then
            StatusDisplayCallback(string.format("✅ %s esquivado: De vuelta bajo roca.", labelName))
        end
    end
    State.IsDodgingThreat = false
end

-- Monitor de Bloaters (desaparición) + Spitter / Hazmat (proximidad / ataque ácido)
task.spawn(function()
    local trackedBloaters = {}
    local toxicCooldownUntil = 0

    while true do
        task.wait(0.15)
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root or State.IsDodgingThreat or State.IsDashingCarrot then continue end

        local myPos = root.Position
        local now = tick()
        local currentAliveBloaters = {}
        local folder = workspace:FindFirstChild("Characters") or workspace

        local toxicSumPos = Vector3.zero
        local toxicCount = 0

        for _, ent in ipairs(folder:GetChildren()) do
            if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
                local n = ent.Name:lower()
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                local eHum = ent:FindFirstChildOfClass("Humanoid")

                if eRoot and eHum then
                    local isAlive = (eHum.Health > 0) and (ent:GetAttribute("Dead") ~= true)
                    local dist = (eRoot.Position - myPos).Magnitude

                    -- 1. Rastreo de Bloaters
                    if Config.AutoEvadeBloaters and (n:find("bloat") or n:find("boom")) then
                        if dist <= Config.BloaterScanRadius and isAlive then
                            currentAliveBloaters[ent] = eRoot.Position
                            trackedBloaters[ent] = eRoot.Position
                        end
                    end

                    -- 2. Detección de Spitter y Hazmat (y cualquier variante con ese nombre)
                    if Config.AutoEvadeToxic and isAlive and (n:find("spitter") or n:find("hazmat")) then
                        if dist <= Config.ToxicScanRadius and now >= toxicCooldownUntil then
                            toxicSumPos = toxicSumPos + eRoot.Position
                            toxicCount = toxicCount + 1
                        end
                    end
                end
            end
        end

        -- Comprobar si desapareció algún Bloater
        if Config.AutoEvadeBloaters then
            local sumBloat = Vector3.zero
            local bloatCount = 0
            for ent, lastPos in pairs(trackedBloaters) do
                if not currentAliveBloaters[ent] then
                    trackedBloaters[ent] = nil
                    sumBloat = sumBloat + lastPos
                    bloatCount = bloatCount + 1
                end
            end

            if bloatCount >= Config.BloaterThreshold then
                local bPos = sumBloat / bloatCount
                task.spawn(function()
                    triggerFastDiagonalDodge(bPos, "Bloater", Config.BloaterSideStuds, Config.BloaterDropStuds, Config.BloaterHoldDown, Config.BloaterPreDelay)
                end)
                continue
            end
        else
            table.clear(trackedBloaters)
        end

        -- Disparar esquive diagonal si hay Spitter o Hazmat tirando peste cerca
        if toxicCount > 0 and now >= toxicCooldownUntil then
            toxicCooldownUntil = now + Config.ToxicHoldDown + 1.2
            local avgToxicPos = toxicSumPos / toxicCount
            task.spawn(function()
                triggerFastDiagonalDodge(avgToxicPos, "Spitter/Hazmat", Config.ToxicSideStuds, Config.ToxicDropStuds, Config.ToxicHoldDown, 0)
            end)
        end
    end
end)

-- ==============================================================================
-- 6. RODEAR LA PIEL INFERIOR DE LA ROCA (ÓRBITA LENTA + EVASIÓN DE JEFES)
-- ==============================================================================

local function isBossEntity(ent, hum)
    local n = ent.Name:lower()
    if n:find("experiment") or n:find("cyborg") or n:find("tyrant") or n:find("boss") or n:find("titan") or n:find("juggernaut") then
        return true
    end
    if hum and hum.MaxHealth >= Config.BossMinMaxHP then
        return true
    end
    return false
end

task.spawn(function()
    local orbitAngle = 0
    local lastTick = tick()

    while true do
        local now = tick()
        local dt = now - lastTick
        lastTick = now
        task.wait(0.12)

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root or State.IsDodgingThreat or State.IsDashingCarrot or State.IsWalkingToTarget then
            continue
        end

        -- Solo actuar cuando ya estamos posicionados bajo la roca con Fly activo
        local bp = root:FindFirstChild("DescentBP")
        local rock = State.AnchorRockPart or State.SelectedPart
        if not bp or not rock or not rock.Parent then
            State.ActiveBossCount = 0
            continue
        end

        -- Escanear jefes cercanos (Experiment, Cyborg, Tyrant, etc.)
        local folder = workspace:FindFirstChild("Characters") or workspace
        local activeBosses = {}
        local avgBossPos = Vector3.zero

        for _, ent in ipairs(folder:GetChildren()) do
            if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
                local eHum = ent:FindFirstChildOfClass("Humanoid")
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                if eHum and eHum.Health > 0 and ent:GetAttribute("Dead") ~= true and eRoot then
                    if isBossEntity(ent, eHum) then
                        local dist = (eRoot.Position - root.Position).Magnitude
                        if dist <= Config.BossScanRadius then
                            table.insert(activeBosses, eRoot.Position)
                            avgBossPos = avgBossPos + eRoot.Position
                        end
                    end
                end
            end
        end

        State.ActiveBossCount = #activeBosses
        local bossesPresent = (Config.AutoEvadeBosses and #activeBosses > 0)

        -- Si no está activa la órbita ni hay jefes que esquivar, mantener posición base
        if not Config.AutoRockOrbit and not bossesPresent then
            if State.IsEvadingBoss then
                State.IsEvadingBoss = false
                State.IsNoclip = false
                setCharacterCollide(true)
            end
            continue
        end

        -- Calcular radio de órbita ajustado al tamaño real de la roca
        local rockHalfX = rock.Size.X * 0.5
        local rockHalfZ = rock.Size.Z * 0.5
        local orbitRadX = math.max(3.5, rockHalfX * Config.OrbitRadiusRatio)
        local orbitRadZ = math.max(3.5, rockHalfZ * Config.OrbitRadiusRatio)

        -- Avanzar ángulo lentamente según la velocidad configurada (acelera un 40% si hay jefes)
        local speedMult = bossesPresent and 1.4 or 1.0
        orbitAngle = (orbitAngle + (Config.OrbitAngularSpeed * speedMult * dt)) % (math.pi * 2)

        local centerX = rock.Position.X
        local centerZ = rock.Position.Z

        -- Si hay jefes grandes, desplazar el centro de giro hacia el lado contrario de los jefes
        local extraSink = 0
        if bossesPresent then
            State.IsEvadingBoss = true
            avgBossPos = avgBossPos / #activeBosses
            local awayHoriz = Vector3.new(rock.Position.X - avgBossPos.X, 0, rock.Position.Z - avgBossPos.Z)
            local awayDir = (awayHoriz.Magnitude > 0.2) and awayHoriz.Unit or Vector3.new(1, 0, 0)

            -- Empujar hacia el borde opuesto dentro de la roca y hundirse más
            centerX = rock.Position.X + (awayDir.X * math.min(rockHalfX * 0.45, 14))
            centerZ = rock.Position.Z + (awayDir.Z * math.min(rockHalfZ * 0.45, 14))
            extraSink = Config.BossExtraDepth
        else
            State.IsEvadingBoss = false
        end

        local targetX = centerX + math.cos(orbitAngle) * orbitRadX
        local targetZ = centerZ + math.sin(orbitAngle) * orbitRadZ

        -- Seguir la curva real de la piel inferior de la roca en cada punto (targetX, targetZ)
        local skinPos = getExactUndersideSkinPoint(rock, Vector3.new(targetX, rock.Position.Y, targetZ))
        local targetY = skinPos.Y - Config.SkinOffset - extraSink

        -- Mantener Noclip activo mientras rodea la malla inferior de la roca para no atorarse
        State.IsNoclip = true
        setCharacterCollide(false)
        bp.Position = Vector3.new(targetX, targetY, targetZ)
        State.BaseAnchorPos = bp.Position
    end
end)

-- ==============================================================================
-- 7. LECTOR DIRECTO DE ETERNALNIGHTTIME / TOPUI.DAYCOUNTER ("Survived: 12:00")
-- ==============================================================================

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
    local alreadyTriggeredThisFreeze = false

    while true do
        task.wait(Config.TimeCheckInterval)
        local curSec, labelStr = getSurvivalTimeSecondsAndLabel()
        State.DetectedHudTime = labelStr

        if not Config.AutoPower5OnTimeStop or not curSec then
            lastSeconds = nil
            alreadyTriggeredThisFreeze = false
            continue
        end

        if lastSeconds then
            if math.abs(curSec - lastSeconds) < 0.01 then
                if not alreadyTriggeredThisFreeze then
                    alreadyTriggeredThisFreeze = true
                    if StatusDisplayCallback then
                        StatusDisplayCallback(string.format("⏱️ Reloj (%s) detenido: Esperando 30s para 5to Poder...", labelStr))
                    end

                    local myCancelId = State.EmergencyCancelId
                    local waitEnd = tick() + Config.TimeStopDelay
                    while tick() < waitEnd do
                        task.wait(0.25)
                        if State.EmergencyCancelId ~= myCancelId or not Config.AutoPower5OnTimeStop then
                            break
                        end
                    end

                    if State.EmergencyCancelId == myCancelId and Config.AutoPower5OnTimeStop then
                        local checkSec, checkLabel = getSurvivalTimeSecondsAndLabel()
                        if checkSec and math.abs(checkSec - curSec) < 0.01 then
                            if StatusDisplayCallback then
                                StatusDisplayCallback(string.format("⚡ Reloj (%s) sigue quieto: Activando 5to Poder -> Arma 2...", checkLabel))
                            end
                            activatePowerSlot5()
                        end
                    end
                end
            elseif curSec > lastSeconds then
                alreadyTriggeredThisFreeze = false
            end
        end

        lastSeconds = curSec
    end
end)

-- ==============================================================================
-- 8. CARRERA RÁPIDA POR ZANAHORIAS (<20% SACIEDAD + <5 ZOMBIES EN 35 STUDS)
-- ==============================================================================

local function findNearestCarrot(maxDist)
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local bestItem, bestPart = nil, nil
    local shortest = maxDist

    for _, item in ipairs(dropped:GetChildren()) do
        local isCarrot = item.Name:lower():find("carrot") or item:GetAttribute("ItemType") == "Food"
        if isCarrot and item:GetAttribute("CanPickUp") ~= false then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part then
                local d = (part.Position - root.Position).Magnitude
                if d <= shortest then
                    shortest = d
                    bestItem = item
                    bestPart = part
                end
            end
        end
    end
    return bestItem, bestPart
end

task.spawn(function()
    while true do
        task.wait(0.8)
        if not Config.AutoCarrotDash or State.IsDashingCarrot or State.IsDodgingThreat or State.IsEvadingBoss then
            continue
        end

        local hungerPct = getHungerPercent()
        if hungerPct >= Config.CarrotHungerThreshold then
            continue
        end

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

        local nearbyZombies = countZombiesInRadius(root.Position, Config.CarrotZombieRadius)
        if nearbyZombies >= Config.CarrotMaxZombies then
            if StatusDisplayCallback then
                StatusDisplayCallback(string.format("🥕 Saciedad %d%% (<20%%): Esperando (%d zombies en 35m)...", hungerPct, nearbyZombies))
            end
            continue
        end

        local item, part = findNearestCarrot(Config.CarrotMaxDist)
        if not item or not part then continue end

        State.IsDashingCarrot = true
        local savedRock = State.AnchorRockPart
        local savedCF = root.CFrame
        local wasAnchored = root.Anchored
        local hadBP = root:FindFirstChild("DescentBP") ~= nil
        local savedBPPos = hadBP and root.DescentBP.Position or savedCF.Position

        if StatusDisplayCallback then
            StatusDisplayCallback(string.format("🥕 Saciedad %d%% | %d zombies: Subiendo por zanahoria...", hungerPct, nearbyZombies))
        end

        ascendAndReleaseAll(nil)
        local myCancelId = State.EmergencyCancelId
        task.wait(0.1)

        local origSpeed = hum.WalkSpeed
        hum.WalkSpeed = 34
        local dashEnd = tick() + 4.0

        while Config.AutoCarrotDash and State.EmergencyCancelId == myCancelId and tick() < dashEnd and part and part.Parent and hum.Health > 0 do
            RunService.Heartbeat:Wait()
            local toCarrot = part.Position - root.Position
            local horiz = Vector3.new(toCarrot.X, 0, toCarrot.Z)

            if horiz.Magnitude <= 5.5 then
                if PickUpRemote then
                    pcall(function() PickUpRemote:FireServer(item) end)
                end
                break
            end

            local avoidVec = Vector3.zero
            local folder = workspace:FindFirstChild("Characters") or workspace
            for _, ent in ipairs(folder:GetChildren()) do
                if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
                    local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                    if eRoot then
                        local diff = root.Position - eRoot.Position
                        local d = Vector3.new(diff.X, 0, diff.Z).Magnitude
                        if d <= 14 and d > 0.5 then
                            avoidVec = avoidVec + (Vector3.new(diff.X, 0, diff.Z).Unit * (15 - d) * 1.5)
                        end
                    end
                end
            end

            local moveDir = (horiz.Unit + avoidVec).Unit
            hum:MoveTo(root.Position + moveDir * 12)
        end

        hum.WalkSpeed = origSpeed
        if State.EmergencyCancelId ~= myCancelId then
            State.IsDashingCarrot = false
            continue
        end

        task.wait(0.12)
        for _, cont in ipairs({char, lp:FindFirstChild("Backpack")}) do
            if cont then
                for _, t in ipairs(cont:GetChildren()) do
                    if t:IsA("Tool") and (t.Name:lower():find("carrot") or t:GetAttribute("ItemType") == "Food") then
                        hum:EquipTool(t)
                        task.wait(0.05)
                        pcall(function() t:Activate() end)
                        local useRem = t:FindFirstChild("Use") or t:FindFirstChild("Consume")
                        if useRem and useRem:IsA("RemoteEvent") then
                            pcall(function() useRem:FireServer() end)
                        end
                        task.wait(0.15)
                        break
                    end
                end
            end
        end

        if State.EmergencyCancelId ~= myCancelId then
            State.IsDashingCarrot = false
            continue
        end

        if StatusDisplayCallback then
            StatusDisplayCallback("🔙 Regresando a la posición original...")
        end

        State.IsNoclip = true
        setCharacterCollide(false)

        if hadBP then
            State.IsFlying = true
            hum.PlatformStand = true
            local bp = Instance.new("BodyPosition")
            bp.Name = "DescentBP"
            bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
            bp.P = 35000
            bp.D = 900
            bp.Position = savedBPPos
            bp.Parent = root

            local bg = Instance.new("BodyGyro")
            bg.Name = "DescentBG"
            bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
            bg.CFrame = savedCF
            bg.Parent = root

            local retTimeout = tick() + 5.0
            while State.EmergencyCancelId == myCancelId and tick() < retTimeout and (root.Position - savedBPPos).Magnitude > 1.5 do
                RunService.Heartbeat:Wait()
            end
            State.AnchorRockPart = savedRock
            State.BaseAnchorPos = savedBPPos
        else
            root.CFrame = savedCF
            root.Anchored = wasAnchored
        end

        if State.EmergencyCancelId == myCancelId then
            State.IsNoclip = false
            setCharacterCollide(true)
            if Config.AutoEquipSlot2 then
                equipSlotWeapon(2)
            end
            if StatusDisplayCallback then
                StatusDisplayCallback("✅ Zanahoria comida. De vuelta en refugio con Arma 2.")
            end
        end

        State.IsDashingCarrot = false
        task.wait(2.0)
    end
end)

-- ==============================================================================
-- 9. CLASIFICADOR Y RANKING DE PROFUNDIDAD
-- ==============================================================================

local function scanAndRankTerrain(keyword)
    clearAllHighlights()
    State.FilteredObjects = {}
    local baseCenter = Vector3.new(0, 0, 0)
    keyword = (keyword or ""):lower()

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude
            if dist <= 350 then
                local nLower = desc.Name:lower()
                local isCharacterPart = lp.Character and desc:IsDescendantOf(lp.Character)
                if not isCharacterPart and (keyword == "" or nLower:find(keyword, 1, true)) then
                    local bottomY = getPartBottomDepth(desc)
                    table.insert(State.FilteredObjects, {
                        Part = desc, Name = desc.Name, Class = desc.ClassName,
                        Pos = pos, Size = desc.Size, BottomY = bottomY, CenterY = pos.Y
                    })
                end
            end
        end
    end

    table.sort(State.FilteredObjects, function(a, b) return a.BottomY < b.BottomY end)

    for i = 1, math.min(40, #State.FilteredObjects) do
        local obj = State.FilteredObjects[i]
        local hl = Instance.new("Highlight")
        hl.Name = "RankHighlight"
        hl.Adornee = obj.Part
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        applyHighlightStyle(hl, obj.Part == State.SelectedPart)
        hl.Parent = CoreGui
        State.HighlightMap[obj.Part] = hl
    end

    if State.SelectedPart and not State.HighlightMap[State.SelectedPart] then
        selectTargetPart(State.SelectedPart)
    end
end

-- ==============================================================================
-- 10. INTERFAZ GRÁFICA FLOTANTE NATIVA (3 PESTAÑAS)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("TerrainInspectorGuiV110")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TerrainInspectorGuiV110"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 120, 110)
FloatBtn.Text = "🔍\nV11.0"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 535, 0, 520)
MainFrame.Position = UDim2.new(0.5, -267, 0.5, -260)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
TitleBar.Text = "  🔍 EXPLORADOR TERRENO V11.0 | ANTI-SPITTER & ÓRBITA ROCA"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TabExplorerBtn = Instance.new("TextButton")
TabExplorerBtn.Size = UDim2.new(0.34, -8, 0, 28)
TabExplorerBtn.Position = UDim2.new(0, 10, 0, 40)
TabExplorerBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
TabExplorerBtn.Text = "📊 EXPLORADOR"
TabExplorerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TabExplorerBtn.TextSize = 10
TabExplorerBtn.Font = Enum.Font.GothamBold
TabExplorerBtn.Parent = MainFrame
Instance.new("UICorner", TabExplorerBtn).CornerRadius = UDim.new(0, 6)

local TabConfigBtn = Instance.new("TextButton")
TabConfigBtn.Size = UDim2.new(0.33, -8, 0, 28)
TabConfigBtn.Position = UDim2.new(0.34, 4, 0, 40)
TabConfigBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabConfigBtn.Text = "⚙️ CONFIGURACIÓN"
TabConfigBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabConfigBtn.TextSize = 10
TabConfigBtn.Font = Enum.Font.GothamBold
TabConfigBtn.Parent = MainFrame
Instance.new("UICorner", TabConfigBtn).CornerRadius = UDim.new(0, 6)

local TabCoordsBtn = Instance.new("TextButton")
TabCoordsBtn.Size = UDim2.new(0.33, -8, 0, 28)
TabCoordsBtn.Position = UDim2.new(0.67, 0, 0, 40)
TabCoordsBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabCoordsBtn.Text = "📍 COORDENADAS"
TabCoordsBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabCoordsBtn.TextSize = 10
TabCoordsBtn.Font = Enum.Font.GothamBold
TabCoordsBtn.Parent = MainFrame
Instance.new("UICorner", TabCoordsBtn).CornerRadius = UDim.new(0, 6)

local ExplorerPage = Instance.new("Frame")
ExplorerPage.Size = UDim2.new(1, 0, 1, -74)
ExplorerPage.Position = UDim2.new(0, 0, 0, 74)
ExplorerPage.BackgroundTransparency = 1
ExplorerPage.Visible = true
ExplorerPage.Parent = MainFrame

local ConfigPage = Instance.new("ScrollingFrame")
ConfigPage.Size = UDim2.new(1, 0, 1, -74)
ConfigPage.Position = UDim2.new(0, 0, 0, 74)
ConfigPage.BackgroundTransparency = 1
ConfigPage.BorderSizePixel = 0
ConfigPage.CanvasSize = UDim2.new(0, 0, 0, 960)
ConfigPage.ScrollBarThickness = 5
ConfigPage.Visible = false
ConfigPage.Parent = MainFrame

local CoordsPage = Instance.new("Frame")
CoordsPage.Size = UDim2.new(1, 0, 1, -74)
CoordsPage.Position = UDim2.new(0, 0, 0, 74)
CoordsPage.BackgroundTransparency = 1
CoordsPage.Visible = false
CoordsPage.Parent = MainFrame

local function switchTab(activeBtn, activePage)
    ExplorerPage.Visible = (activePage == ExplorerPage)
    ConfigPage.Visible   = (activePage == ConfigPage)
    CoordsPage.Visible   = (activePage == CoordsPage)

    for _, btn in ipairs({TabExplorerBtn, TabConfigBtn, TabCoordsBtn}) do
        if btn == activeBtn then
            btn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            btn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
            btn.TextColor3 = Color3.fromRGB(200, 200, 200)
        end
    end
end

TabExplorerBtn.MouseButton1Click:Connect(function() switchTab(TabExplorerBtn, ExplorerPage) end)
TabConfigBtn.MouseButton1Click:Connect(function() switchTab(TabConfigBtn, ConfigPage) end)
TabCoordsBtn.MouseButton1Click:Connect(function() switchTab(TabCoordsBtn, CoordsPage) end)

-- ==============================================================================
-- 11. PESTAÑA 1: EXPLORADOR
-- ==============================================================================

local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -20, 0, 76)
InfoCard.Position = UDim2.new(0, 10, 0, 4)
InfoCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
InfoCard.Parent = ExplorerPage
Instance.new("UICorner", InfoCard).CornerRadius = UDim.new(0, 6)

local InfoTitle = Instance.new("TextLabel")
InfoTitle.Size = UDim2.new(1, -12, 0, 20)
InfoTitle.Position = UDim2.new(0, 6, 0, 4)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = "📌 Survived: 12:00 | Jefes: 0 | Spitter/Bloater: ON"
InfoTitle.TextColor3 = Color3.fromRGB(90, 190, 255)
InfoTitle.TextSize = 10
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.TextXAlignment = Enum.TextXAlignment.Left
InfoTitle.Parent = InfoCard

task.spawn(function()
    while true do
        task.wait(1.0)
        if not State.SelectedPart then
            InfoTitle.Text = string.format(
                "📌 Survived: [%s] | Jefes: %d | Órbita: %s",
                State.DetectedHudTime,
                State.ActiveBossCount,
                Config.AutoRockOrbit and "ON" or "OFF"
            )
        end
    end
end)

local InfoDetails = Instance.new("TextLabel")
InfoDetails.Size = UDim2.new(1, -12, 0, 46)
InfoDetails.Position = UDim2.new(0, 6, 0, 25)
InfoDetails.BackgroundTransparency = 1
InfoDetails.Text = "Rodea la piel inferior de la roca esquivando Jefes, Spitter, Hazmat y Bloaters."
InfoDetails.TextColor3 = Color3.fromRGB(200, 200, 200)
InfoDetails.TextSize = 9
InfoDetails.Font = Enum.Font.Code
InfoDetails.TextWrapped = true
InfoDetails.TextXAlignment = Enum.TextXAlignment.Left
InfoDetails.TextYAlignment = Enum.TextYAlignment.Top
InfoDetails.Parent = InfoCard

StatusDisplayCallback = function(msg)
    InfoDetails.Text = msg
end

local DropHereBtn = Instance.new("TextButton")
DropHereBtn.Size = UDim2.new(0.55, -12, 0, 32)
DropHereBtn.Position = UDim2.new(0, 10, 0, 86)
DropHereBtn.BackgroundColor3 = Color3.fromRGB(115, 55, 175)
DropHereBtn.Text = "⬇️ BAJAR AQUÍ (PIES)"
DropHereBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DropHereBtn.TextSize = 9
DropHereBtn.Font = Enum.Font.GothamBold
DropHereBtn.Parent = ExplorerPage
Instance.new("UICorner", DropHereBtn).CornerRadius = UDim.new(0, 6)

DropHereBtn.MouseButton1Click:Connect(function()
    task.spawn(function() descendBelowFeetObject(StatusDisplayCallback) end)
end)

local AscendReleaseBtn = Instance.new("TextButton")
AscendReleaseBtn.Size = UDim2.new(0.45, -12, 0, 32)
AscendReleaseBtn.Position = UDim2.new(0.55, 2, 0, 86)
AscendReleaseBtn.BackgroundColor3 = Color3.fromRGB(25, 145, 95)
AscendReleaseBtn.Text = "⬆️ SUBIR Y SOLTAR TODO"
AscendReleaseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AscendReleaseBtn.TextSize = 9
AscendReleaseBtn.Font = Enum.Font.GothamBold
AscendReleaseBtn.Parent = ExplorerPage
Instance.new("UICorner", AscendReleaseBtn).CornerRadius = UDim.new(0, 6)

AscendReleaseBtn.MouseButton1Click:Connect(function()
    task.spawn(function() ascendAndReleaseAll(StatusDisplayCallback) end)
end)

local ClickModeBtn = Instance.new("TextButton")
ClickModeBtn.Size = UDim2.new(0.33, -8, 0, 28)
ClickModeBtn.Position = UDim2.new(0, 10, 0, 124)
ClickModeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
ClickModeBtn.Text = "🎯 CLICK: OFF"
ClickModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClickModeBtn.TextSize = 9
ClickModeBtn.Font = Enum.Font.GothamBold
ClickModeBtn.Parent = ExplorerPage
Instance.new("UICorner", ClickModeBtn).CornerRadius = UDim.new(0, 6)
UIRefs.ClickBtn = ClickModeBtn

local CopyNameBtn = Instance.new("TextButton")
CopyNameBtn.Size = UDim2.new(0.34, -8, 0, 28)
CopyNameBtn.Position = UDim2.new(0.33, 4, 0, 124)
CopyNameBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 170)
CopyNameBtn.Text = "📋 COPIAR NOMBRE"
CopyNameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyNameBtn.TextSize = 9
CopyNameBtn.Font = Enum.Font.GothamBold
CopyNameBtn.Parent = ExplorerPage
Instance.new("UICorner", CopyNameBtn).CornerRadius = UDim.new(0, 6)

local StopFlyBtn = Instance.new("TextButton")
StopFlyBtn.Size = UDim2.new(0.33, -8, 0, 28)
StopFlyBtn.Position = UDim2.new(0.67, 0, 0, 124)
StopFlyBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 20)
StopFlyBtn.Text = "🛑 SOLTAR FLY/TODO"
StopFlyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFlyBtn.TextSize = 9
StopFlyBtn.Font = Enum.Font.GothamBold
StopFlyBtn.Parent = ExplorerPage
Instance.new("UICorner", StopFlyBtn).CornerRadius = UDim.new(0, 6)

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(0.55, -10, 0, 28)
SearchBox.Position = UDim2.new(0, 10, 0, 158)
SearchBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
SearchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBox.PlaceholderText = "Filtrar (ej. rock, tree, ground)..."
SearchBox.Text = ""
SearchBox.TextSize = 10
SearchBox.Font = Enum.Font.Code
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = ExplorerPage
Instance.new("UICorner", SearchBox).CornerRadius = UDim.new(0, 6)

local FilterBtn = Instance.new("TextButton")
FilterBtn.Size = UDim2.new(0.45, -10, 0, 28)
FilterBtn.Position = UDim2.new(0.55, 0, 0, 158)
FilterBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
FilterBtn.Text = "📊 ORDENAR PROFUNDIDAD"
FilterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FilterBtn.TextSize = 9
FilterBtn.Font = Enum.Font.GothamBold
FilterBtn.Parent = ExplorerPage
Instance.new("UICorner", FilterBtn).CornerRadius = UDim.new(0, 6)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 1, -198)
ScrollFrame.Position = UDim2.new(0, 10, 0, 192)
ScrollFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = ExplorerPage
Instance.new("UICorner", ScrollFrame).CornerRadius = UDim.new(0, 6)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)
UIListLayout.Parent = ScrollFrame

-- ==============================================================================
-- 12. PESTAÑA 2: PANEL DE CONFIGURACIÓN (CON SCROLL)
-- ==============================================================================

local function createToggleBtn(yPos, text, color, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, 34)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 9
    btn.Font = Enum.Font.GothamBold
    btn.Parent = ConfigPage
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    btn.MouseButton1Click:Connect(function() onClick(btn) end)
    return btn
end

UIRefs.BloaterBtn = createToggleBtn(6, "💣 ANTI-BLOATER DIAGONAL (SI DESAPARECE 1): ON", Color3.fromRGB(30, 145, 80), function(btn)
    Config.AutoEvadeBloaters = not Config.AutoEvadeBloaters
    btn.BackgroundColor3 = Config.AutoEvadeBloaters and Color3.fromRGB(30, 145, 80) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoEvadeBloaters and "💣 ANTI-BLOATER DIAGONAL (SI DESAPARECE 1): ON" or "💣 ANTI-BLOATER: OFF"
end)

UIRefs.ToxicBtn = createToggleBtn(46, "☣️ ANTI-SPITTER / HAZMAT (DIAGONAL): ON", Color3.fromRGB(40, 155, 115), function(btn)
    Config.AutoEvadeToxic = not Config.AutoEvadeToxic
    btn.BackgroundColor3 = Config.AutoEvadeToxic and Color3.fromRGB(40, 155, 115) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoEvadeToxic and "☣️ ANTI-SPITTER / HAZMAT (DIAGONAL): ON" or "☣️ ANTI-SPITTER / HAZMAT: OFF"
end)

UIRefs.OrbitBtn = createToggleBtn(86, "🔄 RODEAR BAJO PIEL DE ROCA + JEFES: ON", Color3.fromRGB(0, 135, 195), function(btn)
    Config.AutoRockOrbit = not Config.AutoRockOrbit
    Config.AutoEvadeBosses = Config.AutoRockOrbit
    btn.BackgroundColor3 = Config.AutoRockOrbit and Color3.fromRGB(0, 135, 195) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoRockOrbit and "🔄 RODEAR BAJO PIEL DE ROCA + JEFES: ON" or "🔄 RODEAR BAJO PIEL DE ROCA + JEFES: OFF"
end)

UIRefs.Power5Btn = createToggleBtn(126, "⏱️ PODER 5 SI RELOJ SURVIVED SE DETIENE (30s): ON", Color3.fromRGB(115, 55, 175), function(btn)
    Config.AutoPower5OnTimeStop = not Config.AutoPower5OnTimeStop
    btn.BackgroundColor3 = Config.AutoPower5OnTimeStop and Color3.fromRGB(115, 55, 175) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoPower5OnTimeStop and "⏱️ PODER 5 SI RELOJ SURVIVED SE DETIENE (30s): ON" or "⏱️ PODER 5 EN RELOJ SURVIVED: OFF"
end)

UIRefs.CarrotBtn = createToggleBtn(166, "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): OFF", Color3.fromRGB(65, 70, 85), function(btn)
    Config.AutoCarrotDash = not Config.AutoCarrotDash
    btn.BackgroundColor3 = Config.AutoCarrotDash and Color3.fromRGB(210, 120, 20) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoCarrotDash and "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): ON" or "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): OFF"
end)

UIRefs.AnchorBtn = createToggleBtn(206, "⚓ ANCLAR AFK AQUÍ (SIN JALÓN + ARMA 2): OFF", Color3.fromRGB(45, 85, 155), function(btn)
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then
        if not root.Anchored then
            clearFlightForcesOnly(root)
            State.IsFlying = false
            root.Anchored = true
            btn.BackgroundColor3 = Color3.fromRGB(210, 120, 20)
            btn.Text = "⚓ ANCLADO AFK AQUÍ (ARMA 2 ACTIVA): ON"
            if Config.AutoEquipSlot2 then equipSlotWeapon(2) end
        else
            root.Anchored = false
            btn.BackgroundColor3 = Color3.fromRGB(45, 85, 155)
            btn.Text = "⚓ ANCLAR AFK AQUÍ (SIN JALÓN + ARMA 2): OFF"
        end
    end
end)

createToggleBtn(246, "🧲 RETENER CON BODYPOSITION AL BAJAR: ON", Color3.fromRGB(0, 135, 195), function(btn)
    Config.LockPositionBP = not Config.LockPositionBP
    btn.BackgroundColor3 = Config.LockPositionBP and Color3.fromRGB(0, 135, 195) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.LockPositionBP and "🧲 RETENER CON BODYPOSITION AL BAJAR: ON" or "🔓 LIBRE AL BAJAR (ANCLA SIN JALAR DE VUELTA): OFF"
end)

createToggleBtn(286, "MODO: 🦇 BAJO PIEL INFERIOR (RAYCAST VERTICAL)", Color3.fromRGB(115, 55, 175), function(btn)
    if Config.Mode == "UnderSkin" then
        Config.Mode = "Bunker"
        btn.BackgroundColor3 = Color3.fromRGB(35, 130, 95)
        btn.Text = "MODO: 🪨 BÚNKER DENTRO (EN SUELO REAL)"
    else
        Config.Mode = "UnderSkin"
        btn.BackgroundColor3 = Color3.fromRGB(115, 55, 175)
        btn.Text = "MODO: 🦇 BAJO PIEL INFERIOR (RAYCAST VERTICAL)"
    end
end)

createToggleBtn(326, "✈️ MANTENER FLY ACTIVO AL LLEGAR: ON", Color3.fromRGB(0, 135, 195), function(btn)
    Config.KeepFly = not Config.KeepFly
    btn.BackgroundColor3 = Config.KeepFly and Color3.fromRGB(0, 135, 195) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.KeepFly and "✈️ MANTENER FLY ACTIVO AL LLEGAR: ON" or "🛑 APAGAR FLY AUTOMÁTICAMENTE AL LLEGAR: OFF"
end)

createToggleBtn(366, "📐 TRAYECTORIA: BAJADA RECTA (SIN IRSE DE LADO)", Color3.fromRGB(30, 145, 80), function(btn)
    Config.GoToDeepestEdge = not Config.GoToDeepestEdge
    btn.BackgroundColor3 = Config.GoToDeepestEdge and Color3.fromRGB(190, 115, 20) or Color3.fromRGB(30, 145, 80)
    btn.Text = Config.GoToDeepestEdge and "📐 TRAYECTORIA: ESQUINA PROFUNDA (DIAGONAL)" or "📐 TRAYECTORIA: BAJADA RECTA (SIN IRSE DE LADO)"
end)

local function createStepperControl(parent, yPos, titleText, getValText, onMinus, onPlus)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 44)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.62, -10, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = titleText .. "\n" .. getValText()
    lbl.TextColor3 = Color3.fromRGB(230, 235, 245)
    lbl.TextSize = 9
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local minusBtn = Instance.new("TextButton")
    minusBtn.Size = UDim2.new(0, 46, 0, 30)
    minusBtn.Position = UDim2.new(1, -106, 0, 7)
    minusBtn.BackgroundColor3 = Color3.fromRGB(160, 45, 55)
    minusBtn.Text = "➖"
    minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minusBtn.TextSize = 12
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.Parent = row
    Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

    local plusBtn = Instance.new("TextButton")
    plusBtn.Size = UDim2.new(0, 46, 0, 30)
    plusBtn.Position = UDim2.new(1, -54, 0, 7)
    plusBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
    plusBtn.Text = "➕"
    plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    plusBtn.TextSize = 12
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.Parent = row
    Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

    minusBtn.MouseButton1Click:Connect(function() onMinus(); lbl.Text = titleText .. "\n" .. getValText() end)
    plusBtn.MouseButton1Click:Connect(function() onPlus(); lbl.Text = titleText .. "\n" .. getValText() end)
end

-- Velocidad configurable para dar vueltas alrededor de la piel baja de la roca
createStepperControl(ConfigPage, 408, "🐢 VELOCIDAD ÓRBITA EN ROCA",
    function() return string.format("Actual: %.2f rad/s (Giro medio lento)", Config.OrbitAngularSpeed) end,
    function() Config.OrbitAngularSpeed = math.max(0.10, Config.OrbitAngularSpeed - 0.10) end,
    function() Config.OrbitAngularSpeed = math.min(2.50, Config.OrbitAngularSpeed + 0.10) end
)

createStepperControl(ConfigPage, 458, "👹 BAJADA EXTRA ANTI-JEFES (STUDS)",
    function() return string.format("Actual: -%d studs al lado opuesto", Config.BossExtraDepth) end,
    function() Config.BossExtraDepth = math.max(4, Config.BossExtraDepth - 2) end,
    function() Config.BossExtraDepth = math.min(30, Config.BossExtraDepth + 2) end
)

createStepperControl(ConfigPage, 508, "💓 VIDA MÍNIMA DETECCIÓN JEFES (HP)",
    function() return string.format("Actual: >= %d MaxHealth", Config.BossMinMaxHP) end,
    function() Config.BossMinMaxHP = math.max(1500, Config.BossMinMaxHP - 500) end,
    function() Config.BossMinMaxHP = math.min(20000, Config.BossMinMaxHP + 500) end
)

createStepperControl(ConfigPage, 558, "⏳ RETARDO ANTES DE IRSE (BLOATER)",
    function() return string.format("Actual: %.1f seg antes de esquivar", Config.BloaterPreDelay) end,
    function() Config.BloaterPreDelay = math.max(0.0, Config.BloaterPreDelay - 0.1) end,
    function() Config.BloaterPreDelay = math.min(2.0, Config.BloaterPreDelay + 0.1) end
)

createStepperControl(ConfigPage, 608, "⏱️ TIEMPO RESGUARDO BLOATER (SEG)",
    function() return string.format("Actual: %.1f segundos antes de volver", Config.BloaterHoldDown) end,
    function() Config.BloaterHoldDown = math.max(1.0, Config.BloaterHoldDown - 0.5) end,
    function() Config.BloaterHoldDown = math.min(10.0, Config.BloaterHoldDown + 0.5) end
)

createStepperControl(ConfigPage, 658, "↗️ DIAGONAL OPUESTA BLOATER/SPITTER",
    function() return string.format("Actual: %d studs lado / -%d studs abajo", Config.BloaterSideStuds, Config.BloaterDropStuds) end,
    function()
        Config.BloaterSideStuds = math.max(6, Config.BloaterSideStuds - 2)
        Config.ToxicSideStuds = Config.BloaterSideStuds + 2
    end,
    function()
        Config.BloaterSideStuds = math.min(35, Config.BloaterSideStuds + 2)
        Config.ToxicSideStuds = Config.BloaterSideStuds + 2
    end
)

createStepperControl(ConfigPage, 708, "🎯 AJUSTE BAJO PIEL INFERIOR",
    function() return string.format("Actual: -%.1f studs", Config.SkinOffset) end,
    function() Config.SkinOffset = math.max(0.0, Config.SkinOffset - 0.2) end,
    function() Config.SkinOffset = math.min(6.0, Config.SkinOffset + 0.2) end
)

createStepperControl(ConfigPage, 758, "✈️ VELOCIDAD DE VUELO (FLY)",
    function() return string.format("Actual: %d studs/s", Config.FlySpeed) end,
    function() Config.FlySpeed = math.max(20, Config.FlySpeed - 10) end,
    function() Config.FlySpeed = math.min(250, Config.FlySpeed + 10) end
)

createStepperControl(ConfigPage, 808, "🚶 VELOCIDAD AL CAMINAR",
    function() return string.format("Actual: %d WalkSpeed", Config.WalkSpeed) end,
    function() Config.WalkSpeed = math.max(16, Config.WalkSpeed - 4) end,
    function() Config.WalkSpeed = math.min(80, Config.WalkSpeed + 4) end
)

createToggleBtn(858, "🚶 CAMINAR PRIMERO ANTES DE BAJAR: ON", Color3.fromRGB(0, 130, 110), function(btn)
    Config.WalkFirst = not Config.WalkFirst
    btn.BackgroundColor3 = Config.WalkFirst and Color3.fromRGB(0, 130, 110) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.WalkFirst and "🚶 CAMINAR PRIMERO ANTES DE BAJAR: ON" or "✈️ VOLAR DIRECTO SIN CAMINAR: OFF"
end)

-- ==============================================================================
-- 13. PESTAÑA 3: COORDENADAS EN TIEMPO REAL
-- ==============================================================================

local CoordCard = Instance.new("Frame")
CoordCard.Size = UDim2.new(1, -20, 0, 180)
CoordCard.Position = UDim2.new(0, 10, 0, 10)
CoordCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
CoordCard.Parent = CoordsPage
Instance.new("UICorner", CoordCard).CornerRadius = UDim.new(0, 8)

local CoordHeader = Instance.new("TextLabel")
CoordHeader.Size = UDim2.new(1, -20, 0, 28)
CoordHeader.Position = UDim2.new(0, 10, 0, 8)
CoordHeader.BackgroundTransparency = 1
CoordHeader.Text = "📍 POSICIÓN ACTUAL DE TU PERSONAJE (EN VIVO)"
CoordHeader.TextColor3 = Color3.fromRGB(0, 255, 190)
CoordHeader.TextSize = 11
CoordHeader.Font = Enum.Font.GothamBold
CoordHeader.TextXAlignment = Enum.TextXAlignment.Left
CoordHeader.Parent = CoordCard

local LiveCoordText = Instance.new("TextLabel")
LiveCoordText.Size = UDim2.new(1, -20, 0, 75)
LiveCoordText.Position = UDim2.new(0, 10, 0, 40)
LiveCoordText.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
LiveCoordText.TextColor3 = Color3.fromRGB(255, 255, 255)
LiveCoordText.TextSize = 12
LiveCoordText.Font = Enum.Font.Code
LiveCoordText.Text = "Calculando..."
LiveCoordText.Parent = CoordCard
Instance.new("UICorner", LiveCoordText).CornerRadius = UDim.new(0, 6)

local CopyVecBtn = Instance.new("TextButton")
CopyVecBtn.Size = UDim2.new(1, -20, 0, 42)
CopyVecBtn.Position = UDim2.new(0, 10, 0, 126)
CopyVecBtn.BackgroundColor3 = Color3.fromRGB(0, 135, 215)
CopyVecBtn.Text = "📋 COPIAR Vector3.new(X, Y, Z)"
CopyVecBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyVecBtn.TextSize = 11
CopyVecBtn.Font = Enum.Font.GothamBold
CopyVecBtn.Parent = CoordCard
Instance.new("UICorner", CopyVecBtn).CornerRadius = UDim.new(0, 6)

local currentFormattedVector = "Vector3.new(0, 0, 0)"

task.spawn(function()
    while true do
        task.wait(0.15)
        if CoordsPage.Visible then
            local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local p = root.Position
                currentFormattedVector = string.format("Vector3.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
                LiveCoordText.Text = string.format("X: %.2f   |   Y: %.2f   |   Z: %.2f\n\nFormato Lua:\n%s", p.X, p.Y, p.Z, currentFormattedVector)
            else
                LiveCoordText.Text = "Personaje no encontrado..."
            end
        end
    end
end)

CopyVecBtn.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(currentFormattedVector) elseif toclipboard then toclipboard(currentFormattedVector) end
    CopyVecBtn.Text = "✅ ¡COORDENADAS COPIADAS!"
    task.wait(1.2)
    CopyVecBtn.Text = "📋 COPIAR Vector3.new(X, Y, Z)"
end)

-- ==============================================================================
-- 14. RENDERIZADO DE LISTA Y EVENTOS
-- ==============================================================================

local RowButtons = {}

local function refreshRowSelectionVisuals()
    for part, rowFrame in pairs(RowButtons) do
        if rowFrame and rowFrame.Parent then
            rowFrame.BackgroundColor3 = (part == State.SelectedPart) and Color3.fromRGB(20, 65, 115) or Color3.fromRGB(22, 26, 36)
        end
    end
end

local function updateScrollList()
    for _, child in ipairs(ScrollFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    RowButtons = {}

    for rank, obj in ipairs(State.FilteredObjects) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 36)
        row.BackgroundColor3 = (obj.Part == State.SelectedPart) and Color3.fromRGB(20, 65, 115) or Color3.fromRGB(22, 26, 36)
        row.Parent = ScrollFrame
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        RowButtons[obj.Part] = row

        local selectBtn = Instance.new("TextButton")
        selectBtn.Size = UDim2.new(1, -82, 1, 0)
        selectBtn.Position = UDim2.new(0, 6, 0, 0)
        selectBtn.BackgroundTransparency = 1
        selectBtn.Text = string.format("#%d [%s] Base Y: %.1f | (%.0f, %.0f, %.0f)", rank, obj.Name, obj.BottomY, obj.Pos.X, obj.CenterY, obj.Pos.Z)
        selectBtn.TextColor3 = (obj.BottomY <= -5) and Color3.fromRGB(0, 255, 180) or Color3.fromRGB(220, 220, 220)
        selectBtn.TextSize = 9
        selectBtn.Font = Enum.Font.Code
        selectBtn.TextXAlignment = Enum.TextXAlignment.Left
        selectBtn.Parent = row

        selectBtn.MouseButton1Click:Connect(function()
            selectTargetPart(obj.Part)
            refreshRowSelectionVisuals()
            InfoTitle.Text = string.format("📌 #%d Seleccionado: '%s' (%s)", rank, obj.Name, obj.Class)
            InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)\nRuta: %s", obj.BottomY, obj.CenterY, obj.Size.X, obj.Size.Y, obj.Size.Z, obj.Part:GetFullName())
        end)

        local goBtn = Instance.new("TextButton")
        goBtn.Size = UDim2.new(0, 72, 0, 28)
        goBtn.Position = UDim2.new(1, -76, 0, 4)
        goBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        goBtn.Text = "⬇️ BAJAR"
        goBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        goBtn.TextSize = 9
        goBtn.Font = Enum.Font.GothamBold
        goBtn.Parent = row
        Instance.new("UICorner", goBtn).CornerRadius = UDim.new(0, 4)

        goBtn.MouseButton1Click:Connect(function()
            selectTargetPart(obj.Part)
            refreshRowSelectionVisuals()
            InfoTitle.Text = string.format("📌 #%d Destino: '%s' (%s)", rank, obj.Name, obj.Class)
            task.spawn(function()
                executeRefugeEntry(obj.Part, StatusDisplayCallback, false)
            end)
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #State.FilteredObjects * 40)
end

mouse.Button1Down:Connect(function()
    if not State.ClickInspect then return end
    local targetPart = mouse.Target
    if targetPart and targetPart:IsA("BasePart") then
        if lp.Character and targetPart:IsDescendantOf(lp.Character) then return end
        selectTargetPart(targetPart)
        refreshRowSelectionVisuals()
        local bottomY = getPartBottomDepth(targetPart)
        InfoTitle.Text = string.format("📌 Click en: '%s' (%s)", targetPart.Name, targetPart.ClassName)
        InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)\nRuta: %s", bottomY, targetPart.Position.Y, targetPart.Size.X, targetPart.Size.Y, targetPart.Size.Z, targetPart:GetFullName())
        SearchBox.Text = targetPart.Name
    end
end)

ClickModeBtn.MouseButton1Click:Connect(function()
    State.ClickInspect = not State.ClickInspect
    ClickModeBtn.BackgroundColor3 = State.ClickInspect and Color3.fromRGB(30, 160, 80) or Color3.fromRGB(160, 40, 50)
    ClickModeBtn.Text = State.ClickInspect and "🎯 CLICK: ON" or "🎯 CLICK: OFF"
end)

CopyNameBtn.MouseButton1Click:Connect(function()
    if State.SelectedPart then
        local txt = State.SelectedPart.Name
        if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
        CopyNameBtn.Text = "✅ ¡COPIADO!"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE"
    end
end)

StopFlyBtn.MouseButton1Click:Connect(function()
    fullEmergencyResetAll()
    InfoDetails.Text = "🛑 TODO DETENIDO Y RESTAURADO (Fly, Noclip, Bloater, Spitter, Órbita y Jefes en OFF)."
end)

FilterBtn.MouseButton1Click:Connect(function()
    FilterBtn.Text = "⏳ ANALIZANDO..."
    scanAndRankTerrain(SearchBox.Text)
    updateScrollList()
    FilterBtn.Text = string.format("✅ %d ORDENADOS", #State.FilteredObjects)
    task.wait(1.2)
    FilterBtn.Text = "📊 ORDENAR PROFUNDIDAD"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Carga inicial + Equipar Arma 2 por defecto
scanAndRankTerrain("")
updateScrollList()
if Config.AutoEquipSlot2 then
    equipSlotWeapon(2)
end
