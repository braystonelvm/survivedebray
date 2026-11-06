-- ==============================================================================
-- BASE DEFENDER & TOWER WATCHDOG V3.5 (NATIVO ROBLOX - 0% LIBRERÍAS EXTERNAS)
-- Fijación Slot 2 / Swap 2⇄3 (50s) + Torre Plato Anti-Flotar + Paseo 20s
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local BaseCenter = Vector3.new(0, 0, 0)
local DAY_90_TARGET_POS = Vector3.new(0.1, 0.9, -8.0)
local BASE_WANDER_RADIUS = 80

local Config = {
    Active = true,
    FlySpeed = 70,
    Day90Threshold = 90,

    -- Alimentación de día
    EatScanRadius = 100,
    FullHungerTarget = 95,
    EatCooldown = 0.9,

    -- Control de Armas
    AutoEquipWeapon = true,
    SwapWeaponsEnabled = false, -- Por defecto FALSE: Solo mantiene el Slot 2 fijo sin cambiar
    SwapInterval = 50,          -- 50 segundos exactos si se activa el Swap

    -- Paseo matutino (20 segundos por cada movimiento aleatorio)
    MovementPattern = "Aleatorio Total",
    PatternSwitchInterval = 20, -- 20 segundos por cada patrón
    JumpInterval = 12           -- Salto independiente cada 12 segundos
}

local State = {
    CurrentDay = 0,
    Status = "Iniciando...",
    ActiveSlot = 2,             -- 2 (Primario) o 3 (Secundario)
    LastSwapTick = tick(),
    IsEating = false,
    LastEatTick = 0,
    Day90Enforced = false,

    -- Torre dinámica
    CurrentTowerName = "Buscando...",
    TowerTopPos = nil,
    IsLandedOnTower = false,
    IsExitingTower = false,

    -- Patrones de movimiento
    PatternTick = tick(),
    CurrentActivePattern = "Zigzag",
    PatternStep = 1,
    WanderTarget = nil,
    CircleAngle = 0,
    LastPeriodicJump = tick()
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

-- Destruye cualquier fuerza física residual para que el personaje se mueva y salte libremente
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

-- Salida elevada: sube 10 studs para librar las barandillas de la torre plato y avanza afuera
local function exitDishTowerSafely(towerPos)
    if State.IsExitingTower then return end
    State.IsExitingTower = true

    local _, root, _ = getCharacterParts()
    if root then
        -- 1. Subir verticalmente para superar el borde de la torre plato
        local upPos = root.Position + Vector3.new(0, 10.0, 0)
        flyToPoint(upPos, Config.FlySpeed, 2.0)

        -- 2. Moverse horizontalmente hacia el exterior
        local outwardDir = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(towerPos.X, 0, towerPos.Z)).Unit
        if outwardDir.Magnitude < 0.1 then outwardDir = Vector3.new(1, 0, 0) end
        local clearEdgePos = upPos + (outwardDir * 18.0)
        flyToPoint(clearEdgePos, Config.FlySpeed, 2.0)

        -- 3. Liberar físicas completamente para que caiga y camine sin ataduras
        unlockCharacterPhysics()
    end

    State.IsExitingTower = false
end

-- ==============================================================================
-- 3. MOTOR EXACTO DE ARMAS (BACKPACKGUI: SLOT 2 FIJO / SWAP 2 ⇄ 3)
-- ==============================================================================

