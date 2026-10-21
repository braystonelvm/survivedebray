-- ==============================================================================
-- AUTO-EAT DEFINITIVO: FILTRO ESTRICTO DORADAS (VIDA) / NORMALES (HAMBRE)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,
    HealthThreshold = 60,       -- Come SOLO ZANAHORIA DORADA si la vida cae de este %
    HungerThreshold = 50,       -- Come CUALQUIER ZANAHORIA si el hambre cae de este %
    ScanRadius = 24,            -- Radio de absorción en carrera o auto (studs)
    Cooldown = 0.9              -- Tiempo mínimo entre bocados
}

local State = {
    IsEating = false,
    LastEatTick = 0,
    Status = "Monitoreando..."
}

local PickUpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Interaction"):WaitForChild("PickUpItem")

-- ==============================================================================
-- 1. DETECCIÓN DE STATS (VIDA Y HAMBRE)
-- ==============================================================================

local function getPlayerStats()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return 100, 100 end

    local hpPct = math.floor((hum.Health / math.max(hum.MaxHealth, 1)) * 100)

    local hunger = char:GetAttribute("Hunger") or lp:GetAttribute("Hunger")
    local maxHunger = char:GetAttribute("MaxHunger") or lp:GetAttribute("MaxHunger") or 100

    local hungerPct = 100
    if type(hunger) == "number" then
        hungerPct = math.floor((hunger / maxHunger) * 100)
    else
        local hVal = char:FindFirstChild("Hunger") or lp:FindFirstChild("Hunger")
        if hVal and (hVal:IsA("NumberValue") or hVal:IsA("IntValue")) then
            hungerPct = math.floor((hVal.Value / 100) * 100)
        end
    end

    return hpPct, hungerPct
end

-- ==============================================================================
-- 2. DISCRIMINADOR MATEMÁTICO: DORADA VS NORMAL
-- ==============================================================================

local function isGoldenCarrot(item)
    -- Validación 1: Atributos directos del juego
    if item:GetAttribute("Golden") == true or item:GetAttribute("Rarity") == "Golden" then
        return true
    end

    -- Validación 2: Confirmación forense por Material Metal y Color Oro
    local mainPart = item:FindFirstChild("MainPart") or item:FindFirstChildWhichIsA("BasePart")
    if mainPart then
        if mainPart.Material == Enum.Material.Metal then
            return true
        end
        -- Detección por canal Rojo puro (Las doradas tienen R = 1.0, las normales R = 0.65)
        if mainPart.Color.R > 0.9 then
            return true
        end
    end

    return false
end

-- ==============================================================================
-- 3. BUSCADOR EN EL SUELO (ALGORITMO TURBO DE DISTANCIA AL CUADRADO)
-- ==============================================================================

local function findBestGroundFood(onlyGolden)
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return nil end

    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local myPos = root.Position
    local bestItem = nil
    
    local maxRadius = Config.ScanRadius
    local shortestDistSq = maxRadius * maxRadius

    for _, item in ipairs(dropped:GetChildren()) do
        local isFood = (item:GetAttribute("ItemType") == "Food") 
            or item.Name:lower():find("carrot")

        if isFood and item:GetAttribute("CanPickUp") ~= false then
            -- FILTRO ESTRICTO: Si la vida está baja, solo acepta doradas comprobadas
            local isGold = isGoldenCarrot(item)
            if not onlyGolden or isGold then
                local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                if part then
                    local pPos = part.Position
                    local dx = pPos.X - myPos.X
                    local dz = pPos.Z - myPos.Z

                    -- Descarte rápido en cruz (Ahorra 100% CPU en Delta con miles de ítems)
                    if math.abs(dx) <= maxRadius and math.abs(dz) <= maxRadius then
                        local dy = pPos.Y - myPos.Y
                        local distSq = (dx * dx) + (dy * dy) + (dz * dz)

                        if distSq <= shortestDistSq then
                            shortestDistSq = distSq
                            bestItem = item
                        end
                    end
                end
            end
        end
    end

    return bestItem
