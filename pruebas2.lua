-- ==============================================================================
-- PILOTO AÉREO DE TECHO V2.0 (WAYPOINTS PRECALCULADOS 0% LAG + I INVERTIDA)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local lp = Players.LocalPlayer

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local Config = {
    Active = false,
    Direction = "ESTE",         -- Por defecto hacia el ESTE (+X)
    Pattern = "Círculo",        -- "Círculo", "Cuadrado", "Zigzag", "Rombo", "I Invertida"

    -- Distancias y alturas configurables
    ForwardStuds = 30,          -- Studs que avanza recto antes de iniciar la figura
    PatternRadius = 24,         -- Amplitud/radio real de la figura en studs
    VerticalDipStuds = 3.0,     -- Studs que baja y sube suavemente durante la figura
    FlySpeed = 65,              -- Velocidad de desplazamiento en studs/s
    RubberbandThreshold = 14,   -- Si el servidor te regresa a <14 studs del origen, vuelve a salir

    -- Gestión de Poder 5 y Arma 2
    AutoWeaponCycle = true,
    Power5Mode = "CooldownHUD", -- "CooldownHUD" (solo Slot 5 exacto) o "TimerFixed" (120s)
    Power5Interval = 120,
    EquipSlot2Default = true
}

local State = {
    StartOrigin = nil,
    Waypoints = {},             -- Lista precalculada de coordenadas Vector3 (0% lag)
    CurrentWpIndex = 1,
    VirtualPos = nil,           -- Posición guía independiente del tirón del servidor
    Phase = "Idle",             -- "Idle", "Advancing", "Pattern"
    StatusText = "En espera (Detenido)",
    LastPower5Tick = 0,
    Power5CooldownText = "Listo"
}

local DIRECTION_VECTORS = {
    NORTE = Vector3.new(0, 0, -1),
    SUR   = Vector3.new(0, 0, 1),
    ESTE  = Vector3.new(1, 0, 0),
    OESTE = Vector3.new(-1, 0, 0)
}

-- ==============================================================================
-- 1. GENERADOR DE COORDENADAS PRECALCULADAS (SE EJECUTA 1 SOLA VEZ = 0% LAG)
-- ==============================================================================