-- Extrae el nombre exacto asignado al Slot 2 o 3 dentro de PlayerGui.BackpackGui
local function getHotbarToolName(slotNum)
    local slotStr = tostring(slotNum)
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")

    if bpg then
        -- 1. Buscar directamente por el nombre del Frame ("2", "3")
        local slotFrame = bpg:FindFirstChild(slotStr, true)
        if slotFrame and slotFrame:IsA("GuiObject") then
            for _, child in ipairs(slotFrame:GetChildren()) do
                if child:IsA("TextLabel") and child.Text ~= "" and child.Text ~= slotStr and not child.Text:match("^%d+$") then
                    return child.Text
                elseif child:IsA("ObjectValue") and child.Value and child.Value:IsA("Tool") then
                    return child.Value.Name
                end
            end
        end

        -- 2. Buscar por el texto de la casilla en BackpackGui
        for _, desc in ipairs(bpg:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.Text:gsub("%s+", "") == slotStr then
                local parent = desc.Parent
                if parent then
                    for _, child in ipairs(parent:GetChildren()) do
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

    -- Respaldo según tu reporte forense
    if slotNum == 2 then return "LMG" end
    if slotNum == 3 then return "Bat" end

    return nil
end

-- Mantiene en mano el arma seleccionada sin desequiparla repetidamente
local function enforceEquippedWeapon(targetToolName)
    if not targetToolName or targetToolName == "" then return end
    local char, _, hum = getCharacterParts()
    if not hum or hum.Health <= 0 then return end

    local currentTool = char:FindFirstChildOfClass("Tool")

    -- Si la herramienta en mano ya es la correcta, NO TOCAR NADA (evita que se guarde sola)
    if currentTool and currentTool.Name == targetToolName then
        return
    end

    -- Si tiene equipada otra cosa (como la Candy Bag o comida), desequiparla primero
    if currentTool and currentTool.Name ~= targetToolName then
        hum:UnequipTools()
        task.wait(0.06)
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
                -- LÓGICA DE SELECCIÓN:
                if Config.SwapWeaponsEnabled then
                    -- Intercambia estrictamente entre Slot 2 y Slot 3 cada 50 segundos
                    if (tick() - State.LastSwapTick) >= Config.SwapInterval then
                        State.ActiveSlot = (State.ActiveSlot == 2) and 3 or 2
                        State.LastSwapTick = tick()
                    end
                else
                    -- Modo normal: FIJO EN SLOT 2
                    State.ActiveSlot = 2
                end

                local targetWeaponName = getHotbarToolName(State.ActiveSlot)
                enforceEquippedWeapon(targetWeaponName)
            end
        end
    end
end)

-- Re-equipar automáticamente al revivir
lp.CharacterAdded:Connect(function()
    task.wait(1.5)
    if Config.Active and Config.AutoEquipWeapon then
        local targetWeaponName = getHotbarToolName(State.ActiveSlot)
        enforceEquippedWeapon(targetWeaponName)
    end
end)

-- ==============================================================================
-- 4. ALIMENTACIÓN AUTOMÁTICA EN BASE
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
        local isFood = (itemType == "food") or n:find("carrot") or n:find("beans") or n:find("mre")

        if isFood and item:GetAttribute("CanPickUp") ~= false then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part then
                local distBase = (Vector3.new(part.Position.X, 0, part.Position.Z) - BaseCenter).Magnitude
                if distBase <= maxRadius then
                    local d = (part.Position - root.Position).Magnitude
                    if d < shortest then
                        shortest = d
                        best = { Item = item, Part = part, Dist = d }
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
        if foodTool.Parent ~= char then hum:EquipTool(foodTool); task.wait(0.05) end
        pcall(function() foodTool:Activate() end)
        task.wait(0.20)
    end

    -- Re-equipar arma de inmediato tras comer
    local targetWeaponName = getHotbarToolName(State.ActiveSlot)
    enforceEquippedWeapon(targetWeaponName)

    State.LastEatTick = tick()
    State.IsEating = false
end

