-- ==============================================================================
-- TELEPORT VEHÍCULO: BASE (RETIRADA TÁCTICA) Y RETORNO | CERO DESTABILIZACIÓN
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

-- CONFIGURACIÓN DE PUNTOS Y TIEMPO
local BASE_POSITION = Vector3.new(-114.5, 25.0, -2.0) -- Punto 1 (Centro de Base elevado para evitar colisiones)
local WAIT_IN_BASE = 4.0                              -- Segundos que permanecerás en la base antes de volver
local TELEPORT_KEY = Enum.KeyCode.B                   -- Tecla para activar la maniobra

local InAction = false

-- ESTABILIZADOR ANTIVUELCO Y TRASLADO RÍGIDO
local function safeMoveCar(carModel, targetPosition, keepYawOnly)
    if not carModel or not carModel.PrimaryPart and not carModel:FindFirstChildWhichIsA("BasePart") then return end

    local primary = carModel.PrimaryPart or carModel:FindFirstChildWhichIsA("VehicleSeat") or carModel:FindFirstChildWhichIsA("BasePart")
    local curCF = primary.CFrame

    -- Mantener la dirección hacia donde miraba el auto, pero forzar inclinación en 0 (nivelado perfecto)
    local targetCF
    if keepYawOnly then
        local _, yaw, _ = curCF:ToOrientation()
        targetCF = CFrame.new(targetPosition) * CFrame.Angles(0, yaw, 0)
    else
        targetCF = CFrame.new(targetPosition) * curCF.Rotation
    end

    -- 1. Anular toda inercia previa antes del salto
    for _, part in ipairs(carModel:GetDescendants()) do
        if part:IsA("BasePart") then
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end

    -- 2. Traslado en bloque mediante PivotTo
    carModel:PivotTo(targetCF)

    -- 3. Anular rebote y fuerzas residuales de suspensión post-salto
    task.wait(0.03)
    for _, part in ipairs(carModel:GetDescendants()) do
        if part:IsA("BasePart") then
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

-- EJECUCIÓN DEL CICLO (ORIGEN -> BASE -> RETORNO)
local function executeBaseEvac()
    if InAction then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then
        print("[EVAC]: Debes estar sentado conduciendo el auto.")
        return
    end

    local seat = hum.SeatPart
    local carModel = seat:FindFirstAncestorOfClass("Model")
    if not carModel then return end

    InAction = true

    -- Guardar la posición de ataque original (Punto 2)
    local returnPosition = seat.Position + Vector3.new(0, 1.5, 0)

    print("[EVAC]: Trasladando a la Base...")
    safeMoveCar(carModel, BASE_POSITION, true)

    -- Esperar el tiempo fijado dentro de la base
    local countdown = WAIT_IN_BASE
    while countdown > 0 do
        task.wait(0.5)
        countdown = countdown - 0.5
        -- Mantener el vehículo quieto mientras esté en la base elevada
        if carModel and carModel.PrimaryPart then
            carModel.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
        end
    end

    print("[EVAC]: Regresando a la posición de combate...")
    safeMoveCar(carModel, returnPosition, true)

    task.wait(0.5)
    InAction = false
end

-- ================= INTERFAZ FLOTANTE MINIMALISTA =================
local existing = lp.PlayerGui:FindFirstChild("CarEvacGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarEvacGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

-- Botón Principal
local EvacBtn = Instance.new("TextButton")
EvacBtn.Size = UDim2.new(0, 56, 0, 56)
EvacBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
EvacBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
EvacBtn.Text = "🛡️\nBASE"
EvacBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EvacBtn.TextSize = 12
EvacBtn.Font = Enum.Font.GothamBold
EvacBtn.Active = true
EvacBtn.Draggable = true
EvacBtn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = EvacBtn

-- Botón para capturar coordenada actual como Punto 1 (Base)
local SetBaseBtn = Instance.new("TextButton")
SetBaseBtn.Size = UDim2.new(0, 75, 0, 24)
SetBaseBtn.Position = UDim2.new(0.04, 62, 0.40, 16)
SetBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
SetBaseBtn.Text = "📍 Fijar Base"
SetBaseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
SetBaseBtn.TextSize = 10
SetBaseBtn.Font = Enum.Font.Gotham
SetBaseBtn.Parent = ScreenGui

local sCorner = Instance.new("UICorner")
sCorner.CornerRadius = UDim.new(0, 4)
sCorner.Parent = SetBaseBtn

SetBaseBtn.MouseButton1Click:Connect(function()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if root then
        -- Guarda tu posición actual con +10 studs de altura para que el auto flote sobre obstáculos
        BASE_POSITION = root.Position + Vector3.new(0, 10, 0)
        SetBaseBtn.Text = "✅ Guardado"
        task.wait(1.2)
        SetBaseBtn.Text = "📍 Fijar Base"
    end
end)

EvacBtn.MouseButton1Click:Connect(executeBaseEvac)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == TELEPORT_KEY then
        executeBaseEvac()
    end
end)
