-- ==============================================================================
-- AUTO-REPARAR Y SUBIR AL AUTO (ULTRA-LIGERO / CERO LAG) | TECLA 'V'
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local MAX_DISTANCE = 150 -- Radio de 150 studs (óptimo para combate)

-- 1. DETECTAR SI EL AUTO TIENE PROMPT DE REPARACIÓN ACTIVO
local function getRepairPrompt(carModel)
    for _, prompt in ipairs(carModel:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local act = prompt.ActionText:lower()
            local obj = prompt.ObjectText:lower()
            local name = prompt.Name:lower()
            if act:find("repar") or act:find("repair") or obj:find("repar") or name:find("repar") then
                return prompt
            end
        end
    end
    return nil
end

local function mountAndRepairClosestCar()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    -- Si ya estás conduciendo, no hace nada
    if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then return end

    local myPos = root.Position
    local bestSeat = nil
    local shortestDist = MAX_DISTANCE

    -- Búsqueda directa en Structures (Cero lag: solo modelos con asientos de conductor)
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

        -- ================= FASE 1: REPARACIÓN PREVIA =================
        local repairPrompt = getRepairPrompt(carModel)
        if repairPrompt then
            -- Moverse junto a la pieza del prompt (capó/motor) para validar rango del servidor
            local promptPart = repairPrompt.Parent
            local pPos = promptPart and (promptPart:IsA("BasePart") and promptPart.Position or (promptPart:IsA("Attachment") and promptPart.WorldPosition)) or (bestSeat.Position + Vector3.new(0, 1, 0))
            
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = CFrame.new(pPos + Vector3.new(0, 2.0, 0))
            task.wait(0.04)

            -- Ejecutar reparación instantánea
            local tries = 0
            while repairPrompt and repairPrompt.Parent and repairPrompt.Enabled and tries < 3 do
                repairPrompt.HoldDuration = 0
                repairPrompt.RequiresLineOfSight = false
                repairPrompt.MaxActivationDistance = 50
                if fireproximityprompt then
                    pcall(function() fireproximityprompt(repairPrompt, 0) end)
                end
                tries = tries + 1
                task.wait(0.10)
                repairPrompt = getRepairPrompt(carModel)
            end
            task.wait(0.06)
        end

        -- ================= FASE 2: ENTRADA Y SUBIDA AL VEHÍCULO =================
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = bestSeat.CFrame * CFrame.new(0, 1.2, 0)

        -- Disparar prompts de acceso si el chasis los requiere
        for _, prompt in ipairs(carModel:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                local act = prompt.ActionText:lower()
                local obj = prompt.ObjectText:lower()
                -- Excluir el prompt de reparar en caso de que aún exista
                if not act:find("repar") and not obj:find("repar") then
                    prompt.HoldDuration = 0
                    prompt.RequiresLineOfSight = false
                    if fireproximityprompt then
                        pcall(function() fireproximityprompt(prompt, 0) end)
                    end
                end
            end
        end

        -- Sentar al conductor
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

Btn.MouseButton1Click:Connect(mountAndRepairClosestCar)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.V then
        mountAndRepairClosestCar()
    end
end)
