-- ==============================================================================
-- MI HUB PERSONAL - SOBREVIVE AL APOCALIPSIS ZOMBIE (V4 MULTI-PATRÓN & RADAR)
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
    AttackMode = "Zigzag Clásico", -- Opciones: "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico"
    SwitchInterval = 0.5,          -- Frecuencia por defecto a 0.5s
    LateralDist = 25,              -- Amplitud por defecto de 25 studs
    MoveSpeed = 80,                -- Velocidad por defecto de 80 studs/s
    EvadeBloaters = true,          -- Esquivar explosiones activado
    BloaterDangerDist = 30,        -- Radio de peligro del Bloater en studs
    AutoDetectHorde = true         -- Escaneo de anuncios de dirección de oleada
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local DetectedHordeSide = "Desconocido"

-- FRENADO FÍSICO TEMPORAL (AUTO Y PERSONAJE)
local function applyBrake(duration)
    duration = duration or 1.0
    task.spawn(function()
        local endTime = tick() + duration
        while tick() < endTime do
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            -- Si estás en un auto, frenar el chasis
            if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
                local seat = hum.SeatPart
                local carModel = seat:FindFirstAncestorOfClass("Model") or seat.Parent
                local primary = carModel and (carModel.PrimaryPart or seat)
                if primary then
                    primary.AssemblyLinearVelocity = Vector3.new(0, primary.AssemblyLinearVelocity.Y, 0)
                    primary.AssemblyAngularVelocity = Vector3.zero
                end
            end

            if root then
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- Limpieza o aplicación de Highlight
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

    local humModel = target:FindFirstAncestorOfClass("Model")
    while humModel and not humModel:FindFirstChildOfClass("Humanoid") and humModel.Parent ~= workspace do
        local higherModel = humModel.Parent:FindFirstAncestorOfClass("Model")
        if higherModel then humModel = higherModel else break end
    end
    if humModel and humModel:FindFirstChildOfClass("Humanoid") then
        return humModel
    end

    local current = target
    local topModel = nil
    while current and current ~= workspace do
        if current:IsA("Model") then
            topModel = current
            local pName = current.Parent and current.Parent.Name:lower() or ""
            if current.Parent == workspace or pName == "characters" or pName == "structures" or pName == "tiles" or pName == "map" then
                return current
            end
        end
        current = current.Parent
    end

    if topModel then return topModel end
    if target.Name:lower():find("mesh") and target.Parent and target.Parent ~= workspace then
        return target.Parent
    end

    return target
end

-- DETECCIÓN DE BOMBAS DE BLOATERS
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
    Title = "ZOMBIE HUB | CUSTOM V4",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 460),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Horde = Window:AddTab({ Title = "Radar Luna Roja", Icon = "moon" })
}

Tabs.Combat:AddSection("Controles de Movimiento y Evasión")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(Value) Config.ZigZagEnabled = Value end
})

Tabs.Combat:AddDropdown("ModeDropdown", {
    Title = "Modo de Ataque / Patrón",
    Values = { "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico" },
    Default = "Zigzag Clásico",
    Callback = function(Value)
        Config.AttackMode = Value
        Fluent:Notify({ Title = "Modo Cambiado", Content = "Nuevo patrón: " .. Value, Duration = 2 })
    end
})

Tabs.Combat:AddToggle("BloaterEvadeToggle", {
    Title = "🛡️ Evasión Activa de Bloaters",
    Description = "Detecta bloaters caídos y los esquiva automáticamente",
    Default = true,
    Callback = function(Value) Config.EvadeBloaters = Value end
})

Tabs.Combat:AddParagraph({
    Title = "Controles Rápidos de Teclado",
    Content = "• Presiona 'T': Fijar objetivo y ACTIVAR automáticamente.\n• Presiona '9': PAUSAR movimiento y frenar 1s (mantiene objetivo).\n• Presiona '0': DESMARCAR objetivo, apagar y frenar 1s."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación (Segundos)",
    Default = 0.5,
    Min = 0.0,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value) Config.SwitchInterval = Value end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud / Rango de giro (Studs)",
    Default = 25,
    Min = 4,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.LateralDist = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Movimiento",
    Default = 80,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

-- PESTAÑA DEL RADAR DE LUNA ROJA
local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Dirección de Llegada Actual",
    Content = "Escaneando anuncios del juego..."
})

Tabs.Horde:AddButton({
    Title = "🔍 Escanear Variables de Horda Ahora",
    Description = "Registra los textos y atributos activos del mapa",
    Callback = function()
        local foundTexts = {}
        local pGui = lp:FindFirstChild("PlayerGui")
        if pGui then
            for _, desc in ipairs(pGui:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" then
                    local t = desc.Text:lower()
                    if t:find("norte") or t:find("sur") or t:find("este") or t:find("oeste") or t:find("north") or t:find("south") or t:find("east") or t:find("west") or t:find("horda") or t:find("wave") then
                        table.insert(foundTexts, string.format("[%s]: '%s'", desc.Name, desc.Text))
                    end
                end
            end
        end

        local report = #foundTexts > 0 and table.concat(foundTexts, "\n") or "No hay textos activos de dirección en pantalla en este momento."
        if setclipboard then setclipboard(report) elseif toclipboard then toclipboard(report) end
        Fluent:Notify({ Title = "Escaneo de Horda", Content = "Textos copiados al portapapeles.", Duration = 3 })
    end
})

-- 2. BOTÓN FLOTANTE (ARRASTRABLE Y ABAJO)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomHubFloatingBtn"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

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

-- 3. FORZAR CURSOR LIMPIO SIEMPRE ACTIVO (SIN PUNTOS CIAN DECORATIVOS)
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
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
                    Content = string.format("Fijado: %s | Modo: %s", chosen.Name, Config.AttackMode),
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
            Content = "Frenando 1s. Objetivo conservado.",
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
            Content = "Auto-Movimiento apagado y frenando 1s.",
            Duration = 2
        })
    end
