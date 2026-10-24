-- ==============================================================================
-- AUTO-UNSTUCK WATCHDOG: DETECTOR DE DESPLAZAMIENTO + FILTRO LLANTAS + TRIPLE PIVOT
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

local Config = {
    WatchdogEnabled = true,
    StuckTimeout = 3.5,       -- Segundos detenido antes de considerarse atascado
    MinMoveDistance = 2.0,    -- Mínimo de studs que debe avanzar en ese tiempo
    MaxWheelDisplacement = 12 -- Si una llanta está a más de 12 studs del chasis, se considera salida
}

local WatchdogState = {
    IsPiloting = false,       -- Indica si el auto debería estarse moviendo
    LastPos = Vector3.zero,
    LastMoveTick = tick(),
    Status = "Monitoreando...",
    TotalUnstucks = 0,
    IgnoredBrokenWheels = 0
}

-- ==============================================================================
-- 1. OBTENCIÓN DE VEHÍCULO Y PARTES
-- ==============================================================================

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getVehicle()
    local _, _, hum = getCharacterParts()
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local car = seat:FindFirstAncestorOfClass("Model") or seat.Parent
        return car, seat
    end
    return nil, nil
end

-- ==============================================================================
-- 2. FILTRO: VERIFICAR SI LAS LLANTAS SIGUEN EN SU SITIO
-- ==============================================================================

local function areWheelsIntact(car, seat)
    if not car or not seat then return false end

    local seatPos = seat.Position
    local wheelCount = 0

    for _, part in ipairs(car:GetDescendants()) do
        if part:IsA("BasePart") then
            local n = part.Name:lower()
            if n:find("wheel") or n:find("tire") or n:find("rueda") or n:find("llanta") then
                wheelCount = wheelCount + 1
                local distToSeat = (part.Position - seatPos).Magnitude

                -- Si una rueda se salió o se desfasó por el bug bajo tierra
                if distToSeat > Config.MaxWheelDisplacement then
                    return false, string.format("Llanta '%s' salida (a %d studs del asiento)", part.Name, math.floor(distToSeat))
                end
            end
        end
    end

    -- Si el auto tiene al menos 2 ruedas detectadas y todas están cerca del chasis
    return true, "Llantas en posición normal"
end

-- ==============================================================================
-- 3. RUTINA: TRIPLE PIVOT TO SECUENCIAL
-- ==============================================================================

