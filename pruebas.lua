-- ==============================================================================
-- AUTO-EAT OPTIMIZADO (ZANAHORIAS / COMIDA NATIVA - 0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,
    HealthThreshold = 50, -- Porcentaje de vida para comer (0 - 100)
    HungerThreshold = 40, -- Porcentaje de hambre para comer (0 - 100)
    FoodItemName = "Carrot", -- Nombre exacto o parcial (Zanahorias)
    Cooldown = 1.2 -- Tiempo de espera entre cada bocado
}

local State = {
    IsEating = false,
    LastEatTick = 0,
    Status = "Esperando..."
}

-- ==============================================================================
-- 1. DETECCIÓN DE STATS (VIDA Y HAMBRE)
-- ==============================================================================

local function getPlayerStats()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return 100, 100 end

    -- Porcentaje de Vida
    local hpPct = math.floor((hum.Health / math.max(hum.MaxHealth, 1)) * 100)

    -- Porcentaje de Hambre / Comida (Leído desde Atributos del Personaje o Jugador)
    local hunger = char:GetAttribute("Hunger") or lp:GetAttribute("Hunger")
    local maxHunger = char:GetAttribute("MaxHunger") or lp:GetAttribute("MaxHunger") or 100

    local hungerPct = 100
    if type(hunger) == "number" then
        hungerPct = math.floor((hunger / maxHunger) * 100)
    else
        -- Búsqueda secundaria en valores NumberValue/IntValue si el juego los usa
        local hVal = char:FindFirstChild("Hunger") or lp:FindFirstChild("Hunger")
        if hVal and (hVal:IsA("NumberValue") or hVal:IsA("IntValue")) then
            hungerPct = math.floor((hVal.Value / 100) * 100)
        end
    end

    return hpPct, hungerPct
end

-- ==============================================================================
-- 2. LOCALIZACIÓN Y CONSUMO DEL ALIMENTO (NATIVO)
-- ==============================================================================

local function findFoodTool()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local targetName = Config.FoodItemName:lower()

    for _, container in ipairs({char, bp}) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") then
                    local n = item.Name:lower()
                    -- Búsqueda por Carrot o coincidencia de comida
                    if n:find(targetName) or n:find("zanahoria") or item:GetAttribute("ItemType") == "Food" then
                        return item
                    end
                end
            end
        end
    end
    return nil
end

local function consumeFood()
    if State.IsEating then return end
    if (tick() - State.LastEatTick) < Config.Cooldown then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local foodTool = findFoodTool()
    if not foodTool then
        State.Status = "⚠️ Sin comida en inventario"
        return
    end

    State.IsEating = true
    State.Status = "🥕 Comiendo " .. foodTool.Name .. "..."

    -- Guardar el arma o ítem que tenías equipado antes de comer
    local previousTool = nil
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") and item ~= foodTool then
            previousTool = item
            break
        end
    end

    -- Equipar la zanahoria / comida
    if foodTool.Parent ~= char then
        hum:EquipTool(foodTool)
        task.wait(0.08)
    end

    -- Activar consumo nativo
    pcall(function() foodTool:Activate() end)

    -- Ejecutar Remote de uso si existe adentro de la herramienta
    local useRemote = foodTool:FindFirstChild("Use") or foodTool:FindFirstChild("Consume")
    if useRemote and useRemote:IsA("RemoteEvent") then
        pcall(function() useRemote:FireServer() end)
    end

    State.LastEatTick = tick()
    task.wait(0.35)

    -- Re-equipar el arma que tenías en la mano
    if previousTool and previousTool.Parent then
        hum:EquipTool(previousTool)
    end

    State.IsEating = false
end

-- ==============================================================================
-- 3. BUCLE DE CONTROL (0% LAG: REVISIÓN CADA 0.4 SEGUNDOS)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.4)
        if Config.Enabled then
            local hpPct, hungerPct = getPlayerStats()

            -- Evaluar si se cumple la condición de vida o hambre
            if hpPct <= Config.HealthThreshold or hungerPct <= Config.HungerThreshold then
                consumeFood()
            else
                State.Status = string.format("🟢 OK (Vida: %d%% | Comida: %d%%)", hpPct, hungerPct)
            end
        else
            State.Status = "🔴 OFF"
        end
    end
end)

-- ==============================================================================
-- 4. INTERFAZ TÁCTIL Y MENÚ DE CONFIGURACIÓN
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoEatProGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante / Widget
local WidgetBtn = Instance.new("TextButton")
WidgetBtn.Size = UDim2.new(0, 52, 0, 52)
WidgetBtn.Position = UDim2.new(0.04, 0, 0.60, 0)
WidgetBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
WidgetBtn.Text = "🥕\nCOMER"
WidgetBtn.TextColor3 = Color3.fromRGB(255, 150, 40)
WidgetBtn.TextSize = 10
WidgetBtn.Font = Enum.Font.GothamBold
WidgetBtn.Active = true
WidgetBtn.Draggable = true
WidgetBtn.Parent = ScreenGui

local WidgetCorner = Instance.new("UICorner")
WidgetCorner.CornerRadius = UDim.new(1, 0)
WidgetCorner.Parent = WidgetBtn

