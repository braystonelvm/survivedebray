-- ==============================================================================
-- BASE DEFENDER & TOWER WATCHDOG V4.0 (INTERFAZ NATIVA - 0% LIBRERÍAS EXTERNAS)
-- Prioridad Comida Mañana + Evasión Obstáculos + Slot 2 Fijo / Swap 50s + Evasión Zombies
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local BaseCenter = Vector3.new(0, 0, 0)
local DAY_90_TARGET_POS = Vector3.new(0.1, 0.9, -8.0)
local BASE_WANDER_RADIUS = 85

local Config = {
    Active = true,
    FlySpeed = 70,
    Day90Threshold = 90,

    -- Alimentación matutina prioritaria
    EatScanRadius = 100,        -- Radio para buscar comida en la base
    FullHungerTarget = 95,      -- Come hasta tener 95%+ antes de pasear
    EatCooldown = 0.9,

    -- Control de Armas
    AutoEquipWeapon = true,
    SwapWeaponsEnabled = false, -- FALSE = Solo Slot 2 fijo. TRUE = Intercambia con Slot 3
    SwapInterval = 50,          -- 50 segundos exactos entre Slot 2 y 3

    -- Paseo matutino (20 segundos por cada movimiento aleatorio)
    MovementPattern = "Aleatorio Total",
    PatternSwitchInterval = 20, -- 20 segundos por patrón
    JumpInterval = 12,          -- Salto ocasional cada 12 segundos

    -- Evasión de Zombies
    ZombieEvadeDist = 15        -- Esquiva zombies si están a menos de 15 studs (en tierra)
}

local State = {
    CurrentDay = 0,
    Status = "Iniciando...",
    ActiveSlot = 2,
    LastSwapTick = tick(),
    IsEating = false,
    LastEatTick = 0,
    Day90Enforced = false,

    -- Torre dinámica
    CurrentTowerName = "Buscando...",
    TowerTopPos = nil,
    IsLandedOnTower = false,
    IsExitingTower = false,

    -- Estados de paseo y comida matutina
    MorningEatingDone = false,
    PatternTick = tick(),
    CurrentActivePattern = "Zigzag",
    PatternStep = 1,
    WanderTarget = nil,
    CircleAngle = 0,
    LastPeriodicJump = tick(),
    BurstJumping = false
}

local PickUpRemote = nil
task.spawn(function()
    local rem = ReplicatedStorage:WaitForChild("Remotes", 5)
    local inter = rem and rem:WaitForChild("Interaction", 5)
    if inter then
        PickUpRemote = inter:WaitForChild("PickUpItem", 5)
    end
end)

-- ==============================================================================
-- 1. FÍSICAS DESBLOQUEADAS (ANTI-PESADEZ / LIBERTAD TOTAL DE SALTO)
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function unlockCharacterPhysics()
    local _, root, hum = getCharacterParts()
    if root then
        for _, obj in ipairs(root:GetChildren()) do
            if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") or obj.Name:find("TowerFlight") then
                obj:Destroy()
            end
        end
    end
    if hum then
        hum.PlatformStand = false
        hum.AutoRotate = true
    end
end