local function buildPatternWaypoints(originPos)
    local fwd = DIRECTION_VECTORS[Config.Direction] or Vector3.new(1, 0, 0)
    local right = Vector3.new(-fwd.Z, 0, fwd.X)
    local center = originPos + (fwd * Config.ForwardStuds)
    local r = Config.PatternRadius
    local dip = Config.VerticalDipStuds
    local pts = {}

    if Config.Pattern == "Círculo" then
        -- 16 puntos exactos alrededor del centro formando un círculo amplio real
        local segments = 16
        for i = 0, segments - 1 do
            local theta = (i / segments) * (math.pi * 2)
            local yOff = -math.abs(math.sin(theta)) * dip
            local p = center + (fwd * (math.cos(theta) * r)) + (right * (math.sin(theta) * r)) + Vector3.new(0, yOff, 0)
            table.insert(pts, p)
        end

    elseif Config.Pattern == "Cuadrado" then
        table.insert(pts, center + (fwd * r) + (right * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center + (fwd * r) - (right * r))
        table.insert(pts, center - (fwd * r) - (right * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center - (fwd * r) + (right * r))

    elseif Config.Pattern == "Zigzag" then
        local steps = 4
        for i = 0, steps do
            local t = (i / steps) * 2 - 1 -- de -1 a +1 en avance
            local side = ((i % 2 == 0) and 1 or -1) * r
            local yOff = ((i % 2 == 0) and -dip or 0)
            table.insert(pts, center + (fwd * (t * (r * 0.75))) + (right * side) + Vector3.new(0, yOff, 0))
        end
        for i = steps - 1, 1, -1 do
            local t = (i / steps) * 2 - 1
            local side = ((i % 2 == 0) and -1 or 1) * r
            table.insert(pts, center + (fwd * (t * (r * 0.75))) + (right * side))
        end

    elseif Config.Pattern == "Rombo" then
        table.insert(pts, center + (fwd * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center + (right * r))
        table.insert(pts, center - (fwd * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center - (right * r))

    elseif Config.Pattern == "I Invertida" then
        -- Forma una I invertida (⊥): llega al frente (center), barre todo hacia un lado,
        -- cruza todo hacia el otro lado y vuelve al centro para repetir
        table.insert(pts, center)
        table.insert(pts, center + (right * r) + Vector3.new(0, -dip, 0))
        table.insert(pts, center)
        table.insert(pts, center - (right * r) + Vector3.new(0, -dip, 0))
    end

    State.Waypoints = pts
    State.CurrentWpIndex = 1
end

-- ==============================================================================
-- 2. GESTIÓN ESTRICTA DE PODER 5 (SIN CONFUNDIR CON SLOT 4) Y ARMA 2
-- ==============================================================================

local function pressNumberKey(num)
    local kc = (num == 2 and Enum.KeyCode.Two) or (num == 5 and Enum.KeyCode.Five)
    if kc then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, kc, false, game)
            task.wait(0.04)
            VirtualInputManager:SendKeyEvent(false, kc, false, game)
        end)
    end
end

-- Busca EXCLUSIVAMENTE la ranura exacta (ej. "5" o "Slot5", nunca "4")
local function getExactSlotFrameAndTool(slotNum)
    local slotStr = tostring(slotNum)
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")
    local exactFrame = nil
    local toolName = nil

    if bpg then
        -- Buscar primero en Hotbar directo para no leer otras ranuras
        local hotbar = bpg:FindFirstChild("Hotbar", true)
        local searchRoot = hotbar or bpg
        for _, child in ipairs(searchRoot:GetChildren()) do
            if child:IsA("GuiObject") and (child.Name == slotStr or child.Name == "Slot" .. slotStr) then
                exactFrame = child
                break
            end
        end

        if exactFrame then
            for _, desc in ipairs(exactFrame:GetDescendants()) do
                if desc:IsA("ObjectValue") and desc.Value and desc.Value:IsA("Tool") then
                    return desc.Value, exactFrame
                elseif desc:IsA("TextLabel") and desc.Text ~= "" and desc.Text ~= slotStr and not desc.Text:match("^[%d:%.s]+$") then
                    toolName = desc.Text
                end
            end
        end
    end

    if not toolName and slotNum == 2 then
        toolName = "LMG"
    end

    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    if toolName then
        if char and char:FindFirstChild(toolName) then return char[toolName], exactFrame end
        if bp and bp:FindFirstChild(toolName) then return bp[toolName], exactFrame end
    end

    local allTools = {}
    if char then
        for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then table.insert(allTools, t) end end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(allTools, t) end end
    end

    return allTools[slotNum], exactFrame
end

local function equipSlot2Only()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return end

    local tool2 = getExactSlotFrameAndTool(2)
    if tool2 then
        if char:FindFirstChildOfClass("Tool") ~= tool2 then
            hum:EquipTool(tool2)
        end
    else
        pressNumberKey(2)
    end
end

-- Solo inspecciona el frame de la ranura 5 (ignora el 4to poder por completo)
local function isPower5ReadyStrict()
    local tool5, slot5Frame = getExactSlotFrameAndTool(5)

    if slot5Frame then
        for _, desc in ipairs(slot5Frame:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" and desc.Text ~= "5" then
                local txt = desc.Text:gsub("%s+", "")
                if txt:match("^%d+:%d+$") or txt:match("^%d+s?$") or txt:match("^%d+%.%d+s?$") then
                    local val = tonumber(txt:match("%d+"))
                    if val and val > 0 then
                        State.Power5CooldownText = "Slot 5 en CD (" .. txt .. ")"
                        return false
                    end
                end
            end
        end
    end

    if tool5 then
        local cd = tool5:GetAttribute("Cooldown") or tool5:GetAttribute("RemainingCooldown")
        if type(cd) == "number" and cd > 0 then
            State.Power5CooldownText = string.format("Slot 5 en CD (%.0fs)", cd)
            return false
        end
        if tool5:GetAttribute("OnCooldown") == true then
            State.Power5CooldownText = "Slot 5 en Cooldown"
            return false
        end
    end

    State.Power5CooldownText = "Slot 5 Listo"
    return true
end

local function triggerPower5AndReturnSlot2()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return end

    local tool5 = getExactSlotFrameAndTool(5)
    if tool5 then
        hum:EquipTool(tool5)
        task.wait(0.06)
        pcall(function() tool5:Activate() end)
        for _, child in ipairs(tool5:GetChildren()) do
            if child:IsA("RemoteEvent") then
                local n = child.Name:lower()
                if n:find("use") or n:find("cast") or n:find("ability") or n:find("activate") then
                    pcall(function() child:FireServer() end)
                end
            end
        end
        task.wait(0.15)
    else
        pressNumberKey(5)
        task.wait(0.15)
    end

    State.LastPower5Tick = tick()
    if Config.EquipSlot2Default then
        equipSlot2Only()
    end
end

task.spawn(function()
    while true do
        task.wait(0.5)
        if not Config.Active or not Config.AutoWeaponCycle then continue end

        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum or hum.Health <= 0 then continue end

        if Config.Power5Mode == "CooldownHUD" then
            if (tick() - State.LastPower5Tick) >= 3.0 and isPower5ReadyStrict() then
                triggerPower5AndReturnSlot2()
            else
                if Config.EquipSlot2Default then
                    equipSlot2Only()
                end
            end
        else
            local elapsed = tick() - State.LastPower5Tick
            if State.LastPower5Tick == 0 or elapsed >= Config.Power5Interval then
                triggerPower5AndReturnSlot2()
            else
                State.Power5CooldownText = string.format("Timer: %ds / %ds", math.floor(Config.Power5Interval - elapsed), Config.Power5Interval)
                if Config.EquipSlot2Default then
                    equipSlot2Only()
                end
            end
        end
    end
end)

-- ==============================================================================
-- 3. FÍSICAS DE VUELO Y SEGUIMIENTO DE COORDENADAS PRECALCULADAS
-- ==============================================================================

local function resetPhysicsCompletely()
    State.Phase = "Idle"
    State.VirtualPos = nil
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if root then
        root.Anchored = false
        for _, obj in ipairs(root:GetChildren()) do
            if obj.Name == "RoofFlyBP" or obj.Name == "RoofFlyBG" then
                obj:Destroy()
            end
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = true
            end
        end
    end

    if hum then
        hum.PlatformStand = false
        hum.AutoRotate = true
    end
end

local function ensureFlightForces(root)
    local bp = root:FindFirstChild("RoofFlyBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "RoofFlyBP"
        bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bp.P = 42000
        bp.D = 900
        bp.Position = root.Position
        bp.Parent = root
    end

    local bg = root:FindFirstChild("RoofFlyBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "RoofFlyBG"
        bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bg.CFrame = root.CFrame
        bg.Parent = root
    end

    return bp, bg
end

RunService.Heartbeat:Connect(function(dt)
    if not Config.Active then return end

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    if not State.StartOrigin then
        State.StartOrigin = root.Position
        State.VirtualPos = root.Position
        State.Phase = "Advancing"
        buildPatternWaypoints(State.StartOrigin)
    end

    hum.PlatformStand = true
    local bp, bg = ensureFlightForces(root)

    local fwdDir = DIRECTION_VECTORS[Config.Direction] or Vector3.new(1, 0, 0)
    local advanceDest = State.StartOrigin + (fwdDir * Config.ForwardStuds)

    -- Si el servidor regresó al personaje al punto inicial del techo mientras hacía la figura:
    -- reiniciar el cursor al inicio y volver a avanzar los 30 studs
    local distToStart = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(State.StartOrigin.X, 0, State.StartOrigin.Z)).Magnitude
    if State.Phase == "Pattern" and distToStart < Config.RubberbandThreshold and Config.ForwardStuds > Config.RubberbandThreshold then
        State.Phase = "Advancing"
        State.VirtualPos = root.Position
        State.CurrentWpIndex = 1
    end

    local targetWp = advanceDest

    if State.Phase == "Advancing" then
        State.StatusText = string.format("➡️ Avanzando al %s (%d studs)...", Config.Direction, Config.ForwardStuds)
        targetWp = advanceDest

        if (State.VirtualPos - advanceDest).Magnitude <= 1.0 then
            State.Phase = "Pattern"
            State.CurrentWpIndex = 1
        end

    elseif State.Phase == "Pattern" then
        local wps = State.Waypoints
        if #wps == 0 then
            buildPatternWaypoints(State.StartOrigin)
            wps = State.Waypoints
        end

        targetWp = wps[State.CurrentWpIndex] or advanceDest
        State.StatusText = string.format("🌪️ %s (%d/%d) | %s", Config.Pattern, State.CurrentWpIndex, #wps, Config.Direction)

        if (State.VirtualPos - targetWp).Magnitude <= 1.2 then
            State.CurrentWpIndex = (State.CurrentWpIndex % #wps) + 1
            targetWp = wps[State.CurrentWpIndex]
        end
    end

    -- Mover el cursor virtual sin depender de la fricción del servidor (evita que el círculo se encoja)
    local diff = targetWp - State.VirtualPos
    local dist = diff.Magnitude
    if dist > 0.01 then
        State.VirtualPos = State.VirtualPos + (diff.Unit * math.min(dist, Config.FlySpeed * dt))
    end

    bp.Position = State.VirtualPos
    bg.CFrame = CFrame.lookAt(root.Position, root.Position + fwdDir)
end)

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA NATIVA ROBLOX (CONTROL + CONFIGURACIÓN)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("RoofAerialPilotGuiV2")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RoofAerialPilotGuiV2"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(20, 125, 175)
FloatBtn.Text = "✈️\nV2.0"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 510, 0, 440)
MainFrame.Position = UDim2.new(0.5, -255, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 19, 26)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 29, 40)
TitleBar.Text = "  ✈️ PILOTO AÉREO V2.0 | COORDENADAS PRECALCULADAS (0% LAG)"
TitleBar.TextColor3 = Color3.fromRGB(0, 235, 255)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TabMainBtn = Instance.new("TextButton")
TabMainBtn.Size = UDim2.new(0.5, -12, 0, 28)
TabMainBtn.Position = UDim2.new(0, 10, 0, 40)
TabMainBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 170)
TabMainBtn.Text = "🎮 CONTROL DE VUELO"
TabMainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TabMainBtn.TextSize = 10
TabMainBtn.Font = Enum.Font.GothamBold
TabMainBtn.Parent = MainFrame
Instance.new("UICorner", TabMainBtn).CornerRadius = UDim.new(0, 6)

local TabConfigBtn = Instance.new("TextButton")
TabConfigBtn.Size = UDim2.new(0.5, -12, 0, 28)
TabConfigBtn.Position = UDim2.new(0.5, 2, 0, 40)
TabConfigBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TabConfigBtn.Text = "⚙️ CONFIGURACIÓN"
TabConfigBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
TabConfigBtn.TextSize = 10
TabConfigBtn.Font = Enum.Font.GothamBold
TabConfigBtn.Parent = MainFrame
Instance.new("UICorner", TabConfigBtn).CornerRadius = UDim.new(0, 6)

local MainPage = Instance.new("Frame")
MainPage.Size = UDim2.new(1, 0, 1, -74)
MainPage.Position = UDim2.new(0, 0, 0, 74)
MainPage.BackgroundTransparency = 1
MainPage.Visible = true
MainPage.Parent = MainFrame

local ConfigPage = Instance.new("ScrollingFrame")
ConfigPage.Size = UDim2.new(1, 0, 1, -74)
ConfigPage.Position = UDim2.new(0, 0, 0, 74)
ConfigPage.BackgroundTransparency = 1
ConfigPage.BorderSizePixel = 0
ConfigPage.CanvasSize = UDim2.new(0, 0, 0, 350)
ConfigPage.ScrollBarThickness = 5
ConfigPage.Visible = false
ConfigPage.Parent = MainFrame

local function switchTab(activeBtn, activePage)
    MainPage.Visible = (activePage == MainPage)
    ConfigPage.Visible = (activePage == ConfigPage)
    TabMainBtn.BackgroundColor3 = (activePage == MainPage) and Color3.fromRGB(0, 130, 170) or Color3.fromRGB(30, 35, 48)
    TabMainBtn.TextColor3 = (activePage == MainPage) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    TabConfigBtn.BackgroundColor3 = (activePage == ConfigPage) and Color3.fromRGB(0, 130, 170) or Color3.fromRGB(30, 35, 48)
    TabConfigBtn.TextColor3 = (activePage == ConfigPage) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
end

TabMainBtn.MouseButton1Click:Connect(function() switchTab(TabMainBtn, MainPage) end)
TabConfigBtn.MouseButton1Click:Connect(function() switchTab(TabConfigBtn, ConfigPage) end)

-- ==============================================================================
-- 5. PESTAÑA 1: CONTROL DE VUELO
-- ==============================================================================

local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, -20, 0, 66)
StatusCard.Position = UDim2.new(0, 10, 0, 4)
StatusCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
StatusCard.Parent = MainPage
Instance.new("UICorner", StatusCard).CornerRadius = UDim.new(0, 6)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -12, 1, -8)
StatusLabel.Position = UDim2.new(0, 6, 0, 4)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Estado: En espera (Detenido)"
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 180)
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextWrapped = true
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.Parent = StatusCard