local function executeTriplePivot(car, seat)
    if not car or not seat then return end

    WatchdogState.TotalUnstucks = WatchdogState.TotalUnstucks + 1

    local function zeroVelocity()
        for _, p in ipairs(car:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end

    -- SALTO 1: Despegar del fondo (+4 studs arriba y leve retroceso)
    local cf1 = car:GetPivot()
    local look1 = cf1.LookVector
    local flatLook = Vector3.new(look1.X, 0, look1.Z)
    if flatLook.Magnitude < 0.1 then flatLook = Vector3.new(0, 0, 1) else flatLook = flatLook.Unit end

    local targetPos1 = cf1.Position + Vector3.new(0, 4.0, 0) - (flatLook * 4.0)
    car:PivotTo(CFrame.lookAt(targetPos1, targetPos1 + flatLook))
    zeroVelocity()
    task.wait(0.1)

    -- SALTO 2: Enderezar chasis en el aire (+4.5 studs arriba y 0° de inclinación)
    local cf2 = car:GetPivot()
    local targetPos2 = cf2.Position + Vector3.new(0, 4.5, 0)
    car:PivotTo(CFrame.lookAt(targetPos2, targetPos2 + flatLook))
    zeroVelocity()
    task.wait(0.1)

    -- SALTO 3: Consolidar salida sobre la superficie (+5.0 studs arriba)
    local cf3 = car:GetPivot()
    local targetPos3 = cf3.Position + Vector3.new(0, 5.0, 0)
    car:PivotTo(CFrame.lookAt(targetPos3, targetPos3 + flatLook))
    zeroVelocity()

    WatchdogState.LastPos = targetPos3
    WatchdogState.LastMoveTick = tick()
end

-- ==============================================================================
-- 4. BUCLE DE DETECCIÓN DE DESPLAZAMIENTO (1.5s)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.25)

        if Config.WatchdogEnabled then
            local car, seat = getVehicle()

            if car and seat then
                local currentPos = (car.PrimaryPart and car.PrimaryPart.Position) or seat.Position

                -- Si está activo el piloto automático o el auto intenta moverse
                if WatchdogState.IsPiloting then
                    local movedDist = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(WatchdogState.LastPos.X, 0, WatchdogState.LastPos.Z)).Magnitude

                    -- Si avanzó adecuadamente, reinicia el temporizador
                    if movedDist >= Config.MinMoveDistance then
                        WatchdogState.LastPos = currentPos
                        WatchdogState.LastMoveTick = tick()
                        WatchdogState.Status = "En movimiento normal"
                    else
                        -- Si lleva más de 1.5s sin moverse
                        local stuckTime = tick() - WatchdogState.LastMoveTick

                        if stuckTime >= Config.StuckTimeout then
                            -- Comprobación obligatoria de llantas
                            local intact, reason = areWheelsIntact(car, seat)

                            if intact then
                                WatchdogState.Status = "🚨 Atascado detectado -> Ejecutando Triple PivotTo..."
                                executeTriplePivot(car, seat)
                            else
                                WatchdogState.IgnoredBrokenWheels = WatchdogState.IgnoredBrokenWheels + 1
                                WatchdogState.Status = "⚠️ Ignorado: " .. reason
                                -- Evitar disparar continuamente mientras las llantas sigan salidas
                                WatchdogState.LastMoveTick = tick() + 2.0
                            end
                        else
                            WatchdogState.Status = string.format("Inmóvil hace %.1fs / %.1fs", stuckTime, Config.StuckTimeout)
                        end
                    end
                else
                    WatchdogState.LastPos = currentPos
                    WatchdogState.LastMoveTick = tick()
                    WatchdogState.Status = "Piloto apagado (Inactivo)"
                end
            else
                WatchdogState.Status = "Fuera del vehículo"
                WatchdogState.LastMoveTick = tick()
            end
        else
            WatchdogState.Status = "Watchdog desactivado"
        end
    end
end)

-- ==============================================================================
-- 5. INTERFAZ GRÁFICA TÁCTIL (DELTA / MÓVIL)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WatchdogUnstuckGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 440, 0, 320)
MainFrame.Position = UDim2.new(0.5, -220, 0.5, -160)
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
TitleBar.Text = "  🛠️ VIGILANTE DE DESPLAZAMIENTO & TRIPLE PIVOT"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel de Estado
local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 100)
StatusBox.Position = UDim2.new(0, 10, 0, 44)
StatusBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
StatusBox.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusBox.TextSize = 10
StatusBox.Font = Enum.Font.Code
StatusBox.TextXAlignment = Enum.TextXAlignment.Left
StatusBox.TextYAlignment = Enum.TextYAlignment.Top
StatusBox.Text = "Iniciando..."
StatusBox.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusBox

-- Botón 1: Simular / Activar Modo Piloto (Para que el watchdog sepa que el auto debe moverse)
local PilotToggleBtn = Instance.new("TextButton")
PilotToggleBtn.Size = UDim2.new(0.48, -5, 0, 42)
PilotToggleBtn.Position = UDim2.new(0, 10, 0, 154)
PilotToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
PilotToggleBtn.Text = "PILOTO AUTOMÁTICO:\nOFF"
PilotToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PilotToggleBtn.TextSize = 10
PilotToggleBtn.Font = Enum.Font.GothamBold
PilotToggleBtn.Parent = MainFrame

local PilotCorner = Instance.new("UICorner")
PilotCorner.CornerRadius = UDim.new(0, 6)
PilotCorner.Parent = PilotToggleBtn

PilotToggleBtn.MouseButton1Click:Connect(function()
    WatchdogState.IsPiloting = not WatchdogState.IsPiloting
    if WatchdogState.IsPiloting then
        PilotToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 65)
        PilotToggleBtn.Text = "PILOTO AUTOMÁTICO:\nON (MONITOREANDO)"
        local car, seat = getVehicle()
        if car and seat then
            WatchdogState.LastPos = (car.PrimaryPart and car.PrimaryPart.Position) or seat.Position
            WatchdogState.LastMoveTick = tick()
        end
    else
        PilotToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
        PilotToggleBtn.Text = "PILOTO AUTOMÁTICO:\nOFF"
    end
