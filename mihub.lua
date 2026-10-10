-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE (ANTI-BLOATERS V3)
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
    SwitchInterval = 0.5,   -- Frecuencia por defecto ajustada a 0.5s
    LateralDist = 25,       -- Amplitud por defecto de 25 studs
    MoveSpeed = 80,         -- Velocidad por defecto de 80 studs/s
    EvadeBloaters = true,   -- Esquivar explosiones activado
    BloaterDangerDist = 30  -- Radio de peligro del Bloater en studs
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil

-- FRENADO FÍSICO TEMPORAL (AUTO Y PERSONAJE)
local function applyBrake(duration)
    duration = duration or 1.0
    task.spawn(function()
        local endTime = tick() + duration
        while tick() < endTime do
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            -- Si estás montado en un auto, frenar el chasis completo
            if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
                local seat = hum.SeatPart
                local carModel = seat:FindFirstAncestorOfClass("Model") or seat.Parent
                local primary = carModel and (carModel.PrimaryPart or seat)
                if primary then
                    primary.AssemblyLinearVelocity = Vector3.new(0, primary.AssemblyLinearVelocity.Y, 0)
                    primary.AssemblyAngularVelocity = Vector3.zero
                end
            end

            -- Frenar al personaje
            if root then
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- Crear o limpiar Highlight visual
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

-- EXTRAER EL MODELO COMPLETO (EVITA SELECCIONAR SOLO "MESH")
local function getCompleteObject(target)
    if not target or target == lp.Character or target:IsDescendantOf(lp.Character) then 
        return nil 
    end

    -- 1. Si es un Zombie o Jugador con Humanoid
    local humModel = target:FindFirstAncestorOfClass("Model")
    while humModel and not humModel:FindFirstChildOfClass("Humanoid") and humModel.Parent ~= workspace do
        local higherModel = humModel.Parent:FindFirstAncestorOfClass("Model")
        if higherModel then
            humModel = higherModel
        else
            break
        end
    end
    if humModel and humModel:FindFirstChildOfClass("Humanoid") then
        return humModel
    end

    -- 2. Escalar ancestros buscando el Modelo contenedor principal
    local current = target
    local topModel = nil

    while current and current ~= workspace do
        if current:IsA("Model") then
            topModel = current
            local parentName = current.Parent and current.Parent.Name:lower() or ""
            if current.Parent == workspace or parentName == "characters" or parentName == "structures" or parentName == "tiles" or parentName == "map" then
                return current
            end
        end
        current = current.Parent
    end

    if topModel then
        return topModel
    end

    if target.Name:lower():find("mesh") and target.Parent and target.Parent ~= workspace then
        return target.Parent
    end

    return target
end

-- RASTREO Y DETECCIÓN DE EXPLOSIONES DE BLOATERS
local function getBloaterDangerZones()
    local dangers = {}
    local charFolder = workspace:FindFirstChild("Characters") or workspace

    local function checkEntity(entity)
        if entity:IsA("Model") and entity ~= lp.Character then
            local name = entity.Name:lower()
            local variant = tostring(entity:GetAttribute("Variant") or ""):lower()
            local isBloater = name:find("bloat") or name:find("boom") or name:find("explod") or variant:find("bloat") or variant:find("boom")

            if isBloater then
                local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
                local hum = entity:FindFirstChildOfClass("Humanoid")
                local isDowned = (hum and hum.Health <= 0) or entity:GetAttribute("Exploding") == true or entity:GetAttribute("Dead") == true or name:find("corpse") or name:find("ragdoll")

                if eRoot and (isDowned or (hum and hum.Health <= 50)) then
                    table.insert(dangers, eRoot.Position)
                end
            end
        end
    end

    for _, entity in ipairs(charFolder:GetChildren()) do checkEntity(entity) end
    if charFolder ~= workspace then
        for _, entity in ipairs(workspace:GetChildren()) do checkEntity(entity) end
    end

    return dangers
end

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | CUSTOM V3",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 440),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" })
}