task.spawn(function()
    while true do
        task.wait(0.35)
        StatusLabel.Text = string.format(
            "Estado: %s\nDirección: %s | Forma: %s\nPoder 5: %s | Arma 2: %s",
            State.StatusText,
            Config.Direction,
            Config.Pattern,
            State.Power5CooldownText,
            Config.AutoWeaponCycle and "ON" or "OFF"
        )
    end
end)

local StartBtn = Instance.new("TextButton")
StartBtn.Size = UDim2.new(0.5, -12, 0, 40)
StartBtn.Position = UDim2.new(0, 10, 0, 78)
StartBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
StartBtn.Text = "▶️ INICIAR VUELO"
StartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StartBtn.TextSize = 11
StartBtn.Font = Enum.Font.GothamBold
StartBtn.Parent = MainPage
Instance.new("UICorner", StartBtn).CornerRadius = UDim.new(0, 8)

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(0.5, -12, 0, 40)
StopBtn.Position = UDim2.new(0.5, 2, 0, 78)
StopBtn.BackgroundColor3 = Color3.fromRGB(195, 45, 55)
StopBtn.Text = "⏹️ DETENER (QUITAR FLY)"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.TextSize = 10
StopBtn.Font = Enum.Font.GothamBold
StopBtn.Parent = MainPage
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 8)

