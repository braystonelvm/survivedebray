-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- Variables de configuración
local Config = {
    ZigZagEnabled = false,
    SwitchInterval = 1.2,
    LateralDist = 14,
    MoveSpeed = 45,
    AutoSendItems = false,
    CollectRadius = 25,
    BasePrevent = true,
    BaseRadius = 45,
    SpreadRadius = 5
}

local CurrentTarget = nil
local TargetHighlight = nil
local DropPointMarker = nil
local TeleportedCache = {} -- Registro de ítems ya procesados para no trabarlos

local function clearHighlight()
    if TargetHighlight then
        TargetHighlight:Destroy()
        TargetHighlight = nil
    end
end

local function applyHighlight(obj)
    clearHighlight()
    if obj then
        TargetHighlight = Instance.new("Highlight")
        TargetHighlight.Name = "CustomTargetHighlight"
        TargetHighlight.FillColor = Color3.fromRGB(255, 30, 60)
        TargetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        TargetHighlight.FillTransparency = 0.4
        TargetHighlight.Adornee = obj
        TargetHighlight.Parent = obj
    end
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Items = Window:AddTab({ Title = "Teletransporte", Icon = "box" })
}

-- PESTAÑA 1: COMBATE Y AUTO
Tabs.Combat:AddSection("Controles de Zigzag / Atropello")

Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento / Atropello Automático",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

Tabs.Combat:AddParagraph({
    Title = "Teclas de Selector",
    Content = "• Presiona 'T' apuntando a un Zombie o Zona para fijarlo.\n• Presiona 'Y' para desmarcar el objetivo."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación (Segundos)",
    Default = 1.2,
    Min = 0.3,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value)
        Config.SwitchInterval = Value
    end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Ancho de Atropello (Studs)",
    Default = 14,
    Min = 4,
    Max = 35,
    Rounding = 0,
    Callback = function(Value)
        Config.LateralDist = Value
    end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Movimiento / Auto",
    Default = 45,
    Min = 16,
    Max = 120,
    Rounding = 0,
    Callback = function(Value)
        Config.MoveSpeed = Value
    end
})

-- PESTAÑA 2: TELETRANSPORTE Y BASE PREVENT
Tabs.Items:AddSection("Punto de Entrega (Trituradora / Base)")

Tabs.Items:AddButton({
    Title = "Poner Bolita de Destino Aquí",
    Description = "Coloca el marcador en la posición exacta donde estás parado",
    Callback = function()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        if DropPointMarker then
            DropPointMarker:Destroy()
        end

        DropPointMarker = Instance.new("Part")
        DropPointMarker.Name = "CustomDropPoint"
        DropPointMarker.Shape = Enum.PartType.Ball
        DropPointMarker.Size = Vector3.new(3, 3, 3)
        DropPointMarker.Material = Enum.Material.Neon
        DropPointMarker.Color = Color3.fromRGB(0, 255, 170)
        DropPointMarker.Anchored = true
        DropPointMarker.CanCollide = false
        DropPointMarker.CFrame = root.CFrame - Vector3.new(0, 1.5, 0)
        DropPointMarker.Parent = workspace

        -- Limpiar memoria de ítems al mover la bolita
        table.clear(TeleportedCache)

        Fluent:Notify({
            Title = "Destino Guardado",
            Content = "Punto de entrega fijado con la esfera verde.",
            Duration = 3
        })
    end
})

Tabs.Items:AddToggle("AutoSendToggle", {
    Title = "Enviar Ítems al Pasar Sobre Ellos",
    Default = false,
    Callback = function(Value)
        Config.AutoSendItems = Value
        if not Value then
            table.clear(TeleportedCache)
        end
    end
})

Tabs.Items:AddSection("Protección de Base (Base Prevent)")

Tabs.Items:AddToggle("BasePreventToggle", {
    Title = "Activar Base Prevent",
    Description = "No mueve ningún ítem que ya se encuentre dentro del área de la base",
    Default = true,
    Callback = function(Value)
        Config.BasePrevent = Value
    end
})

Tabs.Items:AddSlider("BaseRadiusSlider", {
    Title = "Radio Seguro de la Base (Studs)",
    Default = 45,
    Min = 20,
    Max = 100,
    Rounding = 0,
    Callback = function(Value)
        Config.BaseRadius = Value
    end
})

Tabs.Items:AddSlider("SpreadSlider", {
    Title = "Dispersión de Ítems al llegar (Studs)",
    Default = 5,
    Min = 2,
    Max = 12,
    Rounding = 0,
    Callback = function(Value)
        Config.SpreadRadius = Value
    end
})

