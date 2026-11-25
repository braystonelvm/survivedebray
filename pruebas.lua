-- ==============================================================================
-- EXPLORADOR FORENSE DE TERRENO V11.3 (TOP 5 CERCANAS + 4 PESTAÑAS + UI PRO)
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

    -- Anti-Bloater Diagonal (Siempre activo hasta pulsar PARAR TODO)
    AutoEvadeBloaters = true,
    BloaterThreshold = 1,
    BloaterPreDelay = 0.0,
    BloaterSideStuds = 16,
    BloaterDropStuds = 14,
    BloaterHoldDown = 4.0,
    BloaterScanRadius = 55,

    -- Repulsión Diagonal a Variantes (Independiente de Bloaters, desactivable)
    AutoEvadeToxic = true,
    ToxicScanRadius = 65,
    ToxicSideStuds = 10,
    ToxicDropStuds = 10,
    ToxicHoldDown = 2.8,

    -- Órbita subterránea bajo la piel de la roca (Para Jefes y Variantes)
    AutoRockOrbit = true,
    OrbitAngularSpeed = 0.55,
    OrbitMultiSpeed = 1.15,
    OrbitRadiusRatio = 0.38,
    OrbitMultiRadiusRatio = 0.54,
    BossMinMaxHP = 4500,
    BossScanRadius = 110,
    BossExtraDepth = 6,

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
    IsDodgingThreat = false,
    IsOrbitingThreat = false,
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
    ActiveSpecialCount = 0
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
-- 4. CONTROL DE FÍSICAS, FLY, NOCLIP, PARAR TODO Y REACTIVACIÓN AL BAJAR
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
    State.IsOrbitingThreat = false
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
    Config.AutoPower5OnTimeStop = true

    if UIRefs.ToxicBtn then
        UIRefs.ToxicBtn.BackgroundColor3 = Color3.fromRGB(40, 155, 115)
        UIRefs.ToxicBtn.Text = "☣️ REPULSIÓN DIAGONAL VARIANTES (SPITTER/HAZMAT): ON"
    end
    if UIRefs.OrbitBtn then
        UIRefs.OrbitBtn.BackgroundColor3 = Color3.fromRGB(0, 135, 195)
        UIRefs.OrbitBtn.Text = "🔄 ÓRBITA SUBTERRÁNEA (JEFES Y VARIANTES): ON"
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
    Config.AutoPower5OnTimeStop = false
    Config.AutoCarrotDash = false
    State.ClickInspect = false
    State.ActiveSpecialCount = 0

    if UIRefs.ToxicBtn then
        UIRefs.ToxicBtn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.ToxicBtn.Text = "☣️ REPULSIÓN DIAGONAL VARIANTES (SPITTER/HAZMAT): OFF"
    end
    if UIRefs.OrbitBtn then
        UIRefs.OrbitBtn.BackgroundColor3 = Color3.fromRGB(65, 70, 85)
        UIRefs.OrbitBtn.Text = "🔄 ÓRBITA SUBTERRÁNEA (JEFES Y VARIANTES): OFF"
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
        UIRefs.AnchorBtn.Text = "⚓ ANCLAR POSICIÓN AFK: OFF"
    end
    if UIRefs.ClickBtn then
        UIRefs.ClickBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
        UIRefs.ClickBtn.Text = "🎯 CLICK INSPECCIONAR: OFF"
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
        statusCallback(string.format("⬇️ Bajando a Y: %.1f (Bloater + Variantes + Órbita ON)...", targetDest.Y))
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

        State.AnchorRockPart = targetPart
        State.BaseAnchorPos = targetDest

        if Config.KeepFly and Config.LockPositionBP then
            bp.Position = targetDest
            if statusCallback then statusCallback("🔒 Bajo roca: Órbita y Repulsión activas.") end
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
-- 5. EVASIÓN DIAGONAL (BLOATERS 16/14m +4s Y VARIANTES SPITTER/HAZMAT/SPLITTER)
-- ==============================================================================

local StatusDisplayCallback = nil

local function isDangerousToxicVariant(rawName)
    local clean = rawName:lower():match("^%s*(.-)%s*$")
    if clean == "spitter" or clean == "hazmat" then
        return false
    end
    if clean:find("splitter", 1, true) then
        return true
    end
    if clean:find("spitter", 1, true) or clean:find("hazmat", 1, true) then
        return true
    end
    return false
end

local function isAnyBloater(rawName)
    local low = rawName:lower()
    return low:find("bloater", 1, true) ~= nil or low:find("bloat", 1, true) ~= nil