Tabs.Combat:AddSection("Controles de Movimiento y Evasión")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(Value)
        Config.ZigZagEnabled = Value
    end
})

Tabs.Combat:AddToggle("BloaterEvadeToggle", {
    Title = "🛡️ Evasión Activa de Bloaters",
    Description = "Detecta bloaters caídos y los esquiva automáticamente",
    Default = true,
    Callback = function(Value)
        Config.EvadeBloaters = Value
    end
})

Tabs.Combat:AddParagraph({
    Title = "Controles Rápidos de Teclado",
    Content = "• Presiona 'T': Fijar objetivo y ACTIVAR movimiento.\n• Presiona '9': PAUSAR movimiento y frenar 1s (mantiene el objetivo).\n• Presiona '0': DESMARCAR objetivo, apagar y frenar 1s."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación (0 = Continuo)",
    Default = 0.5,
    Min = 0.0,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value)
        Config.SwitchInterval = Value
    end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud / Ancho de pista (Studs)",
    Default = 25,
    Min = 4,
    Max = 60,
    Rounding = 0,
    Callback = function(Value)
        Config.LateralDist = Value
    end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Movimiento",
    Default = 80,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        Config.MoveSpeed = Value
    end
})

-- 2. BOTÓN FLOTANTE (ARRASTRABLE Y MÁS ABAJO EN PANTALLA)
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
FloatBtn.Position = UDim2.new(0.04, 0, 0.72, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- 3. CURSOR PERMANENTE ULTRA-LIGERO (SOBREPONE TORRETAS Y MENÚS)
local CursorGui = Instance.new("ScreenGui")
CursorGui.Name = "AlwaysOnTopCursor"
CursorGui.ResetOnSpawn = false
CursorGui.DisplayOrder = 2147483647 -- Máxima prioridad posible de renderizado
CursorGui.IgnoreGuiInset = true

if gethui then
    CursorGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(CursorGui)
    CursorGui.Parent = game:GetService("CoreGui")
else
    CursorGui.Parent = lp:WaitForChild("PlayerGui")
end

local CursorDot = Instance.new("Frame")
CursorDot.Name = "CursorPointer"
CursorDot.Size = UDim2.fromOffset(8, 8)
CursorDot.AnchorPoint = Vector2.new(0.5, 0.5)
CursorDot.BackgroundColor3 = Color3.fromRGB(0, 255, 200) -- Cian neón visible en cualquier entorno
CursorDot.BorderSizePixel = 0
CursorDot.Active = false
CursorDot.Selectable = false
CursorDot.Parent = CursorGui

local CursorCorner = Instance.new("UICorner")
CursorCorner.CornerRadius = UDim.new(1, 0)
CursorCorner.Parent = CursorDot

local CursorStroke = Instance.new("UIStroke")
CursorStroke.Color = Color3.fromRGB(0, 0, 0)
CursorStroke.Thickness = 1.5
CursorStroke.Parent = CursorDot

local CursorRing = Instance.new("Frame")
CursorRing.Size = UDim2.fromOffset(18, 18)
CursorRing.AnchorPoint = Vector2.new(0.5, 0.5)
CursorRing.Position = UDim2.fromScale(0.5, 0.5)
CursorRing.BackgroundTransparency = 1
CursorRing.Active = false
CursorRing.Selectable = false
CursorRing.Parent = CursorDot

local RingCorner = Instance.new("UICorner")
RingCorner.CornerRadius = UDim.new(1, 0)
RingCorner.Parent = CursorRing

local RingStroke = Instance.new("UIStroke")
RingStroke.Color = Color3.fromRGB(255, 255, 255)
RingStroke.Thickness = 1.2
RingStroke.Transparency = 0.25
RingStroke.Parent = CursorRing

RunService.RenderStepped:Connect(function()
    -- Evitar que scripts del auto deshabiliten el icono nativo
    UserInputService.MouseIconEnabled = true
    -- Seguir la posición del ratón en tiempo real
    local mousePos = UserInputService:GetMouseLocation()
    CursorDot.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
end)

-- 4. CONTROL DE TECLAS: 'T' (ACTIVAR), '9' (PAUSA Y FRENO), '0' (DESMARCAR Y FRENO)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    -- Tecla T: Fijar y ACTIVAR
    if input.KeyCode == Enum.KeyCode.T then
        local rawTarget = mouse.Target
        if rawTarget then
            local chosen = getCompleteObject(rawTarget)
            if chosen then
                CurrentTarget = chosen
                applyHighlight(chosen)
                Config.ZigZagEnabled = true
                pcall(function() ZigZagToggleInstance:SetValue(true) end)

                Fluent:Notify({
                    Title = "Objetivo Fijado [T]",
                    Content = string.format("Fijado: %s | Auto-Movimiento ACTIVADO", chosen.Name),
                    Duration = 2.5
                })
            end
        end
    end

    -- Tecla 9: Pausar y frenar 1s (mantiene el objetivo guardado)
    if input.KeyCode == Enum.KeyCode.Nine or input.KeyCode == Enum.KeyCode.KeypadNine then
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        applyBrake(1.0)

        Fluent:Notify({
            Title = "Pausado [9]",
            Content = "Movimiento en pausa. Frenando 1s (Objetivo conservado)",
            Duration = 2
        })
    end

    -- Tecla 0: Desmarcar, apagar y frenar 1s
    if input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.KeypadZero then
        CurrentTarget = nil
        clearHighlight()
        Config.ZigZagEnabled = false
        pcall(function() ZigZagToggleInstance:SetValue(false) end)
        applyBrake(1.0)

        Fluent:Notify({
            Title = "Objetivo Limpiado [0]",
            Content = "Auto-Movimiento apagado y frenando 1s",
            Duration = 2
        })
    end
end)