StartBtn.MouseButton1Click:Connect(function()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then
        State.StartOrigin = root.Position
        State.VirtualPos = root.Position
        State.Phase = "Advancing"
        buildPatternWaypoints(State.StartOrigin)
        Config.Active = true
        if Config.EquipSlot2Default then
            equipSlot2Only()
        end
    end
end)

StopBtn.MouseButton1Click:Connect(function()
    Config.Active = false
    State.StartOrigin = nil
    State.StatusText = "Detenido (Físicas reiniciadas)"
    resetPhysicsCompletely()
end)

-- Dirección Cardinal (ESTE seleccionado por defecto)
local DirTitle = Instance.new("TextLabel")
DirTitle.Size = UDim2.new(1, -20, 0, 18)
DirTitle.Position = UDim2.new(0, 10, 0, 126)
DirTitle.BackgroundTransparency = 1
DirTitle.Text = "🧭 DIRECCIÓN DE AVANCE INICIAL:"
DirTitle.TextColor3 = Color3.fromRGB(180, 200, 220)
DirTitle.TextSize = 10
DirTitle.Font = Enum.Font.GothamBold
DirTitle.TextXAlignment = Enum.TextXAlignment.Left
DirTitle.Parent = MainPage

local dirButtons = {}
local dirs = {"NORTE", "SUR", "ESTE", "OESTE"}
for i, dName in ipairs(dirs) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.25, -7, 0, 32)
    b.Position = UDim2.new((i - 1) * 0.25, 10 - ((i - 1) * 2), 0, 146)
    b.BackgroundColor3 = (Config.Direction == dName) and Color3.fromRGB(0, 145, 215) or Color3.fromRGB(30, 35, 48)
    b.Text = dName
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 10
    b.Font = Enum.Font.GothamBold
    b.Parent = MainPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    dirButtons[dName] = b

    b.MouseButton1Click:Connect(function()
        Config.Direction = dName
        if State.StartOrigin then
            buildPatternWaypoints(State.StartOrigin)
            if Config.Active then State.Phase = "Advancing" end
        end
        for k, btn in pairs(dirButtons) do
            btn.BackgroundColor3 = (k == dName) and Color3.fromRGB(0, 145, 215) or Color3.fromRGB(30, 35, 48)
        end
    end)
