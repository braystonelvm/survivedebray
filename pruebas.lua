-- ==============================================================================
-- HACKER UNDERGROUND AUTO-FARM V3: PREDICCIÓN DE MASAS (300 ZOMBIES) + ZANAHORIAS
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera

local Config = {
    Enabled = false,
    UseRockBunker = false,
    UndergroundDepth = -6.0,      -- Profundidad de ataque
    LowHealthDepth = -10.5,       -- Profundidad si baja la vida
    RockBunkerDepth = -1.8,
    MoveSpeed = 38,               -- Velocidad aumentada para que nunca te alcancen
    ScanRadius = 200,             -- Escaneo de 200 studs

    -- MOVIMIENTO CONSTANTE Y PREDICCIÓN DE MASAS
    ConstantMotion = true,        -- Nunca se queda quieto: patrulla y esquiva sin parar
    PatrolRadius = 65,            -- Amplitud de desplazamiento alrededor de tu zona
    PredictionTime = 1.2,         -- Segundos hacia el futuro para predecir a dónde va la masa
    NormalZombieSafeDist = 32,    -- Ampliado a 32 studs contra zombies normales
    LethalZombieSafeDist = 55,    -- Ampliado a 55 studs contra Bloaters y Hazmats

    -- PODERES DE CLASE HACKER
    AutoInfiltrate = true,        -- Cada 15s al zombie con menos vida
    AutoSystemOverride = true,    -- Cada 120s
    AutoGunVirusChain = true,     -- Disparar al infectado con menos vida
    WaitAfterKill = 3.0,          -- Pausa de 3s tras matar al infectado
    ShotInterval = 0.28,
    MaxAbilityRange = 52,

    -- COMIDA (ZANAHORIAS)
    AutoEatEnabled = true,
    HungryThreshold = 30,
    FullHungerThreshold = 85
}

local FarmState = {
    Mode = "IDLE",                -- "ORBITING", "EVADING MASS", "EATING"
    AnchorPos = Vector3.new(0, 0, 120),
    NearestRockPos = nil,
    SavedFarmPlots = {},          -- Lista de parcelas detectadas o guardadas
    ManualCarrotPos = nil,        -- Coordenada manual opcional de zanahorias
    OrbitAngle = 0,
    CurrentEscapeDir = Vector3.new(1, 0, 0),
    WaitingForChain = false,
    ChainWaitUntil = 0,
    CurrentHunger = 100,
    CurrentHP = 100,
    TotalZombiesIn200 = 0,
    InfectedCount = 0
}

-- ==============================================================================
-- CURSOR SIEMPRE VISIBLE
-- ==============================================================================
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. UTILIDADES DEL JUGADOR Y HERRAMIENTAS
-- ==============================================================================

local function getCharParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function findPlayerTool(toolName, toolType)
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    for _, container in ipairs({char, bp}) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") then
                    if toolName and item.Name:lower() == toolName:lower() then
                        return item
                    elseif toolType and tostring(item:GetAttribute("ToolType")):lower() == toolType:lower() then
                        return item
                    end
                end
            end
        end
    end
    return nil
end

local function isAbilityReady(tool)
    if not tool then return false end
    local cd = tool:GetAttribute("Cooldown")
    return (cd == nil) or (type(cd) == "number" and cd <= 0.05)
end

-- ==============================================================================
-- 2. ESCÁNER Y REGISTRO DE PARCELAS DE ZANAHORIAS (FARM PLOTS)
-- ==============================================================================

local function scanAndSaveFarmPlots()
    local plots = {}
    local structures = workspace:FindFirstChild("Structures") or workspace

    -- Busca en Structures y también en Workspace general
    for _, container in ipairs({structures, workspace}) do
        for _, obj in ipairs(container:GetChildren()) do
            local n = obj.Name:lower()
            if obj.Name == "Farm Plot" or n:find("farm plot") or n:find("carrot") then
                local pos = obj:IsA("Model") and obj:GetPivot().Position or (obj:IsA("BasePart") and obj.Position)
                if pos then
                    table.insert(plots, { Instance = obj, Position = pos })
                end
            end
        end
    end

    FarmState.SavedFarmPlots = plots
    return #plots
