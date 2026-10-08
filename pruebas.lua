-- ==============================================================================
-- AUTO-SUBIR AL AUTO (ULTRA-LIGERO / CERO LAG EN BATALLA) | TECLA 'V'
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local MAX_DISTANCE = 150 -- Radio de 150 studs (óptimo para combate)

local function mountClosestCar()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    -- Si ya estás conduciendo, no hace nada
    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return end

    local myPos = root.Position
    local bestSeat = nil
    local shortestDist = MAX_DISTANCE

    -- Búsqueda directa en Structures (Cero lag: solo revisa modelos de vehículos)
    local container = workspace:FindFirstChild("Structures") or workspace
    for _, model in ipairs(container:GetChildren()) do
        if model:IsA("Model") then
            local seat = model:FindFirstChild("DriveSeat") or model:FindFirstChildWhichIsA("VehicleSeat")
            if seat and seat.Occupant == nil then
                local dist = (seat.Position - myPos).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    bestSeat = seat
                end
            end
        end
    end

    -- Si encontró un auto a menos de 150 studs
    if bestSeat then
        local carModel = bestSeat:FindFirstAncestorOfClass("Model")

        -- 1. Detener inercia y posicionar sobre el asiento
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        root.CFrame = bestSeat.CFrame * CFrame.new(0, 1.2, 0)

        -- 2. Disparar prompt de entrada solo del auto seleccionado
        if carModel then
            for _, prompt in ipairs(carModel:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") then
                    prompt.HoldDuration = 0
                    prompt.RequiresLineOfSight = false
                    if fireproximityprompt then
                        pcall(function() fireproximityprompt(prompt, 0) end)
                    end
                end
            end
        end

        -- 3. Sentar instantáneamente
        task.wait(0.03)
        hum:ChangeState(Enum.HumanoidStateType.Seated)
        pcall(function() bestSeat:Sit(hum) end)
    end
end

-- ================= BOTÓN FLOTANTE MINIMALISTA =================
local existing = lp.PlayerGui:FindFirstChild("FastMountGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FastMountGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(0, 48, 0, 48)
Btn.Position = UDim2.new(0.04, 0, 0.48, 0)
Btn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
Btn.Text = "🚗\n[V]"
Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Btn.TextSize = 12
Btn.Font = Enum.Font.GothamBold
Btn.Active = true
Btn.Draggable = true
Btn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = Btn

Btn.MouseButton1Click:Connect(mountClosestCar)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.V then
        mountClosestCar()
    end
end)