end

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
        StatusDisplayCallback(string.format("⚠️ ¡%s! Esquive diagonal (%dm lado / -%dm) por %.1fs...", labelName, sideStuds, dropStuds, holdTime))
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
        local lastToxicName = "Variante Tóxica"

        for _, ent in ipairs(folder:GetChildren()) do
            if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                local eHum = ent:FindFirstChildOfClass("Humanoid")

                if eRoot and eHum then
                    local isAlive = (eHum.Health > 0) and (ent:GetAttribute("Dead") ~= true)
                    local dist = (eRoot.Position - myPos).Magnitude

                    if Config.AutoEvadeBloaters and isAnyBloater(ent.Name) then
                        if dist <= Config.BloaterScanRadius and isAlive then
                            currentAliveBloaters[ent] = { Pos = eRoot.Position, Name = ent.Name }
                            trackedBloaters[ent] = { Pos = eRoot.Position, Name = ent.Name }
                        end
                    end

                    if Config.AutoEvadeToxic and isAlive and isDangerousToxicVariant(ent.Name) then
                        if dist <= Config.ToxicScanRadius and now >= toxicCooldownUntil then
                            toxicSumPos = toxicSumPos + eRoot.Position
                            toxicCount = toxicCount + 1
                            lastToxicName = ent.Name
                        end
                    end
                end
            end
        end

        if Config.AutoEvadeBloaters then
            local sumBloat = Vector3.zero
            local bloatCount = 0
            local bloatLabel = "Bloater"
            for ent, data in pairs(trackedBloaters) do
                if not currentAliveBloaters[ent] then
                    trackedBloaters[ent] = nil
                    sumBloat = sumBloat + data.Pos
                    bloatCount = bloatCount + 1
                    bloatLabel = data.Name
                end
            end

            if bloatCount >= Config.BloaterThreshold then
                local bPos = sumBloat / bloatCount
                task.spawn(function()
                    triggerFastDiagonalDodge(bPos, bloatLabel, Config.BloaterSideStuds, Config.BloaterDropStuds, Config.BloaterHoldDown, Config.BloaterPreDelay)
                end)
                continue
            end
        else
            table.clear(trackedBloaters)
        end

        if Config.AutoEvadeToxic and toxicCount > 0 and now >= toxicCooldownUntil then
            toxicCooldownUntil = now + Config.ToxicHoldDown + 1.2
            local avgToxicPos = toxicSumPos / toxicCount
            task.spawn(function()
                triggerFastDiagonalDodge(avgToxicPos, lastToxicName, Config.ToxicSideStuds, Config.ToxicDropStuds, Config.ToxicHoldDown, 0)
            end)
        end
    end
end)

-- ==============================================================================
-- 6. ÓRBITA SUBTERRÁNEA BAJO LA PIEL DE LA ROCA (TODOS LOS JEFES Y VARIANTES)
-- ==============================================================================

local function isBossOrVariant(ent, hum)
    local n = ent.Name:lower()
    if n:find("experiment") or n:find("cyborg") or n:find("tyrant") or n:find("boss") or n:find("titan") or n:find("juggernaut") then
        return true, true
    end
    if hum and hum.MaxHealth >= Config.BossMinMaxHP then
        return true, true
    end
    if isDangerousToxicVariant(ent.Name) or isAnyBloater(ent.Name) then
        return true, false
    end
    return false, false
end

