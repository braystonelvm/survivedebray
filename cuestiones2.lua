-- ==============================================================================
-- BASE DEFENDER & TOWER WATCHDOG V2.5 (NATIVO - 0% LAG / 0% ERRORES)
-- Paseo Aleatorio de Mañana + Selector Exacto Hotbar (Slot 2 / Swap 3) + Torre
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
local BASE_WANDER_RADIUS = 85 -- Radio dentro de la base para caminar de día

local Config = {
    Active = true,
    FlySpeed = 65,

    -- Día 90+
    Day90Threshold = 90,

    -- Búsqueda de comida y paseo matutino
    EatScanRadius = 100,        -- Rango máximo para buscar comida en la base
    FullHungerTarget = 95,      -- Umbral de hambre para saciarse
    EatCooldown = 0.9,

    -- Armas (Slots directos 1 al 9 y 0)
    AutoEquipWeapon = true,     -- Asegura tener siempre el arma activa
    SwapWeaponsEnabled = false, -- Alternar entre arma 2 y 3
    SwapInterval = 30           -- Segundos entre intercambio (configurable)
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
    WanderTarget = nil,
    NextWanderTick = 0
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
-- 1. IDENTIFICACIÓN Y SELECCIÓN EXACTA DE SLOTS DE LA HOTBAR (1 AL 9 Y 0)
-- ==============================================================================

local KeyCodeBySlot = {
    [1] = Enum.KeyCode.One,
    [2] = Enum.KeyCode.Two,
    [3] = Enum.KeyCode.Three,
    [4] = Enum.KeyCode.Four,
    [5] = Enum.KeyCode.Five,
    [6] = Enum.KeyCode.Six,
    [7] = Enum.KeyCode.Seven,
    [8] = Enum.KeyCode.Eight,
    [9] = Enum.KeyCode.Nine,
    [10] = Enum.KeyCode.Zero
}

-- Inspecciona la barra de acceso directo para extraer el objeto exacto de ese slot
local function getToolFromHotbarSlot(slotNum)
    local targetTool = nil
    local targetToolName = nil

    -- 1. Revisar la barra nativa CoreGui (Backpack de Roblox)
    pcall(function()
        local robloxGui = CoreGui:FindFirstChild("RobloxGui")
        local backpack = robloxGui and robloxGui:FindFirstChild("Backpack")
        local hotbar = backpack and backpack:FindFirstChild("Hotbar")
        if hotbar then
            for _, slotFrame in ipairs(hotbar:GetChildren()) do
                local isMatch = false
                local numLabel = slotFrame:FindFirstChild("NumberLabel")
                if numLabel then
                    local txt = numLabel.Text
                    if txt == tostring(slotNum) or (slotNum == 10 and (txt == "0" or txt == "10")) then
                        isMatch = true
                    end
                elseif slotFrame.Name == "Slot" .. tostring(slotNum) or slotFrame.Name == tostring(slotNum) then
                    isMatch = true
                end

                if isMatch then
                    local toolVal = slotFrame:FindFirstChild("Tool")
                    if toolVal and toolVal:IsA("ObjectValue") and toolVal.Value and toolVal.Value:IsA("Tool") then
                        targetTool = toolVal.Value
                        return
                    end
                    local nameLabel = slotFrame:FindFirstChild("ToolName") or slotFrame:FindFirstChild("ToolNameLabel")
                    if not nameLabel then
                        for _, d in ipairs(slotFrame:GetChildren()) do
                            if d:IsA("TextLabel") and d ~= numLabel and d.Text ~= "" then
                                nameLabel = d
                                break
                            end
                        end
                    end
                    if nameLabel and nameLabel.Text ~= "" then
                        targetToolName = nameLabel.Text
                    end
                    return
                end
            end
        end
    end)

    if targetTool and targetTool.Parent then return targetTool end

    -- 2. Revisar si la barra es una GUI personalizada en PlayerGui
    if not targetToolName then
        pcall(function()
            local pg = lp:FindFirstChild("PlayerGui")
            if pg then
                for _, gui in ipairs(pg:GetChildren()) do
                    if gui:IsA("ScreenGui") and gui.Enabled then
                        for _, desc in ipairs(gui:GetDescendants()) do
                            if desc:IsA("Frame") or desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
                                local numLabel = desc:FindFirstChild("NumberLabel")
                                local isMatch = false
                                if numLabel and (numLabel.Text == tostring(slotNum) or (slotNum == 10 and numLabel.Text == "0")) then
                                    isMatch = true
                                elseif desc.Name == "Slot" .. tostring(slotNum) or desc.Name == tostring(slotNum) then
                                    isMatch = true
                                end

                                if isMatch then
                                    local toolVal = desc:FindFirstChild("Tool") or desc:FindFirstChildWhichIsA("ObjectValue")
                                    if toolVal and toolVal.Value and toolVal.Value:IsA("Tool") then
                                        targetTool = toolVal.Value
                                        return
                                    end
                                    for _, d in ipairs(desc:GetChildren()) do
                                        if d:IsA("TextLabel") and d ~= numLabel and d.Text ~= "" then
                                            targetToolName = d.Text
                                            break
                                        end
                                    end
                                    if targetToolName then return end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    if targetTool and targetTool.Parent then return targetTool end

    -- 3. Si se extrajo el nombre exacto de la casilla, buscar esa herramienta específica
    if targetToolName and targetToolName ~= "" then
        local char = lp.Character
        if char then
            local t = char:FindFirstChild(targetToolName)
            if t and t:IsA("Tool") then return t end
        end
        local bp = lp:FindFirstChild("Backpack")
        if bp then
            local t = bp:FindFirstChild(targetToolName)
            if t and t:IsA("Tool") then return t end
        end
    end

    return nil
end

-- Limpia cualquier arma secundaria equipada por error y sostiene solo el slot seleccionado
local function equipSlotClean(slotNum)
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local tool = getToolFromHotbarSlot(slotNum)

    if tool then
        -- Si ya la tiene en mano, no hacer nada para evitar parpadeos
        if tool.Parent == char then
            return
        end

        -- Si tiene otra cosa equipada (como la mochila o un objeto del inventario), desequiparla primero
        local equipped = char:FindFirstChildOfClass("Tool")
        if equipped and equipped ~= tool then
            hum:UnequipTools()
            task.wait(0.06)
        end

        hum:EquipTool(tool)
    else
        -- Respaldo con pulsación de tecla virtual hacia el hotbar
        local vim = game:GetService("VirtualInputManager")
        local key = KeyCodeBySlot[slotNum]
        if vim and key then
            pcall(function()
                vim:SendKeyEvent(true, key, false, game)
                task.wait(0.04)
                vim:SendKeyEvent(false, key, false, game)
            end)
        end
    end
end

-- Bucle de verificación de armas cada 5 segundos y alternador (Swap)
task.spawn(function()
    while true do
        task.wait(5.0)

        if Config.Active and Config.AutoEquipWeapon then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if hum and hum.Health > 0 then
                if Config.SwapWeaponsEnabled then
                    if (tick() - State.LastSwapTick) >= Config.SwapInterval then
                        State.CurrentSlot = (State.CurrentSlot == 2) and 3 or 2
                        State.LastSwapTick = tick()
                    end
                else
                    State.CurrentSlot = 2
                end

                equipSlotClean(State.CurrentSlot)
            end
        end
    end
end)

-- Re-equipar automáticamente de inmediato al revivir o reaparecer
lp.CharacterAdded:Connect(function(char)
    task.wait(1.5)
    if Config.Active and Config.AutoEquipWeapon then
        equipSlotClean(State.CurrentSlot)
    end
end)

-- ==============================================================================
-- 2. AUXILIARES: JUGADOR, ESTADOS Y TORRES DINÁMICAS
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getPlayerStats()
    local char, _, hum = getCharacterParts()
    if not hum then return 100, 100 end

    local hpPct = math.floor((hum.Health / math.max(hum.MaxHealth, 1)) * 100)
    local hunger = char:GetAttribute("Hunger") or lp:GetAttribute("Hunger") or 100
    local maxHunger = char:GetAttribute("MaxHunger") or lp:GetAttribute("MaxHunger") or 100
    local hungerPct = math.floor((hunger / maxHunger) * 100)

    return hpPct, hungerPct
end

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

    if #candidates == 0 then
        local structFolder = workspace:FindFirstChild("Structures") or workspace
        for _, obj in ipairs(structFolder:GetDescendants()) do
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

    table.sort(candidates, function(a, b) return a.Dist < b.Dist end)

    if #candidates > 0 then
        local best = candidates[1]
        local topY = best.CFrame.Position.Y + (best.Size.Y * 0.5) + 1.2
        for _, desc in ipairs(best.Model:GetDescendants()) do
            if desc:IsA("BasePart") then
                local dn = desc.Name:lower()
                if dn:find("floor") or dn:find("platform") or dn:find("piso") or dn:find("stand") then
                    if desc.Position.Y > best.CFrame.Position.Y then
                        topY = math.max(topY, desc.Position.Y + 2.8)
                    end
                end
            end
        end
        return Vector3.new(best.CFrame.Position.X, topY, best.CFrame.Position.Z), best.Name, best.Dist
    end

    return nil, nil, nil
end

-- ==============================================================================
-- 3. FÍSICAS DE VUELO Y DESPLAZAMIENTO
-- ==============================================================================

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

local function removeFlightPhysics(root)
    if not root then return end
    local bp = root:FindFirstChild("TowerFlightBP")
    if bp then bp:Destroy() end
    local bg = root:FindFirstChild("TowerFlightBG")
    if bg then bg:Destroy() end
    root.AssemblyLinearVelocity = Vector3.zero
end

local function flyToDestination(targetPos, speed, stopDist)
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
-- 4. ALIMENTACIÓN AUTOMÁTICA EN BASE
-- ==============================================================================

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

    if previousTool and previousTool.Parent then
        hum:EquipTool(previousTool)
    end

    State.LastEatTick = tick()
    State.IsEating = false
end

-- ==============================================================================
-- 5. BUCLE PRINCIPAL (PASEO MATUTINO RANDOM, TORRE Y DÍA 90+)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(1.0)

        if not Config.Active then
            local _, root, _ = getCharacterParts()
            if root then removeFlightPhysics(root) end
            State.Status = "Script pausado"
            continue
        end

        local char, root, hum = getCharacterParts()
        if not root or not hum or hum.Health <= 0 then
            task.wait(2.0)
            continue
        end

        local currentDay = getCurrentDay()
        State.CurrentDay = currentDay
        local night = isNightTime()
        local _, hungerPct = getPlayerStats()

        -- CASO 1: DÍA 90 O SUPERIOR (GUARDIA FIJA EN Vector3.new(0.1, 0.9, -8))
        if currentDay >= Config.Day90Threshold then
            State.Day90Enforced = true
            removeFlightPhysics(root)

            local distTo90 = (root.Position - DAY_90_TARGET_POS).Magnitude
            if distTo90 > 2.5 then
                State.Status = string.format("⚠️ Día %d >= 90: Reubicando en (0.1, 0.9, -8)", currentDay)
                hum:MoveTo(DAY_90_TARGET_POS)

                local diff = DAY_90_TARGET_POS - root.Position
                local horiz = Vector3.new(diff.X, 0, diff.Z)
                if horiz.Magnitude > 3.0 then
                    root.AssemblyLinearVelocity = Vector3.new(horiz.Unit.X * 18, root.AssemblyLinearVelocity.Y, horiz.Unit.Z * 18)
                end
            else
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                State.Status = string.format("🛡️ Día %d: En guardia fija en (0.1, 0.9, -8)", currentDay)
            end

        -- CASO 2: NOCHE (VOLAR Y GUARDAR EN LA CIMA DE CUALQUIER TORRE)
        elseif night then
            State.Day90Enforced = false
            State.WanderTarget = nil
            local towerTop, towerName, towerDist = findNearestWatchtower(root.Position)

            if towerTop then
                State.CurrentTowerName = towerName
                local distToTop = (root.Position - towerTop).Magnitude

                if distToTop > 3.5 then
                    State.Status = string.format("🌙 Noche: Volando a cima de '%s' (%dm)...", towerName, math.floor(towerDist))
                    flyToDestination(towerTop, Config.FlySpeed, 2.5)
                else
                    local bp = getOrCreateFlightPhysics(root)
                    bp.Position = towerTop
                    State.Status = string.format("🌙 En guardia en la cima de '%s'", towerName)
                end
            else
                State.CurrentTowerName = "No encontrada"
                State.Status = "⚠️ Noche: Buscando torre en el mapa..."
                removeFlightPhysics(root)
            end

        -- CASO 3: DÍA / MAÑANA (CAMINAR RANDOM POR LA BASE + COMER SI TIENE HAMBRE)
        else
            State.Day90Enforced = false
            removeFlightPhysics(root)

            -- Prioridad A: Si tiene hambre < 95%, buscar comida y comer
            if hungerPct < Config.FullHungerTarget then
                local foodTarget = findGroundFoodInBase(Config.EatScanRadius)
                if foodTarget then
                    State.Status = string.format("☀️ Mañana: Yendo a comida a %dm (Hambre: %d%%)", math.floor(foodTarget.Dist), hungerPct)
                    if foodTarget.Dist > 5.5 then
                        hum:MoveTo(foodTarget.Part.Position)
                    else
                        eatFood(foodTarget.Item)
                    end
                else
                    State.Status = string.format("☀️ Mañana: Sin comida cerca, paseando (Hambre: %d%%)", hungerPct)
                end
            end

            -- Prioridad B: Paseo aleatorio continuo por la base
            local now = tick()
            if not State.WanderTarget or now >= State.NextWanderTick or (root.Position - State.WanderTarget).Magnitude <= 4.0 then
                local randAngle = math.random() * math.pi * 2
                local randDist = math.random(15, BASE_WANDER_RADIUS)
                State.WanderTarget = BaseCenter + Vector3.new(math.cos(randAngle) * randDist, 0, math.sin(randAngle) * randDist)
                State.NextWanderTick = now + math.random(4, 7)
            end

            if State.WanderTarget and hungerPct >= Config.FullHungerTarget then
                State.Status = string.format("☀️ Mañana: Paseando por la base de forma random (Hambre: %d%%)", hungerPct)
                hum:MoveTo(State.WanderTarget)
            elseif State.WanderTarget and not findGroundFoodInBase(Config.EatScanRadius) then
                hum:MoveTo(State.WanderTarget)
            end

            -- Salto automático si topa con vallas o pequeños desniveles
            local ray = Ray.new(root.Position, root.CFrame.LookVector * 4.0)
            local hit = workspace:FindPartOnRayWithIgnoreList(ray, {char})
            if hit and hit.CanCollide then
                hum.Jump = true
            end
        end
    end
end)

-- ==============================================================================
-- 6. INTERFAZ GRÁFICA NATIVA ROBLOX (SCREENGUI)
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

local existing = GuiParent:FindFirstChild("BaseDefenderUniversalGuiV25")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BaseDefenderUniversalGuiV25"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 460, 0, 380)
MainFrame.Position = UDim2.new(0.5, -230, 0.5, -190)
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
TitleBar.Text = "   🏰 BASE DEFENDER V2.5 (PASEO RANDOM & HOTBAR 2/3)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 95)
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

-- Botón 1: Encender / Apagar Script
local ToggleBtn
ToggleBtn = createBtn("🟢 SCRIPT ACTIVO: ON", Color3.fromRGB(30, 150, 70), UDim2.new(0, 10, 0, 146), UDim2.new(0.48, -5, 0, 36), function()
    Config.Active = not Config.Active
    if Config.Active then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 70)
        ToggleBtn.Text = "🟢 SCRIPT ACTIVO: ON"
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
        ToggleBtn.Text = "🔴 SCRIPT ACTIVO: OFF"
        local _, root, _ = getCharacterParts()
        if root then removeFlightPhysics(root) end
    end
end)

