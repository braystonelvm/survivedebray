-- ==============================================================================
-- BASE DEFENDER & TOWER WATCHDOG V3.0 (SUPER UNLOCKED - NATIVO ROBLOX)
-- Físicas Libres + Salida de Torre Elevada + Mapeo BackpackGui + 9 Modos de Paseo
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

    -- Comida
    EatScanRadius = 100,
    FullHungerTarget = 95,
    EatCooldown = 0.9,

    -- Armas (Slots basados en BackpackGui)
    AutoEquipWeapon = true,
    PrimarySlot = 2,           -- Slot 2 por defecto (ej. LMG)
    SecondarySlot = 3,         -- Slot 3 por defecto (ej. Bat)
    SwapWeaponsEnabled = false,
    SwapInterval = 30,

    -- Movimiento Matutino
    MovementPattern = "Aleatorio Total", -- Modo de paseo por defecto
    PatternSwitchInterval = 15,         -- Tiempo de rotación si está en Aleatorio Total
    JumpInterval = 12                   -- Salto ocasional cada 12 segundos
}

local State = {
    CurrentDay = 0,
    Status = "Iniciando...",
    CurrentSlot = 2,
    LastSwapTick = tick(),
    IsEating = false,
    LastEatTick = 0,
    Day90Enforced = false,
    CurrentTowerName = "Buscando...",
    TowerTopPos = nil,
    IsLandedOnTower = false,
    LastPeriodicJump = tick(),

    -- Variables de patrones de paseo
    PatternTick = tick(),
    CurrentActivePattern = "Zigzag",
    PatternStep = 1,
    WanderTarget = nil,
    CircleAngle = 0
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
-- 1. FÍSICAS TOTALMENTE LIBERADAS (ANTI-PESADEZ / ANTI-TRABAS)
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function unlockCharacterPhysics()
    local char, root, hum = getCharacterParts()
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
-- 2. DETECCIÓN DE TORRE DINÁMICA & SALIDA ELEVADA (PLATO)
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

-- Descenso inteligente para salir del plato de la torre
local function exitDishTowerSafely(towerPos)
    local _, root, _ = getCharacterParts()
    if not root then return end

    -- 1. Elevarse 9 studs sobre la barandilla
    local upPos = root.Position + Vector3.new(0, 9.0, 0)
    flyToPoint(upPos, Config.FlySpeed, 2.0)

    -- 2. Desplazarse horizontalmente hacia afuera de la torre
    local outwardDir = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(towerPos.X, 0, towerPos.Z)).Unit
    if outwardDir.Magnitude < 0.1 then outwardDir = Vector3.new(1, 0, 0) end
    local clearEdgePos = upPos + (outwardDir * 16.0)
    flyToPoint(clearEdgePos, Config.FlySpeed, 2.0)

    -- 3. Soltar físicas limpiamente para descender a pie
    unlockCharacterPhysics()
end

-- ==============================================================================
-- 3. SELECTOR PRECISO DE ARMAS VÍA BACKPACKGUI (SIN CONFUSIONES)
-- ==============================================================================