task.spawn(function()
    local orbitAngle = 0
    local lastTick = tick()

    while true do
        local now = tick()
        local dt = now - lastTick
        lastTick = now
        task.wait(0.10)

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root or State.IsDodgingThreat or State.IsDashingCarrot or State.IsWalkingToTarget then
            continue
        end

        local bp = root:FindFirstChild("DescentBP")
        local rock = State.AnchorRockPart or State.SelectedPart
        if not bp or not rock or not rock.Parent then
            State.ActiveSpecialCount = 0
            continue
        end

        local folder = workspace:FindFirstChild("Characters") or workspace
        local activeSpecials = {}
        local avgThreatPos = Vector3.zero
        local hasGiantBoss = false

        for _, ent in ipairs(folder:GetChildren()) do
            if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
                local eHum = ent:FindFirstChildOfClass("Humanoid")
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
                if eHum and eHum.Health > 0 and ent:GetAttribute("Dead") ~= true and eRoot then
                    local isSpec, isBoss = isBossOrVariant(ent, eHum)
                    if isSpec then
                        local dist = (eRoot.Position - root.Position).Magnitude
                        if dist <= Config.BossScanRadius then
                            table.insert(activeSpecials, eRoot.Position)
                            avgThreatPos = avgThreatPos + eRoot.Position
                            if isBoss then
                                hasGiantBoss = true
                            end
                        end
                    end
                end
            end
        end

        State.ActiveSpecialCount = #activeSpecials

        if not Config.AutoRockOrbit then
            if State.IsOrbitingThreat then
                State.IsOrbitingThreat = false
                State.IsNoclip = false
                setCharacterCollide(true)
            end
            continue
        end

        if #activeSpecials == 0 then
            if State.IsOrbitingThreat then
                State.IsOrbitingThreat = false
                State.IsNoclip = false
                setCharacterCollide(true)
            end
            continue
        end

        State.IsOrbitingThreat = true
        local multipleThreats = (#activeSpecials > 1)

        local rockHalfX = rock.Size.X * 0.5
        local rockHalfZ = rock.Size.Z * 0.5
        local ratio = multipleThreats and Config.OrbitMultiRadiusRatio or Config.OrbitRadiusRatio
        local currentSpeed = multipleThreats and Config.OrbitMultiSpeed or Config.OrbitAngularSpeed

        local orbitRadX = math.max(4.5, rockHalfX * ratio)
        local orbitRadZ = math.max(4.5, rockHalfZ * ratio)

        orbitAngle = (orbitAngle + (currentSpeed * dt)) % (math.pi * 2)

        avgThreatPos = avgThreatPos / #activeSpecials
        local awayHoriz = Vector3.new(rock.Position.X - avgThreatPos.X, 0, rock.Position.Z - avgThreatPos.Z)
        local awayDir = (awayHoriz.Magnitude > 0.2) and awayHoriz.Unit or Vector3.new(1, 0, 0)

        local centerX = rock.Position.X + (awayDir.X * math.min(rockHalfX * 0.42, 13))
        local centerZ = rock.Position.Z + (awayDir.Z * math.min(rockHalfZ * 0.42, 13))
        local extraSink = hasGiantBoss and Config.BossExtraDepth or 2

        local targetX = centerX + math.cos(orbitAngle) * orbitRadX
        local targetZ = centerZ + math.sin(orbitAngle) * orbitRadZ

        local skinPos = getExactUndersideSkinPoint(rock, Vector3.new(targetX, rock.Position.Y, targetZ))
        local targetY = skinPos.Y - Config.SkinOffset - extraSink

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
        if not Config.AutoCarrotDash or State.IsDashingCarrot or State.IsDodgingThreat or State.IsOrbitingThreat then
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
-- 9. ESCÁNER INICIAL (MANTIENE RESPLANDOR) + ORDENAMIENTO POR CERCANÍA (0% LAG)
-- ==============================================================================

local function scanInitialTerrainWithHighlights()
    clearAllHighlights()
    State.FilteredObjects = {}
    local baseCenter = Vector3.new(0, 0, 0)

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude
            if dist <= 350 then
                local isCharacterPart = lp.Character and desc:IsDescendantOf(lp.Character)
                if not isCharacterPart then
                    local bottomY = getPartBottomDepth(desc)
                    table.insert(State.FilteredObjects, {
                        Part = desc, Name = desc.Name, Class = desc.ClassName,
                        Pos = pos, Size = desc.Size, BottomY = bottomY, CenterY = pos.Y,
                        DistToPlayer = 999
                    })
                end
            end
        end
    end

    table.sort(State.FilteredObjects, function(a, b) return a.BottomY < b.BottomY end)

    -- Mantener el resplandor amarillo inicial en los primeros 40 objetos
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

-- Ordena por cercanía al jugador sin recorrer todo workspace (0% lag)
local function sortObjectsByProximityFast()
    if #State.FilteredObjects == 0 then
        scanInitialTerrainWithHighlights()
    end

    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local myPos = root and root.Position or Vector3.new(0, 0, 0)

    -- Filtrar piezas eliminadas y calcular distancia al jugador
    local validList = {}
    for _, obj in ipairs(State.FilteredObjects) do
        if obj.Part and obj.Part.Parent then
            local pPos = obj.Part.Position
            obj.Pos = pPos
            obj.CenterY = pPos.Y
            obj.DistToPlayer = (pPos - myPos).Magnitude
            table.insert(validList, obj)
        end
    end
    State.FilteredObjects = validList

    table.sort(State.FilteredObjects, function(a, b)
        return a.DistToPlayer < b.DistToPlayer
    end)
end

-- ==============================================================================
-- 10. INTERFAZ GRÁFICA FLOTANTE NATIVA (4 PESTAÑAS REORGANIZADAS)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("TerrainInspectorGuiV113")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TerrainInspectorGuiV113"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 120, 110)
FloatBtn.Text = "🔍\nV11.3"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 545, 0, 520)
MainFrame.Position = UDim2.new(0.5, -272, 0.5, -260)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
TitleBar.Text = "  🔍 EXPLORADOR TERRENO V11.3 | TOP 5 CERCANAS & CONTROL"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

-- Barra de 4 Pestañas
local TabExplorerBtn = Instance.new("TextButton")
TabExplorerBtn.Size = UDim2.new(0.25, -7, 0, 28)
TabExplorerBtn.Position = UDim2.new(0, 10, 0, 40)
TabExplorerBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
TabExplorerBtn.Text = "📊 EXPLORADOR"
TabExplorerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TabExplorerBtn.TextSize = 9
TabExplorerBtn.Font = Enum.Font.GothamBold
TabExplorerBtn.Parent = MainFrame
Instance.new("UICorner", TabExplorerBtn).CornerRadius = UDim.new(0, 6)

local TabFullListBtn = Instance.new("TextButton")
TabFullListBtn.Size = UDim2.new(0.25, -7, 0, 28)
TabFullListBtn.Position = UDim2.new(0.25, 5, 0, 40)
TabFullListBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabFullListBtn.Text = "📋 LISTA COMPLETA"
TabFullListBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabFullListBtn.TextSize = 9
TabFullListBtn.Font = Enum.Font.GothamBold
TabFullListBtn.Parent = MainFrame
Instance.new("UICorner", TabFullListBtn).CornerRadius = UDim.new(0, 6)

local TabConfigBtn = Instance.new("TextButton")
TabConfigBtn.Size = UDim2.new(0.25, -7, 0, 28)
TabConfigBtn.Position = UDim2.new(0.50, 2, 0, 40)
TabConfigBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabConfigBtn.Text = "⚙️ CONFIG"
TabConfigBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabConfigBtn.TextSize = 9
TabConfigBtn.Font = Enum.Font.GothamBold
TabConfigBtn.Parent = MainFrame
Instance.new("UICorner", TabConfigBtn).CornerRadius = UDim.new(0, 6)

local TabCoordsBtn = Instance.new("TextButton")
TabCoordsBtn.Size = UDim2.new(0.25, -7, 0, 28)
TabCoordsBtn.Position = UDim2.new(0.75, -1, 0, 40)
TabCoordsBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabCoordsBtn.Text = "📍 INSPECTOR"
TabCoordsBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabCoordsBtn.TextSize = 9
TabCoordsBtn.Font = Enum.Font.GothamBold
TabCoordsBtn.Parent = MainFrame
Instance.new("UICorner", TabCoordsBtn).CornerRadius = UDim.new(0, 6)

local ExplorerPage = Instance.new("Frame")
ExplorerPage.Size = UDim2.new(1, 0, 1, -74)
ExplorerPage.Position = UDim2.new(0, 0, 0, 74)
ExplorerPage.BackgroundTransparency = 1
ExplorerPage.Visible = true
ExplorerPage.Parent = MainFrame

local FullListPage = Instance.new("Frame")
FullListPage.Size = UDim2.new(1, 0, 1, -74)
FullListPage.Position = UDim2.new(0, 0, 0, 74)
FullListPage.BackgroundTransparency = 1
FullListPage.Visible = false
FullListPage.Parent = MainFrame

local ConfigPage = Instance.new("ScrollingFrame")
ConfigPage.Size = UDim2.new(1, 0, 1, -74)
ConfigPage.Position = UDim2.new(0, 0, 0, 74)
ConfigPage.BackgroundTransparency = 1
ConfigPage.BorderSizePixel = 0
ConfigPage.CanvasSize = UDim2.new(0, 0, 0, 920)
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
    FullListPage.Visible = (activePage == FullListPage)
    ConfigPage.Visible   = (activePage == ConfigPage)
    CoordsPage.Visible   = (activePage == CoordsPage)

    for _, btn in ipairs({TabExplorerBtn, TabFullListBtn, TabConfigBtn, TabCoordsBtn}) do
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
TabFullListBtn.MouseButton1Click:Connect(function() switchTab(TabFullListBtn, FullListPage) end)
TabConfigBtn.MouseButton1Click:Connect(function() switchTab(TabConfigBtn, ConfigPage) end)
TabCoordsBtn.MouseButton1Click:Connect(function() switchTab(TabCoordsBtn, CoordsPage) end)

-- ==============================================================================
-- 11. PESTAÑA 1: EXPLORADOR (BOTONES PRINCIPALES + ANCLAR AFK + TOP 5 CERCANAS)
-- ==============================================================================

local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -20, 0, 68)
InfoCard.Position = UDim2.new(0, 10, 0, 4)
InfoCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
InfoCard.Parent = ExplorerPage
Instance.new("UICorner", InfoCard).CornerRadius = UDim.new(0, 6)