end

-- 5 Modos de Pirueta (Incluyendo "I Invertida")
local PatTitle = Instance.new("TextLabel")
PatTitle.Size = UDim2.new(1, -20, 0, 18)
PatTitle.Position = UDim2.new(0, 10, 0, 186)
PatTitle.BackgroundTransparency = 1
PatTitle.Text = "🌪️ FORMA EN EL AIRE (WAYPOINTS PRECALCULADOS):"
PatTitle.TextColor3 = Color3.fromRGB(180, 200, 220)
PatTitle.TextSize = 10
PatTitle.Font = Enum.Font.GothamBold
PatTitle.TextXAlignment = Enum.TextXAlignment.Left
PatTitle.Parent = MainPage

local patButtons = {}
local patterns = {"Círculo", "Cuadrado", "Zigzag", "Rombo", "I Invertida"}
for i, pName in ipairs(patterns) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.20, -5, 0, 32)
    b.Position = UDim2.new((i - 1) * 0.20, 10 - ((i - 1) * 1.5), 0, 206)
    b.BackgroundColor3 = (Config.Pattern == pName) and Color3.fromRGB(125, 65, 185) or Color3.fromRGB(30, 35, 48)
    b.Text = pName
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 9
    b.Font = Enum.Font.GothamBold
    b.Parent = MainPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    patButtons[pName] = b

    b.MouseButton1Click:Connect(function()
        Config.Pattern = pName
        if State.StartOrigin then
            buildPatternWaypoints(State.StartOrigin)
        end
        for k, btn in pairs(patButtons) do
            btn.BackgroundColor3 = (k == pName) and Color3.fromRGB(125, 65, 185) or Color3.fromRGB(30, 35, 48)
        end
    end)
