-- ==============================================================================
-- AUTO-REPARAR Y SUBIR AL AUTO (REPARACIÓN EN CAPÓ + SUBIDA) | TECLA 'V'
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local MAX_DISTANCE = 150 -- Radio de búsqueda en studs

-- 1. LOCALIZAR EL PROMPT DE REPARACIÓN VÁLIDO
local function getActiveRepairPrompt(carModel)
    for _, prompt in ipairs(carModel:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local name = prompt.Name:lower()
            local act = prompt.ActionText:lower()
            local obj = prompt.ObjectText:lower()
            if name:find("repair") or act:find("repair") or act:find("repar") or obj:find("repar") then
                return prompt
            end
        end
    end
    return nil
end

-- 2. FUNCIÓN MAESTRA DE REPARACIÓN Y MONTAJE
local function mountAndRepairClosestCar()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    -- Si ya estás conduciendo, ignorar
    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return end

    local myPos = root.Position
    local bestSeat = nil
    local shortestDist = MAX_DISTANCE

    -- Búsqueda directa en Structures
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

    if bestSeat then
        local carModel = bestSeat:FindFirstAncestorOfClass("Model")
        if not carModel then return end

        local isDead = carModel:GetAttribute("Dead") == true
        local repairPrompt = getActiveRepairPrompt(carModel)

        -- ================= FASE 1: REPARAR DESDE EL CAPÓ/MOTOR =================
        if isDead or repairPrompt then
            -- Ubicarse 6.5 studs hacia el frente del DriveSeat (frente al motor)
            local hoodPos = bestSeat.CFrame * CFrame.new(0, 0.5, -6.5)

            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = hoodPos
            task.wait(0.08)

            local repairTimeout = tick() + 2.0
            while (carModel:GetAttribute("Dead") == true or repairPrompt) and tick() < repairTimeout do
                repairPrompt = getActiveRepairPrompt(carModel)
                if repairPrompt then
                    repairPrompt.HoldDuration = 0
                    repairPrompt.RequiresLineOfSight = false
                    repairPrompt.MaxActivationDistance = 50

                    if fireproximityprompt then
                        pcall(function() fireproximityprompt(repairPrompt) end)
                        pcall(function() fireproximityprompt(repairPrompt, 0) end)
                        pcall(function() fireproximityprompt(repairPrompt, 5) end)
                    end
                end
                task.wait(0.18)
            end
            task.wait(0.1)
        end

        -- ================= FASE 2: ENTRADA Y SUBIDA AL VEHÍCULO =================
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = bestSeat.CFrame * CFrame.new(0, 1.2, 0)

        -- Activar SitPrompt del DriveSeat
        local sitPrompt = bestSeat:FindFirstChild("SitPrompt") or bestSeat:FindFirstChildOfClass("ProximityPrompt")
        if sitPrompt then
            sitPrompt.HoldDuration = 0
            sitPrompt.RequiresLineOfSight = false
            if fireproximityprompt then
                pcall(function() fireproximityprompt(sitPrompt) end)
                pcall(function() fireproximityprompt(sitPrompt, 0) end)
            end
        end

        -- Sentar al jugador
        task.wait(0.04)
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

Btn.MouseButton1Click:Connect(mountAndRepairClosestCar)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.V then
        mountAndRepairClosestCar()
    end
end)