local InfoTitle = Instance.new("TextLabel")
InfoTitle.Size = UDim2.new(1, -12, 0, 20)
InfoTitle.Position = UDim2.new(0, 6, 0, 4)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = "📌 Survived: 12:00 | Especiales: 0 | Órbita: ON"
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
                "📌 Survived: [%s] | Especiales: %d | Órbita: %s | Bloater: %s",
                State.DetectedHudTime,
                State.ActiveSpecialCount,
                Config.AutoRockOrbit and "ON" or "OFF",
                Config.AutoEvadeBloaters and "ON" or "OFF"
            )
        end
    end
end)

local InfoDetails = Instance.new("TextLabel")
InfoDetails.Size = UDim2.new(1, -12, 0, 40)
InfoDetails.Position = UDim2.new(0, 6, 0, 24)
InfoDetails.BackgroundTransparency = 1
InfoDetails.Text = "Bloater (16/14m, 4s) y Órbita de Jefes/Variantes activos. Pulsa '🛑 PARAR TODO' para detener todo."
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

-- Fila 1: Bajar Aquí + Subir y Soltar
local DropHereBtn = Instance.new("TextButton")
DropHereBtn.Size = UDim2.new(0.55, -12, 0, 30)
DropHereBtn.Position = UDim2.new(0, 10, 0, 78)
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
AscendReleaseBtn.Size = UDim2.new(0.45, -12, 0, 30)
AscendReleaseBtn.Position = UDim2.new(0.55, 2, 0, 78)
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

-- Fila 2: Botón GRANDE de "🛑 PARAR TODO"
local StopAllBtn = Instance.new("TextButton")
StopAllBtn.Size = UDim2.new(1, -20, 0, 36)
StopAllBtn.Position = UDim2.new(0, 10, 0, 114)
StopAllBtn.BackgroundColor3 = Color3.fromRGB(205, 45, 45)
StopAllBtn.Text = "🛑 PARAR TODO (DETENER VUELO, BLOATER, ÓRBITA Y VARIANTES)"
StopAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopAllBtn.TextSize = 10
StopAllBtn.Font = Enum.Font.GothamBold
StopAllBtn.Parent = ExplorerPage
Instance.new("UICorner", StopAllBtn).CornerRadius = UDim.new(0, 6)

-- Fila 3: Botón ANCLAR POSICIÓN AFK (Movido aquí por ser muy importante)
local AnchorAfkMainBtn = Instance.new("TextButton")
AnchorAfkMainBtn.Size = UDim2.new(1, -20, 0, 30)
AnchorAfkMainBtn.Position = UDim2.new(0, 10, 0, 156)
AnchorAfkMainBtn.BackgroundColor3 = Color3.fromRGB(45, 85, 155)
AnchorAfkMainBtn.Text = "⚓ ANCLAR POSICIÓN AFK: OFF"
AnchorAfkMainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AnchorAfkMainBtn.TextSize = 10
AnchorAfkMainBtn.Font = Enum.Font.GothamBold
AnchorAfkMainBtn.Parent = ExplorerPage
Instance.new("UICorner", AnchorAfkMainBtn).CornerRadius = UDim.new(0, 6)
UIRefs.AnchorBtn = AnchorAfkMainBtn

AnchorAfkMainBtn.MouseButton1Click:Connect(function()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then
        if not root.Anchored then
            clearFlightForcesOnly(root)
            State.IsFlying = false
            root.Anchored = true
            AnchorAfkMainBtn.BackgroundColor3 = Color3.fromRGB(210, 120, 20)
            AnchorAfkMainBtn.Text = "⚓ ANCLADO POSICIÓN AFK (ARMA 2): ON"
            if Config.AutoEquipSlot2 then equipSlotWeapon(2) end
        else
            root.Anchored = false
            AnchorAfkMainBtn.BackgroundColor3 = Color3.fromRGB(45, 85, 155)
            AnchorAfkMainBtn.Text = "⚓ ANCLAR POSICIÓN AFK: OFF"
        end
    end
end)

