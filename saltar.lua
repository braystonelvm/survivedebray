-- ==============================================================================
-- AUTO-ENTER CLOSEST VEHICLE (INSTANT CAR MOUNT) | TECLA 'V'
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

-- FUNCIÓN PARA SUBIR AL AUTO MÁS CERCANO AL INSTANTE
local function enterClosestVehicle()
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return end

    -- Si ya estás sentado en un vehículo, no hacer nada
    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        return
    end

    local closestSeat = nil
    local shortestDist = math.huge
    local myPos = root.Position

    -- 1. Buscar en estructuras y mapa todos los VehicleSeats libres
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("VehicleSeat") and desc.Occupant == nil then
            local dist = (desc.Position - myPos).Magnitude
            if dist < shortestDist then
                shortestDist = dist
                closestSeat = desc
            end
        end
    end

    if closestSeat then
        local carModel = closestSeat:FindFirstAncestorOfClass("Model")
        local carName = carModel and carModel.Name or "Vehículo"

        -- 2. Frenar inercia y teletransportar directamente sobre el asiento
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        root.CFrame = closestSeat.CFrame * CFrame.new(0, 1.2, 0)

        -- 3. Si el vehículo requiere interacción por ProximityPrompt, forzarlo
        if carModel then
            for _, prompt in ipairs(carModel:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") then
                    local act = (prompt.ActionText .. " " .. prompt.ObjectText):lower()
                    if act:find("conducir") or act:find("drive") or act:find("subir") or act:find("entrar") or act:find("asiento") then
                        prompt.HoldDuration = 0
                        prompt.RequiresLineOfSight = false
                        if fireproximityprompt then
                            pcall(function() fireproximityprompt(prompt) end)
                            pcall(function() fireproximityprompt(prompt, 0) end)
                        end
                    end
                end
            end
        end

        -- 4. Forzar anclaje físico al asiento (Instant Sit)
        task.wait(0.04)
        hum:ChangeState(Enum.HumanoidStateType.Seated)
        pcall(function() closestSeat:Sit(hum) end)
    end
end

-- ================= INTERFAZ / BOTÓN FLOTANTE =================
local existing = lp.PlayerGui:FindFirstChild("InstantCarMountGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "InstantCarMountGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 52, 0, 52)
FloatBtn.Position = UDim2.new(0.04, 0, 0.48, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 120)
FloatBtn.Text = "🚗\n[V]"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 13
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local UIStroke = Instance.new("UIStroke")
UIStroke.Thickness = 2
UIStroke.Color = Color3.fromRGB(255, 255, 255)
UIStroke.Transparency = 0.4
UIStroke.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    enterClosestVehicle()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.V then
        enterClosestVehicle()
    end
end)