local function getOrCreateFlightPhysics(root)
    local bp = root:FindFirstChild("TowerFlightBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "TowerFlightBP"
        bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bp.P = 28000
        bp.D = 900
        bp.Position = root.Position
        bp.Parent = root
    end

    local bg = root:FindFirstChild("TowerFlightBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "TowerFlightBG"
        bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bg.CFrame = root.CFrame
        bg.Parent = root
    end

    return bp, bg
end

local function flyToPoint(targetPos, speed, stopDist)
    stopDist = stopDist or 2.5
    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    local bp = getOrCreateFlightPhysics(root)
    local timeout = tick() + 15.0

    while Config.Active and tick() < timeout do
        RunService.Heartbeat:Wait()
        local diff = targetPos - root.Position
        if diff.Magnitude <= stopDist then
            bp.Position = targetPos
            return true
        end
        local stepDir = diff.Unit
        bp.Position = root.Position + (stepDir * (speed * 0.1))
    end

    bp.Position = targetPos
    return false
end

-- ==============================================================================
-- 2. DETECCIÓN DE TORRE, ATERRIZAJE DE PIE Y SALIDA ELEVADA (PLATO)
-- ==============================================================================

local function findNearestWatchtower(myPos)
    local candidates = {}
    local searchFolders = {
        workspace:FindFirstChild("Structures"),
        workspace:FindFirstChild("Map"),
        workspace
    }

    for _, container in ipairs(searchFolders) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Model") then
                    local n = obj.Name:lower()
                    if n:find("watchtower") or n:find("tower") or n:find("torre") then
                        local cf, sz = obj:GetBoundingBox()
                        local dist = (Vector3.new(cf.Position.X, 0, cf.Position.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                        table.insert(candidates, { Model = obj, CFrame = cf, Size = sz, Dist = dist, Name = obj.Name })
                    end
                end
            end
        end
        if #candidates > 0 then break end
    end

    table.sort(candidates, function(a, b) return a.Dist < b.Dist end)

    if #candidates > 0 then
        local best = candidates[1]
        local topY = best.CFrame.Position.Y + (best.Size.Y * 0.5) + 1.2
        for _, desc in ipairs(best.Model:GetDescendants()) do
            if desc:IsA("BasePart") then
                local dn = desc.Name:lower()
                if dn:find("floor") or dn:find("platform") or dn:find("piso") or dn:find("stand") then
                    if desc.Position.Y > best.CFrame.Position.Y then
                        topY = math.max(topY, desc.Position.Y + 2.5)
                    end
                end
            end
        end
        return Vector3.new(best.CFrame.Position.X, topY, best.CFrame.Position.Z), best.Name, best.Dist
    end

    return nil, nil, nil
end

local function exitDishTowerSafely(towerPos)
    if State.IsExitingTower then return end
    State.IsExitingTower = true

    local _, root, _ = getCharacterParts()
    if root then
        -- 1. Subir verticalmente 10 studs para librar los bordes altos del plato
        local upPos = root.Position + Vector3.new(0, 10.0, 0)
        flyToPoint(upPos, Config.FlySpeed, 2.0)

        -- 2. Avanzar horizontalmente hacia afuera de la torre
        local outwardDir = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(towerPos.X, 0, towerPos.Z)).Unit
        if outwardDir.Magnitude < 0.1 then outwardDir = Vector3.new(1, 0, 0) end
        local clearEdgePos = upPos + (outwardDir * 18.0)
        flyToPoint(clearEdgePos, Config.FlySpeed, 2.0)

        -- 3. Liberar físicas completamente para caminar y saltar sin trabas
        unlockCharacterPhysics()
    end

    State.IsExitingTower = false
end

-- ==============================================================================
-- 3. CONTROL DE ARMAS ESTRICTO (SLOT 2 FIJO / SWAP 2 ⇄ 3 CADA 50s)
-- ==============================================================================

local function getHotbarToolName(slotNum)
    local slotStr = tostring(slotNum)
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")

    if bpg then
        for _, desc in ipairs(bpg:GetDescendants()) do
            if (desc.Name == slotStr or desc.Name == "Slot" .. slotStr) and desc:IsA("GuiObject") then
                for _, child in ipairs(desc:GetChildren()) do
                    if child:IsA("TextLabel") and child.Text ~= "" and child.Text ~= slotStr and not child.Text:match("^%d+$") then
                        return child.Text
                    elseif child:IsA("ObjectValue") and child.Value and child.Value:IsA("Tool") then
                        return child.Value.Name
                    end
                end
            end
        end

        for _, desc in ipairs(bpg:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.Text:gsub("%s+", "") == slotStr then
                local p = desc.Parent
                if p then
                    for _, child in ipairs(p:GetChildren()) do
                        if child:IsA("TextLabel") and child ~= desc and child.Text ~= "" and not child.Text:match("^%d+$") then
                            return child.Text
                        elseif child:IsA("ObjectValue") and child.Value and child.Value:IsA("Tool") then
                            return child.Value.Name
                        end
                    end
                end
            end
        end
    end

    -- Respaldo exacto de tu inventario
    if slotNum == 2 then return "LMG" end
    if slotNum == 3 then return "Bat" end
    return nil
end

local function enforceEquippedWeapon(targetToolName)
    if not targetToolName or targetToolName == "" then return end
    local char, _, hum = getCharacterParts()
    if not hum or hum.Health <= 0 then return end

    local inHand = char:FindFirstChildOfClass("Tool")

    -- Si ya la tiene en mano, NO tocar nada (evita desequipados involuntarios)
    if inHand and inHand.Name == targetToolName then
        return
    end

    -- Si tiene un arma distinta (o comida/Candy Bag), desequipar solo esa
    if inHand and inHand.Name ~= targetToolName then
        hum:UnequipTools()
        task.wait(0.05)
    end

    local bp = lp:FindFirstChild("Backpack")
    local toolToEquip = bp and bp:FindFirstChild(targetToolName)

    if toolToEquip and toolToEquip:IsA("Tool") then
        hum:EquipTool(toolToEquip)
    end
end

-- Bucle de verificación de arma cada 5 segundos
task.spawn(function()
    while true do
        task.wait(5.0)

        if Config.Active and Config.AutoEquipWeapon and not State.IsEating then
            local _, _, hum = getCharacterParts()
            if hum and hum.Health > 0 then
                if Config.SwapWeaponsEnabled then
                    if (tick() - State.LastSwapTick) >= Config.SwapInterval then
                        State.ActiveSlot = (State.ActiveSlot == 2) and 3 or 2
                        State.LastSwapTick = tick()
                    end
                else
                    -- Modo Fijo: SIEMPRE Slot 2
                    State.ActiveSlot = 2
                end

                local targetWeapon = getHotbarToolName(State.ActiveSlot)
                enforceEquippedWeapon(targetWeapon)
            end
        end
    end
end)

lp.CharacterAdded:Connect(function()
    task.wait(1.5)
    if Config.Active and Config.AutoEquipWeapon then
        local targetWeapon = getHotbarToolName(State.ActiveSlot)
        enforceEquippedWeapon(targetWeapon)
    end
end)

-- ==============================================================================
-- 4. ALIMENTACIÓN AUTOMÁTICA EN BASE (MECÁNICA ORIGINAL EXACTA)
-- ==============================================================================

local function getPlayerStats()
    local char, _, hum = getCharacterParts()
    if not hum then return 100, 100 end

    local hpPct = math.floor((hum.Health / math.max(hum.MaxHealth, 1)) * 100)
    local hunger = char:GetAttribute("Hunger") or lp:GetAttribute("Hunger") or 100
    local maxHunger = char:GetAttribute("MaxHunger") or lp:GetAttribute("MaxHunger") or 100
    local hungerPct = math.floor((hunger / maxHunger) * 100)

    return hpPct, hungerPct
end

local function findGroundFoodInBase(maxRadius)
    local _, root = getCharacterParts()
    if not root then return nil end

    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local best = nil
    local shortest = maxRadius

    for _, item in ipairs(dropped:GetChildren()) do
        local n = item.Name:lower()
        local itemType = tostring(item:GetAttribute("ItemType") or ""):lower()
        local isFood = (itemType == "food") or n:find("carrot") or n:find("beans") or n:find("mre") or n:find("chips")

        if isFood and item:GetAttribute("CanPickUp") ~= false then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part then
                local distFromBase = (Vector3.new(part.Position.X, 0, part.Position.Z) - BaseCenter).Magnitude
                if distFromBase <= maxRadius then
                    local distToMe = (part.Position - root.Position).Magnitude
                    if distToMe < shortest then
                        shortest = distToMe
                        best = { Item = item, Part = part, Dist = distToMe }
                    end
                end
            end
        end
    end
    return best
end

local function eatFood(foodItem)
    if State.IsEating or not PickUpRemote then return end
    if (tick() - State.LastEatTick) < Config.EatCooldown then return end

    local char, _, hum = getCharacterParts()
    if not hum or hum.Health <= 0 then return end

    State.IsEating = true
    local previousTool = char:FindFirstChildOfClass("Tool")

    pcall(function() PickUpRemote:FireServer(foodItem) end)

    local foodTool = nil
    local startWait = tick()
    while (tick() - startWait) < 0.6 do
        for _, cont in ipairs({char, lp:FindFirstChild("Backpack")}) do
            if cont then
                for _, item in ipairs(cont:GetChildren()) do
                    if item:IsA("Tool") and (item:GetAttribute("ItemType") == "Food" or item.Name:lower():find("carrot") or item.Name:lower():find("beans")) then
                        foodTool = item
                        break
                    end
                end
            end
        end
        if foodTool then break end
        task.wait(0.04)
    end

    if foodTool then
        if foodTool.Parent ~= char then
            hum:EquipTool(foodTool)
            task.wait(0.05)
        end
        pcall(function() foodTool:Activate() end)
        local useRemote = foodTool:FindFirstChild("Use") or foodTool:FindFirstChild("Consume")
        if useRemote and useRemote:IsA("RemoteEvent") then
            pcall(function() useRemote:FireServer() end)
        end
        task.wait(0.20)
    end

    -- Re-equipar el arma configurada inmediatamente
    local targetWeapon = getHotbarToolName(State.ActiveSlot)
    enforceEquippedWeapon(targetWeapon)

    State.LastEatTick = tick()
    State.IsEating = false
end

-- ==============================================================================
-- 5. EVASIÓN DE OBSTÁCULOS Y EVASIÓN DE ZOMBIES (15 STUDS)
-- ==============================================================================

-- Evasión de Zombies si está en el suelo (no en la torre)
local function getZombieAvoidanceVector(rootPos, scanDist)
    local avoidVec = Vector3.zero
    local count = 0
    local folder = workspace:FindFirstChild("Characters") or workspace

    for _, ent in ipairs(folder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and not Players:GetPlayerFromCharacter(ent) then
            local hum = ent:FindFirstChildOfClass("Humanoid")
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent.PrimaryPart
            if hum and hum.Health > 0 and eRoot then
                local diff = rootPos - eRoot.Position
                local dist = Vector3.new(diff.X, 0, diff.Z).Magnitude
                if dist <= scanDist and dist > 0.5 then
                    local pushDir = Vector3.new(diff.X, 0, diff.Z).Unit
                    local weight = (scanDist - dist) / scanDist
                    avoidVec = avoidVec + (pushDir * weight * 22)
                    count = count + 1
                end
            end
        end
    end
    return avoidVec, count
end

-- Evasión de muros, cercas y cajas con Raycasting
local function checkObstaclesAndSteer(root, moveDir)
    if not root or moveDir.Magnitude < 0.1 then return moveDir end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = RaycastFilterType.Exclude
    if lp.Character then
        rayParams.FilterDescendantsInstances = {lp.Character}
    end

    local forwardHit = workspace:Raycast(root.Position, moveDir * 6.0, rayParams)
    if forwardHit and forwardHit.Instance and forwardHit.Instance.CanCollide then
        -- Comprobar si es un obstáculo bajo saltando
        local highHit = workspace:Raycast(root.Position + Vector3.new(0, 3.2, 0), moveDir * 6.0, rayParams)
        if not highHit then
            local _, _, hum = getCharacterParts()
            if hum then hum.Jump = true end
            return moveDir
        else
            -- Muro alto: desviar a la derecha o izquierda
            local rightVec = Vector3.new(-moveDir.Z, 0, moveDir.X)
            local rightHit = workspace:Raycast(root.Position, rightVec * 6.5, rayParams)
            local leftHit = workspace:Raycast(root.Position, (-rightVec) * 6.5, rayParams)

            if not rightHit then
                return (moveDir + rightVec * 1.6).Unit
            elseif not leftHit then
                return (moveDir - rightVec * 1.6).Unit
            else
                return -moveDir -- Retorcer si está arrinconado
            end
        end
    end

    return moveDir
end

-- ==============================================================================
-- 6. MOTOR DE PASEO MATUTINO (20 SEGUNDOS POR MOVIMIENTO + EVASIÓN)
-- ==============================================================================

local PATTERNS = {
    "Zigzag",
    "Dando Vueltas",
    "En Cuadrado",
    "Siguiendo Compañeros",
    "Solo Saltando",
    "Zigzag en el Mismo Lugar",
    "Salto 5 Veces",
    "Dando Vueltas sobre Sí Mismo"
}

local function getNearestTeammate(myPos)
    local best = nil
    local shortest = math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local dist = (Vector3.new(r.Position.X, 0, r.Position.Z) - myPos).Magnitude
                if dist < shortest and dist < 120 then
                    shortest = dist
                    best = r
                end
            end
        end
    end
    return best
end

local function executeMorningMovement(char, root, hum)
    local now = tick()

    -- Salto periódico independiente cada 12 segundos
    if now - State.LastPeriodicJump >= Config.JumpInterval then
        hum.Jump = true
        State.LastPeriodicJump = now
    end

    -- Rotación cada 20 segundos
    local activeMode = Config.MovementPattern
    if Config.MovementPattern == "Aleatorio Total" then
        if now - State.PatternTick >= Config.PatternSwitchInterval then
            State.CurrentActivePattern = PATTERNS[math.random(1, #PATTERNS)]
            State.PatternTick = now
            State.WanderTarget = nil
            State.PatternStep = 1
        end
        activeMode = State.CurrentActivePattern
    end

    local rawMoveDir = Vector3.zero

    if activeMode == "Zigzag" then
        if not State.WanderTarget or (root.Position - State.WanderTarget).Magnitude <= 4 then
            local randAngle = math.random() * math.pi * 2
            local r = math.random(20, BASE_WANDER_RADIUS)
            State.WanderTarget = BaseCenter + Vector3.new(math.cos(randAngle) * r, 0, math.sin(randAngle) * r)
        end
        local toDest = (State.WanderTarget - root.Position).Unit
        local perp = Vector3.new(-toDest.Z, 0, toDest.X)
        local wave = perp * (math.sin(now * 3.5) * 14)
        rawMoveDir = ((toDest * 12) + wave).Unit

    elseif activeMode == "Dando Vueltas" then
        State.CircleAngle = State.CircleAngle + 0.08
        local r = 28
        local circPos = BaseCenter + Vector3.new(math.cos(State.CircleAngle) * r, 0, math.sin(State.CircleAngle) * r)
        rawMoveDir = (circPos - root.Position).Unit

    elseif activeMode == "En Cuadrado" then
        local size = 20
        local corners = {
            BaseCenter + Vector3.new(-size, 0, -size),
            BaseCenter + Vector3.new(size, 0, -size),
            BaseCenter + Vector3.new(size, 0, size),
            BaseCenter + Vector3.new(-size, 0, size)
        }
        local currentCorner = corners[State.PatternStep]
        if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(currentCorner.X, 0, currentCorner.Z)).Magnitude <= 4.5 then
            State.PatternStep = (State.PatternStep % 4) + 1
        end
        rawMoveDir = (corners[State.PatternStep] - root.Position).Unit

    elseif activeMode == "Siguiendo Compañeros" then
        local mate = getNearestTeammate(root.Position)
        if mate then
            local dist = (Vector3.new(mate.Position.X, 0, mate.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
            if dist > 8 then
                rawMoveDir = (mate.Position - root.Position).Unit
            end
        else
            rawMoveDir = (BaseCenter - root.Position).Unit
        end

    elseif activeMode == "Solo Saltando" then
        if now % 0.8 < 0.25 then hum.Jump = true end
        if not State.WanderTarget or (root.Position - State.WanderTarget).Magnitude <= 3 then
            local r = math.random(5, 18)
            local ang = math.random() * math.pi * 2
            State.WanderTarget = BaseCenter + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
        end
        rawMoveDir = (State.WanderTarget - root.Position).Unit

    elseif activeMode == "Zigzag en el Mismo Lugar" then
        local offset = math.sin(now * 5.0) * 8.0
        rawMoveDir = (BaseCenter + Vector3.new(offset, 0, 0) - root.Position).Unit

    elseif activeMode == "Salto 5 Veces" then
        if not State.BurstJumping then
            State.BurstJumping = true
            task.spawn(function()
                for _ = 1, 5 do
                    local _, _, h = getCharacterParts()
                    if h then h.Jump = true end
                    task.wait(0.45)
                end
                task.wait(2.5)
                State.BurstJumping = false
            end)
        end
        rawMoveDir = (BaseCenter - root.Position).Unit

    elseif activeMode == "Dando Vueltas sobre Sí Mismo" then
        local spinDir = Vector3.new(math.cos(now * 8), 0, math.sin(now * 8))
        root.CFrame = CFrame.lookAt(root.Position, root.Position + spinDir)
        return
    end

    -- Integrar Evasión de Obstáculos activa
    local steeredDir = checkObstaclesAndSteer(root, rawMoveDir)

    -- Mover
    if steeredDir.Magnitude > 0.1 then
        hum:MoveTo(root.Position + (steeredDir * 10))
    end
end

-- ==============================================================================
-- 7. BUCLE PRINCIPAL DE ESTADOS (TORRE, DÍA 90+, COMIDA Y PASEO)
-- ==============================================================================

local function isNightTime()
    local ws = workspace
    local isNight = ws:GetAttribute("Night")
    if isNight == nil then
        isNight = (Lighting.ClockTime >= 18.0 or Lighting.ClockTime <= 6.0)
    end
    return isNight
end

local function getCurrentDay()
    local d = workspace:GetAttribute("CurrentDay")
    if d and type(d) == "number" then return d end
    return 0
end

task.spawn(function()
    while true do
        task.wait(0.5)

        if not Config.Active then
            unlockCharacterPhysics()
            State.Status = "Script pausado"
            continue
        end

        local char, root, hum = getCharacterParts()
        if not root or not hum or hum.Health <= 0 then
            task.wait(1.5)
            continue
        end

        local currentDay = getCurrentDay()
        State.CurrentDay = currentDay
        local night = isNightTime()
        local _, hungerPct = getPlayerStats()

        -- ======================================================================
        -- CASO 1: DÍA 90 O SUPERIOR (GUARDIA EN Vector3.new(0.1, 0.9, -8))
        -- ======================================================================
        if currentDay >= Config.Day90Threshold then
            State.Day90Enforced = true
            unlockCharacterPhysics()

            local distTo90 = (root.Position - DAY_90_TARGET_POS).Magnitude
            if distTo90 > 2.5 then
                State.Status = string.format("⚠️ Día %d >= 90: Yendo a (0.1, 0.9, -8)", currentDay)
                hum:MoveTo(DAY_90_TARGET_POS)
            else
                State.Status = string.format("🛡️ Día %d: En guardia fija en (0.1, 0.9, -8)", currentDay)
            end

        -- ======================================================================
        -- CASO 2: NOCHE (TORRE / RESGUARDO / EVASIÓN DE ZOMBIES SI ESTÁ ABAJO)
        -- ======================================================================
        elseif night then
            State.Day90Enforced = false
            State.MorningEatingDone = false -- Reiniciar ciclo de comida para la siguiente mañana

            local towerTop, towerName = findNearestWatchtower(root.Position)

            if towerTop then
                State.CurrentTowerName = towerName
                State.TowerTopPos = towerTop
                local distToTop = (root.Position - towerTop).Magnitude

                -- Volar hacia la torre
                if distToTop > 4.5 then
                    State.IsLandedOnTower = false
                    State.Status = string.format("🌙 Volando a la cima de '%s'...", towerName)
                    flyToPoint(towerTop, Config.FlySpeed, 2.5)
                else
                    -- ATERRIZAJE: Suelta el vuelo y se para de pie
                    if not State.IsLandedOnTower then
                        unlockCharacterPhysics()
                        State.IsLandedOnTower = true
                    end

                    -- Vigilante anticaídas de la torre
                    if root.Position.Y < (towerTop.Y - 5.0) then
                        State.IsLandedOnTower = false
                        flyToPoint(towerTop, Config.FlySpeed, 2.0)
                    else
                        -- EN LA TORRE: No esquiva zombies, se queda quieto
                        State.Status = string.format("🌙 En la torre '%s' (Protegido)", towerName)
                    end
                end
            else
                -- SI NO HAY TORRE Y ESTÁ EN EL SUELO DE NOCHE: Esquivar zombies a 15 studs
                State.IsLandedOnTower = false
                unlockCharacterPhysics()

                local avoidVec, count = getZombieAvoidanceVector(root.Position, Config.ZombieEvadeDist)
                if count > 0 then
                    State.Status = string.format("⚠️ Noche sin torre: Esquivando %d zombies...", count)
                    local safeDir = checkObstaclesAndSteer(root, avoidVec.Unit)
                    hum:MoveTo(root.Position + (safeDir * 15))
                else
                    State.Status = "🌙 Noche sin torre: Buscando refugio..."
                    hum:MoveTo(BaseCenter)
                end
            end

        -- ======================================================================
        -- CASO 3: MAÑANA / DÍA (1° COMIDA HASTA 95%+ -> 2° PASEO RANDOM CON EVASIÓN)
        -- ======================================================================
        else
            State.Day90Enforced = false

            -- Si amanece arriba de la torre, salir volando por arriba del plato
            if State.TowerTopPos and (root.Position - State.TowerTopPos).Magnitude <= 14 then
                State.Status = "☀️ Saliendo por arriba del plato de la torre..."
                exitDishTowerSafely(State.TowerTopPos)
                State.TowerTopPos = nil
                State.IsLandedOnTower = false
            end

            unlockCharacterPhysics()

            -- Comprobar si hay zombies cerca en el suelo durante el día
            local avoidVec, count = getZombieAvoidanceVector(root.Position, Config.ZombieEvadeDist)
            if count > 0 then
                State.Status = string.format("🏃 Esquivando %d zombies cerca (15m)...", count)
                local safeDir = checkObstaclesAndSteer(root, avoidVec.Unit)
                hum:MoveTo(root.Position + (safeDir * 14))
                continue
            end

            -- PASO 1: PRIMERO BUSCAR COMIDA EN LA MAÑANA HASTA SACIARSE (>= 95%)
            if hungerPct < Config.FullHungerTarget and not State.MorningEatingDone then
                local foodTarget = findGroundFoodInBase(Config.EatScanRadius)
                if foodTarget then
                    State.Status = string.format("☀️ 1° Comiendo en base (Hambre: %d%%)", hungerPct)
                    if foodTarget.Dist > 5.0 then
                        local toFood = (foodTarget.Part.Position - root.Position).Unit
                        local steeredDir = checkObstaclesAndSteer(root, toFood)
                        hum:MoveTo(root.Position + (steeredDir * 10))
                    else
                        eatFood(foodTarget.Item)
                    end
                else
                    State.Status = string.format("☀️ Buscando comida en base... (Hambre: %d%%)", hungerPct)
                    local wanderDir = checkObstaclesAndSteer(root, (BaseCenter - root.Position).Unit)
                    hum:MoveTo(root.Position + (wanderDir * 10))
                end

            -- PASO 2: UNA VEZ LLENO, INICIAR PASEO CON MOVIMIENTOS RANDOM (20s C/U)
            else
                State.MorningEatingDone = true
                executeMorningMovement(char, root, hum)
                local curPatternName = (Config.MovementPattern == "Aleatorio Total") and State.CurrentActivePattern or Config.MovementPattern
                State.Status = string.format("☀️ 2° Paseando: %s (Hambre: %d%%)", curPatternName, hungerPct)
            end
        end
    end
end)

-- ==============================================================================
-- 8. INTERFAZ GRÁFICA NATIVA ROBLOX (SCREENGUI)
-- ==============================================================================

local function getSafeGuiParent()
    local success, res = pcall(function()
        if gethui then return gethui() end
        return CoreGui
    end)
    if success and res then return res end
    return lp:WaitForChild("PlayerGui")
end

local GuiParent = getSafeGuiParent()
local existing = GuiParent:FindFirstChild("BaseDefenderUniversalGuiV40")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BaseDefenderUniversalGuiV40"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 470, 0, 420)
MainFrame.Position = UDim2.new(0.5, -235, 0.5, -210)
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
TitleBar.Text = "   🏰 BASE DEFENDER V4.0 (COMIDA 1° + SLOT 2 FIJO)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 100)
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

-- Botón 1: Activar/Pausar
local ToggleBtn
ToggleBtn = createBtn("🟢 SCRIPT ACTIVO: ON", Color3.fromRGB(30, 150, 70), UDim2.new(0, 10, 0, 150), UDim2.new(0.48, -5, 0, 36), function()
    Config.Active = not Config.Active
    if Config.Active then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 70)
        ToggleBtn.Text = "🟢 SCRIPT ACTIVO: ON"
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
        ToggleBtn.Text = "🔴 SCRIPT ACTIVO: OFF"
        unlockCharacterPhysics()
    end
end)

-- Botón 2: Liberar Físicas
createBtn("🔓 LIBERAR FÍSICAS (0% PESADEZ)", Color3.fromRGB(45, 100, 180), UDim2.new(0.52, 0, 0, 150), UDim2.new(0.48, -10, 0, 36), function()
    unlockCharacterPhysics()
end)

-- Botón 3: Control de Arma (Slot 2 Fijo vs Swap 50s)
local SwapBtn
SwapBtn = createBtn("🔫 MODO ARMA: SOLO SLOT 2 (FIJO)", Color3.fromRGB(40, 130, 80), UDim2.new(0, 10, 0, 192), UDim2.new(1, -20, 0, 34), function()
    Config.SwapWeaponsEnabled = not Config.SwapWeaponsEnabled
    if Config.SwapWeaponsEnabled then
        SwapBtn.BackgroundColor3 = Color3.fromRGB(140, 45, 160)
        SwapBtn.Text = string.format("🔄 SWAP ACTIVO: SLOT 2 ⇄ 3 (CADA %ds)", Config.SwapInterval)
    else
        SwapBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 80)
        SwapBtn.Text = "🔫 MODO ARMA: SOLO SLOT 2 (FIJO)"
        State.ActiveSlot = 2
        local weaponName = getHotbarToolName(2)
        enforceEquippedWeapon(weaponName)
    end
end)

-- Botones 4 y 5: Ajuste tiempo de Swap (+5s / -5s)
createBtn("➖ TIEMPO SWAP (-5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0, 10, 0, 232), UDim2.new(0.48, -5, 0, 30), function()
    Config.SwapInterval = math.max(10, Config.SwapInterval - 5)
    if Config.SwapWeaponsEnabled then
        SwapBtn.Text = string.format("🔄 SWAP ACTIVO: SLOT 2 ⇄ 3 (CADA %ds)", Config.SwapInterval)
    end
end)

createBtn("➕ TIEMPO SWAP (+5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0.52, 0, 0, 232), UDim2.new(0.48, -10, 0, 30), function()
    Config.SwapInterval = math.min(180, Config.SwapInterval + 5)
    if Config.SwapWeaponsEnabled then
        SwapBtn.Text = string.format("🔄 SWAP ACTIVO: SLOT 2 ⇄ 3 (CADA %ds)", Config.SwapInterval)
    end
end)

-- Botón 6: Selector de Modos de Paseo (20s)
local PatternList = {
    "Aleatorio Total",
    "Zigzag",
    "Dando Vueltas",
    "En Cuadrado",
    "Siguiendo Compañeros",
    "Solo Saltando",
    "Zigzag en el Mismo Lugar",
    "Salto 5 Veces",
    "Dando Vueltas sobre Sí Mismo"
}
local curPatternIdx = 1

local PatternBtn
PatternBtn = createBtn(string.format("PASEO: %s (%ds)", Config.MovementPattern, Config.PatternSwitchInterval), Color3.fromRGB(190, 120, 20), UDim2.new(0, 10, 0, 268), UDim2.new(1, -20, 0, 32), function()
    curPatternIdx = curPatternIdx + 1
    if curPatternIdx > #PatternList then curPatternIdx = 1 end
    Config.MovementPattern = PatternList[curPatternIdx]
    PatternBtn.Text = string.format("PASEO: %s (%ds)", Config.MovementPattern, Config.PatternSwitchInterval)
    State.WanderTarget = nil
    State.PatternStep = 1
end)

-- Botones 7 y 8: Ajuste tiempo de paseo
createBtn("➖ TIEMPO PASEO (-5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0, 10, 0, 304), UDim2.new(0.48, -5, 0, 28), function()
    Config.PatternSwitchInterval = math.max(10, Config.PatternSwitchInterval - 5)
    PatternBtn.Text = string.format("PASEO: %s (%ds)", Config.MovementPattern, Config.PatternSwitchInterval)
end)

createBtn("➕ TIEMPO PASEO (+5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0.52, 0, 0, 304), UDim2.new(0.48, -10, 0, 28), function()
    Config.PatternSwitchInterval = math.min(90, Config.PatternSwitchInterval + 5)
    PatternBtn.Text = string.format("PASEO: %s (%ds)", Config.MovementPattern, Config.PatternSwitchInterval)
end)

-- Botones 9 y 10: Torre Manual y Salida del Plato
createBtn("🗼 VOLAR Y POSARSE EN TORRE", Color3.fromRGB(30, 120, 90), UDim2.new(0, 10, 0, 338), UDim2.new(0.48, -5, 0, 34), function()
    local _, root, _ = getCharacterParts()
    if root then
        local tTop, _ = findNearestWatchtower(root.Position)
        if tTop then
            flyToPoint(tTop, Config.FlySpeed, 2.5)
            unlockCharacterPhysics()
            State.IsLandedOnTower = true
        end
    end
end)

createBtn("🚪 SALIR DEL BORDE DE TORRE", Color3.fromRGB(160, 45, 55), UDim2.new(0.52, 0, 0, 338), UDim2.new(0.48, -10, 0, 34), function()
    local _, root, _ = getCharacterParts()
    if root and State.TowerTopPos then
        exitDishTowerSafely(State.TowerTopPos)
    else
        unlockCharacterPhysics()
    end
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "🏰\nV4.0"
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

-- Monitor visual de estado en tiempo real
task.spawn(function()
    while true do
        task.wait(0.5)

        local pHP, pHunger = getPlayerStats()
        local night = isNightTime()
        local dayNum = getCurrentDay()

        local tool2Name = getHotbarToolName(2) or "Vacío"
        local tool3Name = getHotbarToolName(3) or "Vacío"
        local activeToolName = (State.ActiveSlot == 2) and tool2Name or tool3Name

        local weaponModeText = Config.SwapWeaponsEnabled and string.format("Swap Activo (%ds)", Config.SwapInterval) or "Fijo (Sin Swap)"

        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Día: %d | Fase: %s | Salud: %d%% | Hambre: %d%%\n" ..
            "Torre: '%s' | %s\n" ..
            "Arma en Mano: Slot %d ['%s'] | Modo: %s\n" ..
            "  • Slot 2: '%s' | Slot 3: '%s'\n" ..
            "Evasión: Zombies (15m) + Muros/Cercas activos",
            State.Status,
            dayNum, night and "🌙 NOCHE" or "☀️ DÍA", pHP, pHunger,
            State.CurrentTowerName, State.IsLandedOnTower and "Posado de Pie" or "En Movimiento",
            State.ActiveSlot, activeToolName, weaponModeText,
            tool2Name, tool3Name
        )
    end
end)
