-- ==============================================================================
-- REPARADOR TURBO CALIBRADO (ANTI-ROLLBACK / CERO TELETRANSPORTE) & GODMODE
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local TurboConfig = {
    BlockImpactDamage = true,     -- Inmunidad al Tank (Bloqueo de 'Impact')
    UltraRepairActive = true,     -- Reparación activa
    BurstPackets = 4,             -- Paquetes por ciclo (Calibrado para no saturar red)
    ScanInterval = 0.06,          -- Intervalo óptimo (~16 ciclos/seg = ~64 PPS)
    MaxDistance = 14.0,           -- 14 studs (Dentro del límite seguro de 15 del juego)
    RepairTruck = true            -- Reparar el camión si estás montado
}

local Stats = {
    PacketsSentLastSec = 0,
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
            return nil -- Descarta el choque contra Tanks
        end
        return oldNamecall(self, ...)
    end)
end

-- ==============================================================================
-- 2. INTERFAZ NATIVA ROBLOX (WIDGET FLOTANTE)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SmoothRepairGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante
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
MainFrame.Size = UDim2.new(0, 420, 0, 320)
MainFrame.Position = UDim2.new(0.5, -210, 0.5, -160)
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
TitleBar.Text = "  REPARADOR TURBO (CALIBRADO ANTI-DESYNC)"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -20, 0, 80)
StatusLbl.Position = UDim2.new(0, 10, 0, 44)
StatusLbl.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
StatusLbl.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusLbl.TextSize = 11
StatusLbl.Font = Enum.Font.Code
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.TextYAlignment = Enum.TextYAlignment.Top
StatusLbl.Text = " Sistema de reparación activo..."
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

createToggleBtn(136, "Reparación Rápida Fluida (Sin Rollback)", TurboConfig.UltraRepairActive, function(s)
    TurboConfig.UltraRepairActive = s
end)

createToggleBtn(180, "Inmunidad a Choques de Tanks (Anti-Impact)", TurboConfig.BlockImpactDamage, function(s)
    TurboConfig.BlockImpactDamage = s
end)

createToggleBtn(224, "Reparar Camión Actual en Movimiento", TurboConfig.RepairTruck, function(s)
    TurboConfig.RepairTruck = s
end)

-- Selector de Perfil de Velocidad
local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(1, -20, 0, 36)
ModeBtn.Position = UDim2.new(0, 10, 0, 268)
ModeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
ModeBtn.Text = "⚡ Modo: RÁPIDO EQUILIBRADO (~60 PPS)"
ModeBtn.TextColor3 = Color3.fromRGB(255, 200, 0)
ModeBtn.TextSize = 12
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.Parent = MainFrame

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 6)
ModeCorner.Parent = ModeBtn

local currentMode = 1
ModeBtn.MouseButton1Click:Connect(function()
    currentMode = (currentMode % 2) + 1
    if currentMode == 1 then
        TurboConfig.BurstPackets = 4
        TurboConfig.ScanInterval = 0.06
        ModeBtn.Text = "⚡ Modo: RÁPIDO EQUILIBRADO (~60 PPS)"
    else
        TurboConfig.BurstPackets = 7
        TurboConfig.ScanInterval = 0.05
        ModeBtn.Text = "🔥 Modo: VELOZ SIN DESYNC (~140 PPS)"
    end
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- ==============================================================================
-- 3. MOTOR DE DISPARO CALIBRADO (FLUJO CONSTANTE SIN LAG)
-- ==============================================================================
local packetCounter = 0

-- Monitor por segundo
task.spawn(function()
    while true do
        task.wait(1.0)
        Stats.PacketsSentLastSec = packetCounter
        packetCounter = 0

        local truck = getCurrentTruck()
        local tInfo = truck and string.format("Camión: %s | Anti-Tank: %s", truck.Name, TurboConfig.BlockImpactDamage and "ACTIVO" or "OFF") or "A pie"

        StatusLbl.Text = string.format(
            " %s\n Tasa de Red: %d paquetes/seg (PPS Fluido)\n Estructura en rango: %s\n Estado Salud: %s",
            tInfo,
            Stats.PacketsSentLastSec,
            Stats.CurrentTargetName,
            Stats.CurrentTargetHP
        )
    end
end)

-- Bucle de reparación coordinado
task.spawn(function()
    while true do
        task.wait(TurboConfig.ScanInterval)

        if TurboConfig.UltraRepairActive then
            local repairRemote = getRepairRemote()
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local truck, seat = getCurrentTruck()

            if repairRemote and root then
                -- 1. Reparación de camión si aplica
                if TurboConfig.RepairTruck and truck then
                    for _ = 1, TurboConfig.BurstPackets do
                        repairRemote:FireServer(truck)
                        repairRemote:FireServer(truck.PrimaryPart or seat)
                        packetCounter = packetCounter + 2
                    end
                end

                -- 2. Escaneo de estructuras respetando el rango de 14 studs
                local structFolder = workspace:FindFirstChild("Structures") or workspace
                local foundDamaged = false

                for _, struct in ipairs(structFolder:GetChildren()) do
                    if struct:IsA("Model") then
                        local primary = struct.PrimaryPart or struct:FindFirstChildWhichIsA("BasePart")
                        if primary then
                            local dist = (primary.Position - root.Position).Magnitude
                            if dist <= TurboConfig.MaxDistance then
                                local mock = struct:FindFirstChild("MockHumanoid")
                                if mock then
                                    local hp = mock:GetAttribute("Health") or 0
                                    local maxHp = mock:GetAttribute("MaxHealth") or 100

                                    if hp < maxHp then
                                        foundDamaged = true
                                        Stats.CurrentTargetName = struct.Name
                                        Stats.CurrentTargetHP = string.format("%d / %d (%.0f%%)", hp, maxHp, (hp / maxHp) * 100)

                                        -- Disparo de ráfaga controlada
                                        for _ = 1, TurboConfig.BurstPackets do
                                            repairRemote:FireServer(struct)
                                            packetCounter = packetCounter + 1
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                if not foundDamaged then
                    Stats.CurrentTargetName = "Ninguna dañada en rango (<14 studs)"
                    Stats.CurrentTargetHP = "100%"
                end
            end
        end
    end
end)

print("[REPARADOR]: Calibrado con éxito. Sin teletransportes de posición.")
