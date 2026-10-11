-- ==============================================================================
-- LABORATORIO DE INMORTALIDAD & GODMODE TESTER (SIN DEPENDENCIAS EXTERNAS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local TestModes = {
    BlockImpactRemote = true,    -- Modo 1: Bloquear Remote 'Impact' del camión
    BlockDamageRemotes = false,  -- Modo 2: Bloquear cualquier Remote de daño (Hit, Damage, Hurt)
    DisableTruckCanTouch = false,-- Modo 3: Desactivar CanTouch en el camión (Física sí, daño por toque no)
    DisableTankCanTouch = false, -- Modo 4: Desarmar hitboxes de Tanks cercanos (CanTouch = false)
    FlingTankRepel = false,      -- Modo 5: Repulsión física de Tanks antes del impacto
    SyncedAutoRepair = false     -- Modo 6: Reparación en bucle seguro (0.42s)
}

local Diagnostics = {
    CurrentTruckHP = "Buscando...",
    MaxTruckHP = "Buscando...",
    HPLocation = "Desconocida",
    LastDamageTaken = 0,
    LastDamageTime = "Nunca",
    InterceptedImpactCalls = 0,
    InterceptedDamageCalls = 0,
    Logs = {}
}

local function logMsg(txt)
    local entry = string.format("[%s] %s", os.date("%X"), txt)
    table.insert(Diagnostics.Logs, entry)
    if #Diagnostics.Logs > 30 then table.remove(Diagnostics.Logs, 1) end
    print(entry)
end

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

-- RASTREADOR EN VIVO DE LA VIDA DEL CAMIÓN (BUSCA EN ATRIBUTOS, VALORES Y GUI)
local lastRecordedHP = nil
local function trackTruckHealth()
    local truck, seat = getCurrentTruck()
    if not truck then
        Diagnostics.CurrentTruckHP = "No estás montado"
        Diagnostics.MaxTruckHP = "N/A"
        return
    end

    local foundHP, foundMax = nil, nil
    local loc = "No encontrada"

    -- 1. Buscar en Atributos del camión
    for _, attr in ipairs({"Health", "HP", "Durability", "Vida", "VehicleHealth"}) do
        local val = truck:GetAttribute(attr)
        if val and type(val) == "number" then
            foundHP = val
            foundMax = truck:GetAttribute("Max" .. attr) or 1000
            loc = "Atributo: " .. attr
            break
        end
    end

    -- 2. Buscar en Values dentro del camión
    if not foundHP then
        for _, desc in ipairs(truck:GetDescendants()) do
            if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                local n = desc.Name:lower()
                if n == "health" or n == "hp" or n == "durability" or n == "vida" then
                    foundHP = desc.Value
                    foundMax = 1000
                    loc = "Value: " .. desc:GetFullName()
                    break
                end
            end
        end
    end

    -- 3. Buscar en el MockHumanoid o Humanoid del camión
    if not foundHP then
        local hum = truck:FindFirstChildOfClass("Humanoid") or truck:FindFirstChild("MockHumanoid")
        if hum then
            if hum:IsA("Humanoid") then
                foundHP = hum.Health
                foundMax = hum.MaxHealth
                loc = "Humanoid interno"
            else
                foundHP = hum:GetAttribute("Health")
                foundMax = hum:GetAttribute("MaxHealth")
                loc = "MockHumanoid"
            end
        end
    end

    -- 4. Buscar en la interfaz del jugador (PlayerGui) si hay velocímetro con barra de vida
    if not foundHP then
        local pGui = lp:FindFirstChild("PlayerGui")
        if pGui then
            for _, desc in ipairs(pGui:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible and desc.Text:find("%d") then
                    local pName = desc.Parent and desc.Parent.Name:lower() or ""
                    local lName = desc.Name:lower()
                    if pName:find("car") or pName:find("veh") or lName:find("hp") or lName:find("health") then
                        foundHP = tonumber(desc.Text:match("%d+"))
                        if foundHP then
                            loc = "GUI: " .. desc.Name
                            break
                        end
                    end
                end
            end
        end
    end

    if foundHP then
        Diagnostics.CurrentTruckHP = tostring(foundHP)
        Diagnostics.MaxTruckHP = tostring(foundMax or "?")
        Diagnostics.HPLocation = loc

        -- Detección de daño recibido
        if lastRecordedHP and foundHP < lastRecordedHP then
            local lost = lastRecordedHP - foundHP
            Diagnostics.LastDamageTaken = lost
            Diagnostics.LastDamageTime = os.date("%X")
            logMsg(string.format("💥 ¡DAÑO DETECTADO! -%.1f HP (Vida actual: %.1f)", lost, foundHP))
        end
        lastRecordedHP = foundHP
    else
        Diagnostics.CurrentTruckHP = "No visible en cliente"
        Diagnostics.HPLocation = "Controlada 100% por Servidor"
    end
end

-- ==============================================================================
-- 1. HOOKMETAMETHOD (ESPÍA Y BLOQUEO DE REMOTES)
-- ==============================================================================
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if method == "FireServer" then
            local rName = tostring(self.Name)

            -- MODO 1: Bloquear Impact del camión
            if rName == "Impact" then
                Diagnostics.InterceptedImpactCalls = Diagnostics.InterceptedImpactCalls + 1
                if TestModes.BlockImpactRemote then
                    logMsg("🛑 Bloqueado Remote 'Impact' (Colisión)")
                    return nil
                end
            end

            -- MODO 2: Bloquear cualquier Remote con nombre de daño/golpe
            local rLower = rName:lower()
            if rLower:find("damage") or rLower:find("hit") or rLower:find("hurt") or rLower:find("takedamage") then
                Diagnostics.InterceptedDamageCalls = Diagnostics.InterceptedDamageCalls + 1
                if TestModes.BlockDamageRemotes then
                    logMsg("🛑 Bloqueado Remote de daño: " .. rName)
                    return nil
                end
            end
        end

        return oldNamecall(self, ...)
    end)
end

-- ==============================================================================
-- 2. FÍSICAS: CANTOUCH DEL CAMIÓN Y DE LOS TANKS
-- ==============================================================================
RunService.Heartbeat:Connect(function()
    local truck = getCurrentTruck()
    if not truck then return end

    -- MODO 3: Desactivar CanTouch en partes exteriores del camión
    if TestModes.DisableTruckCanTouch then
        for _, p in ipairs(truck:GetDescendants()) do
            if p:IsA("BasePart") and p.CanTouch then
                p.CanTouch = false
            end
        end
    end

    -- MODO 4 & 5: Detectar Tanks cercanos (radio 35 studs)
    if TestModes.DisableTankCanTouch or TestModes.FlingTankRepel then
        local tPos = truck.PrimaryPart and truck.PrimaryPart.Position
        local charFolder = workspace:FindFirstChild("Characters") or workspace

        if tPos then
            for _, ent in ipairs(charFolder:GetChildren()) do
                if ent:IsA("Model") and ent ~= lp.Character then
                    local eName = ent.Name:lower()
                    local isTank = eName:find("tank") or tostring(ent:GetAttribute("Variant") or ""):lower():find("tank")

                    if isTank then
                        local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
                        if eRoot and (eRoot.Position - tPos).Magnitude <= 35 then
                            -- MODO 4: Apagar CanTouch en el Tank para que no active daño por contacto
                            if TestModes.DisableTankCanTouch then
                                for _, part in ipairs(ent:GetDescendants()) do
                                    if part:IsA("BasePart") and part.CanTouch then
                                        part.CanTouch = false
                                    end
                                end
                            end

                            -- MODO 5: Repulsión física (empujar hacia abajo/atrás al Tank)
                            if TestModes.FlingTankRepel then
                                local awayDir = (eRoot.Position - tPos).Unit
                                eRoot.AssemblyLinearVelocity = Vector3.new(awayDir.X * 120, -50, awayDir.Z * 120)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- MODO 6: AUTO-REPARACIÓN EN BUCLE SEGURO (0.42s)
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

-- ==============================================================================
-- 3. INTERFAZ NATIVA ROBLOX (WIDGET FLOTANTE Y PANEL)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NativeGodmodeLabGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante
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
MainFrame.Size = UDim2.new(0, 520, 0, 440)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -220)
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
TitleBar.Text = "  LABORATORIO DE INMORTALIDAD (TESTER)"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel de Estado de Vida en Tiempo Real
local HealthPanel = Instance.new("TextLabel")
HealthPanel.Size = UDim2.new(1, -20, 0, 75)
HealthPanel.Position = UDim2.new(0, 10, 0, 42)
HealthPanel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
HealthPanel.TextColor3 = Color3.fromRGB(0, 255, 170)
HealthPanel.TextSize = 11
HealthPanel.Font = Enum.Font.Code
HealthPanel.TextXAlignment = Enum.TextXAlignment.Left
HealthPanel.TextYAlignment = Enum.TextYAlignment.Top
HealthPanel.Text = " Rastreando vida del vehículo..."
HealthPanel.Parent = MainFrame

local HPPanelCorner = Instance.new("UICorner")
HPPanelCorner.CornerRadius = UDim.new(0, 6)
HPPanelCorner.Parent = HealthPanel

-- Contenedor de Botones de Prueba
local function createTestToggle(yPos, name, defaultVal, callback)
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

createTestToggle(124, "Modo 1: Bloquear Remote 'Impact' (Colisión)", TestModes.BlockImpactRemote, function(v)
    TestModes.BlockImpactRemote = v
end)

createTestToggle(160, "Modo 2: Bloquear Remotes de Daño Globales (Hit/Damage)", TestModes.BlockDamageRemotes, function(v)
    TestModes.BlockDamageRemotes = v
end)

createTestToggle(196, "Modo 3: Camión No-Touch (CanTouch = false en chasis)", TestModes.DisableTruckCanTouch, function(v)
    TestModes.DisableTruckCanTouch = v
    if not v then
        local t = getCurrentTruck()
        if t then
            for _, p in ipairs(t:GetDescendants()) do if p:IsA("BasePart") then p.CanTouch = true end end
        end
    end
end)

createTestToggle(232, "Modo 4: Desarmar Hitbox del Tank (CanTouch = false en Tank)", TestModes.DisableTankCanTouch, function(v)
    TestModes.DisableTankCanTouch = v
end)

createTestToggle(268, "Modo 5: Repulsión Antigravedad de Tanks (Fling cercano)", TestModes.FlingTankRepel, function(v)
    TestModes.FlingTankRepel = v
end)

createTestToggle(304, "Modo 6: Auto-Reparación en Bucle Seguro (+125 cada 0.42s)", TestModes.SyncedAutoRepair, function(v)
    TestModes.SyncedAutoRepair = v
end)

-- Botón de Copiar Registro
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 345)
CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
CopyBtn.Text = "📋 COPIAR REGISTRO DE EVENTOS Y DAÑO"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 12
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local rep = {
        "==================================================================",
        "          REGISTRO DE LABORATORIO: INMORTALIDAD VEHICULAR         ",
        "==================================================================",
        "Hora: " .. os.date("%X"),
        string.format("Vida Camión: %s / %s (%s)", Diagnostics.CurrentTruckHP, Diagnostics.MaxTruckHP, Diagnostics.HPLocation),
        string.format("Último Daño: -%.1f HP a las %s", Diagnostics.LastDamageTaken, Diagnostics.LastDamageTime),
        string.format("Remotes Impact Interceptados: %d", Diagnostics.InterceptedImpactCalls),
        string.format("Remotes Daño Interceptados: %d", Diagnostics.InterceptedDamageCalls),
        "\n[HISTORIAL DE EVENTOS RECIENTES]:"
    }
    for _, l in ipairs(Diagnostics.Logs) do table.insert(rep, " " .. l) end
    table.insert(rep, "==================================================================")

    local txt = table.concat(rep, "\n")
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡REGISTRO COPIADO!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR REGISTRO DE EVENTOS Y DAÑO"
end)