local WidgetStroke = Instance.new("UIStroke")
WidgetStroke.Color = Color3.fromRGB(255, 150, 40)
WidgetStroke.Thickness = 1.5
WidgetStroke.Parent = WidgetBtn

-- Ventana de Ajustes
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
TitleBar.Text = "  🥕 AUTO-COMER (ZANAHORIAS / COMIDA)"
TitleBar.TextColor3 = Color3.fromRGB(255, 150, 40)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Interruptor ON/OFF
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

-- Configuración de Vida (%)
local HpLabel = Instance.new("TextLabel")
HpLabel.Size = UDim2.new(0.65, 0, 0, 24)
HpLabel.Position = UDim2.new(0, 10, 0, 88)
HpLabel.BackgroundTransparency = 1
HpLabel.Text = "Comer si la Vida baja de (%):"
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

local HpBoxCorner = Instance.new("UICorner")
HpBoxCorner.CornerRadius = UDim.new(0, 4)
HpBoxCorner.Parent = HpBox

HpBox.FocusLost:Connect(function()
    local val = tonumber(HpBox.Text)
    if val then
        Config.HealthThreshold = math.clamp(math.floor(val), 1, 100)
    end
    HpBox.Text = tostring(Config.HealthThreshold)
end)

-- Configuración de Comida/Hambre (%)
local HungerLabel = Instance.new("TextLabel")
HungerLabel.Size = UDim2.new(0.65, 0, 0, 24)
HungerLabel.Position = UDim2.new(0, 10, 0, 122)
HungerLabel.BackgroundTransparency = 1
HungerLabel.Text = "Comer si el Hambre baja de (%):"
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

local HungerBoxCorner = Instance.new("UICorner")
HungerBoxCorner.CornerRadius = UDim.new(0, 4)
HungerBoxCorner.Parent = HungerBox

HungerBox.FocusLost:Connect(function()
    local val = tonumber(HungerBox.Text)
    if val then
        Config.HungerThreshold = math.clamp(math.floor(val), 1, 100)
    end
    HungerBox.Text = tostring(Config.HungerThreshold)
end)

-- Nombre de la Comida
local FoodNameLabel = Instance.new("TextLabel")
FoodNameLabel.Size = UDim2.new(0.45, 0, 0, 24)
FoodNameLabel.Position = UDim2.new(0, 10, 0, 156)
FoodNameLabel.BackgroundTransparency = 1
FoodNameLabel.Text = "Nombre del Alimento:"
FoodNameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
FoodNameLabel.TextSize = 10
FoodNameLabel.Font = Enum.Font.GothamBold
FoodNameLabel.TextXAlignment = Enum.TextXAlignment.Left
FoodNameLabel.Parent = MainFrame

local FoodBox = Instance.new("TextBox")
FoodBox.Size = UDim2.new(0.50, -10, 0, 26)
FoodBox.Position = UDim2.new(0.50, 0, 0, 156)
FoodBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
FoodBox.TextColor3 = Color3.fromRGB(255, 170, 40)
FoodBox.Text = Config.FoodItemName
FoodBox.TextSize = 10
FoodBox.Font = Enum.Font.Code
FoodBox.ClearTextOnFocus = false
FoodBox.Parent = MainFrame

local FoodBoxCorner = Instance.new("UICorner")
FoodBoxCorner.CornerRadius = UDim.new(0, 4)
FoodBoxCorner.Parent = FoodBox

FoodBox.FocusLost:Connect(function()
    if FoodBox.Text ~= "" then
        Config.FoodItemName = FoodBox.Text
    end
end)

-- Monitor de Estado en Tiempo Real
local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(1, -20, 0, 50)
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
StatusText.Text = "Estado: Inicializando..."
StatusText.TextColor3 = Color3.fromRGB(255, 200, 80)
StatusText.TextSize = 10
StatusText.Font = Enum.Font.Code
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Parent = StatusFrame

-- Botón Comer Manual Ahora
local EatNowBtn = Instance.new("TextButton")
EatNowBtn.Size = UDim2.new(1, -20, 0, 34)
EatNowBtn.Position = UDim2.new(0, 10, 0, 256)
EatNowBtn.BackgroundColor3 = Color3.fromRGB(210, 105, 30)
EatNowBtn.Text = "🍽️ FORZAR COMER AHORA"
EatNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EatNowBtn.TextSize = 10
EatNowBtn.Font = Enum.Font.GothamBold
EatNowBtn.Parent = MainFrame

local EatNowCorner = Instance.new("UICorner")
EatNowCorner.CornerRadius = UDim.new(0, 6)
EatNowCorner.Parent = EatNowBtn

EatNowBtn.MouseButton1Click:Connect(function()
    consumeFood()
end)

WidgetBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Actualización periódica del monitor visual
task.spawn(function()
    while true do
        task.wait(0.35)
        local hp, hg = getPlayerStats()
        StatusText.Text = string.format("Vida actual: %d%% | Hambre: %d%%\nAcción: %s", hp, hg, State.Status)
    end
end)