end

local function findBestRockBunker()
    local _, root = getCharParts()
    local myPos = root and root.Position or Vector3.zero
    local mapFolder = workspace:FindFirstChild("Map") or workspace

    local bestPos = nil
    local shortestDist = 250

    for _, desc in ipairs(mapFolder:GetDescendants()) do
        if desc:IsA("BasePart") then
            local n = desc.Name:lower()
            if (n:find("rock") or n:find("stone") or n:find("boulder")) and desc.Size.X >= 7 and desc.Size.Z >= 7 then
                local dist = (desc.Position - myPos).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    bestPos = desc.Position
                end
            end
        end
    end

    FarmState.NearestRockPos = bestPos
    return bestPos
end

-- ==============================================================================
-- 3. ESCÁNER PREDICTIVO DE MASAS (200 STUDS) Y BUSCADOR DE HUECOS LIBRES
-- ==============================================================================

local function isLethalZombie(entity)
    local n = entity.Name:lower()
    local var = tostring(entity:GetAttribute("Variant") or ""):lower()
    local check = n .. " " .. var
    return check:find("bloat") or check:find("acid") or check:find("hazmat") or check:find("nuclear") or check:find("boom")
end

local function hasHackerVirus(entity)
    if entity:GetAttribute("HackerVirus") == true then return true end
    for k, v in pairs(entity:GetAttributes()) do
        if k:lower():find("hackervirus") and v == true then return true end
    end
    if entity:FindFirstChild("VirusHighlight") then return true end
    return false
end

local function analyzeHordeAndPredict(originPos)
    local charFolder = workspace:FindFirstChild("Characters")
    if not charFolder then return {}, nil, nil, 0 end

    local predictedThreats = {} -- { Pos, IsLethal }
    local lowestInfected = nil
    local lowestInfectedHP = math.huge

    local lowestUninfected = nil
    local lowestUninfectedHP = math.huge
    local infectedTotal = 0
    local totalIn200 = 0

    local myXZ = Vector3.new(originPos.X, 0, originPos.Z)

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and ent:GetAttribute("Zombie") == true then
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
            local hum = ent:FindFirstChildOfClass("Humanoid")

            if eRoot and hum and hum.Health > 0 then
                local zXZ = Vector3.new(eRoot.Position.X, 0, eRoot.Position.Z)
                local horizDist = (zXZ - myXZ).Magnitude

                if horizDist <= Config.ScanRadius then
                    totalIn200 = totalIn200 + 1
                    local lethal = isLethalZombie(ent)

                    -- Predicción: Dónde estará este zombie en Config.PredictionTime segundos
                    local vel = eRoot.AssemblyLinearVelocity
                    local velXZ = Vector3.new(vel.X, 0, vel.Z)
                    local predictedXZ = zXZ + (velXZ * Config.PredictionTime)

                    table.insert(predictedThreats, {
                        CurrentXZ = zXZ,
                        PredictedXZ = predictedXZ,
                        Dist = horizDist,
                        IsLethal = lethal
                    })

                    -- Clasificación para poderes de Hacker
                    local infected = hasHackerVirus(ent)
                    if infected then
                        infectedTotal = infectedTotal + 1
                        if horizDist <= 95 and hum.Health < lowestInfectedHP then
                            lowestInfectedHP = hum.Health
                            lowestInfected = { Model = ent, Root = eRoot, Hum = hum, Dist = horizDist }
                        end
                    else
                        if horizDist <= Config.MaxAbilityRange and hum.Health < lowestUninfectedHP then
                            lowestUninfectedHP = hum.Health
                            lowestUninfected = { Model = ent, Root = eRoot, Hum = hum, Dist = horizDist }
                        end
                    end
                end
            end
        end
    end

    FarmState.TotalZombiesIn200 = totalIn200
    FarmState.InfectedCount = infectedTotal
    return predictedThreats, lowestInfected, lowestUninfected, infectedTotal