-- Botón de Reset de Registro
local ResetBtn = Instance.new("TextButton")
ResetBtn.Size = UDim2.new(1, -20, 0, 32)
ResetBtn.Position = UDim2.new(0, 10, 0, 390)
ResetBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
ResetBtn.Text = "🔄 REINICIAR CONTADORES DE DAÑO"
ResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetBtn.TextSize = 11
ResetBtn.Font = Enum.Font.GothamBold
ResetBtn.Parent = MainFrame

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 6)
ResetCorner.Parent = ResetBtn

ResetBtn.MouseButton1Click:Connect(function()
    Diagnostics.LastDamageTaken = 0
    Diagnostics.LastDamageTime = "Ninguno"
    Diagnostics.InterceptedImpactCalls = 0
    Diagnostics.InterceptedDamageCalls = 0
    table.clear(Diagnostics.Logs)
    logMsg("Contadores reiniciados.")
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- Bucle de actualización de monitor
task.spawn(function()
    while true do
        task.wait(0.3)
        trackTruckHealth()

        HealthPanel.Text = string.format(
            " Vida Camión: %s / %s | Fuente: %s\n Último Daño Sufrido: -%.1f HP (Hora: %s)\n Impact bloqueados: %d | Remotes Daño bloqueados: %d",
            Diagnostics.CurrentTruckHP,
            Diagnostics.MaxTruckHP,
            Diagnostics.HPLocation,
            Diagnostics.LastDamageTaken,
            Diagnostics.LastDamageTime,
            Diagnostics.InterceptedImpactCalls,
            Diagnostics.InterceptedDamageCalls
        )
    end
end)

print("[LABORATORIO]: Iniciado con éxito.")