-- Botón 2: Ir a Torre Manual
createBtn("🗼 VOLAR A TORRE CERCANA", Color3.fromRGB(45, 100, 180), UDim2.new(0.52, 0, 0, 146), UDim2.new(0.48, -10, 0, 36), function()
    local _, root, _ = getCharacterParts()
    if root then
        local towerTop, towerName = findNearestWatchtower(root.Position)
        if towerTop then
            flyToDestination(towerTop, Config.FlySpeed, 2.5)
        end
    end
end)

-- Botón 3: Toggle Intercambio de Armas (Slot 2 ⇄ Slot 3)
local SwapBtn
SwapBtn = createBtn("🔄 SWAP ARMAS (2 ⇄ 3): OFF", Color3.fromRGB(50, 55, 70), UDim2.new(0, 10, 0, 188), UDim2.new(1, -20, 0, 34), function()
    Config.SwapWeaponsEnabled = not Config.SwapWeaponsEnabled
    if Config.SwapWeaponsEnabled then
        SwapBtn.BackgroundColor3 = Color3.fromRGB(190, 120, 20)
        SwapBtn.Text = string.format("🔄 SWAP ARMAS (2 ⇄ 3): ON (CADA %ds)", Config.SwapInterval)
    else
        SwapBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        SwapBtn.Text = "⚪ SOLO ARMA SLOT 2 (FIJA)"
        State.CurrentSlot = 2
        equipSlotClean(2)
    end
end)