end

-- Calcula la dirección más despejada evaluando 12 ángulos alrededor del jugador
local function findBestEscapeDirection(myXZ, anchorXZ, threats, tangentDir)
    local bestDir = tangentDir
    local lowestDangerScore = math.huge

    for i = 1, 12 do
        local angle = (i - 1) * (math.pi * 2 / 12)
        local candidateDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        -- Punto de prueba a 35 studs en esa dirección
        local samplePoint = myXZ + (candidateDir * 35)

        local dangerScore = 0

        -- 1. Penalizar si esa dirección nos lleva directo hacia zombies o su trayectoria futura
        for _, t in ipairs(threats) do
            local dNow = (samplePoint - t.CurrentXZ).Magnitude
            local dPred = (samplePoint - t.PredictedXZ).Magnitude
            local minD = math.min(dNow, dPred)

            local safeRadius = t.IsLethal and Config.LethalZombieSafeDist or Config.NormalZombieSafeDist
            local weight = t.IsLethal and 4.5 or 1.0

            if minD < safeRadius then
                dangerScore = dangerScore + ((safeRadius - minD) ^ 2) * weight
            end
        end

        -- 2. Penalizar suavemente si se aleja demasiado del radio máximo permitido (200 studs)
        local distFromAnchor = (samplePoint - anchorXZ).Magnitude
        if distFromAnchor > Config.PatrolRadius * 1.4 then
            dangerScore = dangerScore + ((distFromAnchor - Config.PatrolRadius) * 15)
        end

        -- 3. Favorecer fluidez con la dirección de órbita actual para no dar giros bruscos
        local alignment = candidateDir:Dot(tangentDir)
        dangerScore = dangerScore - (alignment * 40)

        if dangerScore < lowestDangerScore then
            lowestDangerScore = dangerScore
            bestDir = candidateDir
        end
    end

    return bestDir.Unit
end

-- ==============================================================================
-- 4. ATAQUE AUTOMÁTICO: INFILTRATE + SYSTEM OVERRIDE + UZI VIRUS CHAIN
-- ==============================================================================

local function useAbilityTool(tool, targetRoot)
    local char, root, hum = getCharParts()
    if not char or not hum or not tool then return end

    if tool.Parent ~= char then
        hum:EquipTool(tool)
        task.wait(0.06)
    end

    if targetRoot and root then
        cam.CFrame = CFrame.new(cam.CFrame.Position, targetRoot.Position)
    end

    pcall(function() tool:Activate() end)
    local useRemote = tool:FindFirstChild("Use")
    if useRemote and useRemote:IsA("RemoteEvent") then
        if targetRoot then
            pcall(function() useRemote:FireServer(targetRoot.Parent) end)
            pcall(function() useRemote:FireServer(targetRoot.Position) end)
        else
            pcall(function() useRemote:FireServer() end)
        end
    end
end