-- 5. MOTOR DE DESPLAZAMIENTO FÍSICO CON ESQUIVE DE BLOATERS
local side = 1
local lastSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled or not CurrentTarget then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    -- Obtener pieza física de referencia
    local targetPart = nil
    if CurrentTarget:IsA("BasePart") then
        targetPart = CurrentTarget
    elseif CurrentTarget:IsA("Model") then
        targetPart = CurrentTarget:FindFirstChild("HumanoidRootPart") 
            or CurrentTarget:FindFirstChild("Torso") 
            or CurrentTarget.PrimaryPart 
            or CurrentTarget:FindFirstChildWhichIsA("BasePart", true)
    end

    if targetPart and targetPart.Parent then
        local cf = targetPart.CFrame
        local destination = nil

        -- A. CÁLCULO DE OSCILACIÓN
        if Config.SwitchInterval <= 0.05 then
            -- Modo continuo sin pausas
            local wave = math.sin(tick() * 3.8)
            local lateralOffset = cf.RightVector * (wave * Config.LateralDist)
            destination = targetPart.Position + lateralOffset
        else
            -- Por intervalos definidos
            if tick() - lastSwitch >= Config.SwitchInterval then
                side = -side
                lastSwitch = tick()
            end
            local lateralOffset = cf.RightVector * (side * Config.LateralDist)
            destination = targetPart.Position + lateralOffset
        end

        -- B. ESCUDO EVASOR DE BLOATERS
        if Config.EvadeBloaters then
            local dangerZones = getBloaterDangerZones()
            for _, bombPos in ipairs(dangerZones) do
                local distToBomb = (root.Position - bombPos).Magnitude
                if distToBomb <= Config.BloaterDangerDist then
                    local avoidDir = (root.Position - bombPos).Unit
                    if avoidDir.Magnitude == 0 or avoidDir ~= avoidDir then
                        avoidDir = cf.RightVector * side
                    end
                    destination = destination + Vector3.new(avoidDir.X, 0, avoidDir.Z) * 26
                end
            end
        end

        -- C. APLICACIÓN DE FUERZA CINÉTICA
        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.2 then
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB V3 ACTIVO",
    Content = "T: Activar | 9: Pausa + Freno | 0: Cancelar + Freno",
    Duration = 4
})

Window:SelectTab(1)
