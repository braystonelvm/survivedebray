-- ==============================================================================
-- ZOMBIE HUB MASTER V7 (MODO STALKER: EMBESTIDA EN STRAIGHTROAD + CERO LAG)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local BaseCenter = Vector3.new(0, 0, 0)

local SECTOR_ROUTES = {
    SUR = {
        Gate = Vector3.new(0, -1.9, 120.0),
        Combat = Vector3.new(0, 14.5, 180.0)
    },
    NORTE = {
        Gate = Vector3.new(0, -1.7, -120.0),
        Combat = Vector3.new(0, 14.5, -180.0)
    },
    ESTE = {
        Gate = Vector3.new(120.0, -1.9, 0.0),
        Combat = Vector3.new(180.0, 14.5, 0.0)
    },
    OESTE = {
        Gate = Vector3.new(-120.0, -1.9, 0.0),
        Combat = Vector3.new(-180.0, 14.5, 0.0)
    }
}

local Config = {
    ZigZagEnabled = false,
    AttackMode = "Stalker", -- "Stalker", "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico"
    SwitchInterval = 0.5,
    LateralDist = 25,
    MoveSpeed = 95,          -- Velocidad por defecto aumentada para embestida
    EvadeBloaters = true,
    BloaterDangerDist = 30,
    AutoRouteToWave = true
}

local CurrentTarget = nil
local TargetHighlight = nil
local ZigZagToggleInstance = nil
local CurrentActiveSector = "SUR"

-- LISTAS EN CACHÉ PARA RENDIMIENTO SIN LAG
local CachedBloaterDangers = {}
local CachedHordeClusterOffset = 0 -- Desplazamiento lateral del grupo de zombies

local function applyBrake(duration)
    duration = duration or 1.0
    task.spawn(function()
        local endTime = tick() + duration
        while tick() < endTime do
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local hum = char and char:FindFirstChildOfClass("Humanoid")

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

-- FILTRO ESTRICTO DE OBJETOS: DESCARTA MOCHILAS, DROPS Y PARTES DEL MAPA
local function isValidZombie(entity)
    if not entity or not entity:IsA("Model") or entity == lp.Character or Players:GetPlayerFromCharacter(entity) then
        return false
    end
    local name = entity.Name:lower()
    if name:find("dropped") or name:find("bag") or name:find("loot") or name:find("item") 
       or name:find("crate") or name:find("debris") or name:find("corpse") or name:find("ragdoll") 
       or name:find("car") or name:find("fence") or name:find("door") then
        return false
    end
    local hum = entity:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    local root = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
    return root ~= nil, root
end

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
            if current.Parent == workspace or pName == "characters" or pName == "structures" or pName == "tiles" or pName == "map" or pName == "roads" then
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

-- ==============================================================================
-- BUCLE DE CACHÉ DE BLOATERS (CERO LAG: CORRE CADA 0.3s)
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.3)
        if Config.EvadeBloaters then
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local myPos = root and root.Position or BaseCenter

            local newDangers = {}
            local charFolder = workspace:FindFirstChild("Characters") or workspace

            for _, entity in ipairs(charFolder:GetChildren()) do
                if entity:IsA("Model") and entity ~= char then
                    local name = entity.Name:lower()
                    local variant = tostring(entity:GetAttribute("Variant") or ""):lower()
                    local isBloater = name:find("bloat") or name:find("boom") or name:find("explod") or variant:find("bloat") or variant:find("boom")

                    if isBloater then
                        local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
                        if eRoot and (eRoot.Position - myPos).Magnitude <= 80 then
                            local hum = entity:FindFirstChildOfClass("Humanoid")
                            local isDowned = (hum and hum.Health <= 0) or entity:GetAttribute("Exploding") == true or entity:GetAttribute("Dead") == true or name:find("corpse") or name:find("ragdoll")

                            if isDowned or (hum and hum.Health <= 50) then
                                table.insert(newDangers, eRoot.Position)
                            end
                        end
                    end
                end
            end
            CachedBloaterDangers = newDangers
        else
            table.clear(CachedBloaterDangers)
        end
    end
end)

