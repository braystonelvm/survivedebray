-- ==============================================================================
-- LABORATORIO DE INMORTALIDAD V2: RADAR DE TANKS (ESP) & PROTECCIÓN DE HORDA
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local TestModes = {
    BlockImpactRemote = true,       -- Bloquear Remote 'Impact' (Colisiones)
    BlockDamageRemotes = true,      -- Bloquear Remotes globales de daño
    DisableTruckCanTouch = false,   -- Apagar CanTouch en chasis del camión
    ProtectAllZombies = true,       -- True = Protege contra toda la horda / False = Solo Tanks
    FlingRepel = false,             -- Repulsión física de zombies antes del contacto
    SyncedAutoRepair = true,        -- Auto-reparación de fondo (+125 cada 0.42s)
    TankESP = true                  -- Resaltar Tanks automáticamente con neón rojo
}

local Diagnostics = {
    CurrentTruckHP = "Buscando...",
    MaxTruckHP = "Buscando...",
    HPLocation = "Desconocida",
    LastDamageTaken = 0,
    LastDamageTime = "Ninguno",
    ImpactBlockedCount = 0,
    DamageBlockedCount = 0,
    ClosestTankDist = "Ninguno en radar",
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

-- RASTREO PRECISO DE VIDA DEL CAMIÓN
local lastHP = nil
local function updateTruckHP()
    local truck, seat = getCurrentTruck()
    if not truck then
        Diagnostics.CurrentTruckHP = "No estás montado"
        Diagnostics.MaxTruckHP = "N/A"
        return
    end

    local foundHP, foundMax = nil, nil
    local loc = "No encontrada"

    -- 1. Atributos
    for _, attr in ipairs({"Health", "HP", "Durability", "Vida", "VehicleHealth"}) do
        local val = truck:GetAttribute(attr)
        if val and type(val) == "number" then
            foundHP = val
            foundMax = truck:GetAttribute("Max" .. attr) or 1000
            loc = "Atributo: " .. attr
            break
        end
    end

    -- 2. Values
    if not foundHP then
        for _, desc in ipairs(truck:GetDescendants()) do
            if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                local n = desc.Name:lower()
                if n == "health" or n == "hp" or n == "durability" then
                    foundHP = desc.Value
                    foundMax = 1000
                    loc = "Value: " .. desc.Name
                    break
                end
            end
        end
    end

    -- 3. Humanoid / MockHumanoid
    if not foundHP then
        local mock = truck:FindFirstChild("MockHumanoid") or truck:FindFirstChildOfClass("Humanoid")
        if mock then
            foundHP = mock:GetAttribute("Health") or (mock:IsA("Humanoid") and mock.Health)
            foundMax = mock:GetAttribute("MaxHealth") or (mock:IsA("Humanoid") and mock.MaxHealth)
            loc = mock.ClassName
        end
    end

    if foundHP then
        Diagnostics.CurrentTruckHP = string.format("%.1f", foundHP)
        Diagnostics.MaxTruckHP = tostring(foundMax or "?")
        Diagnostics.HPLocation = loc

        if lastHP and foundHP < lastHP then
            Diagnostics.LastDamageTaken = lastHP - foundHP
            Diagnostics.LastDamageTime = os.date("%X")
        end
        lastHP = foundHP
    else
        Diagnostics.CurrentTruckHP = "Protegido por Server"
    end
end

-- ==============================================================================
-- 1. HOOKS DE DAÑO (ANULACIÓN DE IMPACTO Y REMOTES)
-- ==============================================================================
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" then
            local rName = tostring(self.Name)

            if TestModes.BlockImpactRemote and rName == "Impact" then
                Diagnostics.ImpactBlockedCount = Diagnostics.ImpactBlockedCount + 1
                return nil
            end

            local rLower = rName:lower()
            if TestModes.BlockDamageRemotes and (rLower:find("damage") or rLower:find("hit") or rLower:find("hurt")) then
                Diagnostics.DamageBlockedCount = Diagnostics.DamageBlockedCount + 1
                return nil
            end
        end
        return oldNamecall(self, ...)
    end)