-- ==============================================================================
-- 5. PASEO MATUTINO (20 SEGUNDOS POR MOVIMIENTO + SALTO CADA 12s)
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

    -- Salto ocasional cada 12 segundos
    if now - State.LastPeriodicJump >= Config.JumpInterval then
        hum.Jump = true
        State.LastPeriodicJump = now
    end

    -- Rotación cada 20 segundos si está en 'Aleatorio Total'
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

    -- Ejecución de patrones
    if activeMode == "Zigzag" then
        if not State.WanderTarget or (root.Position - State.WanderTarget).Magnitude <= 4 then
            local randAngle = math.random() * math.pi * 2
            local r = math.random(20, BASE_WANDER_RADIUS)
            State.WanderTarget = BaseCenter + Vector3.new(math.cos(randAngle) * r, 0, math.sin(randAngle) * r)
        end
        local toDest = (State.WanderTarget - root.Position).Unit
        local perp = Vector3.new(-toDest.Z, 0, toDest.X)
        local wave = perp * (math.sin(now * 3.5) * 14)
        hum:MoveTo(root.Position + (toDest * 12) + wave)

    elseif activeMode == "Dando Vueltas" then
        State.CircleAngle = State.CircleAngle + 0.08
        local r = 28
        local circPos = BaseCenter + Vector3.new(math.cos(State.CircleAngle) * r, 0, math.sin(State.CircleAngle) * r)
        hum:MoveTo(circPos)

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
        hum:MoveTo(corners[State.PatternStep])

    elseif activeMode == "Siguiendo Compañeros" then
        local mate = getNearestTeammate(root.Position)
        if mate then
            local dist = (Vector3.new(mate.Position.X, 0, mate.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
            if dist > 8 then
                hum:MoveTo(mate.Position)
            else
                hum:MoveTo(root.Position)
            end
        else
            hum:MoveTo(BaseCenter)
        end

    elseif activeMode == "Solo Saltando" then
        if now % 0.8 < 0.2 then
            hum.Jump = true
        end
        if not State.WanderTarget or (root.Position - State.WanderTarget).Magnitude <= 3 then
            local r = math.random(5, 18)
            local ang = math.random() * math.pi * 2
            State.WanderTarget = BaseCenter + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
        end
        hum:MoveTo(State.WanderTarget)

    elseif activeMode == "Zigzag en el Mismo Lugar" then
        local offset = math.sin(now * 5.0) * 8.0
        hum:MoveTo(BaseCenter + Vector3.new(offset, 0, 0))

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
        hum:MoveTo(BaseCenter)

    elseif activeMode == "Dando Vueltas sobre Sí Mismo" then
        local spinDir = Vector3.new(math.cos(now * 8), 0, math.sin(now * 8))
        root.CFrame = CFrame.lookAt(root.Position, root.Position + spinDir)
        hum:MoveTo(root.Position)
    end
end

-- ==============================================================================
-- 6. BUCLE PRINCIPAL DE ESTADOS
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

        -- CASO 1: DÍA 90 O SUPERIOR (GUARDIA EN Vector3.new(0.1, 0.9, -8))
        if currentDay >= Config.Day90Threshold then
            State.Day90Enforced = true
            unlockCharacterPhysics()

            local distTo90 = (root.Position - DAY_90_TARGET_POS).Magnitude
            if distTo90 > 2.5 then
                State.Status = string.format("⚠️ Día %d >= 90: Yendo a guardia (0.1, 0.9, -8)", currentDay)
                hum:MoveTo(DAY_90_TARGET_POS)
            else
                State.Status = string.format("🛡️ Día %d: En guardia fija en (0.1, 0.9, -8)", currentDay)
            end

        -- CASO 2: NOCHE (BUSCA TORRE, VUELA, SE POSA DE PIE SIN FLOTAR)
        elseif night then
            State.Day90Enforced = false
            local towerTop, towerName, towerDist = findNearestWatchtower(root.Position)

            if towerTop then
                State.CurrentTowerName = towerName
                State.TowerTopPos = towerTop
                local distToTop = (root.Position - towerTop).Magnitude

                if distToTop > 4.5 then
                    State.IsLandedOnTower = false
                    State.Status = string.format("🌙 Volando a la torre '%s'...", towerName)
                    flyToPoint(towerTop, Config.FlySpeed, 2.5)
                else
                    -- SOLTAR VUELO: Se posa de pie en el piso de la torre sin flotar
                    if not State.IsLandedOnTower then
                        unlockCharacterPhysics()
                        State.IsLandedOnTower = true
                    end

                    -- Si cae de la torre, reactivar vuelo y volver a subir
                    if root.Position.Y < (towerTop.Y - 5.0) then
                        State.IsLandedOnTower = false
                        flyToPoint(towerTop, Config.FlySpeed, 2.0)
                    else
                        State.Status = string.format("🌙 Posado en plataforma de '%s'", towerName)
                    end
                end
            else
                State.Status = "⚠️ Noche: Buscando torre..."
            end

        -- CASO 3: DÍA / MAÑANA (SALIDA POR ARRIBA DEL PLATO + COMIDA + PASEO)
        else
            State.Day90Enforced = false

            -- Si amanece arriba de la torre, subir por arriba del plato y salir
            if State.TowerTopPos and (root.Position - State.TowerTopPos).Magnitude <= 14 then
                State.Status = "☀️ Saliendo por arriba de la torre plato..."
                exitDishTowerSafely(State.TowerTopPos)
                State.TowerTopPos = nil
                State.IsLandedOnTower = false
            end

            unlockCharacterPhysics()

            -- Comer si hambre < 95%
            if hungerPct < Config.FullHungerTarget then
                local foodTarget = findGroundFoodInBase(Config.EatScanRadius)
                if foodTarget then
                    State.Status = string.format("☀️ Comiendo en base (Hambre: %d%%)", hungerPct)
                    if foodTarget.Dist > 5.0 then
                        hum:MoveTo(foodTarget.Part.Position)
                    else
                        eatFood(foodTarget.Item)
                    end
                else
                    executeMorningMovement(char, root, hum)
                end
            else
                -- Paseo matutino activo (20s por movimiento)
                executeMorningMovement(char, root, hum)
                local curPatternName = (Config.MovementPattern == "Aleatorio Total") and State.CurrentActivePattern or Config.MovementPattern
                State.Status = string.format("☀️ Paseo: %s (Hambre: %d%%)", curPatternName, hungerPct)
            end
        end
    end
end)

-- ==============================================================================
-- 7. INTERFAZ GRÁFICA NATIVA ROBLOX (SCREENGUI)
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
local existing = GuiParent:FindFirstChild("BaseDefenderUniversalGuiV35")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BaseDefenderUniversalGuiV35"
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
TitleBar.Text = "   🏰 BASE DEFENDER V3.5 (SLOT 2 FIJO / SWAP 50s)"
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

-- Botón 1: Encender / Apagar
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

-- Botón 2: Desbloquear Físicas
createBtn("🔓 LIBERAR FÍSICAS (PESADEZ 0%)", Color3.fromRGB(45, 100, 180), UDim2.new(0.52, 0, 0, 150), UDim2.new(0.48, -10, 0, 36), function()
    unlockCharacterPhysics()
end)

-- Botón 3: Control de Armas (SLOT 2 FIJO vs SWAP 2 ⇄ 3 CADA 50s)
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

-- Botones 4 y 5: Ajuste de tiempo de Swap (+5s / -5s)
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

-- Botón 6: Selector de Modos de Paseo
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

-- Botones 7 y 8: Ajuste tiempo de rotación de paseo (20s)
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
FloatBtn.Text = "🏰\nV3.5"
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
            "Paseo: %s (Rotación c/%ds | Salto c/12s)",
            State.Status,
            dayNum, night and "🌙 NOCHE" or "☀️ DÍA", pHP, pHunger,
            State.CurrentTowerName, State.IsLandedOnTower and "Posado de Pie" or "En Movimiento",
            State.ActiveSlot, activeToolName, weaponModeText,
            tool2Name, tool3Name,
            (Config.MovementPattern == "Aleatorio Total") and ("Ciclo (" .. State.CurrentActivePattern .. ")") or Config.MovementPattern,
            Config.PatternSwitchInterval
        )
    end
end)
