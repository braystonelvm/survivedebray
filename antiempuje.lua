-- ==============================================================================
-- VEHICLE ANTI-EXPLOSION KNOCKBACK | EMULADOR DE ESTABILIDAD ZHUB (0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,
    ZeroBlastPressure = true,    -- Anula la fuerza de empuje de explosiones
    StabilizeVehicle = true,     -- Impide que el auto salga despedido o vuele
    MaxTiltAngle = 15            -- Ángulo máximo de inclinación permitido
}

local CurrentSeat = nil
local Gyro = nil

-- 1. NEUTRALIZADOR REACTIVO DE EXPLOSIONES (0% CPU)
workspace.DescendantAdded:Connect(function(desc)
    if not Config.Enabled or not Config.ZeroBlastPressure then return end

    if desc:IsA("Explosion") then
        -- Anular la fuerza de choque antes de que mueva el chasis
        desc.BlastPressure = 0

        -- Notificar en consola si se desea depurar
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
            local dist = (desc.Position - hum.SeatPart.Position).Magnitude
            if dist <= 60 then
                print(string.format("[ANTI-EXPLOSION]: Onda expansiva neutralizada a %.1f studs (0 empuje).", dist))
            end
        end
    end
end)

-- 2. ESTABILIZADOR GIROSCÓPICO PARA EL ASIENTO DEL AUTO
local function applyAntiKnockback(seat)
    CurrentSeat = seat

    -- Eliminar estabilizador previo si existe
    if Gyro then Gyro:Destroy() end

    if Config.StabilizeVehicle then
        Gyro = Instance.new("BodyGyro")
        Gyro.Name = "AntiExplosionStabilizer"
        Gyro.MaxTorque = Vector3.new(4e5, 0, 4e5) -- Bloquea vuelcos en X y Z, permite girar libre en Y
        Gyro.P = 15000
        Gyro.D = 800
        Gyro.CFrame = seat.CFrame
        Gyro.Parent = seat
    end
end

local function removeAntiKnockback()
    if Gyro then
        Gyro:Destroy()
        Gyro = nil
    end
    CurrentSeat = nil
end

-- 3. BUCLE DE CONTROL EN RUNSERVICE (MANTENER SIEMPRE HORIZONTAL)
RunService.Heartbeat:Connect(function()
    if not Config.Enabled or not CurrentSeat or not Gyro then return end

    -- Mantener la orientación vertical para que ninguna fuerza externa lo desestabilice
    local currentY = CurrentSeat.Orientation.Y
    Gyro.CFrame = CFrame.Angles(0, math.rad(currentY), 0)

    -- Si una explosión intenta empujar el coche verticalmente con fuerza anormal, clavar velocidad en Y
    local vel = CurrentSeat.AssemblyLinearVelocity
    if vel.Y > 20 then
        CurrentSeat.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
    end
    
    -- Limitar rotaciones bruscas que producen volteretas
    local angVel = CurrentSeat.AssemblyAngularVelocity
    if angVel.Magnitude > 8 then
        CurrentSeat.AssemblyAngularVelocity = Vector3.new(0, angVel.Y, 0)
    end
end)

-- 4. DETECCIÓN SILENCIOSA DEL ASIENTO (CADA 1.5 SEGUNDOS)
task.spawn(function()
    while true do
        task.wait(1.5)
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local seat = hum and hum.SeatPart

        if seat and seat:IsA("VehicleSeat") then
            if seat ~= CurrentSeat then
                applyAntiKnockback(seat)
            end
        else
            if CurrentSeat then
                removeAntiKnockback()
            end
        end
    end
end)

-- ================= INTERFAZ MINIMALISTA (EN PLAYERGUI) =================
local existing = lp.PlayerGui:FindFirstChild("AntiKnockbackGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AntiKnockbackGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 50, 0, 50)
FloatBtn.Position = UDim2.new(0.04, 0, 0.56, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
FloatBtn.Text = "🛡️\nON"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 12
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled
    if Config.Enabled then
        FloatBtn.Text = "🛡️\nON"
        FloatBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
            applyAntiKnockback(hum.SeatPart)
        end
    else
        FloatBtn.Text = "🛡️\nOFF"
        FloatBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
        removeAntiKnockback()
    end
end)