-- ==============================================================================
-- BUCLE DE RASTREO DE GRUPOS DE ZOMBIES EN CARRETERA (MODO STALKER - 0.15s)
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.ZigZagEnabled and Config.AttackMode == "Stalker" and CurrentTarget then
            local tPos = CurrentTarget:IsA("BasePart") and CurrentTarget.Position or (CurrentTarget:IsA("Model") and select(1, CurrentTarget:GetBoundingBox()).Position)
            if tPos then
                local radialVec = Vector3.new(tPos.X - BaseCenter.X, 0, tPos.Z - BaseCenter.Z)
                local roadLengthDir = radialVec.Magnitude > 0 and radialVec.Unit or Vector3.new(0, 0, 1)
                local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X)

                local charFolder = workspace:FindFirstChild("Characters") or workspace
                local lateralSum = 0
                local count = 0

                for _, entity in ipairs(charFolder:GetChildren()) do
                    local valid, eRoot = isValidZombie(entity)
                    if valid then
                        local offset = eRoot.Position - tPos
                        local distAlong = math.abs(offset:Dot(roadLengthDir))
                        local distLateral = offset:Dot(roadWidthDir)

                        -- Solo zombies dentro del tramo de la carretera (+- 50 studs de largo y ancho)
                        if distAlong <= 55 and math.abs(distLateral) <= Config.LateralDist + 10 then
                            lateralSum = lateralSum + distLateral
                            count = count + 1
                        end
                    end
                end

                if count > 0 then
                    -- Centro de masa lateral de la horda para orientar la embestida
                    CachedHordeClusterOffset = math.clamp(lateralSum / count, -Config.LateralDist * 0.8, Config.LateralDist * 0.8)
                else
                    CachedHordeClusterOffset = 0
                end
            end
        end
    end
end)

