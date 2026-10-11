-- ==============================================================================
-- REPARADOR OVERCLOCK 60 FPS & TRUCK GODMODE (BOMBA MULTI-THREAD NATIVA)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local TurboConfig = {
    BlockImpactDamage = true,     -- Inmunidad al Tank (Bloqueo de 'Impact')
    UltraRepairActive = true,     -- Reparación Overclock activa
    PacketsPerBurst = 35,         -- Ráfaga de paquetes por cada ciclo
    ParallelWorkers = 3,          -- Hilos concurrentes simultáneos
    AuraRadius = 35,              -- Rango de detección en studs
    RepairTruck = true            -- Reparar también el camión si estás montado
}

local Stats = {
    PacketsSentLastSec = 0,
    TotalPacketsSent = 0,
    CurrentTargetName = "Ninguno",
    CurrentTargetHP = "N/A"
}

-- OBTENER EL CAMIÓN ACTUAL
local function getCurrentTruck()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        return seat:FindFirstAncestorOfClass("Model") or seat.Parent, seat
    end
    return nil, nil
end

-- OBTENER EL REMOTE REPAIR DIRECTO DESDE LA MOCHILA
local function getRepairRemote()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))
    return hammer and hammer:FindFirstChild("Repair")
end

-- ==============================================================================
-- 1. BLOQUEO DE DAÑO DE IMPACTO (ANTI-TANK GODMODE)
-- ==============================================================================
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if TurboConfig.BlockImpactDamage and method == "FireServer" and self.Name == "Impact" then
            return nil -- Descarta la colisión contra Tanks
        end
        return oldNamecall(self, ...)
    end)
end

-- ==============================================================================
-- 2. INTERFAZ NATIVA ROBLOX (WIDGET ROJO Y PANEL)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NativeTurboRepairGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante (Widget Rojo)
local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(1, 0)
BtnCorner.Parent = FloatBtn

local BtnIcon = Instance.new("TextLabel")
BtnIcon.Size = UDim2.new(1, 0, 1, 0)
BtnIcon.BackgroundTransparency = 1
BtnIcon.Text = "⚡"
BtnIcon.TextSize = 22
BtnIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnIcon.Parent = FloatBtn

-- Ventana Principal
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 430, 0, 360)
MainFrame.Position = UDim2.new(0.5, -215, 0.5, -180)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
TitleBar.Text = "  REPARADOR OVERCLOCK 60 FPS (TURBO)"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Monitor de Rendimiento y Vida
local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -20, 0, 90)
StatusLbl.Position = UDim2.new(0, 10, 0, 44)
StatusLbl.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
StatusLbl.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusLbl.TextSize = 11
StatusLbl.Font = Enum.Font.Code
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.TextYAlignment = Enum.TextYAlignment.Top
StatusLbl.Text = " Calculando tasa de paquetes por segundo (PPS)..."
StatusLbl.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusLbl

local function createToggleBtn(yPos, labelText, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 36)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(140, 35, 35)
    btn.Text = (defaultState and "🟢 " or "🔴 ") .. labelText
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    local state = defaultState
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(140, 35, 35)
        btn.Text = (state and "🟢 " or "🔴 ") .. labelText
        callback(state)
    end)
end

createToggleBtn(144, "Reparación Overclock Extrema (Multi-Thread)", TurboConfig.UltraRepairActive, function(s)
    TurboConfig.UltraRepairActive = s
end)

createToggleBtn(186, "Inmunidad a Choques de Tanks (Anti-Impact)", TurboConfig.BlockImpactDamage, function(s)
    TurboConfig.BlockImpactDamage = s
end)

createToggleBtn(228, "Reparar Camión Actual en Movimiento", TurboConfig.RepairTruck, function(s)
    TurboConfig.RepairTruck = s
end)

-- Selector de Potencia de Bombeo
local SpeedBtn = Instance.new("TextButton")
SpeedBtn.Size = UDim2.new(1, -20, 0, 36)
SpeedBtn.Position = UDim2.new(0, 10, 0, 270)
SpeedBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
SpeedBtn.Text = "🚀 Potencia de Ráfaga: ALTA (35 paquetes/ciclo)"
SpeedBtn.TextColor3 = Color3.fromRGB(255, 200, 0)
SpeedBtn.TextSize = 12
SpeedBtn.Font = Enum.Font.GothamBold
SpeedBtn.Parent = MainFrame