-- Botones 4 y 5: Ajustar Tiempo de Swap (-5s / +5s)
createBtn("➖ TIEMPO SWAP (-5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0, 10, 0, 228), UDim2.new(0.48, -5, 0, 30), function()
    Config.SwapInterval = math.max(5, Config.SwapInterval - 5)
    if Config.SwapWeaponsEnabled then
        SwapBtn.Text = string.format("🔄 SWAP ARMAS (2 ⇄ 3): ON (CADA %ds)", Config.SwapInterval)
    end
end)

createBtn("➕ TIEMPO SWAP (+5s)", Color3.fromRGB(35, 40, 55), UDim2.new(0.52, 0, 0, 228), UDim2.new(0.48, -10, 0, 30), function()
    Config.SwapInterval = math.min(120, Config.SwapInterval + 5)
    if Config.SwapWeaponsEnabled then
        SwapBtn.Text = string.format("🔄 SWAP ARMAS (2 ⇄ 3): ON (CADA %ds)", Config.SwapInterval)
    end
end)

-- Botón 6: Forzar Posición Día 90+
createBtn("🛡️ FORZAR POSICIÓN DÍA 90 (0.1, 0.9, -8)", Color3.fromRGB(140, 45, 160), UDim2.new(0, 10, 0, 264), UDim2.new(1, -20, 0, 32), function()
    local _, root, hum = getCharacterParts()
    if root and hum then
        removeFlightPhysics(root)
        hum:MoveTo(DAY_90_TARGET_POS)
    end
end)