-- 2. BOTÓN FLOTANTE
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomHubFloatingBtn"
ScreenGui.ResetOnSpawn = false
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.22, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- 3. SELECCIÓN CON TECLA 'T' Y CANCELACIÓN CON 'Y'
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.T then
        local target = mouse.Target
        if target then
            local model = target:FindFirstAncestorOfClass("Model")
            local chosen = nil

            if model and model ~= lp.Character and model ~= workspace then
                chosen = model
            else
                chosen = target
            end

            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)

                local displayName = chosen.Name
                if displayName == "Mesh" or displayName == "MeshPart" then
                    if chosen.Parent and chosen.Parent ~= workspace then
                        displayName = chosen.Parent.Name
                    end
                end

                Fluent:Notify({
                    Title = "Objetivo Seleccionado",
                    Content = "Fijado: " .. displayName,
                    Duration = 3
                })
            end
        end
    end

    if input.KeyCode == Enum.KeyCode.Y then
        CurrentTarget = nil
        clearHighlight()
        Fluent:Notify({
            Title = "Objetivo Cancelado",
            Content = "Se desmarcó el objetivo.",
            Duration = 2
        })
    end
end)

-- 4. BUCLE DE MOVIMIENTO (COMBATE / ATROPELLO)
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or not CurrentTarget then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    local targetPart = nil
    if CurrentTarget:IsA("BasePart") then
        targetPart = CurrentTarget
    elseif CurrentTarget:IsA("Model") then
        targetPart = CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget:FindFirstChild("Torso") or CurrentTarget.PrimaryPart or CurrentTarget:FindFirstChildWhichIsA("BasePart")
    end

    if targetPart and targetPart.Parent then
        if tick() - lastSwitch >= Config.SwitchInterval then
            side = -side
            lastSwitch = tick()
        end

        local cf = targetPart.CFrame
        local lateralOffset = cf.RightVector * (side * Config.LateralDist)
        local destination = targetPart.Position + lateralOffset

        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.5 then
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

-- 5. BUCLE DE TELETRANSPORTE ANTI-BUG (PIVOT + FÍSICA LIMPIA)
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function isInsideBase(pos)
    local centerModel = workspace:FindFirstChild("Center")
    if centerModel then
        local centerPart = centerModel:FindFirstChildWhichIsA("BasePart") or centerModel.PrimaryPart
        if centerPart then
            if (pos - centerPart.Position).Magnitude <= Config.BaseRadius then
                return true
            end
        end
    end
    if DropPointMarker and DropPointMarker.Parent then
        if (pos - DropPointMarker.Position).Magnitude <= (Config.BaseRadius * 0.4) then
            return true
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(0.2)
        if Config.AutoSendItems and DropPointMarker and DropPointMarker.Parent then
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                overlapParams.FilterDescendantsInstances = {char, DropPointMarker}

                local partsNearby = workspace:GetPartBoundsInRadius(root.Position, Config.CollectRadius, overlapParams)

                for _, hitPart in ipairs(partsNearby) do
                    -- No mover partes ancladas ni entidades vivas
                    if not hitPart.Anchored and not hitPart:FindFirstAncestorOfClass("Humanoid") then
                        -- Encontrar el modelo completo del ítem
                        local itemModel = hitPart:FindFirstAncestorOfClass("Model") or hitPart
                        local rootEntity = (itemModel:IsA("Model") and (itemModel.PrimaryPart or hitPart)) or hitPart

                        -- Si aún no ha sido transportado y no está en la base
                        if not TeleportedCache[itemModel] and not isInsideBase(rootEntity.Position) then
                            TeleportedCache[itemModel] = true

                            -- Calcular dispersión en círculo
                            local angle = math.random() * math.pi * 2
                            local distance = math.random() * Config.SpreadRadius
                            local offsetX = math.cos(angle) * distance
                            local offsetZ = math.sin(angle) * distance

                            -- Punto destino apenas sobre el suelo (1.5 studs)
                            local destCFrame = CFrame.new(DropPointMarker.Position + Vector3.new(offsetX, 1.5, offsetZ))

                            -- Mover todo el modelo junto para no romper soldaduras
                            if itemModel:IsA("Model") then
                                itemModel:PivotTo(destCFrame)
                            else
                                itemModel.CFrame = destCFrame
                            end

                            -- Reactivar gravedad natural y eliminar inercias de vuelo
                            for _, p in ipairs(itemModel:GetDescendants()) do
                                if p:IsA("BasePart") then
                                    p.AssemblyLinearVelocity = Vector3.new(0, -2, 0) -- Forzar caída al suelo
                                    p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                                end
                            end
                            if itemModel:IsA("BasePart") then
                                itemModel.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
                                itemModel.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                            end
                        end
                    end
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB LISTO",
    Content = "Teletransporte reparado (Física y Modelos fijados).",
    Duration = 4
})

Window:SelectTab(1)
