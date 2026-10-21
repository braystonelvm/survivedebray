-- ==============================================================================
-- AUTO-EAT DESDE EL SUELO (DROPPEDITEMS -> PICKUP -> CONSUME -> RE-EQUIP)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,
    HealthThreshold = 60,       -- Come si la vida cae por debajo de este %
    HungerThreshold = 50,       -- Come si el hambre cae por debajo de este %
    ScanRadius = 18,            -- Rango para aspirar comida del suelo (studs)
    Cooldown = 1.2              -- Tiempo mínimo entre bocados
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
-- 2. BUSCADOR DE ALIMENTOS EN EL SUELO (DROPPEDITEMS)
-- ==============================================================================

local function findNearestGroundFood()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return nil end

    local dropped = workspace:FindFirstChild("DroppedItems")
    if not dropped then return nil end

    local myPos = root.Position
    local bestItem = nil
    local shortestDist = Config.ScanRadius

    for _, item in ipairs(dropped:GetChildren()) do
        -- Filtro según el reporte: ItemType == "Food" o nombre Carrot/Zanahoria
        local isFood = (item:GetAttribute("ItemType") == "Food")
            or item.Name:lower():find("carrot")
            or item.Name:lower():find("food")
            or item.Name:lower():find("zanahoria")

        if isFood and item:GetAttribute("CanPickUp") ~= false then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part then
                local dist = (part.Position - myPos).Magnitude
                if dist <= shortestDist then
                    shortestDist = dist
                    bestItem = item
                end
            end
        end
    end

    return bestItem
end

-- ==============================================================================
-- 3. PROCESO DE COMER (RECOGER -> EQUIPAR -> CONSUMIR -> RESTAURAR ARMA)
-- ==============================================================================

local function eatGroundFood()
    if State.IsEating then return end
    if (tick() - State.LastEatTick) < Config.Cooldown then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local targetFood = findNearestGroundFood()
    if not targetFood then
        State.Status = "⚠️ Sin comida en el suelo cerca"
        return
    end

    State.IsEating = true
    State.Status = "🥕 Consumiendo " .. targetFood.Name .. "..."

    -- Guardar el arma que tenías en mano
    local previousTool = nil
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            previousTool = item
            break
        end
    end

    -- Paso A: Recoger del suelo mediante el remote nativo
    pcall(function()
        PickUpRemote:FireServer(targetFood)
    end)

    -- Paso B: Esperar a que el Tool llegue a Character o Backpack y consumirlo
    local foodTool = nil
    local startWait = tick()

    while (tick() - startWait) < 0.6 do
        for _, cont in ipairs({char, lp:FindFirstChild("Backpack")}) do
            if cont then
                for _, item in ipairs(cont:GetChildren()) do
                    if item:IsA("Tool") and (item:GetAttribute("ItemType") == "Food" or item.Name == targetFood.Name) then
                        foodTool = item
                        break
                    end
                end
            end
        end
        if foodTool then break end
        task.wait(0.04)
    end

    -- Paso C: Consumir el alimento
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

        task.wait(0.25)
    end

    -- Paso D: Re-equipar el arma previa
    if previousTool and previousTool.Parent then
        hum:EquipTool(previousTool)
    end

    State.LastEatTick = tick()
    State.IsEating = false
end

-- ==============================================================================
-- 4. BUCLE DE CONTROL (0% LAG / CADA 0.35s)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.35)
        if Config.Enabled then
            local hpPct, hungerPct = getPlayerStats()

            if hpPct <= Config.HealthThreshold or hungerPct <= Config.HungerThreshold then
                eatGroundFood()
            else
                State.Status = string.format("🟢 OK (Vida: %d%% | Comida: %d%%)", hpPct, hungerPct)
            end
        else
            State.Status = "🔴 OFF"
        end
    end
end)

-- ==============================================================================
-- 5. WIDGET FLOTANTE Y MENÚ TÁCTIL
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoEatGroundGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local WidgetBtn = Instance.new("TextButton")
WidgetBtn.Size = UDim2.new(0, 52, 0, 52)
WidgetBtn.Position = UDim2.new(0.04, 0, 0.62, 0)
WidgetBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
WidgetBtn.Text = "🥕\nCOMER"
WidgetBtn.TextColor3 = Color3.fromRGB(255, 140, 30)
WidgetBtn.TextSize = 10
WidgetBtn.Font = Enum.Font.GothamBold
WidgetBtn.Active = true
WidgetBtn.Draggable = true
WidgetBtn.Parent = ScreenGui

