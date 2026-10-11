-- ==============================================================================
-- TRUCK ANTI-TANK MUSCLE (ANULACIÓN DE IMPACTO Y COLISIÓN SÓLIDA)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Config = {
    GhostTankMode = true,       -- Atraviesa al Tank Muscle (CanCollide = false)
    ZeroMassTank = true,        -- Quita la densidad de roca al Tank (Density = 0.001)
    BlockImpactRemote = true,   -- Bloquea paquetes de daño de choque
    TankRadarESP = true,        -- Resalta en rojo neón a los Tank Muscle
    ScanRadius = 60             -- Radio de neutralización física en studs
}

local Stats = {
    TanksNeutralized = 0,
    ClosestTankDist = "Ninguno",
    ClosestTankName = "N/A"
}

local TankHighlights = {}

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

-- ==============================================================================
-- 1. BLOQUEO DEL REMOTE 'IMPACT'
-- ==============================================================================
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if Config.BlockImpactRemote and method == "FireServer" and self.Name == "Impact" then
            return nil
        end
        return oldNamecall(self, ...)
    end)
end

-- ==============================================================================
-- 2. NEUTRALIZADOR FÍSICO DE TANK MUSCLE (CERO DAÑO POR ESCOMBRO)
-- ==============================================================================
local zeroDensityProperties = PhysicalProperties.new(0.001, 0, 0, 0, 0)

RunService.Heartbeat:Connect(function()
    local truck, seat = getCurrentTruck()
    if not truck then return end

    local truckPos = (truck.PrimaryPart or seat).Position
    local charFolder = workspace:FindFirstChild("Characters") or workspace

    local count = 0
    local closestDist = math.huge
    local closestName = "N/A"

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and not Players:GetPlayerFromCharacter(ent) then
            local name = ent.Name:lower()
            local variant = tostring(ent:GetAttribute("Variant") or ""):lower()
            local isTank = name:find("tank") or name:find("muscle") or variant:find("tank") or variant:find("muscle")

            if isTank then
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
                local hum = ent:FindFirstChildOfClass("Humanoid")

                if eRoot and (not hum or hum.Health > 0) then
                    local dist = (eRoot.Position - truckPos).Magnitude

                    if dist < closestDist then
                        closestDist = dist
                        closestName = ent.Name
                    end

                    -- RESALTADOR VISUAL (ESP)
                    if Config.TankRadarESP and not TankHighlights[ent] then
                        local hl = Instance.new("Highlight")
                        hl.Name = "TankMuscleESP"
                        hl.FillColor = Color3.fromRGB(255, 30, 30)
                        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                        hl.FillTransparency = 0.35
                        hl.Adornee = ent
                        hl.Parent = ent
                        TankHighlights[ent] = hl
                    end

                    -- APLICACIÓN FÍSICA A TANKS DENTRO DEL RANGO
                    if dist <= Config.ScanRadius then
                        count = count + 1

                        for _, part in ipairs(ent:GetDescendants()) do
                            if part:IsA("BasePart") then
                                -- MODO FANTASMA: Sin colisión sólida, pero CON detección táctil para arrollarlo
                                if Config.GhostTankMode and part.CanCollide then
                                    part.CanCollide = false
                                    part.CanTouch = true
                                end

                                -- MASA CERO: Evita que frene el auto como escombro
                                if Config.ZeroMassTank then
                                    pcall(function()
                                        part.CustomPhysicalProperties = zeroDensityProperties
                                        part.Massless = true
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    Stats.TanksNeutralized = count
    Stats.ClosestTankDist = closestDist < 800 and string.format("%.1f studs", closestDist) or "Ninguno"
    Stats.ClosestTankName = closestName
end)

-- ==============================================================================
-- 3. INTERFAZ NATIVA (WIDGET FLOTANTE ROJO)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AntiTankMuscleGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
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
BtnIcon.Text = "🛡️"
BtnIcon.TextSize = 22
BtnIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnIcon.Parent = FloatBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 440, 0, 310)
MainFrame.Position = UDim2.new(0.5, -220, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
TitleBar.Text = "  NEUTRALIZADOR DE TANK MUSCLE"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local MonitorLbl = Instance.new("TextLabel")
MonitorLbl.Size = UDim2.new(1, -20, 0, 68)
MonitorLbl.Position = UDim2.new(0, 10, 0, 42)
MonitorLbl.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
MonitorLbl.TextColor3 = Color3.fromRGB(0, 255, 170)
MonitorLbl.TextSize = 11
MonitorLbl.Font = Enum.Font.Code
MonitorLbl.TextXAlignment = Enum.TextXAlignment.Left
MonitorLbl.TextYAlignment = Enum.TextYAlignment.Top
MonitorLbl.Text = " Escaneando Tank Muscles..."
MonitorLbl.Parent = MainFrame

local MonCorner = Instance.new("UICorner")
MonCorner.CornerRadius = UDim.new(0, 6)
MonCorner.Parent = MonitorLbl

local function createToggle(yPos, name, defaultVal, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 34)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = defaultVal and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(80, 25, 25)
    btn.Text = (defaultVal and "🟢 " or "🔴 ") .. name
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    local st = defaultVal
    btn.MouseButton1Click:Connect(function()
        st = not st
        btn.BackgroundColor3 = st and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(80, 25, 25)
        btn.Text = (st and "🟢 " or "🔴 ") .. name
        callback(st)
    end)
end

createToggle(120, "Modo Fantasma (Atravesar Tank Muscle sin choque)", Config.GhostTankMode, function(v) Config.GhostTankMode = v end)
createToggle(160, "Masa Cero en Tanks (Evita desaceleración de escombro)", Config.ZeroMassTank, function(v) Config.ZeroMassTank = v end)
createToggle(200, "Bloquear Remote 'Impact' (Daño de choque vehicular)", Config.BlockImpactRemote, function(v) Config.BlockImpactRemote = v end)
createToggle(240, "ESP / Resaltador Rojo para Tank Muscle", Config.TankRadarESP, function(v) Config.TankRadarESP = v end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

task.spawn(function()
    while true do
        task.wait(0.3)
        local radarInfo = Stats.ClosestTankDist ~= "Ninguno"
            and string.format("%s a %s", Stats.ClosestTankName, Stats.ClosestTankDist)
            or "Ninguno en radar"

        MonitorLbl.Text = string.format(
            " Tank Muscle más cercano: %s\n Tanks neutralizados en radio (60 studs): %d\n Modo Fantasma: %s | Masa Cero: %s",
            radarInfo,
            Stats.TanksNeutralized,
            Config.GhostTankMode and "ACTIVO (Sin choque)" or "OFF",
            Config.ZeroMassTank and "ACTIVO (Sin frenado)" or "OFF"
        )
    end
end)