end)

-- Botón 2: Forzar Triple Pivot Manual
local ForcePivotBtn = Instance.new("TextButton")
ForcePivotBtn.Size = UDim2.new(0.48, -5, 0, 42)
ForcePivotBtn.Position = UDim2.new(0.52, 0, 0, 154)
ForcePivotBtn.BackgroundColor3 = Color3.fromRGB(190, 90, 20)
ForcePivotBtn.Text = "⚡ FORZAR TRIPLE PIVOT\n(SALTO DE 3 PASOS)"
ForcePivotBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ForcePivotBtn.TextSize = 10
ForcePivotBtn.Font = Enum.Font.GothamBold
ForcePivotBtn.Parent = MainFrame

local ForceCorner = Instance.new("UICorner")
ForceCorner.CornerRadius = UDim.new(0, 6)
ForceCorner.Parent = ForcePivotBtn

ForcePivotBtn.MouseButton1Click:Connect(function()
    local car, seat = getVehicle()
    if car and seat then
        executeTriplePivot(car, seat)
    end
end)

-- Botón 3: Probar Filtro de Llantas Ahora Mismo
local CheckWheelsBtn = Instance.new("TextButton")
CheckWheelsBtn.Size = UDim2.new(1, -20, 0, 36)
CheckWheelsBtn.Position = UDim2.new(0, 10, 0, 206)
CheckWheelsBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 170)
CheckWheelsBtn.Text = "🔍 COMPROBAR ESTADO DE LLANTAS AHORA"
CheckWheelsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CheckWheelsBtn.TextSize = 10
CheckWheelsBtn.Font = Enum.Font.GothamBold
CheckWheelsBtn.Parent = MainFrame

local CheckCorner = Instance.new("UICorner")
CheckCorner.CornerRadius = UDim.new(0, 6)
CheckCorner.Parent = CheckWheelsBtn

CheckWheelsBtn.MouseButton1Click:Connect(function()
    local car, seat = getVehicle()
    if car and seat then
        local intact, reason = areWheelsIntact(car, seat)
        StatusBox.Text = string.format("REVISIÓN DE LLANTAS:\n¿Intactas?: %s\nDetalle: %s", tostring(intact), reason)
    else
        StatusBox.Text = "Súbete al auto para comprobar las llantas."
    end
end)

-- Botón 4: Resetear Contadores
local ResetBtn = Instance.new("TextButton")
ResetBtn.Size = UDim2.new(1, -20, 0, 30)
ResetBtn.Position = UDim2.new(0, 10, 0, 250)
ResetBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
ResetBtn.Text = "REINICIAR TEMPORIZADOR Y CONTADORES"
ResetBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
ResetBtn.TextSize = 9
ResetBtn.Font = Enum.Font.GothamBold
ResetBtn.Parent = MainFrame

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 6)
ResetCorner.Parent = ResetBtn

ResetBtn.MouseButton1Click:Connect(function()
    WatchdogState.LastMoveTick = tick()
    WatchdogState.TotalUnstucks = 0
    WatchdogState.IgnoredBrokenWheels = 0
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "🛠️\nSTUCK"
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

-- Actualización continua de texto
task.spawn(function()
    while true do
        task.wait(0.3)
        local car, seat = getVehicle()
        local wheelInfo = "N/A"
        if car and seat then
            local intact, reason = areWheelsIntact(car, seat)
            wheelInfo = intact and "✅ Intactas" or ("❌ " .. reason)
        end

        StatusBox.Text = string.format(
            "ESTADO: %s\n" ..
            "Llantas: %s\n" ..
            "Tiempo Inmóvil: %.1fs (Límite: %.1fs)\n" ..
            "Desatascos realizados: %d | Ignorados por llantas rotas: %d",
            WatchdogState.Status,
            wheelInfo,
            (car and seat and WatchdogState.IsPiloting) and (tick() - WatchdogState.LastMoveTick) or 0,
            Config.StuckTimeout,
            WatchdogState.TotalUnstucks,
            WatchdogState.IgnoredBrokenWheels
        )
    end
end)