task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.Enabled and FarmState.Mode ~= "EATING" then
            local char, root, hum = getCharParts()
            if char and root and hum and hum.Health > 0 then
                local _, lowestInfected, lowestUninfected, infectedCount = analyzeHordeAndPredict(root.Position)

                -- 1. SYSTEM OVERRIDE (120s)
                if Config.AutoSystemOverride then
                    local sysTool = findPlayerTool("System Override")
                    if sysTool and isAbilityReady(sysTool) and (infectedCount > 0 or lowestUninfected ~= nil) then
                        useAbilityTool(sysTool, nil)
                        task.wait(0.2)
                    end
                end

                -- 2. INFILTRATE (15s) - Al zombie con menos vida
                if Config.AutoInfiltrate then
                    local infTool = findPlayerTool("Infiltrate")
                    if infTool and isAbilityReady(infTool) then
                        local target = lowestUninfected or lowestInfected
                        if target then
                            useAbilityTool(infTool, target.Root)
                            task.wait(0.2)
                        end
                    end
                end

                -- 3. UZI / ARMA: Disparar al infectado con menos vida, matar y esperar 3s
                if Config.AutoGunVirusChain then
                    if FarmState.WaitingForChain then
                        if tick() >= FarmState.ChainWaitUntil then
                            FarmState.WaitingForChain = false
                        end
                    elseif lowestInfected and lowestInfected.Hum and lowestInfected.Hum.Health > 0 then
                        local gun = findPlayerTool("Infiltrator Uzi") or findPlayerTool(nil, "Gun")
                        if gun then
                            local ammo = gun:GetAttribute("Ammo")
                            if type(ammo) == "number" and ammo <= 0 then
                                local reloadFunc = gun:FindFirstChild("Reload")
                                if reloadFunc and reloadFunc:IsA("RemoteFunction") then
                                    task.spawn(function() pcall(function() reloadFunc:InvokeServer() end) end)
                                    task.wait(1.2)
                                end
                            else
                                if gun.Parent ~= char then
                                    hum:EquipTool(gun)
                                    task.wait(0.08)
                                end

                                local targetHum = lowestInfected.Hum
                                local targetRoot = lowestInfected.Root

                                local shots = 0
                                while shots < 4 and targetHum and targetHum.Parent and targetHum.Health > 0 and Config.Enabled and FarmState.Mode ~= "EATING" do
                                    shots = shots + 1
                                    cam.CFrame = CFrame.new(cam.CFrame.Position, targetRoot.Position)
                                    pcall(function() gun:Activate() end)
                                    task.wait(Config.ShotInterval)

                                    if targetHum.Health <= 0 then
                                        FarmState.WaitingForChain = true
                                        FarmState.ChainWaitUntil = tick() + Config.WaitAfterKill
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ==============================================================================
-- 5. SISTEMA DE HAMBRE Y VIAJE A ZANAHORIAS
-- ==============================================================================