-- Separación amplia + Botón centrado de 5 Rocas Cercanas
local Nearest5Btn = Instance.new("TextButton")
Nearest5Btn.Size = UDim2.new(0.68, 0, 0, 32)
Nearest5Btn.Position = UDim2.new(0.16, 0, 0, 204)
Nearest5Btn.BackgroundColor3 = Color3.fromRGB(0, 130, 110)
Nearest5Btn.Text = "📡 ACTUALIZAR 5 ROCAS MÁS CERCANAS"
Nearest5Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Nearest5Btn.TextSize = 10
Nearest5Btn.Font = Enum.Font.GothamBold
Nearest5Btn.Parent = ExplorerPage
Instance.new("UICorner", Nearest5Btn).CornerRadius = UDim.new(0, 8)

-- Contenedor exclusivo para las 5 rocas más cercanas (aparece al presionar el botón)
local Top5Container = Instance.new("Frame")
Top5Container.Size = UDim2.new(1, -20, 0, 192)
Top5Container.Position = UDim2.new(0, 10, 0, 244)
Top5Container.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
Top5Container.Visible = false
Top5Container.Parent = ExplorerPage
Instance.new("UICorner", Top5Container).CornerRadius = UDim.new(0, 6)

local Top5Layout = Instance.new("UIListLayout")
Top5Layout.SortOrder = Enum.SortOrder.LayoutOrder
Top5Layout.Padding = UDim.new(0, 4)
Top5Layout.Parent = Top5Container

-- ==============================================================================
-- 12. PESTAÑA 2: LISTA COMPLETA (SEPARADA EN SU PROPIA PESTAÑA)
-- ==============================================================================

local FullListRefreshBtn = Instance.new("TextButton")
FullListRefreshBtn.Size = UDim2.new(0.64, 0, 0, 30)
FullListRefreshBtn.Position = UDim2.new(0.18, 0, 0, 8)
FullListRefreshBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
FullListRefreshBtn.Text = "🔄 ACTUALIZAR LISTA POR CERCANÍA"
FullListRefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FullListRefreshBtn.TextSize = 10
FullListRefreshBtn.Font = Enum.Font.GothamBold
FullListRefreshBtn.Parent = FullListPage
Instance.new("UICorner", FullListRefreshBtn).CornerRadius = UDim.new(0, 6)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 1, -50)
ScrollFrame.Position = UDim2.new(0, 10, 0, 44)
ScrollFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = FullListPage
Instance.new("UICorner", ScrollFrame).CornerRadius = UDim.new(0, 6)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)
UIListLayout.Parent = ScrollFrame

-- ==============================================================================
-- 13. RENDERIZADO DE TOP 5 Y LISTA COMPLETA
-- ==============================================================================

local RowButtons = {}
local InspectorSelectedLabel = nil

local function refreshRowSelectionVisuals()
    for part, rowFrame in pairs(RowButtons) do
        if rowFrame and rowFrame.Parent then
            rowFrame.BackgroundColor3 = (part == State.SelectedPart) and Color3.fromRGB(20, 65, 115) or Color3.fromRGB(22, 26, 36)
        end
    end
end

local function renderTop5List()
    for _, child in ipairs(Top5Container:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local count = math.min(5, #State.FilteredObjects)
    for rank = 1, count do
        local obj = State.FilteredObjects[rank]
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 34)
        row.BackgroundColor3 = (obj.Part == State.SelectedPart) and Color3.fromRGB(20, 65, 115) or Color3.fromRGB(22, 26, 36)
        row.Parent = Top5Container
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local selectBtn = Instance.new("TextButton")
        selectBtn.Size = UDim2.new(1, -80, 1, 0)
        selectBtn.Position = UDim2.new(0, 6, 0, 0)
        selectBtn.BackgroundTransparency = 1
        selectBtn.Text = string.format("#%d [%s] Dist: %.0fm | Base Y: %.1f", rank, obj.Name, obj.DistToPlayer, obj.BottomY)
        selectBtn.TextColor3 = Color3.fromRGB(0, 255, 185)
        selectBtn.TextSize = 9
        selectBtn.Font = Enum.Font.Code
        selectBtn.TextXAlignment = Enum.TextXAlignment.Left
        selectBtn.Parent = row

        selectBtn.MouseButton1Click:Connect(function()
            selectTargetPart(obj.Part)
            refreshRowSelectionVisuals()
            InfoTitle.Text = string.format("📌 #%d Cercana: '%s' (a %.0fm)", rank, obj.Name, obj.DistToPlayer)
            InfoDetails.Text = string.format("Base Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)", obj.BottomY, obj.Size.X, obj.Size.Y, obj.Size.Z)
            if InspectorSelectedLabel then
                InspectorSelectedLabel.Text = string.format("Seleccionado: '%s' (%s)", obj.Name, obj.Class)
            end
        end)

        local goBtn = Instance.new("TextButton")
        goBtn.Size = UDim2.new(0, 70, 0, 26)
        goBtn.Position = UDim2.new(1, -74, 0, 4)
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
            InfoTitle.Text = string.format("📌 #%d Destino: '%s'", rank, obj.Name)
            task.spawn(function()
                executeRefugeEntry(obj.Part, StatusDisplayCallback, false)
            end)
        end)
    end

    Top5Container.Visible = (count > 0)
end