end

-- ==============================================================================
-- 4. CONSUMO RÁPIDO DE ALIMENTOS
-- ==============================================================================

local function eatGroundFood(onlyGolden)
    if State.IsEating then return end
    if (tick() - State.LastEatTick) < Config.Cooldown then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local targetFood = findBestGroundFood(onlyGolden)
    if not targetFood then
        State.Status = onlyGolden and "⚠️ Buscando Zanahoria Dorada..." or "⚠️ Sin comida cerca"
        return
    end

    State.IsEating = true
    local isGold = isGoldenCarrot(targetFood)
    State.Status = isGold and "✨ Comiendo DORADA..." or "🥕 Comiendo Normal..."

    -- Guardar el arma previa en mano
    local previousTool = nil
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            previousTool = item
            break
        end
    end

    -- Paso A: Recoger del suelo
    pcall(function()
        PickUpRemote:FireServer(targetFood)
    end)

    -- Paso B: Esperar Tool en inventario
    local foodTool = nil
    local startWait = tick()

    while (tick() - startWait) < 0.6 do
        for _, cont in ipairs({char, lp:FindFirstChild("Backpack")}) do
            if cont then
                for _, item in ipairs(cont:GetChildren()) do
                    if item:IsA("Tool") and (item:GetAttribute("ItemType") == "Food" or item.Name:lower():find("carrot")) then
                        foodTool = item
                        break
                    end
                end
            end
        end
        if foodTool then break end
        task.wait(0.04)
    end

    -- Paso C: Consumir
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

    -- Paso D: Re-equipar arma previa
    if previousTool and previousTool.Parent then
        hum:EquipTool(previousTool)
    end

    State.LastEatTick = tick()
    State.IsEating = false
end

-- ==============================================================================
-- 5. BUCLE PRINCIPAL (EVALUACIÓN DE CONDICIONES)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.35)
        if Config.Enabled then
            local hpPct, hungerPct = getPlayerStats()

            -- Condición 1: Si falta vida -> SOLO doradas
            if hpPct <= Config.HealthThreshold then
                eatGroundFood(true)
            -- Condición 2: Si la vida está bien pero hay hambre -> cualquiera
            elseif hungerPct <= Config.HungerThreshold then
                eatGroundFood(false)
            else
                State.Status = string.format("🟢 OK (Vida: %d%% | Comida: %d%%)", hpPct, hungerPct)
            end
        else
            State.Status = "🔴 OFF"
        end
    end
end)

-- ==============================================================================
-- 6. INTERFAZ TÁCTIL Y WIDGET FLOTANTE
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoEatFinalGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local WidgetBtn = Instance.new("TextButton")
WidgetBtn.Size = UDim2.new(0, 52, 0, 52)
WidgetBtn.Position = UDim2.new(0.04, 0, 0.62, 0)
WidgetBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
WidgetBtn.Text = "🥕\nCOMER"
WidgetBtn.TextColor3 = Color3.fromRGB(255, 170, 0)
WidgetBtn.TextSize = 10
WidgetBtn.Font = Enum.Font.GothamBold
WidgetBtn.Active = true
WidgetBtn.Draggable = true
WidgetBtn.Parent = ScreenGui

local WidgetCorner = Instance.new("UICorner")
WidgetCorner.CornerRadius = UDim.new(1, 0)
WidgetCorner.Parent = WidgetBtn