end

-- ==============================================================================
-- 2. RADAR DE TANKS (ESP) Y GESTIÓN DE CANTOUCH
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.2)
        local truck, seat = getCurrentTruck()
        local truckPos = truck and (truck.PrimaryPart or seat).Position
        local charFolder = workspace:FindFirstChild("Characters") or workspace

        local closestDist = math.huge
        local closestName = "N/A"

        for _, ent in ipairs(charFolder:GetChildren()) do
            if ent:IsA("Model") and ent ~= lp.Character and not Players:GetPlayerFromCharacter(ent) then
                local hum = ent:FindFirstChildOfClass("Humanoid")
                local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart

                if eRoot and (not hum or hum.Health > 0) then
                    local name = ent.Name:lower()
                    local variant = tostring(ent:GetAttribute("Variant") or ""):lower()
                    local isTank = name:find("tank") or variant:find("tank") or name:find("golem") or name:find("brute")

                    local dist = truckPos and (eRoot.Position - truckPos).Magnitude or 999

                    -- RADAR Y RESALTADO DE TANKS
                    if isTank then
                        if dist < closestDist then
                            closestDist = dist
                            closestName = ent.Name
                        end

                        if TestModes.TankESP and not TankHighlights[ent] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "TankAlertESP"
                            hl.FillColor = Color3.fromRGB(255, 30, 30)
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.FillTransparency = 0.3
                            hl.Adornee = ent
                            hl.Parent = ent
                            TankHighlights[ent] = hl
                        end
                    end

                    -- GESTIÓN FÍSICA SEGÚN EL MODO (SOLO TANK O TODA LA HORDA)
                    local shouldAffect = TestModes.ProtectAllZombies or isTank
                    if shouldAffect and dist <= 35 then
                        -- Anular CanTouch para que los ataques cuerpo a cuerpo no conecten
                        for _, p in ipairs(ent:GetDescendants()) do
                            if p:IsA("BasePart") and p.CanTouch then
                                p.CanTouch = false
                            end
                        end

                        -- Repulsión física
                        if TestModes.FlingRepel and truckPos then
                            local away = (eRoot.Position - truckPos).Unit
                            eRoot.AssemblyLinearVelocity = Vector3.new(away.X * 100, -30, away.Z * 100)
                        end
                    end
                end
            end
        end

        Diagnostics.ClosestTankDist = closestDist < 800 and string.format("%.1f studs", closestDist) or "Ninguno en radar"
        Diagnostics.ClosestTankName = closestName
    end
end)

-- AUTO-REPARACIÓN DE FONDO (SWEET SPOT 0.42s)
task.spawn(function()
    while true do
        task.wait(0.42)
        if TestModes.SyncedAutoRepair then
            local truck, seat = getCurrentTruck()
            local bp = lp:FindFirstChild("Backpack")
            local hammer = bp and bp:FindFirstChild("Repair Hammer")
            local remote = hammer and hammer:FindFirstChild("Repair")

            if truck and remote then
                pcall(function() remote:FireServer(truck) end)
                pcall(function() remote:FireServer(truck.PrimaryPart or seat) end)
            end
        end
    end
end)

-- GESTIÓN DEL CANTOUCH DEL CAMIÓN
RunService.Heartbeat:Connect(function()
    if TestModes.DisableTruckCanTouch then
        local truck = getCurrentTruck()
        if truck then
            for _, p in ipairs(truck:GetDescendants()) do
                if p:IsA("BasePart") and p.CanTouch then p.CanTouch = false end
            end
        end
    end
end)

-- ==============================================================================
-- 3. INTERFAZ NATIVA ROBLOX (WIDGET FLOTANTE Y PANEL)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ImmortalLabV2Gui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante Rojo
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