local function getToolNameFromSlot(slotNum)
    local slotStr = (slotNum == 10) and "0" or tostring(slotNum)
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")

    if bpg then
        for _, desc in ipairs(bpg:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible then
                local txt = desc.Text:gsub("%s+", "")
                if txt == slotStr then
                    local frame = desc.Parent
                    for _, child in ipairs(frame:GetChildren()) do
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

    -- Si no detectó por BackpackGui, buscar en la lista indexada
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local pool = {}
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then table.insert(pool, t.Name) end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(pool, t.Name) end
        end
    end

    return pool[slotNum]
end

local function equipToolByName(toolName)
    if not toolName or toolName == "" then return end
    local char, _, hum = getCharacterParts()
    if not hum or hum.Health <= 0 then return end

    local currentTool = char:FindFirstChildOfClass("Tool")
    if currentTool and currentTool.Name == toolName then
        return -- Ya la tiene en mano
    end

    local bp = lp:FindFirstChild("Backpack")
    local found = bp and bp:FindFirstChild(toolName)

    if found and found:IsA("Tool") then
        if currentTool then
            hum:UnequipTools()
            task.wait(0.05)
        end
        hum:EquipTool(found)
    end
end

local function syncWeaponSlot(slotNum)
    local toolName = getToolNameFromSlot(slotNum)
    if toolName then
        equipToolByName(toolName)
    end
end

-- Bucle de armas cada 5 segundos y alternador (Swap)
task.spawn(function()
    while true do
        task.wait(5.0)
        if Config.Active and Config.AutoEquipWeapon then
            local _, _, hum = getCharacterParts()
            if hum and hum.Health > 0 then
                if Config.SwapWeaponsEnabled then
                    if (tick() - State.LastSwapTick) >= Config.SwapInterval then
                        State.CurrentSlot = (State.CurrentSlot == Config.PrimarySlot) and Config.SecondarySlot or Config.PrimarySlot
                        State.LastSwapTick = tick()
                    end
                else
                    State.CurrentSlot = Config.PrimarySlot
                end
                syncWeaponSlot(State.CurrentSlot)
            end
        end
    end
end)

-- Re-equipar inmediatamente al revivir
lp.CharacterAdded:Connect(function()
    task.wait(1.5)
    if Config.Active and Config.AutoEquipWeapon then
        syncWeaponSlot(State.CurrentSlot)
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

    State.LastEatTick = tick()
    State.IsEating = false
end

-- ==============================================================================
-- 5. MOTOR DE MOVIMIENTOS MATUTINOS (9 MODOS CONFIGURABLES)
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

    -- 1. Salto ocasional independiente cada 12 segundos
    if now - State.LastPeriodicJump >= Config.JumpInterval then
        hum.Jump = true
        State.LastPeriodicJump = now
    end

    -- 2. Rotación si está en "Aleatorio Total"
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

    -- 3. Ejecución del patrón activo
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
                for i = 1, 5 do
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
-- 6. BUCLE PRINCIPAL DE ESTADOS (TORRE, DÍA 90+ Y PASEO)
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

        -- CASO 1: DÍA 90 O SUPERIOR (GUARDIA FIJA EN Vector3.new(0.1, 0.9, -8))
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

        -- CASO 2: NOCHE (BUSCA CUALQUIER TORRE, SUBE Y SUELTA EL VUELO ARRIBA)
        elseif night then
            State.Day90Enforced = false
            local towerTop, towerName, towerDist = findNearestWatchtower(root.Position)

            if towerTop then
                State.CurrentTowerName = towerName
                State.TowerTopPos = towerTop
                local distToTop = (root.Position - towerTop).Magnitude

                -- Si está lejos de la cima, volar
                if distToTop > 4.5 then
                    State.IsLandedOnTower = false
                    State.Status = string.format("🌙 Volando a la cima de '%s'...", towerName)
                    flyToPoint(towerTop, Config.FlySpeed, 2.5)
                else
                    -- REQUISITO: Soltar el vuelo arriba para posarse de pie y no quedarse flotando
                    if not State.IsLandedOnTower then
                        unlockCharacterPhysics()
                        State.IsLandedOnTower = true
                    end

                    -- Vigilante anticaídas: si cae de la plataforma, reactiva vuelo
                    if root.Position.Y < (towerTop.Y - 5.0) then
                        State.IsLandedOnTower = false
                        flyToPoint(towerTop, Config.FlySpeed, 2.0)
                    else
                        State.Status = string.format("🌙 Posado de pie en la torre '%s'", towerName)
                    end
                end
            else
                State.Status = "⚠️ Noche: Buscando torre..."
            end

        -- CASO 3: MAÑANA / DÍA (SALIDA ELEVADA DE LA TORRE + COMIDA + PASEO RANDOM)
        else
            State.Day90Enforced = false

            -- Si amanece y sigue arriba de la torre, realizar la salida elevada sobre el borde plato
            if State.TowerTopPos and (root.Position - State.TowerTopPos).Magnitude <= 12 then
                State.Status = "☀️ Saliendo por arriba del borde de la torre..."
                exitDishTowerSafely(State.TowerTopPos)
                State.TowerTopPos = nil
                State.IsLandedOnTower = false
            end

            unlockCharacterPhysics()

            -- Comer si el hambre < 95%
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
                -- Paseo activo con los modos configurados
                executeMorningMovement(char, root, hum)
                State.Status = string.format("☀️ Paseo: %s (Hambre: %d%%)", (Config.MovementPattern == "Aleatorio Total") and State.CurrentActivePattern or Config.MovementPattern, hungerPct)
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
local existing = GuiParent:FindFirstChild("BaseDefenderUnlockedGuiV30")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BaseDefenderUnlockedGuiV30"
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
TitleBar.Text = "   🏰 BASE DEFENDER V3.0 (SUPER UNLOCKED)"
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

-- Botón 2: Liberar Físicas / Saltar Inmediato
createBtn("🔓 DESBLOQUEAR FÍSICAS (NORMAL)", Color3.fromRGB(45, 100, 180), UDim2.new(0.52, 0, 0, 150), UDim2.new(0.48, -10, 0, 36), function()
    unlockCharacterPhysics()
end)

-- Botón 3: Selector de Modos de Paseo Matutino
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
PatternBtn = createBtn("PASEO: " .. Config.MovementPattern, Color3.fromRGB(190, 120, 20), UDim2.new(0, 10, 0, 192), UDim2.new(1, -20, 0, 34), function()
    curPatternIdx = curPatternIdx + 1
    if curPatternIdx > #PatternList then curPatternIdx = 1 end
    Config.MovementPattern = PatternList[curPatternIdx]
    PatternBtn.Text = "PASEO: " .. Config.MovementPattern
    State.WanderTarget = nil
    State.PatternStep = 1
end)

-- Botón 4: Toggle Intercambio de Armas (Slot 2 ⇄ Slot 3)
local SwapBtn
SwapBtn = createBtn("🔄 SWAP ARMAS (SLOT 2 ⇄ 3): OFF", Color3.fromRGB(50, 55, 70), UDim2.new(0, 10, 0, 232), UDim2.new(1, -20, 0, 32), function()
    Config.SwapWeaponsEnabled = not Config.SwapWeaponsEnabled
    if Config.SwapWeaponsEnabled then
        SwapBtn.BackgroundColor3 = Color3.fromRGB(140, 45, 160)
        SwapBtn.Text = string.format("🔄 SWAP ARMAS: ON (CADA %ds)", Config.SwapInterval)
    else
        SwapBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        SwapBtn.Text = "⚪ SOLO ARMA SLOT 2 (FIJA)"
        State.CurrentSlot = Config.PrimarySlot
        syncWeaponSlot(Config.PrimarySlot)
    end
end)

-- Botones 5 y 6: Ajustar Slot Primario (1 al 10)
local SlotLabelBtn
SlotLabelBtn = createBtn(string.format("SLOT PRIMARIO: #%d", Config.PrimarySlot), Color3.fromRGB(40, 45, 60), UDim2.new(0, 10, 0, 270), UDim2.new(0.48, -5, 0, 30), function()
    Config.PrimarySlot = Config.PrimarySlot + 1
    if Config.PrimarySlot > 10 then Config.PrimarySlot = 1 end
    SlotLabelBtn.Text = string.format("SLOT PRIMARIO: #%d", Config.PrimarySlot)
    State.CurrentSlot = Config.PrimarySlot
    syncWeaponSlot(Config.PrimarySlot)
end)

local SecSlotLabelBtn
SecSlotLabelBtn = createBtn(string.format("SLOT SWAP: #%d", Config.SecondarySlot), Color3.fromRGB(40, 45, 60), UDim2.new(0.52, 0, 0, 270), UDim2.new(0.48, -10, 0, 30), function()
    Config.SecondarySlot = Config.SecondarySlot + 1
    if Config.SecondarySlot > 10 then Config.SecondarySlot = 1 end
    SecSlotLabelBtn.Text = string.format("SLOT SWAP: #%d", Config.SecondarySlot)
end)

-- Botones 7 y 8: Ajuste de tiempos
createBtn("➖ SWAP (-5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0, 10, 0, 306), UDim2.new(0.48, -5, 0, 28), function()
    Config.SwapInterval = math.max(5, Config.SwapInterval - 5)
    if Config.SwapWeaponsEnabled then
        SwapBtn.Text = string.format("🔄 SWAP ARMAS: ON (CADA %ds)", Config.SwapInterval)
    end
end)

createBtn("➕ SWAP (+5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0.52, 0, 0, 306), UDim2.new(0.48, -10, 0, 28), function()
    Config.SwapInterval = math.min(120, Config.SwapInterval + 5)
    if Config.SwapWeaponsEnabled then
        SwapBtn.Text = string.format("🔄 SWAP ARMAS: ON (CADA %ds)", Config.SwapInterval)
    end
end)

-- Botón 9: Subir a Torre Manual y Salir Limpio
createBtn("🗼 VOLAR A TORRE / POSARSE", Color3.fromRGB(30, 120, 90), UDim2.new(0, 10, 0, 340), UDim2.new(0.48, -5, 0, 34), function()
    local _, root, _ = getCharacterParts()
    if root then
        local tTop, tName = findNearestWatchtower(root.Position)
        if tTop then
            flyToPoint(tTop, Config.FlySpeed, 2.5)
            unlockCharacterPhysics()
        end
    end
end)

createBtn("🚪 SALIR DEL PLATO DE TORRE", Color3.fromRGB(160, 45, 55), UDim2.new(0.52, 0, 0, 340), UDim2.new(0.48, -10, 0, 34), function()
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
FloatBtn.Text = "🏰\nV3.0"
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

        local toolPrimName = getToolNameFromSlot(Config.PrimarySlot) or "Vacío"
        local toolSecName = getToolNameFromSlot(Config.SecondarySlot) or "Vacío"

        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Día: %d | Fase: %s | Salud: %d%% | Hambre: %d%%\n" ..
            "Torre Activa: '%s' | Torre Plato: %s\n" ..
            "Arma en Mano: Slot %d | Prim: '%s' | Sec: '%s'\n" ..
            "Modo Paseo: %s (Salto c/12s)",
            State.Status,
            dayNum, night and "🌙 NOCHE" or "☀️ DÍA", pHP, pHunger,
            State.CurrentTowerName, State.IsLandedOnTower and "Posado (Pie)" or "En Suelo",
            State.CurrentSlot, toolPrimName, toolSecName,
            (Config.MovementPattern == "Aleatorio Total") and ("Ciclo (" .. State.CurrentActivePattern .. ")") or Config.MovementPattern
        )
    end
end)