-- Botón 7: Freno en Seco
createBtn("🛑 FRENAR Y BAJAR", Color3.fromRGB(140, 35, 40), UDim2.new(0, 10, 0, 302), UDim2.new(1, -20, 0, 32), function()
    local _, root, hum = getCharacterParts()
    if root then removeFlightPhysics(root) end
    if hum and root then hum:MoveTo(root.Position) end
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "🏰\nBASE"
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

        local tool2 = getToolFromHotbarSlot(2)
        local tool3 = getToolFromHotbarSlot(3)

        local tool2Name = tool2 and tool2.Name or "Vacío"
        local tool3Name = tool3 and tool3.Name or "Vacío"

        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Torre Detectada: '%s'\n" ..
            "Día: %d | Fase: %s | Salud: %d%% | Hambre: %d%%\n" ..
            "Hotbar Activa: Slot %d | Swap: %s (%ds)\n" ..
            "  • Slot 2: '%s' | Slot 3: '%s'\n" ..
            "Día 90+: %s",
            State.Status,
            State.CurrentTowerName,
            dayNum, night and "🌙 NOCHE" or "☀️ MAÑANA / DÍA", pHP, pHunger,
            State.CurrentSlot, Config.SwapWeaponsEnabled and "ON" or "OFF", Config.SwapInterval,
            tool2Name, tool3Name,
            dayNum >= 90 and "ACTIVO (0.1, 0.9, -8)" or "Esperando (<90)"
        )
    end
end)
