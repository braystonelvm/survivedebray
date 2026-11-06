-- ==============================================================================
-- AUTO-WALK & FLY FOLLOWER V2.0 (INTERFAZ NATIVA ROBLOX - 0% LIBRERÍAS EXTERNAS)
-- 3 Modos: Random / Manual / Lista Blanca + Zona Especial + Vuelo a Base Alta
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local BaseCenter = Vector3.new(0, 0, 0)
local BASE_PERIMETER_RADIUS = 135
local BASE_HIGH_Y_THRESHOLD = 12.0
local SIDE_FLY_DISTANCE = 4.5

local SPECIAL_ZONE_POS = Vector3.new(-90.2, 3.9, -69.7)
local SPECIAL_ZONE_RADIUS = 60
local SPECIAL_FOLLOW_DIST = 7
local NORMAL_MAX_DIST = 25

local WHITELIST_USERS = {
    ["xhstg0137"] = true,
    ["saraaai38"] = true,
    ["lu_lx"] = true
}

local State = {
    Active = false,
    FollowMode = "Random", -- "Random" | "Manual" | "Whitelist"
    CurrentTargetPlayer = nil,
    ManualTargetIndex = 1,
    Status = "Inactivo",
    PlayerCount = 0,
    InSpecialZone = false,
    IsFlyingAboveBase = false
}

-- ==============================================================================
-- 1. FUNCIONES AUXILIARES DE PERSONAJE, FÍSICA Y BASE
-- ==============================================================================

local function getMyParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getPlayerParts(plr)
    if not plr or not plr.Character then return nil, nil end
    local char = plr.Character
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 and root then
        return root, hum
    end
    return nil, nil
end

local function getOtherPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            table.insert(list, p)
        end
    end
    return list
end

local function getWhitelistPlayerInServer()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and WHITELIST_USERS[p.Name:lower()] then
            local root, _ = getPlayerParts(p)
            if root then return p end
        end
    end
    return nil
end

local function isTargetAboveBase(pos)
    local horizDist = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(BaseCenter.X, 0, BaseCenter.Z)).Magnitude
    return (horizDist <= BASE_PERIMETER_RADIUS) and (pos.Y >= BASE_HIGH_Y_THRESHOLD)
end