local WidgetStroke = Instance.new("UIStroke")
WidgetStroke.Color = Color3.fromRGB(255, 170, 0)
WidgetStroke.Thickness = 1.5
WidgetStroke.Parent = WidgetBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 390, 0, 310)
MainFrame.Position = UDim2.new(0.5, -195, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
TitleBar.Text = "  🥕 AUTO-EAT: FILTRO ESTRICTO DORADAS"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local MainToggle = Instance.new("TextButton")
MainToggle.Size = UDim2.new(1, -20, 0, 34)
MainToggle.Position = UDim2.new(0, 10, 0, 44)
MainToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
MainToggle.Text = "⚡ AUTO-EAT: ON"
MainToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
MainToggle.TextSize = 10
MainToggle.Font = Enum.Font.GothamBold
MainToggle.Parent = MainFrame

local MainToggleCorner = Instance.new("UICorner")
MainToggleCorner.CornerRadius = UDim.new(0, 6)
MainToggleCorner.Parent = MainToggle

MainToggle.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled
    if Config.Enabled then
        MainToggle.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
        MainToggle.Text = "⚡ AUTO-EAT: ON"
    else
        MainToggle.BackgroundColor3 = Color3.fromRGB(150, 35, 40)
        MainToggle.Text = "⚡ AUTO-EAT: OFF"
    end
end)

-- Vida (Doradas)
local HpLabel = Instance.new("TextLabel")
HpLabel.Size = UDim2.new(0.68, 0, 0, 24)
HpLabel.Position = UDim2.new(0, 10, 0, 88)
HpLabel.BackgroundTransparency = 1
HpLabel.Text = "Vida baja (%): Comer SOLO DORADA ✨"
HpLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
HpLabel.TextSize = 10
HpLabel.Font = Enum.Font.GothamBold
HpLabel.TextXAlignment = Enum.TextXAlignment.Left
HpLabel.Parent = MainFrame

local HpBox = Instance.new("TextBox")
HpBox.Size = UDim2.new(0.28, -10, 0, 26)
HpBox.Position = UDim2.new(0.72, 0, 0, 88)
HpBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
HpBox.TextColor3 = Color3.fromRGB(255, 255, 255)
HpBox.Text = tostring(Config.HealthThreshold)
HpBox.TextSize = 11
HpBox.Font = Enum.Font.Code
HpBox.ClearTextOnFocus = false
HpBox.Parent = MainFrame

local HpCorner = Instance.new("UICorner")
HpCorner.CornerRadius = UDim.new(0, 4)
HpCorner.Parent = HpBox

HpBox.FocusLost:Connect(function()
    local val = tonumber(HpBox.Text)
    if val then Config.HealthThreshold = math.clamp(math.floor(val), 1, 100) end
    HpBox.Text = tostring(Config.HealthThreshold)
end)

-- Hambre (Cualquiera)
local HungerLabel = Instance.new("TextLabel")
HungerLabel.Size = UDim2.new(0.68, 0, 0, 24)
HungerLabel.Position = UDim2.new(0, 10, 0, 122)
HungerLabel.BackgroundTransparency = 1
HungerLabel.Text = "Hambre baja (%): Comer CUALQUIERA 🥕"
HungerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
HungerLabel.TextSize = 10
HungerLabel.Font = Enum.Font.GothamBold
HungerLabel.TextXAlignment = Enum.TextXAlignment.Left
HungerLabel.Parent = MainFrame

local HungerBox = Instance.new("TextBox")
HungerBox.Size = UDim2.new(0.28, -10, 0, 26)
HungerBox.Position = UDim2.new(0.72, 0, 0, 122)
HungerBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
HungerBox.TextColor3 = Color3.fromRGB(255, 255, 255)
HungerBox.Text = tostring(Config.HungerThreshold)
HungerBox.TextSize = 11
HungerBox.Font = Enum.Font.Code
HungerBox.ClearTextOnFocus = false
HungerBox.Parent = MainFrame

local HungerCorner = Instance.new("UICorner")
HungerCorner.CornerRadius = UDim.new(0, 4)
HungerCorner.Parent = HungerBox

HungerBox.FocusLost:Connect(function()
    local val = tonumber(HungerBox.Text)
    if val then Config.HungerThreshold = math.clamp(math.floor(val), 1, 100) end
    HungerBox.Text = tostring(Config.HungerThreshold)
end)