local function updateFullScrollList()
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
        selectBtn.Text = string.format("#%d [%s] Dist: %.0fm | Base Y: %.1f", rank, obj.Name, obj.DistToPlayer, obj.BottomY)
        selectBtn.TextColor3 = (obj.BottomY <= -5) and Color3.fromRGB(0, 255, 180) or Color3.fromRGB(220, 220, 220)
        selectBtn.TextSize = 9
        selectBtn.Font = Enum.Font.Code
        selectBtn.TextXAlignment = Enum.TextXAlignment.Left
        selectBtn.Parent = row

        selectBtn.MouseButton1Click:Connect(function()
            selectTargetPart(obj.Part)
            refreshRowSelectionVisuals()
            InfoTitle.Text = string.format("📌 #%d Seleccionado: '%s' (a %.0fm)", rank, obj.Name, obj.DistToPlayer)
            InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)", obj.BottomY, obj.CenterY, obj.Size.X, obj.Size.Y, obj.Size.Z)
            if InspectorSelectedLabel then
                InspectorSelectedLabel.Text = string.format("Seleccionado: '%s' (%s)", obj.Name, obj.Class)
            end
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
            InfoTitle.Text = string.format("📌 #%d Destino: '%s'", rank, obj.Name)
            task.spawn(function()
                executeRefugeEntry(obj.Part, StatusDisplayCallback, false)
            end)
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #State.FilteredObjects * 40)
end

-- ==============================================================================
-- 14. PESTAÑA 3: CONFIGURACIÓN (SIN ANCLAR AFK)
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

UIRefs.OrbitBtn = createToggleBtn(6, "🔄 ÓRBITA SUBTERRÁNEA (JEFES Y VARIANTES): ON", Color3.fromRGB(0, 135, 195), function(btn)
    Config.AutoRockOrbit = not Config.AutoRockOrbit
    btn.BackgroundColor3 = Config.AutoRockOrbit and Color3.fromRGB(0, 135, 195) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoRockOrbit and "🔄 ÓRBITA SUBTERRÁNEA (JEFES Y VARIANTES): ON" or "🔄 ÓRBITA SUBTERRÁNEA (JEFES Y VARIANTES): OFF"
end)

UIRefs.ToxicBtn = createToggleBtn(46, "☣️ REPULSIÓN DIAGONAL VARIANTES (SPITTER/HAZMAT): ON", Color3.fromRGB(40, 155, 115), function(btn)
    Config.AutoEvadeToxic = not Config.AutoEvadeToxic
    btn.BackgroundColor3 = Config.AutoEvadeToxic and Color3.fromRGB(40, 155, 115) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoEvadeToxic and "☣️ REPULSIÓN DIAGONAL VARIANTES (SPITTER/HAZMAT): ON" or "☣️ REPULSIÓN DIAGONAL VARIANTES (SPITTER/HAZMAT): OFF"
end)

UIRefs.Power5Btn = createToggleBtn(86, "⏱️ PODER 5 SI RELOJ SURVIVED SE DETIENE (30s): ON", Color3.fromRGB(115, 55, 175), function(btn)
    Config.AutoPower5OnTimeStop = not Config.AutoPower5OnTimeStop
    btn.BackgroundColor3 = Config.AutoPower5OnTimeStop and Color3.fromRGB(115, 55, 175) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoPower5OnTimeStop and "⏱️ PODER 5 SI RELOJ SURVIVED SE DETIENE (30s): ON" or "⏱️ PODER 5 EN RELOJ SURVIVED: OFF"
end)

UIRefs.CarrotBtn = createToggleBtn(126, "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): OFF", Color3.fromRGB(65, 70, 85), function(btn)
    Config.AutoCarrotDash = not Config.AutoCarrotDash
    btn.BackgroundColor3 = Config.AutoCarrotDash and Color3.fromRGB(210, 120, 20) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.AutoCarrotDash and "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): ON" or "🥕 ZANAHORIAS (<20% HAMBRE Y <5 ZOMBIES): OFF"
end)

createToggleBtn(166, "🧲 RETENER CON BODYPOSITION AL BAJAR: ON", Color3.fromRGB(0, 135, 195), function(btn)
    Config.LockPositionBP = not Config.LockPositionBP
    btn.BackgroundColor3 = Config.LockPositionBP and Color3.fromRGB(0, 135, 195) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.LockPositionBP and "🧲 RETENER CON BODYPOSITION AL BAJAR: ON" or "🔓 LIBRE AL BAJAR (ANCLA SIN JALAR DE VUELTA): OFF"
end)

