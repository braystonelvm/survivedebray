-- ==============================================================================
-- REPARADOR DE INGENIERO TURBO & TRUCK GODMODE (SIN DEPENDENCIAS EXTERNAS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Config = {
    BlockImpactDamage = true,    -- Anula daño al atropellar Tanks
    InstantAuraRepair = true,     -- Repara estructuras dañadas en radio
    RepairTruckDirect = true,     -- Intenta reparar el camión por remote
    AuraRadius = 35,             -- Radio de reparación en studs
    PacketsPerCycle = 10         -- Pulsos de reparación por ciclo
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

-- OBTENER EL REMOTE REPAIR DIRECTAMENTE DESDE LA MOCHILA (SIN EQUIPAR)
local function getRepairRemote()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))
    return hammer and hammer:FindFirstChild("Repair")
end

-- ==============================================================================
-- 1. BLOQUEO DE DAÑO POR IMPACTO (ANTI-TANK GODMODE)
-- ==============================================================================
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if Config.BlockImpactDamage and method == "FireServer" and self.Name == "Impact" then
            return nil -- Descarta el paquete de choque
        end
        return oldNamecall(self, ...)
    end)
end

-- ==============================================================================
-- 2. INTERFAZ NATIVA ROBLOX (WIDGET FLOTANTE Y PANEL)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NativeEngineerRepairGui"
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
BtnIcon.Text = "🔨"
BtnIcon.TextSize = 22
BtnIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnIcon.Parent = FloatBtn

-- Ventana Principal
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 420, 0, 320)
MainFrame.Position = UDim2.new(0.5, -210, 0.5, -160)
MainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
TitleBar.Text = "  INGENIERO TURBO & TRUCK DEFENSE"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Estado en vivo
local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -20, 0, 80)
StatusLbl.Position = UDim2.new(0, 10, 0, 44)
StatusLbl.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
StatusLbl.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusLbl.TextSize = 12
StatusLbl.Font = Enum.Font.Code
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.TextYAlignment = Enum.TextYAlignment.Top
StatusLbl.Text = " Buscando estructuras y vehículo..."
StatusLbl.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusLbl

-- Función auxiliar para botones de alternancia
local function createToggleBtn(yPos, labelText, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 38)
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

createToggleBtn(134, "Inmunidad a Choques de Tanks (Anti-Impact)", Config.BlockImpactDamage, function(s)
    Config.BlockImpactDamage = s
end)

createToggleBtn(178, "Aura de Reparación Instantánea (Bases/Vallas)", Config.InstantAuraRepair, function(s)
    Config.InstantAuraRepair = s
end)

createToggleBtn(222, "Reparar Camión Actual en Movimiento", Config.RepairTruckDirect, function(s)
    Config.RepairTruckDirect = s
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- ==============================================================================
-- 3. MOTOR DE REPARACIÓN RÁPIDA (DESDE LA MOCHILA)
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.1)
        local repairRemote = getRepairRemote()
        local char = lp.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local truck, seat = getCurrentTruck()

        local repairedCount = 0

        if repairRemote and root then
            -- 1. REPARACIÓN DEL CAMIÓN (SIN EQUIPAR HERRAMIENTA)
            if Config.RepairTruckDirect and truck then
                for _ = 1, Config.PacketsPerCycle do
                    pcall(function() repairRemote:FireServer(truck) end)
                    pcall(function() repairRemote:FireServer(truck.PrimaryPart or seat) end)
                end
                repairedCount = repairedCount + 1
            end

            -- 2. REPARACIÓN INSTANTÁNEA DE ESTRUCTURAS DAÑADAS
            if Config.InstantAuraRepair then
                local structFolder = workspace:FindFirstChild("Structures") or workspace
                for _, struct in ipairs(structFolder:GetChildren()) do
                    if struct:IsA("Model") then
                        local primary = struct.PrimaryPart or struct:FindFirstChildWhichIsA("BasePart")
                        if primary and (primary.Position - root.Position).Magnitude <= Config.AuraRadius then
                            local mock = struct:FindFirstChild("MockHumanoid")
                            if mock then
                                local hp = mock:GetAttribute("Health") or 0
                                local maxHp = mock:GetAttribute("MaxHealth") or 100

                                -- Solo repara si tiene daño
                                if hp < maxHp then
                                    for _ = 1, Config.PacketsPerCycle do
                                        pcall(function() repairRemote:FireServer(struct) end)
                                    end
                                    repairedCount = repairedCount + 1
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Actualizar texto de estado
        local truckStatus = truck and string.format("Camión: %s | Anti-Tank: %s", truck.Name, Config.BlockImpactDamage and "ACTIVO" or "OFF") or "A pie (sin vehículo)"
        StatusLbl.Text = string.format(" %s\n Martillo: %s\n Estructuras reparándose en rango: %d",
            truckStatus,
            repairRemote and "Detectado en Mochila (Seguro)" or "No encontrado",
            repairedCount
        )
    end
end)

print("[INGENIERO]: Sistema iniciado sin errores.")
