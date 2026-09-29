-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- Variables de configuración
local Config = {
    ZigZagEnabled = false,
    SwitchInterval = 1.5,
    LateralDist = 8,
    OvershootDist = 4,
    WalkSpeed = 22
}

local CurrentTarget = nil
local TargetHighlight = nil

-- Crear Highlight visual para ver a quién tenemos seleccionado
local function highlightZombie(model)
    if TargetHighlight then
        TargetHighlight:Destroy()
        TargetHighlight = nil
    end
    if model then
        TargetHighlight = Instance.new("Highlight")
        TargetHighlight.Name = "ZombieTargetHighlight"
        TargetHighlight.FillColor = Color3.fromRGB(255, 0, 50)
        TargetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        TargetHighlight.FillTransparency = 0.5
        TargetHighlight.Adornee = model
        TargetHighlight.Parent = model
    end
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 420),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate", Icon = "crosshair" })
}

Tabs.Combat:AddSection("Controles")

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Zigzag",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

Tabs.Combat:AddParagraph({
    Title = "Selector Manual",
    Content = "Apunta con el mouse a cualquier zombie y presiona 'E' para fijarlo como objetivo."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Tiempo de oscilación (Segundos)",
    Default = 1.5,
    Min = 0.5,
    Max = 4.0,
    Rounding = 1,
    Callback = function(Value)
        Config.SwitchInterval = Value
    end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud lateral (Studs)",
    Default = 8,
    Min = 3,
    Max = 20,
    Rounding = 0,
    Callback = function(Value)
        Config.LateralDist = Value
    end
})

-- 2. BOTÓN FLOTANTE CÍRCULAR
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomHubFloatingBtn"
ScreenGui.ResetOnSpawn = false
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 50, 0, 50)
FloatBtn.Position = UDim2.new(0.05, 0, 0.25, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- 3. DETECCIÓN POR TECLA 'E' (SELECTOR)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.E then
        local targetPart = mouse.Target
        if targetPart then
            -- Buscar el modelo del zombie hacia arriba en la jerarquía
            local model = targetPart:FindFirstAncestorOfClass("Model")
            if model and model ~= lp.Character then
                CurrentTarget = model
                highlightZombie(model)
                Fluent:Notify({
                    Title = "Objetivo Fijado",
                    Content = "Zombie seleccionado: " .. model.Name,
                    Duration = 3
                })
            end
        end
    end
end)

-- 4. BÚSQUEDA AUTOMÁTICA DE RESPALDO (Si no se presiona E)
local function getFallbackZombie()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local nearest, minDist = nil, math.huge

    for _, obj in ipairs(charFolder:GetChildren()) do
        if obj:IsA("Model") and obj ~= char then
            local part = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj:FindFirstChild("Head")
            if part then
                local d = (part.Position - root.Position).Magnitude
                if d < minDist then
                    minDist = d
                    nearest = obj
                end
            end
        end
    end
    return nearest
end

-- 5. BUCLE DE MOVIMIENTO EN ZIGZAG (FORZADO)
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    -- Usar el objetivo manual (E) o buscar el más cercano
    local target = CurrentTarget
    if not target or not target.Parent then
        target = getFallbackZombie()
    end

    if target then
        local zPart = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso") or target:FindFirstChild("Head")
        if zPart then
            -- Alternar de lado por tiempo
            if tick() - lastSwitch >= Config.SwitchInterval then
                side = -side
                lastSwitch = tick()
            end

            -- Cálculo matemático de posición
            local zCF = zPart.CFrame
            local lateral = zCF.RightVector * (side * Config.LateralDist)
            local forward = zCF.LookVector * Config.OvershootDist
            local destination = zPart.Position + lateral + forward

            -- Forzar dirección del movimiento
            local moveDir = (destination - root.Position).Unit
            hum:Move(moveDir, false)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB",
    Content = "Presiona E mirando a un zombie para fijarlo.",
    Duration = 5
})

Window:SelectTab(1)