createToggleBtn(206, "MODO: 🦇 BAJO PIEL INFERIOR (RAYCAST VERTICAL)", Color3.fromRGB(115, 55, 175), function(btn)
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

createToggleBtn(246, "✈️ MANTENER FLY ACTIVO AL LLEGAR: ON", Color3.fromRGB(0, 135, 195), function(btn)
    Config.KeepFly = not Config.KeepFly
    btn.BackgroundColor3 = Config.KeepFly and Color3.fromRGB(0, 135, 195) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.KeepFly and "✈️ MANTENER FLY ACTIVO AL LLEGAR: ON" or "🛑 APAGAR FLY AUTOMÁTICAMENTE AL LLEGAR: OFF"
end)

createToggleBtn(286, "📐 TRAYECTORIA: BAJADA RECTA (SIN IRSE DE LADO)", Color3.fromRGB(30, 145, 80), function(btn)
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

createStepperControl(ConfigPage, 328, "🐢 VELOCIDAD ÓRBITA NORMAL (1 ENEMIGO)",
    function() return string.format("Actual: %.2f rad/s", Config.OrbitAngularSpeed) end,
    function() Config.OrbitAngularSpeed = math.max(0.15, Config.OrbitAngularSpeed - 0.10) end,
    function() Config.OrbitAngularSpeed = math.min(2.50, Config.OrbitAngularSpeed + 0.10) end
)

createStepperControl(ConfigPage, 378, "⚡ VELOCIDAD ÓRBITA MÚLTIPLE (>1 ENEMIGO)",
    function() return string.format("Actual: %.2f rad/s (Giro amplio)", Config.OrbitMultiSpeed) end,
    function() Config.OrbitMultiSpeed = math.max(0.30, Config.OrbitMultiSpeed - 0.15) end,
    function() Config.OrbitMultiSpeed = math.min(3.50, Config.OrbitMultiSpeed + 0.15) end
)

createStepperControl(ConfigPage, 428, "💣 DIAGONAL BLOATER (SIEMPRE ACTIVO)",
    function() return string.format("Actual: %d studs lado / -%d studs abajo", Config.BloaterSideStuds, Config.BloaterDropStuds) end,
    function()
        Config.BloaterSideStuds = math.max(6, Config.BloaterSideStuds - 2)
        Config.BloaterDropStuds = math.max(6, Config.BloaterDropStuds - 2)
    end,
    function()
        Config.BloaterSideStuds = math.min(30, Config.BloaterSideStuds + 2)
        Config.BloaterDropStuds = math.min(30, Config.BloaterDropStuds + 2)
    end
)

createStepperControl(ConfigPage, 478, "⏱️ TIEMPO RESGUARDO BLOATER (SEG)",
    function() return string.format("Actual: %.1f segundos antes de volver", Config.BloaterHoldDown) end,
    function() Config.BloaterHoldDown = math.max(1.0, Config.BloaterHoldDown - 0.5) end,
    function() Config.BloaterHoldDown = math.min(10.0, Config.BloaterHoldDown + 0.5) end
)

createStepperControl(ConfigPage, 528, "👹 BAJADA EXTRA ANTI-JEFES (STUDS)",
    function() return string.format("Actual: -%d studs al lado opuesto", Config.BossExtraDepth) end,
    function() Config.BossExtraDepth = math.max(2, Config.BossExtraDepth - 2) end,
    function() Config.BossExtraDepth = math.min(24, Config.BossExtraDepth + 2) end
)

createStepperControl(ConfigPage, 578, "💓 VIDA MÍNIMA DETECCIÓN JEFES (HP)",
    function() return string.format("Actual: >= %d MaxHealth", Config.BossMinMaxHP) end,
    function() Config.BossMinMaxHP = math.max(1500, Config.BossMinMaxHP - 500) end,
    function() Config.BossMinMaxHP = math.min(20000, Config.BossMinMaxHP + 500) end
)

createStepperControl(ConfigPage, 628, "⏳ RETARDO ANTES DE IRSE (BLOATER)",
    function() return string.format("Actual: %.1f seg antes de esquivar", Config.BloaterPreDelay) end,
    function() Config.BloaterPreDelay = math.max(0.0, Config.BloaterPreDelay - 0.1) end,
    function() Config.BloaterPreDelay = math.min(2.0, Config.BloaterPreDelay + 0.1) end
)

createStepperControl(ConfigPage, 678, "🎯 AJUSTE BAJO PIEL INFERIOR",
    function() return string.format("Actual: -%.1f studs", Config.SkinOffset) end,
    function() Config.SkinOffset = math.max(0.0, Config.SkinOffset - 0.2) end,
    function() Config.SkinOffset = math.min(6.0, Config.SkinOffset + 0.2) end
)

createStepperControl(ConfigPage, 728, "✈️ VELOCIDAD DE VUELO (FLY)",
    function() return string.format("Actual: %d studs/s", Config.FlySpeed) end,
    function() Config.FlySpeed = math.max(20, Config.FlySpeed - 10) end,
    function() Config.FlySpeed = math.min(250, Config.FlySpeed + 10) end
)

createStepperControl(ConfigPage, 778, "🚶 VELOCIDAD AL CAMINAR",
    function() return string.format("Actual: %d WalkSpeed", Config.WalkSpeed) end,
    function() Config.WalkSpeed = math.max(16, Config.WalkSpeed - 4) end,
    function() Config.WalkSpeed = math.min(80, Config.WalkSpeed + 4) end
)

createToggleBtn(828, "🚶 CAMINAR PRIMERO ANTES DE BAJAR: ON", Color3.fromRGB(0, 130, 110), function(btn)
    Config.WalkFirst = not Config.WalkFirst
    btn.BackgroundColor3 = Config.WalkFirst and Color3.fromRGB(0, 130, 110) or Color3.fromRGB(65, 70, 85)
    btn.Text = Config.WalkFirst and "🚶 CAMINAR PRIMERO ANTES DE BAJAR: ON" or "✈️ VOLAR DIRECTO SIN CAMINAR: OFF"
end)

-- ==============================================================================
-- 15. PESTAÑA 4: INSPECTOR & COORDENADAS (CON CLICK: OFF Y COPIAR NOMBRE)
-- ==============================================================================

local InspectCard = Instance.new("Frame")
InspectCard.Size = UDim2.new(1, -20, 0, 102)
InspectCard.Position = UDim2.new(0, 10, 0, 8)
InspectCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
InspectCard.Parent = CoordsPage
Instance.new("UICorner", InspectCard).CornerRadius = UDim.new(0, 8)

local InspectHeader = Instance.new("TextLabel")
InspectHeader.Size = UDim2.new(1, -20, 0, 24)
InspectHeader.Position = UDim2.new(0, 10, 0, 6)
InspectHeader.BackgroundTransparency = 1
InspectHeader.Text = "🎯 INSPECTOR DE OBJETOS (CLICK EN EL MAPA)"
InspectHeader.TextColor3 = Color3.fromRGB(90, 190, 255)
InspectHeader.TextSize = 11
InspectHeader.Font = Enum.Font.GothamBold
InspectHeader.TextXAlignment = Enum.TextXAlignment.Left
InspectHeader.Parent = InspectCard

InspectorSelectedLabel = Instance.new("TextLabel")
InspectorSelectedLabel.Size = UDim2.new(1, -20, 0, 20)
InspectorSelectedLabel.Position = UDim2.new(0, 10, 0, 30)
InspectorSelectedLabel.BackgroundTransparency = 1
InspectorSelectedLabel.Text = "Seleccionado: (Ninguno)"
InspectorSelectedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
InspectorSelectedLabel.TextSize = 10
InspectorSelectedLabel.Font = Enum.Font.Code
InspectorSelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
InspectorSelectedLabel.Parent = InspectCard

local ClickModeBtn = Instance.new("TextButton")
ClickModeBtn.Size = UDim2.new(0.5, -14, 0, 34)
ClickModeBtn.Position = UDim2.new(0, 10, 0, 58)
ClickModeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
ClickModeBtn.Text = "🎯 CLICK INSPECCIONAR: OFF"
ClickModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClickModeBtn.TextSize = 9
ClickModeBtn.Font = Enum.Font.GothamBold
ClickModeBtn.Parent = InspectCard
Instance.new("UICorner", ClickModeBtn).CornerRadius = UDim.new(0, 6)
UIRefs.ClickBtn = ClickModeBtn

local CopyNameBtn = Instance.new("TextButton")
CopyNameBtn.Size = UDim2.new(0.5, -14, 0, 34)
CopyNameBtn.Position = UDim2.new(0.5, 4, 0, 58)
CopyNameBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 170)
CopyNameBtn.Text = "📋 COPIAR NOMBRE"
CopyNameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyNameBtn.TextSize = 9
CopyNameBtn.Font = Enum.Font.GothamBold
CopyNameBtn.Parent = InspectCard
Instance.new("UICorner", CopyNameBtn).CornerRadius = UDim.new(0, 6)

local CoordCard = Instance.new("Frame")
CoordCard.Size = UDim2.new(1, -20, 0, 180)
CoordCard.Position = UDim2.new(0, 10, 0, 120)
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
-- 16. EVENTOS DE BOTONES Y CLIC EN EL MUNDO
-- ==============================================================================

mouse.Button1Down:Connect(function()
    if not State.ClickInspect then return end
    local targetPart = mouse.Target
    if targetPart and targetPart:IsA("BasePart") then
        if lp.Character and targetPart:IsDescendantOf(lp.Character) then return end
        selectTargetPart(targetPart)
        refreshRowSelectionVisuals()
        local bottomY = getPartBottomDepth(targetPart)
        InfoTitle.Text = string.format("📌 Click en: '%s' (%s)", targetPart.Name, targetPart.ClassName)
        InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)", bottomY, targetPart.Position.Y, targetPart.Size.X, targetPart.Size.Y, targetPart.Size.Z)
        InspectorSelectedLabel.Text = string.format("Seleccionado: '%s' (%s)", targetPart.Name, targetPart.ClassName)
    end
end)