local SpeedCorner = Instance.new("UICorner")
SpeedCorner.CornerRadius = UDim.new(0, 6)
SpeedCorner.Parent = SpeedBtn

local currentLevel = 2
SpeedBtn.MouseButton1Click:Connect(function()
    currentLevel = (currentLevel % 3) + 1
    if currentLevel == 1 then
        TurboConfig.PacketsPerBurst = 15
        TurboConfig.ParallelWorkers = 2
        SpeedBtn.Text = "⚡ Potencia de Ráfaga: MEDIA (15 paquetes)"
    elseif currentLevel == 2 then
        TurboConfig.PacketsPerBurst = 35
        TurboConfig.ParallelWorkers = 3
        SpeedBtn.Text = "🚀 Potencia de Ráfaga: ALTA (35 paquetes)"
    else
        TurboConfig.PacketsPerBurst = 65
        TurboConfig.ParallelWorkers = 4
        SpeedBtn.Text = "🔥 Potencia de Ráfaga: EXTREMA (65 paquetes)"
    end
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- ==============================================================================
-- 3. MOTOR DE DISPARO MULTI-THREAD CON BOMBEO EN PARALELO
-- ==============================================================================
local packetCounterThisSec = 0

-- Contador de paquetes por segundo (PPS)
task.spawn(function()
    while true do
        task.wait(1.0)
        Stats.PacketsSentLastSec = packetCounterThisSec
        packetCounterThisSec = 0

        local truck = getCurrentTruck()
        local truckInfo = truck and string.format("Camión: %s | Anti-Tank: %s", truck.Name, TurboConfig.BlockImpactDamage and "ACTIVO" or "OFF") or "A pie"

        StatusLbl.Text = string.format(
            " %s\n Velocidad de inyección: %d paquetes/seg (PPS)\n Estructura actual: %s\n Vida: %s",
            truckInfo,
            Stats.PacketsSentLastSec,
            Stats.CurrentTargetName,
            Stats.CurrentTargetHP
        )
    end
end)

-- Disparador en ráfaga paralela
local function fireBurst(remote, targetInstance)
    for _ = 1, TurboConfig.ParallelWorkers do
        task.spawn(function()
            for _ = 1, TurboConfig.PacketsPerBurst do
                pcall(function()
                    remote:FireServer(targetInstance)
                end)
                packetCounterThisSec = packetCounterThisSec + 1
                Stats.TotalPacketsSent = Stats.TotalPacketsSent + 1
            end
        end)
    end
end

-- Bucle de escaneo continuo a máxima frecuencia
task.spawn(function()
    while true do
        task.wait(0.03) -- 33 ciclos de escaneo por segundo (prácticamente instantáneo)

        if TurboConfig.UltraRepairActive then
            local repairRemote = getRepairRemote()
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local truck, seat = getCurrentTruck()

            if repairRemote and root then
                -- 1. Reparación del camión si está activada
                if TurboConfig.RepairTruck and truck then
                    fireBurst(repairRemote, truck)
                    fireBurst(repairRemote, truck.PrimaryPart or seat)
                end

                -- 2. Escaneo de estructuras dañadas
                local structFolder = workspace:FindFirstChild("Structures") or workspace
                local foundDamaged = false

                for _, struct in ipairs(structFolder:GetChildren()) do
                    if struct:IsA("Model") then
                        local primary = struct.PrimaryPart or struct:FindFirstChildWhichIsA("BasePart")
                        if primary and (primary.Position - root.Position).Magnitude <= TurboConfig.AuraRadius then
                            local mock = struct:FindFirstChild("MockHumanoid")
                            if mock then
                                local hp = mock:GetAttribute("Health") or 0
                                local maxHp = mock:GetAttribute("MaxHealth") or 100

                                if hp < maxHp then
                                    foundDamaged = true
                                    Stats.CurrentTargetName = struct.Name
                                    Stats.CurrentTargetHP = string.format("%d / %d (%.0f%%)", hp, maxHp, (hp / maxHp) * 100)

                                    -- Disparo masivo inmediato
                                    fireBurst(repairRemote, struct)
                                    break
                                end
                            end
                        end
                    end
                end

                if not foundDamaged then
                    Stats.CurrentTargetName = "Ninguna dañada en rango"
                    Stats.CurrentTargetHP = "100%"
                end
            end
        end
    end
end)

print("[OVERCLOCK]: Reparador Turbo cargado con éxito.")