-- Ventana Principal
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 410)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -205)
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
TitleBar.Text = "  LABORATORIO DE INMORTALIDAD & RADAR"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel de Estado y Radar
local MonitorLbl = Instance.new("TextLabel")
MonitorLbl.Size = UDim2.new(1, -20, 0, 85)
MonitorLbl.Position = UDim2.new(0, 10, 0, 42)
MonitorLbl.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
MonitorLbl.TextColor3 = Color3.fromRGB(0, 255, 170)
MonitorLbl.TextSize = 11
MonitorLbl.Font = Enum.Font.Code
MonitorLbl.TextXAlignment = Enum.TextXAlignment.Left
MonitorLbl.TextYAlignment = Enum.TextYAlignment.Top
MonitorLbl.Text = " Escaneando entorno..."
MonitorLbl.Parent = MainFrame

local MonCorner = Instance.new("UICorner")
MonCorner.CornerRadius = UDim.new(0, 6)
MonCorner.Parent = MonitorLbl

local function createToggle(yPos, name, defaultVal, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 32)
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

createToggle(134, "Bloquear Remote 'Impact' (Choques)", TestModes.BlockImpactRemote, function(v) TestModes.BlockImpactRemote = v end)
createToggle(170, "Protección Contra TODA la Horda (No solo Tanks)", TestModes.ProtectAllZombies, function(v) TestModes.ProtectAllZombies = v end)
createToggle(206, "Camión No-Touch (Desactivar CanTouch en chasis)", TestModes.DisableTruckCanTouch, function(v) TestModes.DisableTruckCanTouch = v end)
createToggle(242, "Repulsión Física (Empujar zombies cercanos)", TestModes.FlingRepel, function(v) TestModes.FlingRepel = v end)
createToggle(278, "Auto-Reparación Sincronizada (+125 cada 0.42s)", TestModes.SyncedAutoRepair, function(v) TestModes.SyncedAutoRepair = v end)
createToggle(314, "ESP / Resaltador Rojo de Tanks", TestModes.TankESP, function(v) TestModes.TankESP = v end)

-- Botón de Reiniciar Daño
local ResetBtn = Instance.new("TextButton")
ResetBtn.Size = UDim2.new(1, -20, 0, 34)
ResetBtn.Position = UDim2.new(0, 10, 0, 356)
ResetBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
ResetBtn.Text = "🔄 REINICIAR CONTADOR DE DAÑO"
ResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetBtn.TextSize = 11
ResetBtn.Font = Enum.Font.GothamBold
ResetBtn.Parent = MainFrame

local RstCorner = Instance.new("UICorner")
RstCorner.CornerRadius = UDim.new(0, 6)
RstCorner.Parent = ResetBtn

ResetBtn.MouseButton1Click:Connect(function()
    Diagnostics.LastDamageTaken = 0
    Diagnostics.LastDamageTime = "Ninguno"
    Diagnostics.ImpactBlockedCount = 0
    Diagnostics.DamageBlockedCount = 0
    ResetBtn.Text = "✅ CONTADORES REINICIADOS"
    task.wait(1)
    ResetBtn.Text = "🔄 REINICIAR CONTADOR DE DAÑO"
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- Actualización continua del monitor
task.spawn(function()
    while true do
        task.wait(0.3)
        updateTruckHP()

        local radarText = Diagnostics.ClosestTankDist ~= "Ninguno en radar" 
            and string.format("🚨 TANK CERCA: %s (%s)", Diagnostics.ClosestTankName, Diagnostics.ClosestTankDist)
            or "Radar Tank: Ninguno en 800 studs"

        MonitorLbl.Text = string.format(
            " Vida Camión: %s / %s | %s\n Daño Recibido: -%.1f HP (Hora: %s)\n Impact bloqueados: %d | Remotes daño: %d\n %s",
            Diagnostics.CurrentTruckHP,
            Diagnostics.MaxTruckHP,
            Diagnostics.HPLocation,
            Diagnostics.LastDamageTaken,
            Diagnostics.LastDamageTime,
            Diagnostics.ImpactBlockedCount,
            Diagnostics.DamageBlockedCount,
            radarText
        )
    end
end)