ClickModeBtn.MouseButton1Click:Connect(function()
    State.ClickInspect = not State.ClickInspect
    ClickModeBtn.BackgroundColor3 = State.ClickInspect and Color3.fromRGB(30, 160, 80) or Color3.fromRGB(160, 40, 50)
    ClickModeBtn.Text = State.ClickInspect and "🎯 CLICK INSPECCIONAR: ON" or "🎯 CLICK INSPECCIONAR: OFF"
end)

CopyNameBtn.MouseButton1Click:Connect(function()
    if State.SelectedPart then
        local txt = State.SelectedPart.Name
        if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
        CopyNameBtn.Text = "✅ ¡COPIADO!"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE"
    else
        CopyNameBtn.Text = "⚠️ SIN SELECCIÓN"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE"
    end
end)

StopAllBtn.MouseButton1Click:Connect(function()
    fullEmergencyResetAll()
    InfoDetails.Text = "🛑 PARAR TODO: Vuelo, Noclip, Bloater, Órbita y Variantes detenidos. Pulsa 'BAJAR' para reactivar."
end)

-- Botón central de Explorador: Ordena por cercanía (0% lag) y despliega las 5 más cercanas
Nearest5Btn.MouseButton1Click:Connect(function()
    sortObjectsByProximityFast()
    renderTop5List()
    updateFullScrollList()
    Nearest5Btn.Text = "✅ TOP 5 CERCANAS ACTUALIZADAS"
    task.wait(1.0)
    Nearest5Btn.Text = "📡 ACTUALIZAR 5 ROCAS MÁS CERCANAS"
end)

-- Botón de la pestaña Lista Completa
FullListRefreshBtn.MouseButton1Click:Connect(function()
    sortObjectsByProximityFast()
    updateFullScrollList()
    FullListRefreshBtn.Text = string.format("✅ %d ORDENADOS POR CERCANÍA", #State.FilteredObjects)
    task.wait(1.0)
    FullListRefreshBtn.Text = "🔄 ACTUALIZAR LISTA POR CERCANÍA"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Carga inicial (mantiene resplandor amarillo) + Ordenar por cercanía + Arma 2
scanInitialTerrainWithHighlights()
sortObjectsByProximityFast()
updateFullScrollList()
if Config.AutoEquipSlot2 then
    equipSlotWeapon(2)
end