local WidgetCorner = Instance.new("UICorner")
WidgetCorner.CornerRadius = UDim.new(1, 0)
WidgetCorner.Parent = WidgetBtn

local WidgetStroke = Instance.new("UIStroke")
WidgetStroke.Color = Color3.fromRGB(255, 140, 30)
WidgetStroke.Thickness = 1.5
WidgetStroke.Parent = WidgetBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 380, 0, 310)
MainFrame.Position = UDim2.new(0.5, -190, 0.5, -155)
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
TitleBar.Text = "  🥕 AUTO-COMER DESDE EL SUELO"
TitleBar.TextColor3 = Color3.fromRGB(255, 140, 30)
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

-- Umbral Vida
local HpLabel = Instance.new("TextLabel")
HpLabel.Size = UDim2.new(0.65, 0, 0, 24)
HpLabel.Position = UDim2.new(0, 10, 0, 88)
HpLabel.BackgroundTransparency = 1
HpLabel.Text = "Comer si la Vida cae de (%):"
HpLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
HpLabel.TextSize = 10
HpLabel.Font = Enum.Font.GothamBold
HpLabel.TextXAlignment = Enum.TextXAlignment.Left
HpLabel.Parent = MainFrame

local HpBox = Instance.new("TextBox")
HpBox.Size = UDim2.new(0.30, -10, 0, 26)
HpBox.Position = UDim2.new(0.70, 0, 0, 88)
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

-- Umbral Hambre
local HungerLabel = Instance.new("TextLabel")
HungerLabel.Size = UDim2.new(0.65, 0, 0, 24)
HungerLabel.Position = UDim2.new(0, 10, 0, 122)
HungerLabel.BackgroundTransparency = 1
HungerLabel.Text = "Comer si el Hambre cae de (%):"
HungerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
HungerLabel.TextSize = 10
HungerLabel.Font = Enum.Font.GothamBold
HungerLabel.TextXAlignment = Enum.TextXAlignment.Left
HungerLabel.Parent = MainFrame

local HungerBox = Instance.new("TextBox")
HungerBox.Size = UDim2.new(0.30, -10, 0, 26)
HungerBox.Position = UDim2.new(0.70, 0, 0, 122)
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

-- Rango de Recogida
local RangeLabel = Instance.new("TextLabel")
RangeLabel.Size = UDim2.new(0.65, 0, 0, 24)
RangeLabel.Position = UDim2.new(0, 10, 0, 156)
RangeLabel.BackgroundTransparency = 1
RangeLabel.Text = "Radio de Comida en Suelo (Studs):"
RangeLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
RangeLabel.TextSize = 10
RangeLabel.Font = Enum.Font.GothamBold
RangeLabel.TextXAlignment = Enum.TextXAlignment.Left
RangeLabel.Parent = MainFrame

local RangeBox = Instance.new("TextBox")
RangeBox.Size = UDim2.new(0.30, -10, 0, 26)
RangeBox.Position = UDim2.new(0.70, 0, 0, 156)
RangeBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
RangeBox.TextColor3 = Color3.fromRGB(255, 140, 30)
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

-- Botón Manual
local EatNowBtn = Instance.new("TextButton")
EatNowBtn.Size = UDim2.new(1, -20, 0, 36)
EatNowBtn.Position = UDim2.new(0, 10, 0, 252)
EatNowBtn.BackgroundColor3 = Color3.fromRGB(210, 95, 20)
EatNowBtn.Text = "🥕 COMER DEL SUELO AHORA"
EatNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EatNowBtn.TextSize = 10
EatNowBtn.Font = Enum.Font.GothamBold
EatNowBtn.Parent = MainFrame

local EatNowCorner = Instance.new("UICorner")
EatNowCorner.CornerRadius = UDim.new(0, 6)
EatNowCorner.Parent = EatNowBtn

EatNowBtn.MouseButton1Click:Connect(function()
    eatGroundFood()
end)

WidgetBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

task.spawn(function()
    while true do
        task.wait(0.35)
        local hp, hg = getPlayerStats()
        StatusText.Text = string.format("Vida: %d%% | Comida: %d%%\nEstado: %s", hp, hg, State.Status)
    end
end)