end

-- Controles de Poder 5 y Arma 2
local WeaponToggleBtn = Instance.new("TextButton")
WeaponToggleBtn.Size = UDim2.new(1, -20, 0, 34)
WeaponToggleBtn.Position = UDim2.new(0, 10, 0, 250)
WeaponToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
WeaponToggleBtn.Text = "🔫 AUTO PODER 5 + SELECCIONAR ARMA 2: ON"
WeaponToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
WeaponToggleBtn.TextSize = 10
WeaponToggleBtn.Font = Enum.Font.GothamBold
WeaponToggleBtn.Parent = MainPage
Instance.new("UICorner", WeaponToggleBtn).CornerRadius = UDim.new(0, 6)

WeaponToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoWeaponCycle = not Config.AutoWeaponCycle
    WeaponToggleBtn.BackgroundColor3 = Config.AutoWeaponCycle and Color3.fromRGB(30, 145, 80) or Color3.fromRGB(65, 70, 85)
    WeaponToggleBtn.Text = Config.AutoWeaponCycle and "🔫 AUTO PODER 5 + SELECCIONAR ARMA 2: ON" or "🔫 AUTO PODER 5 + ARMA 2: OFF"
end)

local Power5ModeBtn = Instance.new("TextButton")
Power5ModeBtn.Size = UDim2.new(1, -20, 0, 34)
Power5ModeBtn.Position = UDim2.new(0, 10, 0, 290)
Power5ModeBtn.BackgroundColor3 = Color3.fromRGB(0, 125, 185)
Power5ModeBtn.Text = "⏱️ MODO PODER 5: DETECTAR RECARGA SLOT 5 (EXACTO)"
Power5ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
Power5ModeBtn.TextSize = 9
Power5ModeBtn.Font = Enum.Font.GothamBold
Power5ModeBtn.Parent = MainPage
Instance.new("UICorner", Power5ModeBtn).CornerRadius = UDim.new(0, 6)

Power5ModeBtn.MouseButton1Click:Connect(function()
    if Config.Power5Mode == "CooldownHUD" then
        Config.Power5Mode = "TimerFixed"
        State.LastPower5Tick = 0
        Power5ModeBtn.BackgroundColor3 = Color3.fromRGB(175, 105, 25)
        Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: TEMPORIZADOR FIJO (CADA %ds)", Config.Power5Interval)
    else
        Config.Power5Mode = "CooldownHUD"
        Power5ModeBtn.BackgroundColor3 = Color3.fromRGB(0, 125, 185)
        Power5ModeBtn.Text = "⏱️ MODO PODER 5: DETECTAR RECARGA SLOT 5 (EXACTO)"
    end
end)

-- ==============================================================================
-- 6. PESTAÑA 2: CONFIGURACIÓN (RECALCULA WAYPOINTS AL INSTANTE AL EDITAR)
-- ==============================================================================