-- ==============================================================================
-- ESCÁNER MANUAL DE DIAGNÓSTICO
-- ==============================================================================
local function executeMasterDiagnostic()
    local char = lp.Character or lp.CharacterAdded:Wait()
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    local refPos = root and root.Position or BaseCenter

    local lines = {}
    local function log(t) table.insert(lines, t) end

    log("==================================================================")
    log("   DIAGNÓSTICO MAESTRO: ENTRADAS, CARRETERAS Y DETECCIÓN DE OLEADA ")
    log("==================================================================")
    log(string.format("Centro de Referencia: Vector3.new(%.1f, %.1f, %.1f)", refPos.X, refPos.Y, refPos.Z))
    log("Hora: " .. os.date("%X"))
    log("------------------------------------------------------------------")

    log("\n[1. CARRETERAS Y ENTRADAS DETECTADAS (RADIO 500 STUDS)]:")
    local roadsFound = {}

    local function inspectRoad(obj)
        if not obj:IsA("Model") and not obj:IsA("BasePart") then return end
        local name = obj.Name:lower()
        if name:find("road") or name:find("tsection") or name:find("section") or name:find("street") or name:find("carretera") or name:find("pista") then
            local cf, size = (obj:IsA("Model") and obj:GetBoundingBox() or obj.CFrame), (obj:IsA("Model") and select(2, obj:GetBoundingBox()) or obj.Size)
            local pos = cf.Position
            local diff = pos - refPos
            local dist = diff.Magnitude

            if dist <= 500 and dist > 8 then
                local direction = "CENTRO"
                if math.abs(diff.Z) > math.abs(diff.X) then
                    direction = (diff.Z < 0) and "NORTE (-Z)" or "SUR (+Z)"
                else
                    direction = (diff.X > 0) and "ESTE (+X)" or "OESTE (-X)"
                end

                table.insert(roadsFound, {
                    Name = obj.Name,
                    Direction = direction,
                    Dist = dist,
                    Position = pos,
                    Size = size,
                    FullName = obj:GetFullName()
                })
            end
        end
    end

    for _, item in ipairs(workspace:GetDescendants()) do
        local pName = item.Parent and item.Parent.Name:lower() or ""
        if pName == "tiles" or pName == "map" or pName == "roads" or item.Parent == workspace then
            inspectRoad(item)
        end
    end

    table.sort(roadsFound, function(a, b) return a.Dist < b.Dist end)

    for i = 1, math.min(#roadsFound, 20) do
        local r = roadsFound[i]
        log(string.format("• [%s] %s | Dist: %.1f studs | Vector3.new(%.1f, %.1f, %.1f)", 
            r.Direction, r.Name, r.Dist, r.Position.X, r.Position.Y, r.Position.Z))
    end

    log("\n------------------------------------------------------------------")
    log("[2. RADAR DE OLEADA: CONCENTRACIÓN DE ZOMBIES]:")

    local quadrantCount = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
    local totalZombies = 0
    local charFolder = workspace:FindFirstChild("Characters") or workspace

    for _, entity in ipairs(charFolder:GetChildren()) do
        local valid, eRoot = isValidZombie(entity)
        if valid then
            local diff = eRoot.Position - refPos
            if diff.Magnitude <= 900 then
                totalZombies = totalZombies + 1
                if math.abs(diff.Z) > math.abs(diff.X) then
                    if diff.Z < 0 then quadrantCount.NORTE = quadrantCount.NORTE + 1 else quadrantCount.SUR = quadrantCount.SUR + 1 end
                else
                    if diff.X > 0 then quadrantCount.ESTE = quadrantCount.ESTE + 1 else quadrantCount.OESTE = quadrantCount.OESTE + 1 end
                end
            end
        end
    end

    log(string.format("Total zombies vivos en radar: %d", totalZombies))
    log(string.format("• Sector NORTE: %d zombies (%.1f%%)", quadrantCount.NORTE, totalZombies > 0 and (quadrantCount.NORTE/totalZombies*100) or 0))
    log(string.format("• Sector SUR:   %d zombies (%.1f%%)", quadrantCount.SUR, totalZombies > 0 and (quadrantCount.SUR/totalZombies*100) or 0))
    log(string.format("• Sector ESTE:  %d zombies (%.1f%%)", quadrantCount.ESTE, totalZombies > 0 and (quadrantCount.ESTE/totalZombies*100) or 0))
    log(string.format("• Sector OESTE: %d zombies (%.1f%%)", quadrantCount.OESTE, totalZombies > 0 and (quadrantCount.OESTE/totalZombies*100) or 0))

    local activeSector = "DISPERSOS / EN PAUSA"
    local maxZ = 0
    for sec, cnt in pairs(quadrantCount) do
        if cnt > maxZ and cnt >= 10 then
            maxZ = cnt
            activeSector = sec
        end
    end
    log(string.format(">>> SECTOR PRINCIPAL ATACANDO: %s <<<", activeSector))

    log("\n------------------------------------------------------------------")
    log("[3. RASTREO EN PLAYERGUI]:")
    local validTexts = {}
    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, desc in ipairs(pGui:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" then
                local tLower = desc.Text:lower()
                local isRadio = tLower:find("bzzt") or tLower:find("survivor") or tLower:find("hello") or tLower:find("radio")
                if not isRadio and not desc.Parent:IsA("TextButton") and #desc.Text >= 2 then
                    table.insert(validTexts, string.format("• [%s] %s: '%s'", desc.Name, desc:GetFullName(), desc.Text))
                end
            end
        end
    end
    for i = 1, math.min(#validTexts, 15) do log(validTexts[i]) end

    log("\n------------------------------------------------------------------")
    log("[4. VALORES GLOBALES]:")
    local function checkGlobals(container, name)
        for k, v in pairs(container:GetAttributes()) do
            local key = k:lower()
            if key:find("wave") or key:find("horde") or key:find("blood") or key:find("night") or key:find("day") then
                log(string.format("• Atributo en %s: %s = %s", name, k, tostring(v)))
            end
        end
    end
    checkGlobals(ReplicatedStorage, "ReplicatedStorage")
    checkGlobals(workspace, "Workspace")

    log("==================================================================")
    local fullReport = table.concat(lines, "\n")
    if setclipboard then setclipboard(fullReport) elseif toclipboard then toclipboard(fullReport) end

    Fluent:Notify({
        Title = "DIAGNÓSTICO COMPLETADO",
        Content = string.format("Sector activo: %s (%d zombies). Reporte copiado.", activeSector, totalZombies),
        Duration = 5
    })
end

-- ==============================================================================
-- INTERFAZ FLUENT
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "ZOMBIE HUB | MASTER V7",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 480),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combate / Auto", Icon = "crosshair" }),
    Horde = Window:AddTab({ Title = "Radar & Forense", Icon = "radar" })
}

Tabs.Combat:AddSection("Controles de Movimiento y Evasión")

ZigZagToggleInstance = Tabs.Combat:AddToggle("ZigZagToggle", {
    Title = "Activar Movimiento Automático",
    Default = false,
    Callback = function(Value) Config.ZigZagEnabled = Value end
})

Tabs.Combat:AddDropdown("ModeDropdown", {
    Title = "Modo de Ataque / Patrón",
    Values = { "Stalker", "Zigzag Clásico", "Rombo", "Círculo", "Cuadrado", "Zigzag Caótico" },
    Default = "Stalker",
    Callback = function(Value) Config.AttackMode = Value end
})

Tabs.Combat:AddToggle("BloaterEvadeToggle", {
    Title = "🛡️ Evasión Activa de Bloaters",
    Description = "Esquiva automáticamente a los Bloaters caídos",
    Default = true,
    Callback = function(Value) Config.EvadeBloaters = Value end
})

Tabs.Combat:AddToggle("AutoRouteToggle", {
    Title = "🚗 Auto-Ruta a la Entrada Activa",
    Description = "Mueve el auto hacia donde ataca la horda",
    Default = true,
    Callback = function(Value) Config.AutoRouteToWave = Value end
})

Tabs.Combat:AddParagraph({
    Title = "Controles Rápidos de Teclado",
    Content = "• Tecla 'T': Fijar StraightRoad/Zombie y ACTIVAR.\n• Tecla '9': PAUSAR movimiento y frenar 1s (mantiene objetivo).\n• Tecla '0': DESMARCAR objetivo, apagar y frenar 1s."
})

Tabs.Combat:AddSlider("IntervalSlider", {
    Title = "Frecuencia de oscilación / Barrido (Segundos)",
    Default = 0.5,
    Min = 0.0,
    Max = 3.0,
    Rounding = 1,
    Callback = function(Value) Config.SwitchInterval = Value end
})

Tabs.Combat:AddSlider("DistSlider", {
    Title = "Amplitud de Barrido Lateral (Studs)",
    Default = 25,
    Min = 4,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.LateralDist = Value end
})

Tabs.Combat:AddSlider("SpeedSlider", {
    Title = "Velocidad de Embestida",
    Default = 95,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(Value) Config.MoveSpeed = Value end
})

Tabs.Horde:AddSection("Radar en Tiempo Real")

local HordeStatusParagraph = Tabs.Horde:AddParagraph({
    Title = "Frente de Combate Activo",
    Content = "Calculando densidad de zombies en las 4 entradas..."
})

Tabs.Horde:AddSection("Herramientas Forenses")

Tabs.Horde:AddButton({
    Title = "📋 EJECUTAR DIAGNÓSTICO MAESTRO COMPLETO",
    Description = "Mapea carreteras a 500 studs, analiza la horda y copia el reporte",
    Callback = function() executeMasterDiagnostic() end
})

-- BOTÓN FLOTANTE
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

RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- CONTROLES DE TECLADO ('T', '9', '0')
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

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

-- RADAR EN SEGUNDO PLANO
task.spawn(function()
    while true do
        task.wait(3.0)

        local counts = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
        local totalZombies = 0
        local charFolder = workspace:FindFirstChild("Characters") or workspace

        for _, entity in ipairs(charFolder:GetChildren()) do
            local valid, eRoot = isValidZombie(entity)
            if valid then
                local p = eRoot.Position - BaseCenter
                if p.Magnitude <= 900 then
                    totalZombies = totalZombies + 1
                    if math.abs(p.Z) > math.abs(p.X) then
                        if p.Z < 0 then counts.NORTE = counts.NORTE + 1 else counts.SUR = counts.SUR + 1 end
                    else
                        if p.X > 0 then counts.ESTE = counts.ESTE + 1 else counts.OESTE = counts.OESTE + 1 end
                    end
                end
            end
        end

        local topSector = CurrentActiveSector
        local maxCount = 0
        for s, c in pairs(counts) do
            if c > maxCount then
                maxCount = c
                topSector = s
            end
        end

        HordeStatusParagraph:SetDesc(string.format(
            "Frente Dominante: %s (%d zombies)\nN: %d | S: %d | E: %d | O: %d | Total: %d",
            topSector, maxCount, counts.NORTE, counts.SUR, counts.ESTE, counts.OESTE, totalZombies
        ))

        if maxCount >= 10 and topSector ~= CurrentActiveSector then
            CurrentActiveSector = topSector
            if Config.AutoRouteToWave then
                Fluent:Notify({
                    Title = "🚨 CAMBIO DE FRENTE DETECTADO",
                    Content = string.format("Reorientando auto hacia la pista del %s...", topSector),
                    Duration = 4
                })
            end
        end
    end
end)

-- ==============================================================================
-- MOTOR CINÉTICO ULTRA-RÁPIDO (MODO STALKER Y PATRONES CLÁSICOS)
-- ==============================================================================
local side = 1
local lastSwitch = tick()
local currentStep = 1
local orbitAngle = 0
local stalkerDir = 1 -- 1 = avanzando lejos de la base, -1 = retrocediendo hacia la base
local lastStalkerSwitch = tick()

RunService.Heartbeat:Connect(function()
    if not Config.ZigZagEnabled then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    local targetPos = nil
    local targetCF = nil
    local targetSize = Vector3.new(60, 10, 60)

    if CurrentTarget then
        if CurrentTarget:IsA("BasePart") then
            targetPos = CurrentTarget.Position
            targetCF = CurrentTarget.CFrame
            targetSize = CurrentTarget.Size
        elseif CurrentTarget:IsA("Model") then
            local bbCF, bbSize = CurrentTarget:GetBoundingBox()
            targetPos = bbCF.Position
            targetCF = bbCF
            targetSize = bbSize
        end
    elseif Config.AutoRouteToWave and SECTOR_ROUTES[CurrentActiveSector] then
        local routeData = SECTOR_ROUTES[CurrentActiveSector]
        local distToGate = (root.Position - routeData.Gate).Magnitude

        if distToGate > 35 and (root.Position - BaseCenter).Magnitude < 110 then
            targetPos = routeData.Gate
            targetCF = CFrame.new(routeData.Gate)
        else
            targetPos = routeData.Combat
            targetCF = CFrame.new(routeData.Combat)
        end
    end

    if targetPos and targetCF then
        local destination = targetPos
        local d = Config.LateralDist

        -- =====================================================================
        -- MODO EXCLUSIVO: STALKER (EMBESTIDA + RETROCESO + BARRIDO EN STRAIGHTROAD)
        -- =====================================================================
        if Config.AttackMode == "Stalker" then
            -- 1. Calcular el eje radial exacto de la carretera respecto a la base
            local toRoadVec = Vector3.new(targetPos.X - BaseCenter.X, 0, targetPos.Z - BaseCenter.Z)
            local roadLengthDir = toRoadVec.Magnitude > 0 and toRoadVec.Unit or Vector3.new(0, 0, 1) -- Dirección alejándose de base
            local roadWidthDir = Vector3.new(-roadLengthDir.Z, 0, roadLengthDir.X) -- Ancho perpendicular

            -- 2. Amplitud longitudinal: tamaño de la carretera + 20 studs a cada lado
            local halfLength = math.max(25, math.max(targetSize.X, targetSize.Z) * 0.45)
            local maxReach = halfLength + 20.0 -- +20 studs hacia la base y +20 al lado opuesto

            -- 3. Calcular posición actual del auto a lo largo de la carretera
            local carOffset = root.Position - targetPos
            local carAlongRoad = carOffset:Dot(roadLengthDir)

            -- 4. Inversión de marcha (pasar y retroceder)
            if stalkerDir == 1 and carAlongRoad >= (maxReach - 5.0) then
                stalkerDir = -1
                lastStalkerSwitch = tick()
            elseif stalkerDir == -1 and carAlongRoad <= -(maxReach - 5.0) then
                stalkerDir = 1
                lastStalkerSwitch = tick()
            end

            -- Failsafe de tiempo: si pasan 3 segundos sin llegar al extremo, invertir marcha
            if tick() - lastStalkerSwitch >= 3.0 then
                stalkerDir = -stalkerDir
                lastStalkerSwitch = tick()
            end

            -- 5. Posición objetivo longitudinal (adelante o atrás)
            local longitudinalTarget = targetPos + (roadLengthDir * (stalkerDir * maxReach))

            -- 6. Barrido lateral rápido (Zigzag) para barrer el ancho de la calzada
            local weaveWave = math.sin(tick() * 5.5) * d
            -- Sumar el sesgo de la horda detectada en caché
            local totalLateral = math.clamp(weaveWave + CachedHordeClusterOffset, -d, d)

            destination = longitudinalTarget + (roadWidthDir * totalLateral)

        -- MODO 1: ZIGZAG CLÁSICO
        elseif Config.AttackMode == "Zigzag Clásico" then
            if Config.SwitchInterval <= 0.05 then
                local wave = math.sin(tick() * 3.8)
                destination = targetPos + (targetCF.RightVector * (wave * d))
            else
                if tick() - lastSwitch >= Config.SwitchInterval then
                    side = -side
                    lastSwitch = tick()
                end
                destination = targetPos + (targetCF.RightVector * (side * d))
            end

        -- MODO 2: ROMBO
        elseif Config.AttackMode == "Rombo" then
            if tick() - lastSwitch >= math.max(0.2, Config.SwitchInterval) then
                currentStep = (currentStep % 4) + 1
                lastSwitch = tick()
            end
            local offsets = {
                targetCF.LookVector * d,
                targetCF.RightVector * d,
                -targetCF.LookVector * d,
                -targetCF.RightVector * d
            }
            destination = targetPos + offsets[currentStep]

        -- MODO 3: CÍRCULO
        elseif Config.AttackMode == "Círculo" then
            orbitAngle = orbitAngle + (Config.MoveSpeed * 0.02)
            destination = targetPos + (targetCF.RightVector * (math.cos(orbitAngle) * d)) + (targetCF.LookVector * (math.sin(orbitAngle) * d))

        -- MODO 4: CUADRADO
        elseif Config.AttackMode == "Cuadrado" then
            if tick() - lastSwitch >= math.max(0.25, Config.SwitchInterval) then
                currentStep = (currentStep % 4) + 1
                lastSwitch = tick()
            end
            local corners = {
                (targetCF.LookVector * d) + (targetCF.RightVector * d),
                (-targetCF.LookVector * d) + (targetCF.RightVector * d),
                (-targetCF.LookVector * d) - (targetCF.RightVector * d),
                (targetCF.LookVector * d) - (targetCF.RightVector * d)
            }
            destination = targetPos + corners[currentStep]

        -- MODO 5: ZIGZAG CAÓTICO
        elseif Config.AttackMode == "Zigzag Caótico" then
            if tick() - lastSwitch >= math.max(0.15, Config.SwitchInterval) then
                side = (math.random() > 0.5 and 1 or -1)
                lastSwitch = tick()
            end
            local randomDist = math.random(math.floor(d * 0.4), math.floor(d))
            local randomForward = (math.random() - 0.5) * (d * 0.5)
            destination = targetPos + (targetCF.RightVector * (side * randomDist)) + (targetCF.LookVector * randomForward)
        end

        -- =====================================================================
        -- ESCUDO EVASOR DE BLOATERS (MÁXIMO 1-3 COMPARACIONES, 0 LAG)
        -- =====================================================================
        if Config.EvadeBloaters and #CachedBloaterDangers > 0 then
            for _, bombPos in ipairs(CachedBloaterDangers) do
                local distToBomb = (root.Position - bombPos).Magnitude
                if distToBomb <= Config.BloaterDangerDist then
                    local avoidDir = (root.Position - bombPos).Unit
                    if avoidDir.Magnitude == 0 or avoidDir ~= avoidDir then
                        avoidDir = targetCF.RightVector * side
                    end
                    destination = destination + Vector3.new(avoidDir.X, 0, avoidDir.Z) * 26
                end
            end
        end

        -- APLICACIÓN CINÉTICA AL VEHÍCULO
        local direction = (destination - root.Position)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude > 1.2 then
            local targetVelocity = horizontalDir.Unit * Config.MoveSpeed
            root.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, root.AssemblyLinearVelocity.Y, targetVelocity.Z)
        end
    end
end)

Fluent:Notify({
    Title = "ZOMBIE HUB V7 ACTIVO",
    Content = "Modo Stalker configurado: embestida +20 studs y barrido continuo.",
    Duration = 4
})

Window:SelectTab(1)