end)

-- 5. DETECTOR EN SEGUNDO PLANO DE ANUNCIOS DE HORDA
task.spawn(function()
    while true do
        task.wait(2.0)
        if Config.AutoDetectHorde then
            local pGui = lp:FindFirstChild("PlayerGui")
            if pGui then
                for _, desc in ipairs(pGui:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" then
                        local text = desc.Text:lower()
                        local sideDetected = nil
                        if text:find("norte") or text:find("north") then sideDetected = "NORTE"
                        elseif text:find("sur") or text:find("south") then sideDetected = "SUR"
                        elseif text:find("este") or text:find("east") then sideDetected = "ESTE"
                        elseif text:find("oeste") or text:find("west") then sideDetected = "OESTE" end

                        if sideDetected and sideDetected ~= DetectedHordeSide then
                            DetectedHordeSide = sideDetected
                            HordeStatusParagraph:SetDesc("🚨 Horda activa aproximándose por el: " .. sideDetected)
                            Fluent:Notify({
                                Title = "¡Alerta de Horda!",
                                Content = "Los zombies están llegando por el " .. sideDetected,
                                Duration = 4
                            })
                            break
                        end
                    end
                end
            end
        end
    end
end)

-- 6. MOTOR CINÉTICO MULTI-MODO CON EVASIÓN DE BLOATERS
local side = 1
local lastSwitch = tick()
local currentStep = 1
local orbitAngle = 0

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
        targetPart = CurrentTarget:FindFirstChild("HumanoidRootPart") 
            or CurrentTarget:FindFirstChild("Torso") 
            or CurrentTarget.PrimaryPart 
            or CurrentTarget:FindFirstChildWhichIsA("BasePart", true)
    end

    if targetPart and targetPart.Parent then
        local cf = targetPart.CFrame
        local destination = targetPart.Position
        local d = Config.LateralDist

        -- =========================================================================
        -- CÁLCULO DEL PATRÓN DE ATAQUE
        -- =========================================================================

        -- MODO 1: ZIGZAG CLÁSICO
        if Config.AttackMode == "Zigzag Clásico" then
            if Config.SwitchInterval <= 0.05 then
                local wave = math.sin(tick() * 3.8)
                destination = targetPart.Position + (cf.RightVector * (wave * d))
            else
                if tick() - lastSwitch >= Config.SwitchInterval then
                    side = -side
                    lastSwitch = tick()
                end
                destination = targetPart.Position + (cf.RightVector * (side * d))
            end

        -- MODO 2: ROMBO (4 VÉRTICES: FRENTE, DERECHA, ATRÁS, IZQUIERDA)
        elseif Config.AttackMode == "Rombo" then
            if tick() - lastSwitch >= math.max(0.2, Config.SwitchInterval) then
                currentStep = (currentStep % 4) + 1
                lastSwitch = tick()
            end
            local offsets = {
                cf.LookVector * d,          -- Adelante
                cf.RightVector * d,         -- Derecha
                -cf.LookVector * d,         -- Atrás
                -cf.RightVector * d         -- Izquierda
            }
            destination = targetPart.Position + offsets[currentStep]

        -- MODO 3: CÍRCULO (ÓRBITA CONTINUA SUAVE)
        elseif Config.AttackMode == "Círculo" then
            orbitAngle = orbitAngle + (Config.MoveSpeed * 0.02)
            destination = targetPart.Position + (cf.RightVector * (math.cos(orbitAngle) * d)) + (cf.LookVector * (math.sin(orbitAngle) * d))

        -- MODO 4: CUADRADO (4 ESQUINAS DEL PERÍMETRO)
        elseif Config.AttackMode == "Cuadrado" then
            if tick() - lastSwitch >= math.max(0.25, Config.SwitchInterval) then
                currentStep = (currentStep % 4) + 1
                lastSwitch = tick()
            end
            local corners = {
                (cf.LookVector * d) + (cf.RightVector * d),   -- Esquina Adelante-Derecha
                (-cf.LookVector * d) + (cf.RightVector * d),  -- Esquina Atrás-Derecha
                (-cf.LookVector * d) - (cf.RightVector * d),  -- Esquina Atrás-Izquierda
                (cf.LookVector * d) - (cf.RightVector * d)    -- Esquina Adelante-Izquierda
            }
            destination = targetPart.Position + corners[currentStep]

        -- MODO 5: ZIGZAG CAÓTICO (ALEATORIO E IMPREDECIBLE)
        elseif Config.AttackMode == "Zigzag Caótico" then
            if tick() - lastSwitch >= math.max(0.15, Config.SwitchInterval) then
                side = (math.random() > 0.5 and 1 or -1)
                lastSwitch = tick()
            end
            local randomDist = math.random(math.floor(d * 0.4), math.floor(d))
            local randomForward = (math.random() - 0.5) * (d * 0.5)
            destination = targetPart.Position + (cf.RightVector * (side * randomDist)) + (cf.LookVector * randomForward)
        end

        -- =========================================================================
        -- ESCUDO EVASOR DE BLOATERS (APLICA A TODOS LOS MODOS)
        -- =========================================================================
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

        -- APLICACIÓN DE VELOCIDAD CINÉTICA
        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.2 then
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB V4 LISTO",
    Content = "Cursor estándar activo | 5 Modos | Radar de hordas incluido",
    Duration = 4
})

Window:SelectTab(1)
