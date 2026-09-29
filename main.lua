-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE
-- ==============================================================================

-- 1. CARGA DE LIBRERÍA DE INTERFAZ (Fluent UI)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

-- 2. SERVICIOS Y VARIABLES LOCALES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

-- Variables de configuración controladas por el menú
local Config = {
    ZigZagEnabled = false,
    SwitchInterval = 2.0,
    LateralDist = 10,
    OvershootDist = 5
}

-- 3. CREACIÓN DE LA VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 420),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

-- Pestañas del menú
local Tabs = {
    Combat = Window:AddTab({ Title = "Combate", Icon = "crosshair" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

-- 4. ELEMENTOS DE LA INTERFAZ
Tabs.Combat:AddSection("Movimiento Automatizado")

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Zigzag hacia Zombie",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Tiempo de oscilación (Segundos)",
    Description = "Tiempo que tarda en cambiar de izquierda a derecha",
    Default = 2.0,
    Min = 0.5,
    Max = 5.0,
    Rounding = 1,
    Callback = function(Value)
        Config.SwitchInterval = Value
    end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud del Zigzag (Studs)",
    Description = "Distancia lateral respecto al zombie",
    Default = 10,
    Min = 4,
    Max = 25,
    Rounding = 0,
    Callback = function(Value)
        Config.LateralDist = Value
    end
})

-- 5. BOTÓN FLOTANTE CIRCULAR ARRASTRABLE (DRAGGABLE TOGGLE)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomHubFloatingBtn"
ScreenGui.ResetOnSpawn = false
-- Proteger UI según executor
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Name = "OpenCloseCircle"
FloatBtn.Size = UDim2.new(0, 52, 0, 52)
FloatBtn.Position = UDim2.new(0.05, 0, 0.2, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 20, 30)
FloatBtn.BackgroundTransparency = 0.1
FloatBtn.Image = "rbxassetid://10723415903" -- Ícono de mira/hub
FloatBtn.ImageColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.Parent = ScreenGui

-- Redondear a círculo completo
local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local UIStroke = Instance.new("UIStroke")
UIStroke.Thickness = 2
UIStroke.Color = Color3.fromRGB(255, 255, 255)
UIStroke.Transparency = 0.4
UIStroke.Parent = FloatBtn

-- Función para arrastrar el botón flotante
local dragging, dragInput, dragStart, startPos

FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = FloatBtn.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

FloatBtn.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        FloatBtn.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-- Abrir/Cerrar la ventana al hacer clic en el círculo
local isOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isOpen = not isOpen
    Window.Root.Visible = isOpen
end)

-- 6. LÓGICA DE DETECCIÓN Y MOVIMIENTO
local function getClosestZombie()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local charactersFolder = workspace:FindFirstChild("Characters")
    if not charactersFolder then return nil end

    local closest = nil
    local minDistance = math.huge

    for _, entity in ipairs(charactersFolder:GetChildren()) do
        if entity ~= char and entity:IsA("Model") then
            local zRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
            local zHum = entity:FindFirstChildOfClass("Humanoid")

            if zRoot and zHum and zHum.Health > 0 then
                local dist = (zRoot.Position - root.Position).Magnitude
                if dist < minDistance then
                    minDistance = dist
                    closest = entity
                end
            end
        end
    end
    return closest
end

-- Bucle de movimiento
task.spawn(function()
    local sideMultiplier = 1
    local lastSideChange = tick()

    while true do
        task.wait(0.05)

        if Config.ZigZagEnabled then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if hum and root and hum.Health > 0 then
                local zombie = getClosestZombie()

                if zombie then
                    local zRoot = zombie:FindFirstChild("HumanoidRootPart") or zombie:FindFirstChild("Torso")

                    if zRoot then
                        if tick() - lastSideChange >= Config.SwitchInterval then
                            sideMultiplier = -sideMultiplier
                            lastSideChange = tick()
                        end

                        local cf = zRoot.CFrame
                        local lateralOffset = cf.RightVector * (sideMultiplier * Config.LateralDist)
                        local forwardOffset = cf.LookVector * Config.OvershootDist
                        local targetPosition = zRoot.Position + lateralOffset + forwardOffset

                        hum:MoveTo(targetPosition)
                    end
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB",
    Content = "Menú activo. Toca el botón rojo flotante para abrir o cerrar.",
    Duration = 5
})

Window:SelectTab(1)
