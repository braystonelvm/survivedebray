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
    SwitchInterval = 1.2,   -- Tiempo hacia cada lado
    LateralDist = 12,       -- Amplitud del zigzag en studs
    MoveSpeed = 24          -- Velocidad forzada de desplazamiento
}

local CurrentTarget = nil
local TargetHighlight = nil

-- Crear o limpiar Highlight visual
local function clearHighlight()
    if TargetHighlight then
        TargetHighlight:Destroy()
        TargetHighlight = nil
    end
end

local function applyHighlight(obj)
    clearHighlight()
    if obj then
        TargetHighlight = Instance.new("Highlight")
        TargetHighlight.Name = "CustomTargetHighlight"
        TargetHighlight.FillColor = Color3.fromRGB(255, 30, 60)
        TargetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        TargetHighlight.FillTransparency = 0.4
        TargetHighlight.Adornee = obj
        TargetHighlight.Parent = obj
    end
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 430),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" })
}

Tabs.Combat:AddSection("Controles de Zigzag")

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

Tabs.Combat:AddParagraph({
    Title = "Controles de Teclas",
    Content = "• Presiona 'E' apuntando a un Zombie o a la Carretera (StraightRoad) para fijarlo.\n• Presiona 'R' para desmarcar el objetivo."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación (Segundos)",
    Default = 1.2,
    Min = 0.4,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value)
        Config.SwitchInterval = Value
    end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud / Ancho de pista (Studs)",
    Default = 12,
    Min = 4,
    Max = 30,
    Rounding = 0,
    Callback = function(Value)
        Config.LateralDist = Value
    end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Movimiento",
    Default = 24,
    Min = 16,
    Max = 80,
    Rounding = 0,
    Callback = function(Value)
        Config.MoveSpeed = Value
    end
})

-- 2. BOTÓN FLOTANTE
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
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.22, 0)
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

-- 3. SELECCIÓN CON TECLA 'E' Y LIMPIEZA CON 'R'
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Tecla E: Fijar
    if input.KeyCode == Enum.KeyCode.E then
        local target = mouse.Target
        if target then
            -- Intentar detectar si es un Zombie
            local model = target:FindFirstAncestorOfClass("Model")
            local chosen = nil

            if model and model ~= lp.Character then
                -- Si es un zombie dentro de Characters o con Humanoid
                if model.Parent and model.Parent.Name == "Characters" or model:FindFirstChildOfClass("Humanoid") then
                    chosen = model
                else
                    -- Si es una pieza de pista/mapa (StraightRoad, TSection, etc.)
                    chosen = target
                end
            else
                chosen = target
            end

            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)
                Fluent:Notify({
                    Title = "Objetivo Seleccionado",
                    Content = "Fijado: " .. chosen.Name,
                    Duration = 3
                })
            end
        end
    end

    -- Tecla R: Desmarcar
    if input.KeyCode == Enum.KeyCode.R then
        CurrentTarget = nil
        clearHighlight()
        Fluent:Notify({
            Title = "Objetivo Limpiado",
            Content = "Se canceló el objetivo actual.",
            Duration = 2
        })
    end
end)

-- 4. BUCLE DE MOVIMIENTO FÍSICO (MOTOR POR VELOCIDAD)
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or not CurrentTarget then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    -- Obtener pieza física de referencia
    local targetPart = nil
    if CurrentTarget:IsA("BasePart") then
        targetPart = CurrentTarget
    elseif CurrentTarget:IsA("Model") then
        targetPart = CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")
    end

    if targetPart and targetPart.Parent then
        -- Alternar dirección cada N segundos
        if tick() - lastSwitch >= Config.SwitchInterval then
            side = -side
            lastSwitch = tick()
        end

        -- Calcular punto lateral oscilante
        local cf = targetPart.CFrame
        local lateralOffset = cf.RightVector * (side * Config.LateralDist)
        local destination = targetPart.Position + lateralOffset

        -- Vector de dirección hacia la meta
        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.5 then
            -- Mover usando velocidad física directa (empuja al muñeco o auto sin que el teclado estorbe)
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB CARGADO",
    Content = "E: Seleccionar | R: Quitar marca | RightCtrl: Ocultar",
    Duration = 5
})

Window:SelectTab(1)