local function harvestAndEatCarrot(plotObj)
    local char, _, hum = getCharParts()
    if not char or not hum then return end

    -- Disparar cualquier ProximityPrompt de zanahorias cerca
    local structures = workspace:FindFirstChild("Structures") or workspace
    for _, desc in ipairs(structures:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local pPos = desc.Parent:IsA("BasePart") and desc.Parent.Position or (desc.Parent:IsA("Model") and desc.Parent:GetPivot().Position)
            if pPos and (pPos - char:GetPivot().Position).Magnitude <= 15 and fireproximityprompt then
                pcall(function() fireproximityprompt(desc) end)
                pcall(function() fireproximityprompt(desc, 0) end)
            end
        end
    end

    local pickRemote = ReplicatedStorage:FindFirstChild("PickUpItem", true)
    if pickRemote and pickRemote:IsA("RemoteEvent") and plotObj then
        for _, child in ipairs(plotObj:GetChildren()) do
            if child.Name:lower():find("carrot") then
                pcall(function() pickRemote:FireServer(child) end)
            end
        end
    end

    local foodTool = findPlayerTool("Carrot") or findPlayerTool(nil, "Food") or findPlayerTool(nil, "Consumable")
    if foodTool then
        if foodTool.Parent ~= char then
            hum:EquipTool(foodTool)
            task.wait(0.08)
        end
        pcall(function() foodTool:Activate() end)
        local useRem = foodTool:FindFirstChild("Use") or foodTool:FindFirstChild("Eat")
        if useRem and useRem:IsA("RemoteEvent") then
            pcall(function() useRem:FireServer() end)
        end
    end
end

task.spawn(function()
    while true do
        task.wait(0.5)
        local char, _, hum = getCharParts()
        if char and hum then
            local hunger = char:GetAttribute("Hunger") or 100
            FarmState.CurrentHunger = hunger
            FarmState.CurrentHP = hum.Health

            if Config.Enabled and Config.AutoEatEnabled then
                if FarmState.Mode ~= "EATING" and hunger <= Config.HungryThreshold then
                    if #FarmState.SavedFarmPlots == 0 then scanAndSaveFarmPlots() end
                    if #FarmState.SavedFarmPlots > 0 or FarmState.ManualCarrotPos then
                        FarmState.Mode = "EATING"
                        Fluent:Notify({
                            Title = "🥕 HAMBRE BAJA (" .. math.floor(hunger) .. "%)",
                            Content = "Viajando bajo tierra a comer zanahorias...",
                            Duration = 3
                        })
                    end
                elseif FarmState.Mode == "EATING" and hunger >= Config.FullHungerThreshold then
                    FarmState.Mode = "ORBITING"
                    Fluent:Notify({
                        Title = "✅ HAMBRE LLENA (" .. math.floor(hunger) .. "%)",
                        Content = "Volviendo a la zona de cacería.",
                        Duration = 3
                    })
                end
            end
        end
    end
end)

-- ==============================================================================
-- 6. MOTOR CINÉTICO CONSTANTE Y PREDICTIVO (NUNCA SE DEJA RODEAR)
-- ==============================================================================

local DesiredCFrame = nil

RunService.Stepped:Connect(function()
    if not Config.Enabled then return end
    local char, root = getCharParts()
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
    if root and DesiredCFrame then
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = DesiredCFrame
    end
end)

RunService.Heartbeat:Connect(function(dt)
    if not Config.Enabled then
        DesiredCFrame = nil
        return
    end

    local _, root, hum = getCharParts()
    if not root or not hum or hum.Health <= 0 then return end

    local myXZ = Vector3.new(root.Position.X, 0, root.Position.Z)
    local anchorXZ = Vector3.new(FarmState.AnchorPos.X, 0, FarmState.AnchorPos.Z)
    local targetY = (hum.Health < 60) and Config.LowHealthDepth or Config.UndergroundDepth

    -- CASO 1: COMIENDO ZANAHORIAS
    if FarmState.Mode == "EATING" then
        local carrotTargetXZ = nil
        local plotInstance = nil

        if FarmState.ManualCarrotPos then
            carrotTargetXZ = Vector3.new(FarmState.ManualCarrotPos.X, 0, FarmState.ManualCarrotPos.Z)
        elseif #FarmState.SavedFarmPlots > 0 then
            carrotTargetXZ = Vector3.new(FarmState.SavedFarmPlots[1].Position.X, 0, FarmState.SavedFarmPlots[1].Position.Z)
            plotInstance = FarmState.SavedFarmPlots[1].Instance
        end

        if carrotTargetXZ then
            targetY = -3.2
            local toCarrot = carrotTargetXZ - myXZ
            if toCarrot.Magnitude <= 7.5 then
                harvestAndEatCarrot(plotInstance)
                DesiredCFrame = CFrame.new(myXZ.X, targetY, myXZ.Z)
            else
                local step = math.min(toCarrot.Magnitude, Config.MoveSpeed * dt)
                local nextXZ = myXZ + (toCarrot.Unit * step)
                DesiredCFrame = CFrame.new(nextXZ.X, targetY, nextXZ.Z)
            end
            root.CFrame = DesiredCFrame
            return
        end
    end

    -- CASO 2: CACERÍA EN MOVIMIENTO CONSTANTE + EVASIÓN PREDICTIVA DE 300 ZOMBIES
    local threats = analyzeHordeAndPredict(root.Position)

    -- Avance angular constante alrededor de tu zona de ataque
    local angularSpeed = Config.MoveSpeed / math.max(25, Config.PatrolRadius)
    FarmState.OrbitAngle = (FarmState.OrbitAngle + angularSpeed * dt) % (math.pi * 2)

    local orbitTargetXZ = anchorXZ + Vector3.new(
        math.cos(FarmState.OrbitAngle) * Config.PatrolRadius,
        0,
        math.sin(FarmState.OrbitAngle) * Config.PatrolRadius
    )

    local toOrbit = orbitTargetXZ - myXZ
    local baseTangentDir = (toOrbit.Magnitude > 0.1) and toOrbit.Unit or Vector3.new(1, 0, 0)

    -- Buscar el corredor libre prediciendo hacia dónde van las masas
    local bestMoveDir = findBestEscapeDirection(myXZ, anchorXZ, threats, baseTangentDir)

    -- Suavizado de dirección para giro fluido y constante
    FarmState.CurrentEscapeDir = (FarmState.CurrentEscapeDir * 0.75 + bestMoveDir * 0.25).Unit

    local nextXZ = myXZ + (FarmState.CurrentEscapeDir * (Config.MoveSpeed * dt))
    FarmState.Mode = (#threats > 0) and "KITING PREDICTIVO" or "ÓRBITA CONSTANTE"

    DesiredCFrame = CFrame.new(nextXZ.X, targetY, nextXZ.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = DesiredCFrame
end)

-- ==============================================================================
-- 7. INTERFAZ FLUENT COMPLETA (SIN QUITAR NADA)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "HACKER UNDERGROUND | FARM V3",
    SubTitle = "Kiting Predictivo (300 Zombies) + Virus + Zanahorias",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 520),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Farmeo Hacker", Icon = "terminal" }),
    Safety = Window:AddTab({ Title = "Movimiento & Masas", Icon = "shield" }),
    Food = Window:AddTab({ Title = "Auto-Zanahorias", Icon = "apple" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Sistema Hacker",
    Content = "Esperando activación..."
})

Tabs.Main:AddToggle("EnableHackerFarm", {
    Title = "💻 Activar Cacería Subterránea V3",
    Description = "Movimiento constante predictivo + Poderes Hacker + Auto-Comida",
    Default = false,
    Callback = function(v)
        Config.Enabled = v
        local _, root = getCharParts()
        if v and root then
            FarmState.AnchorPos = root.Position
            scanAndSaveFarmPlots()
            Fluent:Notify({
                Title = "💻 HACKER FARM V3 ACTIVO",
                Content = string.format("Zona fijada. Parcelas registradas: %d", #FarmState.SavedFarmPlots),
                Duration = 3
            })
        elseif not v and root then
            DesiredCFrame = nil
            root.CFrame = CFrame.new(root.Position.X, 3.5, root.Position.Z)
        end
    end
})

Tabs.Main:AddButton({
    Title = "📍 Fijar Mi Posición Actual como Centro de Cacería",
    Callback = function()
        local _, root = getCharParts()
        if root then
            FarmState.AnchorPos = root.Position
            Fluent:Notify({ Title = "Zona Actualizada", Content = "Nuevo centro de órbita guardado.", Duration = 2.5 })
        end
    end
})

Tabs.Main:AddToggle("InfiltrateToggle", {
    Title = "🦠 Auto-Infiltrate (Cada 15s al de menor vida)",
    Default = true,
    Callback = function(v) Config.AutoInfiltrate = v end
})

Tabs.Main:AddToggle("OverrideToggle", {
    Title = "💥 Auto-System Override (Cada 120s)",
    Default = true,
    Callback = function(v) Config.AutoSystemOverride = v end
})

Tabs.Main:AddToggle("GunChainToggle", {
    Title = "🔫 Disparo a Infectado (Pausa 3s al matar)",
    Default = true,
    Callback = function(v) Config.AutoGunVirusChain = v end
})

-- PESTAÑA MOVIMIENTO & PREDICCIÓN DE MASAS
Tabs.Safety:AddSlider("SpeedSlider", {
    Title = "Velocidad de Desplazamiento Constante",
    Description = "Súbelo si sientes que los zombies corredores se acercan",
    Default = 38,
    Min = 20,
    Max = 75,
    Rounding = 0,
    Callback = function(v) Config.MoveSpeed = v end
})

Tabs.Safety:AddSlider("PatrolRadiusSlider", {
    Title = "Amplitud de Desplazamiento / Órbita (Studs)",
    Description = "Qué tan amplio se mueve tu muñeco para no quedar encerrado",
    Default = 65,
    Min = 30,
    Max = 130,
    Rounding = 0,
    Callback = function(v) Config.PatrolRadius = v end
})

Tabs.Safety:AddSlider("NormalSafeSlider", {
    Title = "Distancia de Esquive Zombies Normales (Studs)",
    Default = 32,
    Min = 18,
    Max = 55,
    Rounding = 0,
    Callback = function(v) Config.NormalZombieSafeDist = v end
})

Tabs.Safety:AddSlider("LethalSafeSlider", {
    Title = "Distancia de Esquive Bloaters / Hazmats (Studs)",
    Default = 55,
    Min = 35,
    Max = 85,
    Rounding = 0,
    Callback = function(v) Config.LethalZombieSafeDist = v end
})

Tabs.Safety:AddSlider("DepthSlider", {
    Title = "Profundidad Subterránea (Y)",
    Default = -6,
    Min = -14,
    Max = -3,
    Rounding = 1,
    Callback = function(v) Config.UndergroundDepth = v end
})

-- PESTAÑA ZANAHORIAS (CON REGISTRO AUTOMÁTICO Y MANUAL)
Tabs.Food:AddToggle("AutoEatToggle", {
    Title = "🥕 Ir a Comer Zanahorias Automáticamente",
    Default = true,
    Callback = function(v) Config.AutoEatEnabled = v end
})

Tabs.Food:AddSlider("HungrySlider", {
    Title = "Ir a Comer cuando Hambre baje de (%)",
    Default = 30,
    Min = 15,
    Max = 60,
    Rounding = 0,
    Callback = function(v) Config.HungryThreshold = v end
})

Tabs.Food:AddButton({
    Title = "🔍 Re-Escanear Mis Farm Plots Automáticamente",
    Description = "Busca todas las parcelas plantadas en la base",
    Callback = function()
        local count = scanAndSaveFarmPlots()
        Fluent:Notify({
            Title = "Escaneo de Zanahorias",
            Content = string.format("Se encontraron %d Farm Plots en el mapa.", count),
            Duration = 3
        })
    end
})

Tabs.Food:AddButton({
    Title = "📌 Guardar Mi Posición Actual como Punto de Zanahorias",
    Description = "Párate sobre tus zanahorias y presiona aquí para forzar esa coordenada",
    Callback = function()
        local _, root = getCharParts()
        if root then
            FarmState.ManualCarrotPos = root.Position
            Fluent:Notify({
                Title = "🥕 Coordenada de Zanahorias Fijada",
                Content = string.format("Guardado en: %.1f, %.1f", root.Position.X, root.Position.Z),
                Duration = 3
            })
        end
    end
})

-- MONITOR COMPLETO EN VIVO
task.spawn(function()
    while true do
        task.wait(0.4)
        local carrotStatus = FarmState.ManualCarrotPos and "Manual Fijado" or (tostring(#FarmState.SavedFarmPlots) .. " Plots")
        StatusParagraph:SetDesc(string.format(
            "Modo: %s | Zombies en 200 studs: %d\nInfectados con Virus: %d | Pausa 3s: %s\nVida: %.0f%% | Hambre: %.0f%% | Zanahorias: %s",
            FarmState.Mode, FarmState.TotalZombiesIn200,
            FarmState.InfectedCount, FarmState.WaitingForChain and "⏳ ESPERANDO" or "LISTO",
            FarmState.CurrentHP, FarmState.CurrentHunger, carrotStatus
        ))
    end
end)

Window:SelectTab(1)