local function createStepper(yPos, title, getSubText, onMinus, onPlus)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 48)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    row.Parent = ConfigPage
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, -10, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title .. "\n" .. getSubText()
    lbl.TextColor3 = Color3.fromRGB(235, 240, 250)
    lbl.TextSize = 9
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local minusBtn = Instance.new("TextButton")
    minusBtn.Size = UDim2.new(0, 46, 0, 32)
    minusBtn.Position = UDim2.new(1, -106, 0, 8)
    minusBtn.BackgroundColor3 = Color3.fromRGB(165, 45, 55)
    minusBtn.Text = "➖"
    minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minusBtn.TextSize = 12
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.Parent = row
    Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

    local plusBtn = Instance.new("TextButton")
    plusBtn.Size = UDim2.new(0, 46, 0, 32)
    plusBtn.Position = UDim2.new(1, -54, 0, 8)
    plusBtn.BackgroundColor3 = Color3.fromRGB(30, 145, 80)
    plusBtn.Text = "➕"
    plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    plusBtn.TextSize = 12
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.Parent = row
    Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

    minusBtn.MouseButton1Click:Connect(function()
        onMinus()
        if State.StartOrigin then buildPatternWaypoints(State.StartOrigin) end
        lbl.Text = title .. "\n" .. getSubText()
    end)

    plusBtn.MouseButton1Click:Connect(function()
        onPlus()
        if State.StartOrigin then buildPatternWaypoints(State.StartOrigin) end
        lbl.Text = title .. "\n" .. getSubText()
    end)
end

createStepper(6, "➡️ DISTANCIA AVANCE INICIAL (STUDS)",
    function() return string.format("Actual: %d studs hacia delante antes de girar", Config.ForwardStuds) end,
    function() Config.ForwardStuds = math.max(5, Config.ForwardStuds - 5) end,
    function() Config.ForwardStuds = math.min(150, Config.ForwardStuds + 5) end
)

createStepper(60, "🔄 AMPLITUD DE FORMA (CÍRCULO / I INVERTIDA / ETC.)",
    function() return string.format("Actual: %d studs de radio / amplitud", Config.PatternRadius) end,
    function() Config.PatternRadius = math.max(8, Config.PatternRadius - 2) end,
    function() Config.PatternRadius = math.min(80, Config.PatternRadius + 2) end
)

createStepper(114, "↕️ BAJADA / SUBIDA EN PIRUETA (STUDS)",
    function() return string.format("Actual: %.1f studs de oscilación vertical", Config.VerticalDipStuds) end,
    function() Config.VerticalDipStuds = math.max(0.0, Config.VerticalDipStuds - 0.5) end,
    function() Config.VerticalDipStuds = math.min(15.0, Config.VerticalDipStuds + 0.5) end
)

createStepper(168, "✈️ VELOCIDAD DE VUELO (STUDS/S)",
    function() return string.format("Actual: %d studs/s", Config.FlySpeed) end,
    function() Config.FlySpeed = math.max(15, Config.FlySpeed - 5) end,
    function() Config.FlySpeed = math.min(200, Config.FlySpeed + 5) end
)

createStepper(222, "🔙 UMBRAL DETECCIÓN REGRESO AL TECHO",
    function() return string.format("Actual: Si vuelves a <%d studs del inicio, sale de nuevo", Config.RubberbandThreshold) end,
    function() Config.RubberbandThreshold = math.max(4, Config.RubberbandThreshold - 2) end,
    function() Config.RubberbandThreshold = math.min(40, Config.RubberbandThreshold + 2) end
)

createStepper(276, "⏱️ TIEMPO DE ESPERA MODO TEMPORIZADOR (PODER 5)",
    function() return string.format("Actual: Cada %d segundos", Config.Power5Interval) end,
    function()
        Config.Power5Interval = math.max(10, Config.Power5Interval - 10)
        if Config.Power5Mode == "TimerFixed" then
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: TEMPORIZADOR FIJO (CADA %ds)", Config.Power5Interval)
        end
    end,
    function()
        Config.Power5Interval = math.min(300, Config.Power5Interval + 10)
        if Config.Power5Mode == "TimerFixed" then
            Power5ModeBtn.Text = string.format("⏱️ MODO PODER 5: TEMPORIZADOR FIJO (CADA %ds)", Config.Power5Interval)
        end
    end
)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
