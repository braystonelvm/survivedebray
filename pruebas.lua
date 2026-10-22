-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE
-- ==============================================================================

-- 1. CARGA DE LIBRERÍA DE INTERFAZ (Fluent UI)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

-- 2. SERVICIOS Y VARIABLES LOCALES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- Variables de configuración controladas por el menú
local Config = {
    ZigZagEnabled = false,
    SwitchInterval = 2.0,   -- Segundos hacia cada lado
    LateralDist = 10,       -- Amplitud en studs a la izquierda/derecha
    OvershootDist = 5       -- Avance para traspasarlo
}

-- 3. CREACIÓN DE LA VENTANA PRINCIPAL (Estilo Rojo / Oscuro)
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

-- Toggle principal para activar o detener el zigzag
local ZigZagToggle = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Zigzag hacia Zombie",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

-- Slider para los segundos de oscilación
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

-- Slider para la amplitud del zigzag
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

-- 5. LÓGICA DE DETECCIÓN Y MOVIMIENTO
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

-- Bucle asíncrono de movimiento
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
                        -- Alternar dirección cada N segundos configurados
                        if tick() - lastSideChange >= Config.SwitchInterval then
                            sideMultiplier = -sideMultiplier
                            lastSideChange = tick()
                        end

                        -- Cálculo de vectores de movimiento
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

-- Notificación de carga
Fluent:Notify({
    Title = "ZOMBIE HUB",
    Content = "Menú cargado. Usa RightControl para ocultar/mostrar.",
    Duration = 5
})

Window:SelectTab(1)