local function getOrCreateFlightPhysics(root)
    local bp = root:FindFirstChild("FollowFlyBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "FollowFlyBP"
        bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bp.P = 28000
        bp.D = 900
        bp.Position = root.Position
        bp.Parent = root
    end

    local bg = root:FindFirstChild("FollowFlyBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "FollowFlyBG"
        bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bg.CFrame = root.CFrame
        bg.Parent = root
    end

    return bp, bg
end

local function removeFlightPhysics(root)
    if not root then return end
    local bp = root:FindFirstChild("FollowFlyBP")
    if bp then bp:Destroy() end
    local bg = root:FindFirstChild("FollowFlyBG")
    if bg then bg:Destroy() end
    root.AssemblyLinearVelocity = Vector3.zero
end

-- ==============================================================================
-- 2. GESTIÓN Y ROTACIÓN DE OBJETIVOS
-- ==============================================================================

local function pickTarget()
    local others = getOtherPlayers()
    State.PlayerCount = #others + 1

    if State.FollowMode == "Whitelist" then
        local wlPlayer = getWhitelistPlayerInServer()
        State.CurrentTargetPlayer = wlPlayer
        return
    end

    if State.FollowMode == "Manual" then
        if #others == 0 then
            State.CurrentTargetPlayer = nil
            return
        end
        if State.ManualTargetIndex > #others then
            State.ManualTargetIndex = 1
        end
        State.CurrentTargetPlayer = others[State.ManualTargetIndex]
        return
    end

    if State.FollowMode == "Random" then
        if not State.CurrentTargetPlayer or not State.CurrentTargetPlayer.Parent or not getPlayerParts(State.CurrentTargetPlayer) then
            if #others > 0 then
                State.CurrentTargetPlayer = others[math.random(1, #others)]
            else
                State.CurrentTargetPlayer = nil
            end
        end
    end
end

-- Actualizador de lista y conteo cada 5 segundos
task.spawn(function()
    while true do
        task.wait(5.0)
        local others = getOtherPlayers()
        State.PlayerCount = #others + 1

        if State.Active then
            if State.FollowMode == "Random" then
                if #others > 0 then
                    State.CurrentTargetPlayer = others[math.random(1, #others)]
                end
            elseif State.FollowMode == "Whitelist" then
                State.CurrentTargetPlayer = getWhitelistPlayerInServer()
            end
        end
    end
end)

-- ==============================================================================
-- 3. MOTOR HÍBRIDO (CAMINATA INTELIGENTE + VUELO A BASE ALTA)
-- ==============================================================================

local currentWanderDest = nil
local nextWanderTick = 0

task.spawn(function()
    while true do
        task.wait(0.15)

        local myChar, myRoot, myHum = getMyParts()

        if not State.Active then
            if myRoot then removeFlightPhysics(myRoot) end
            State.IsFlyingAboveBase = false
            currentWanderDest = nil
            continue
        end

        if not myRoot or not myHum or myHum.Health <= 0 then
            continue
        end

        pickTarget()

        local targetPlr = State.CurrentTargetPlayer

        if State.FollowMode == "Whitelist" and not targetPlr then
            removeFlightPhysics(myRoot)
            State.IsFlyingAboveBase = false
            myHum:MoveTo(myRoot.Position)
            State.Status = "Esperando a: xhstg0137 / saraaai38 / lu_lx..."
            continue
        end

        if not targetPlr then
            removeFlightPhysics(myRoot)
            State.IsFlyingAboveBase = false
            myHum:MoveTo(myRoot.Position)
            State.Status = "Sin jugadores disponibles en la partida"
            continue
        end

        local tRoot, tHum = getPlayerParts(targetPlr)
        if not tRoot or not tHum then
            removeFlightPhysics(myRoot)
            State.IsFlyingAboveBase = false
            myHum:MoveTo(myRoot.Position)
            State.Status = string.format("Esperando reaparición de '%s'", targetPlr.Name)
            continue
        end

        -- CONDICIÓN PRINCIPAL: ¿EL OBJETIVO ESTÁ ARRIBA DE LA BASE?
        if isTargetAboveBase(tRoot.Position) then
            State.IsFlyingAboveBase = true
            State.InSpecialZone = false
            currentWanderDest = nil

            local bp, bg = getOrCreateFlightPhysics(myRoot)

            -- Posición a su costado (vector derecha del objetivo)
            local sideOffset = tRoot.CFrame.RightVector * SIDE_FLY_DISTANCE
            local targetFlyPos = tRoot.Position + sideOffset + Vector3.new(0, 0.4, 0)

            bp.Position = targetFlyPos
            bg.CFrame = CFrame.lookAt(myRoot.Position, myRoot.Position + tRoot.CFrame.LookVector)

            State.Status = string.format("🦅 Volando al costado de '%s' (Base Alta)", targetPlr.Name)
            continue
        else
            -- Si el objetivo bajó o no está arriba de la base, remover físicas de vuelo limpiamente
            if State.IsFlyingAboveBase or myRoot:FindFirstChild("FollowFlyBP") then
                removeFlightPhysics(myRoot)
                State.IsFlyingAboveBase = false
                myHum:ChangeState(Enum.HumanoidStateType.Freefall)
            end
        end

        local distToTarget = (Vector3.new(tRoot.Position.X, 0, tRoot.Position.Z) - Vector3.new(myRoot.Position.X, 0, myRoot.Position.Z)).Magnitude
        local distToSpecialZone = (Vector3.new(tRoot.Position.X, 0, tRoot.Position.Z) - Vector3.new(SPECIAL_ZONE_POS.X, 0, SPECIAL_ZONE_POS.Z)).Magnitude

        -- CONDICIÓN 2: ZONA ESPECIAL (Dentro de 60 studs de la coordenada objetivo)
        if distToSpecialZone <= SPECIAL_ZONE_RADIUS then
            State.InSpecialZone = true
            State.Status = string.format("Zona Especial: Siguiendo a '%s' a 7 studs", targetPlr.Name)

            if distToTarget > SPECIAL_FOLLOW_DIST then
                local dir = (tRoot.Position - myRoot.Position).Unit
                local targetPoint = tRoot.Position - (dir * (SPECIAL_FOLLOW_DIST - 1))
                myHum:MoveTo(targetPoint)
            else
                myHum:MoveTo(myRoot.Position)
            end
            currentWanderDest = nil

        -- CONDICIÓN 3: CAMINATA Y DESPLAZAMIENTO NORMAL EN SUELO
        else
            State.InSpecialZone = false
            local targetMoving = tRoot.AssemblyLinearVelocity.Magnitude > 2.5

            if targetMoving then
                State.Status = string.format("Siguiendo desplazamiento de '%s'", targetPlr.Name)
                if distToTarget > 12 then
                    myHum:MoveTo(tRoot.Position)
                end
                currentWanderDest = nil
            else
                State.Status = string.format("Paseando cerca de '%s' (<= 25 studs)", targetPlr.Name)

                local now = tick()
                if not currentWanderDest or now >= nextWanderTick or (myRoot.Position - currentWanderDest).Magnitude <= 3.5 then
                    local ang = math.random() * math.pi * 2
                    local r = math.random(6, NORMAL_MAX_DIST)
                    currentWanderDest = tRoot.Position + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
                    nextWanderTick = now + math.random(3, 5)
                end

                if distToTarget > NORMAL_MAX_DIST + 4 then
                    myHum:MoveTo(tRoot.Position)
                elseif currentWanderDest then
                    myHum:MoveTo(currentWanderDest)
                end
            end
        end

        -- Salto para librar pequeños desniveles
        local ray = Ray.new(myRoot.Position, myRoot.CFrame.LookVector * 3.5)
        local hit = workspace:FindPartOnRayWithIgnoreList(ray, {myChar})
        if hit and hit.CanCollide then
            myHum.Jump = true
        end
    end
end)

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA NATIVA ROBLOX (SCREENGUI)
-- ==============================================================================

local function getSafeGuiParent()
    local success, res = pcall(function()
        if gethui then return gethui() end
        return CoreGui
    end)
    if success and res then return res end
    return lp:WaitForChild("PlayerGui")
end

local GuiParent = getSafeGuiParent()

local existing = GuiParent:FindFirstChild("AutoWalkFollowerGui")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoWalkFollowerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 440, 0, 360)
MainFrame.Position = UDim2.new(0.5, -220, 0.5, -180)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "   🚶 AUTO-WALK & FLY FOLLOWER (NATIVO)"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 95)
StatusBox.Position = UDim2.new(0, 10, 0, 44)
StatusBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
StatusBox.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusBox.TextSize = 10
StatusBox.Font = Enum.Font.Code
StatusBox.TextXAlignment = Enum.TextXAlignment.Left
StatusBox.TextYAlignment = Enum.TextYAlignment.Top
StatusBox.Text = "Iniciando sistema..."
StatusBox.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusBox

local function createBtn(text, color, pos, size, callback)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- Botón 1: Encender / Apagar
local ToggleBtn
ToggleBtn = createBtn("▶ INICIAR SEGUIMIENTO", Color3.fromRGB(30, 150, 70), UDim2.new(0, 10, 0, 146), UDim2.new(1, -20, 0, 36), function()
    State.Active = not State.Active
    local _, myRoot, myHum = getMyParts()

    if State.Active then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
        ToggleBtn.Text = "⏹ DETENER SEGUIMIENTO"
        pickTarget()
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 70)
        ToggleBtn.Text = "▶ INICIAR SEGUIMIENTO"
        if myRoot then removeFlightPhysics(myRoot) end
        if myHum then myHum:MoveTo(myRoot and myRoot.Position or Vector3.zero) end
        State.IsFlyingAboveBase = false
        State.Status = "Detenido manualmente"
    end
end)

-- Botón 2: Selector de Modo (Random / Manual / Whitelist)
local ModeBtn
ModeBtn = createBtn("MODO: RANDOM (CUALQUIERA)", Color3.fromRGB(45, 100, 180), UDim2.new(0, 10, 0, 190), UDim2.new(1, -20, 0, 34), function()
    if State.FollowMode == "Random" then
        State.FollowMode = "Manual"
        ModeBtn.BackgroundColor3 = Color3.fromRGB(190, 120, 20)
        ModeBtn.Text = "MODO: MANUAL (SELECCIÓN EN VIVO)"
    elseif State.FollowMode == "Manual" then
        State.FollowMode = "Whitelist"
        ModeBtn.BackgroundColor3 = Color3.fromRGB(140, 45, 160)
        ModeBtn.Text = "MODO: LISTA BLANCA (3 USUARIOS)"
    else
        State.FollowMode = "Random"
        ModeBtn.BackgroundColor3 = Color3.fromRGB(45, 100, 180)
        ModeBtn.Text = "MODO: RANDOM (CUALQUIERA)"
    end
    pickTarget()
end)

-- Botones 3 y 4: Cambiar Objetivo Manual (Anterior / Siguiente)
createBtn("◀ JUGADOR ANTERIOR", Color3.fromRGB(45, 50, 65), UDim2.new(0, 10, 0, 232), UDim2.new(0.48, -5, 0, 32), function()
    local others = getOtherPlayers()
    if #others == 0 then return end
    State.ManualTargetIndex = State.ManualTargetIndex - 1
    if State.ManualTargetIndex < 1 then State.ManualTargetIndex = #others end
    State.CurrentTargetPlayer = others[State.ManualTargetIndex]
end)

createBtn("SIGUIENTE JUGADOR ▶", Color3.fromRGB(45, 50, 65), UDim2.new(0.52, 0, 0, 232), UDim2.new(0.48, -10, 0, 32), function()
    local others = getOtherPlayers()
    if #others == 0 then return end
    State.ManualTargetIndex = State.ManualTargetIndex + 1
    if State.ManualTargetIndex > #others then State.ManualTargetIndex = 1 end
    State.CurrentTargetPlayer = others[State.ManualTargetIndex]
end)

-- Botón 5: Forzar Selección Aleatoria Inmediata
createBtn("🎲 SORTEAR OTRO USUARIO AHORA", Color3.fromRGB(35, 120, 100), UDim2.new(0, 10, 0, 272), UDim2.new(1, -20, 0, 32), function()
    local others = getOtherPlayers()
    if #others > 0 then
        State.CurrentTargetPlayer = others[math.random(1, #others)]
    end
end)

-- Botón 6: Detener en Seco y Quitar Vuelo
createBtn("🛑 FRENAR PERSONAJE", Color3.fromRGB(70, 75, 90), UDim2.new(0, 10, 0, 312), UDim2.new(1, -20, 0, 32), function()
    local _, myRoot, myHum = getMyParts()
    if myRoot then removeFlightPhysics(myRoot) end
    if myHum and myRoot then myHum:MoveTo(myRoot.Position) end
    State.IsFlyingAboveBase = false
    currentWanderDest = nil
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "🚶\nWALK"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Monitor visual de estado
task.spawn(function()
    while true do
        task.wait(0.3)

        local targetName = State.CurrentTargetPlayer and State.CurrentTargetPlayer.Name or "Ninguno"
        local _, myRoot, _ = getMyParts()
        local distText = "N/A"

        if State.CurrentTargetPlayer and myRoot then
            local tRoot, _ = getPlayerParts(State.CurrentTargetPlayer)
            if tRoot then
                distText = string.format("%d studs", math.floor((tRoot.Position - myRoot.Position).Magnitude))
            end
        end

        local actionLocationText = "🟢 Suelo Normal"
        if State.IsFlyingAboveBase then
            actionLocationText = "🦅 Vuelo al Costado (Base Alta)"
        elseif State.InSpecialZone then
            actionLocationText = "🚨 Zona Especial (-90.2, 3.9, -69.7)"
        end

        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Jugadores en Servidor: %d (Actualiza c/5s)\n" ..
            "Modo: %s | Objetivo: '%s' (Dist: %s)\n" ..
            "Acción: %s\n" ..
            "Lista Blanca: xhstg0137, saraaai38, lu_lx",
            State.Active and "🟢 ACTIVO" or "🔴 INACTIVO",
            State.PlayerCount,
            State.FollowMode,
            targetName,
            distText,
            actionLocationText
        )
    end
end)