-- Rango de Recolección (Studs)
local RangeLabel = Instance.new("TextLabel")
RangeLabel.Size = UDim2.new(0.68, 0, 0, 24)
RangeLabel.Position = UDim2.new(0, 10, 0, 156)
RangeLabel.BackgroundTransparency = 1
RangeLabel.Text = "Radio de Absorción (Studs):"
RangeLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
RangeLabel.TextSize = 10
RangeLabel.Font = Enum.Font.GothamBold
RangeLabel.TextXAlignment = Enum.TextXAlignment.Left
RangeLabel.Parent = MainFrame

local RangeBox = Instance.new("TextBox")
RangeBox.Size = UDim2.new(0.28, -10, 0, 26)
RangeBox.Position = UDim2.new(0.72, 0, 0, 156)
RangeBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
RangeBox.TextColor3 = Color3.fromRGB(255, 170, 0)
RangeBox.Text = tostring(Config.ScanRadius)
RangeBox.TextSize = 11
RangeBox.Font = Enum.Font.Code
RangeBox.ClearTextOnFocus = false
RangeBox.Parent = MainFrame

local RangeCorner = Instance.new("UICorner")
RangeCorner.CornerRadius = UDim.new(0, 4)
RangeCorner.Parent = RangeBox

RangeBox.FocusLost:Connect(function()
    local val = tonumber(RangeBox.Text)
    if val then Config.ScanRadius = math.clamp(math.floor(val), 5, 50) end
    RangeBox.Text = tostring(Config.ScanRadius)
end)

-- Monitor de Estado
local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(1, -20, 0, 44)
StatusFrame.Position = UDim2.new(0, 10, 0, 194)
StatusFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
StatusFrame.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusFrame

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -12, 1, 0)
StatusText.Position = UDim2.new(0, 6, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.Text = "Iniciando..."
StatusText.TextColor3 = Color3.fromRGB(255, 200, 80)
StatusText.TextSize = 10
StatusText.Font = Enum.Font.Code
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Parent = StatusFrame

-- Botones Manuales
local EatGoldBtn = Instance.new("TextButton")
EatGoldBtn.Size = UDim2.new(0.48, -8, 0, 36)
EatGoldBtn.Position = UDim2.new(0, 10, 0, 252)
EatGoldBtn.BackgroundColor3 = Color3.fromRGB(190, 140, 20)
EatGoldBtn.Text = "✨ COMER DORADA"
EatGoldBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EatGoldBtn.TextSize = 10
EatGoldBtn.Font = Enum.Font.GothamBold
EatGoldBtn.Parent = MainFrame

local EatGoldCorner = Instance.new("UICorner")
EatGoldCorner.CornerRadius = UDim.new(0, 6)
EatGoldCorner.Parent = EatGoldBtn

EatGoldBtn.MouseButton1Click:Connect(function()
    eatGroundFood(true)
end)

local EatAnyBtn = Instance.new("TextButton")
EatAnyBtn.Size = UDim2.new(0.48, -8, 0, 36)
EatAnyBtn.Position = UDim2.new(0.52, 0, 0, 252)
EatAnyBtn.BackgroundColor3 = Color3.fromRGB(210, 95, 20)
EatAnyBtn.Text = "🥕 COMER CUALQUIERA"
EatAnyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EatAnyBtn.TextSize = 10
EatAnyBtn.Font = Enum.Font.GothamBold
EatAnyBtn.Parent = MainFrame

local EatAnyCorner = Instance.new("UICorner")
EatAnyCorner.CornerRadius = UDim.new(0, 6)
EatAnyCorner.Parent = EatAnyBtn

EatAnyBtn.MouseButton1Click:Connect(function()
    eatGroundFood(false)
end)

WidgetBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

task.spawn(function()
    while true do
        task.wait(0.35)
        local hp, hg = getPlayerStats()
        StatusText.Text = string.format("Vida: %d%% | Hambre: %d%%\nEstado: %s", hp, hg, State.Status)
    end
end)
