-- ==============================================================================
-- HACKER UNDERGROUND AUTO-FARM V1: VIRUS CHAIN + EVASIÓN LETAL + AUTO-COMIDA
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
    UndergroundDepth = -6.2,      -- Profundidad segura (alcance de poderes + sin rollback)
    LowHealthDepth = -10.5,       -- Baja más profundo si tu vida está en peligro
    SafeMoveSpeed = 25,           -- Menor a KM_MAX_PLAYER_SPEED (28) para 0 sospecha
    ScanRadius = 200,             -- Escaneo local de 200 studs

    -- ESQUIVE DE ZOMBIES LETALES (BLOATER / HAZMAT)
    EvadeLethals = true,
    LethalSafeDist = 38,          -- Distancia mínima contra explosiones y radiación

    -- PODERES DE HACKER
    AutoInfiltrate = true,        -- Cada 15s al zombie con menos vida
    AutoSystemOverride = true,    -- Cada 120s cuando hay zombies cerca
    AutoGunVirusChain = true,     -- Disparar al infectado con menos vida
    WaitAfterKill = 3.0,          -- Esperar 3s tras matar al infectado
    ShotInterval = 0.28,          -- Cadencia moderada bala por bala
    MaxAbilityRange = 45,         -- Rango para lanzar Infiltrate

    -- COMIDA (ZANAHORIAS)
    AutoEatEnabled = true,
    HungryThreshold = 30,         -- Ir a comer cuando Hunger <= 30%
    FullHungerThreshold = 85      -- Volver a atacar cuando Hunger >= 85%
}

local FarmState = {
    Mode = "IDLE",                -- "FARMING", "EVADING", "EATING"
    AnchorPos = Vector3.new(0, 0, 140), -- Posición base de farmeo (se fija al activar)
    SavedFarmPlots = {},          -- Coordenadas de tus Farm Plots
    CurrentTargetZombie = nil,
    WaitingForChain = false,
    ChainWaitUntil = 0,
    CurrentHunger = 100,
    CurrentHP = 100,
    InfectedCount = 0
}

-- ==============================================================================
-- CURSOR SIEMPRE VISIBLE
-- ==============================================================================
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. UTILIDADES DEL JUGADOR Y DETECCIÓN DE HERRAMIENTAS
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
-- 2. ESCÁNER DE PARCELAS DE ZANAHORIAS (FARM PLOTS)
-- ==============================================================================

local function scanAndSaveFarmPlots()
    local plots = {}
    local structures = workspace:FindFirstChild("Structures") or workspace

    for _, obj in ipairs(structures:GetChildren()) do
        if obj.Name == "Farm Plot" or obj.Name:lower():find("farm") then
            local pos = obj:IsA("Model") and obj:GetPivot().Position or (obj:IsA("BasePart") and obj.Position)
            if pos then
                table.insert(plots, { Instance = obj, Position = pos })
            end
        end
    end

    FarmState.SavedFarmPlots = plots
    return #plots
end

-- ==============================================================================
-- 3. CLASIFICADOR DE ZOMBIES EN 200 STUDS (LETALES, INFECTADOS Y MENOR VIDA)
-- ==============================================================================

local function isLethalZombie(entity)
    local n = entity.Name:lower()
    local var = tostring(entity:GetAttribute("Variant") or ""):lower()
    local check = n .. " " .. var

    if check:find("bloat") or check:find("acid") or check:find("hazmat") or check:find("nuclear") or check:find("boom") then
        return true
    end
    return false
end

local function hasHackerVirus(entity)
    if entity:GetAttribute("HackerVirus") == true then return true end
    for k, v in pairs(entity:GetAttributes()) do
        if k:lower():find("hackervirus") and v == true then
            return true
        end
    end
    if entity:FindFirstChild("VirusHighlight") then return true end
    return false
end

local function analyzeLocalZombies(originPos)
    local charFolder = workspace:FindFirstChild("Characters")
    if not charFolder then return {}, nil, nil, 0 end

    local lethals = {}
    local lowestInfected = nil
    local lowestInfectedHP = math.huge

    local lowestUninfected = nil
    local lowestUninfectedHP = math.huge
    local infectedTotal = 0

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and ent:GetAttribute("Zombie") == true then
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
            local hum = ent:FindFirstChildOfClass("Humanoid")

            if eRoot and hum and hum.Health > 0 then
                local horizDist = (Vector3.new(eRoot.Position.X, 0, eRoot.Position.Z) - Vector3.new(originPos.X, 0, originPos.Z)).Magnitude

                if horizDist <= Config.ScanRadius then
                    -- 1. ¿Es letal (Bloater / Acidic / Hazmat / Nuclear)?
                    if isLethalZombie(ent) then
                        table.insert(lethals, eRoot.Position)
                    end

                    -- 2. ¿Tiene el Virus Hacker?
                    local infected = hasHackerVirus(ent)
                    if infected then
                        infectedTotal = infectedTotal + 1
                        if horizDist <= 95 and hum.Health < lowestInfectedHP then
                            lowestInfectedHP = hum.Health
                            lowestInfected = { Model = ent, Root = eRoot, Hum = hum, Dist = horizDist }
                        end
                    else
                        -- 3. Zombie sano con menos vida (para tirarle Infiltrate)
                        if horizDist <= Config.MaxAbilityRange and hum.Health < lowestUninfectedHP then
                            lowestUninfectedHP = hum.Health
                            lowestUninfected = { Model = ent, Root = eRoot, Hum = hum, Dist = horizDist }
                        end
                    end
                end
            end
        end
    end

    FarmState.InfectedCount = infectedTotal
    return lethals, lowestInfected, lowestUninfected, infectedTotal
end

-- ==============================================================================
-- 4. LÓGICA DE ATAQUE: INFILTRATE + SYSTEM OVERRIDE + UZI VIRUS CHAIN
-- ==============================================================================

local function useAbilityTool(tool, targetRoot)
    local char, root, hum = getCharParts()
    if not char or not hum or not tool then return end

    if tool.Parent ~= char then
        hum:EquipTool(tool)
        task.wait(0.08)
    end

    -- Orientar hacia el objetivo si existe
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

-- Bucle de Poderes y Disparo Moderado
task.spawn(function()
    while true do
        task.wait(0.15)
        if Config.Enabled and FarmState.Mode ~= "EATING" then
            local char, root, hum = getCharParts()
            if char and root and hum and hum.Health > 0 then
                local _, lowestInfected, lowestUninfected, infectedCount = analyzeLocalZombies(root.Position)

                -- 1. PODER 2: SYSTEM OVERRIDE (120s) - Explota a todos apenas esté listo
                if Config.AutoSystemOverride then
                    local sysTool = findPlayerTool("System Override")
                    if sysTool and isAbilityReady(sysTool) and (infectedCount > 0 or lowestUninfected ~= nil) then
                        useAbilityTool(sysTool, nil)
                        task.wait(0.25)
                    end
                end

                -- 2. PODER 1: INFILTRATE (15s) - Al zombie sano con menos vida
                if Config.AutoInfiltrate then
                    local infTool = findPlayerTool("Infiltrate")
                    if infTool and isAbilityReady(infTool) then
                        local target = lowestUninfected or lowestInfected
                        if target then
                            useAbilityTool(infTool, target.Root)
                            task.wait(0.25)
                        end
                    end
                end

                -- 3. ARMA / UZI INFILTRADOR: Matar al infectado con menos vida y esperar 3s
                if Config.AutoGunVirusChain then
                    if FarmState.WaitingForChain then
                        if tick() >= FarmState.ChainWaitUntil then
                            FarmState.WaitingForChain = false
                        end
                    elseif lowestInfected and lowestInfected.Hum and lowestInfected.Hum.Health > 0 then
                        local gun = findPlayerTool("Infiltrator Uzi") or findPlayerTool(nil, "Gun")
                        if gun then
                            -- Recargar si el cargador llegó a 0
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
                                    task.wait(0.1)
                                end

                                FarmState.CurrentTargetZombie = lowestInfected.Model
                                local targetHum = lowestInfected.Hum
                                local targetRoot = lowestInfected.Root

                                -- Disparar moderadamente (máximo 4 tiros en esta ráfaga) hasta que muera
                                local shots = 0
                                while shots < 4 and targetHum and targetHum.Parent and targetHum.Health > 0 and Config.Enabled and FarmState.Mode ~= "EATING" do
                                    shots = shots + 1
                                    cam.CFrame = CFrame.new(cam.CFrame.Position, targetRoot.Position)
                                    pcall(function() gun:Activate() end)

                                    task.wait(Config.ShotInterval)

                                    -- Si el zombie murió por el disparo, activar pausa de 3 segundos
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
-- 5. SISTEMA DE HAMBRE Y VIAJE SUBTERRÁNEO A LAS ZANAHORIAS
-- ==============================================================================

local function harvestAndEatCarrot(plotObj)
    local char, _, hum = getCharParts()
    if not char or not hum then return end

    -- 1. Activar Prompts o PickUpItem en el Farm Plot
    if plotObj then
        for _, desc in ipairs(plotObj:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then
                if fireproximityprompt then
                    pcall(function() fireproximityprompt(desc) end)
                    pcall(function() fireproximityprompt(desc, 0) end)
                end
            end
        end

        local pickRemote = ReplicatedStorage:FindFirstChild("PickUpItem", true)
        if pickRemote and pickRemote:IsA("RemoteEvent") then
            for _, child in ipairs(plotObj:GetChildren()) do
                if child.Name:lower():find("carrot") then
                    pcall(function() pickRemote:FireServer(child) end)
                end
            end
        end
    end

    -- 2. Si hay una zanahoria o comida en la mochila, equiparla y comerla
    local foodTool = findPlayerTool("Carrot") or findPlayerTool(nil, "Food") or findPlayerTool(nil, "Consumable")
    if foodTool then
        if foodTool.Parent ~= char then
            hum:EquipTool(foodTool)
            task.wait(0.1)
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
                    if #FarmState.SavedFarmPlots > 0 then
                        FarmState.Mode = "EATING"
                        Fluent:Notify({
                            Title = "🥕 HAMBRE BAJA (" .. math.floor(hunger) .. "%)",
                            Content = "Viajando bajo tierra hacia tus Farm Plots...",
                            Duration = 3
                        })
                    end
                elseif FarmState.Mode == "EATING" and hunger >= Config.FullHungerThreshold then
                    FarmState.Mode = "FARMING"
                    Fluent:Notify({
                        Title = "✅ HAMBRE LLENA (" .. math.floor(hunger) .. "%)",
                        Content = "Regresando bajo tierra a tu zona de ataque.",
                        Duration = 3
                    })
                end
            end
        end
    end
end)

-- ==============================================================================
-- 6. MOTOR DE MOVIMIENTO SUBTERRÁNEO SEGURO (RESPETA KM_MAX_PLAYER_SPEED = 28)
-- ==============================================================================

-- Noclip continuo mientras el modo subterráneo esté activo
RunService.Stepped:Connect(function()
    if not Config.Enabled then return end
    local char = lp.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

RunService.Heartbeat:Connect(function(dt)
    if not Config.Enabled then return end

    local char, root, hum = getCharParts()
    if not root or not hum or hum.Health <= 0 then return end

    -- Determinar profundidad ideal (más profundo si la vida baja del 65%)
    local targetY = (hum.Health < 65) and Config.LowHealthDepth or Config.UndergroundDepth
    local targetXZ = Vector3.new(FarmState.AnchorPos.X, 0, FarmState.AnchorPos.Z)

    -- MODO A: VIAJANDO A COMER ZANAHORIAS
    if FarmState.Mode == "EATING" and #FarmState.SavedFarmPlots > 0 then
        local plot = FarmState.SavedFarmPlots[1]
        targetXZ = Vector3.new(plot.Position.X, 0, plot.Position.Z)
        targetY = -4.2 -- Suficientemente cerca del suelo para activar el prompt de la zanahoria

        local distToPlot = (Vector3.new(root.Position.X, 0, root.Position.Z) - targetXZ).Magnitude
        if distToPlot <= 8.0 then
            harvestAndEatCarrot(plot.Instance)
        end

    -- MODO B: FARMEANDO Y ESQUIVANDO BLOATERS / HAZMATS EN 200 STUDS
    else
        if Config.EvadeLethals then
            local lethals = analyzeLocalZombies(root.Position)
            local evadeVec = Vector3.zero

            for _, lPos in ipairs(lethals) do
                local diff = Vector3.new(root.Position.X - lPos.X, 0, root.Position.Z - lPos.Z)
                local dist = diff.Magnitude
                if dist <= Config.LethalSafeDist and dist > 0.1 then
                    evadeVec = evadeVec + (diff.Unit * (Config.LethalSafeDist - dist) * 1.5)
                end
            end

            if evadeVec.Magnitude > 0.5 then
                FarmState.Mode = "EVADING"
                targetXZ = Vector3.new(root.Position.X, 0, root.Position.Z) + evadeVec
            else
                FarmState.Mode = "FARMING"
            end
        end
    end

    -- Desplazamiento suave y seguro a <= 25 studs/s para mantener KM_TRUST_SCORE intacto
    local currentXZ = Vector3.new(root.Position.X, 0, root.Position.Z)
    local toTargetXZ = targetXZ - currentXZ
    local distXZ = toTargetXZ.Magnitude

    local nextXZ = currentXZ
    if distXZ > 1.0 then
        local step = math.min(distXZ, Config.SafeMoveSpeed * dt)
        nextXZ = currentXZ + (toTargetXZ.Unit * step)
    end

    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = CFrame.new(nextXZ.X, targetY, nextXZ.Z)
end)

-- ==============================================================================
-- 7. INTERFAZ FLUENT Y CONTROLES
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "HACKER UNDERGROUND | FARM V1",
    SubTitle = "Modo Subterráneo + Virus Chain + Zanahorias",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 480),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Farmeo Hacker", Icon = "terminal" }),
    Safety = Window:AddTab({ Title = "Profundidad & Esquive", Icon = "shield" }),
    Food = Window:AddTab({ Title = "Auto-Zanahorias", Icon = "apple" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Sistema Hacker",
    Content = "Desactivado. Posiciónate donde quieras farmear y actívalo."
})

local MainToggle = Tabs.Main:AddToggle("EnableHackerFarm", {
    Title = "💻 Activar Farmeo Subterráneo Hacker",
    Description = "Fija tu zona actual, baja a profundidad segura y ataca con Virus",
    Default = false,
    Callback = function(v)
        Config.Enabled = v
        local _, root = getCharParts()
        if v and root then
            FarmState.AnchorPos = root.Position
            FarmState.Mode = "FARMING"
            scanAndSaveFarmPlots()
            Fluent:Notify({
                Title = "💻 HACKER FARM ACTIVADO",
                Content = string.format("Zona fijada. Parcelas detectadas: %d", #FarmState.SavedFarmPlots),
                Duration = 3
            })
        elseif not v and root then
            -- Subir a la superficie al apagar
            root.CFrame = CFrame.new(root.Position.X, 3.5, root.Position.Z)
        end
    end
})

Tabs.Main:AddButton({
    Title = "📍 Fijar Posición Actual como Nueva Zona de Ataque",
    Callback = function()
        local _, root = getCharParts()
        if root then
            FarmState.AnchorPos = root.Position
            Fluent:Notify({ Title = "Zona Actualizada", Content = "Nuevo punto de farmeo guardado.", Duration = 2 })
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
    Title = "🔫 Disparo Moderado a Infectado (Pausa 3s al matar)",
    Default = true,
    Callback = function(v) Config.AutoGunVirusChain = v end
})

-- PESTAÑA SEGURIDAD
Tabs.Safety:AddSlider("DepthSlider", {
    Title = "Profundidad Subterránea Normal (Y)",
    Description = "-6.2 evita golpes y no dispara el rollback del servidor",
    Default = -6,
    Min = -14,
    Max = -3,
    Rounding = 1,
    Callback = function(v) Config.UndergroundDepth = v end
})

Tabs.Safety:AddSlider("LethalDistSlider", {
    Title = "Distancia de Esquive (Bloater / Hazmat)",
    Default = 38,
    Min = 20,
    Max = 70,
    Rounding = 0,
    Callback = function(v) Config.LethalSafeDist = v end
})

-- PESTAÑA COMIDA
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
    Title = "🔍 Re-Escanear Mis Farm Plots",
    Callback = function()
        local count = scanAndSaveFarmPlots()
        Fluent:Notify({ Title = "Parcelas Escaneadas", Content = "Farm Plots encontrados: " .. count, Duration = 2.5 })
    end
})

-- ACTUALIZACIÓN DEL MONITOR EN VIVO
task.spawn(function()
    while true do
        task.wait(0.4)
        StatusParagraph:SetDesc(string.format(
            "Modo: %s | Infectados cerca: %d\nVida: %.0f%% | Hambre: %.0f%%\nParcelas registradas: %d | Pausa 3s Post-Kill: %s",
            FarmState.Mode, FarmState.InfectedCount,
            FarmState.CurrentHP, FarmState.CurrentHunger,
            #FarmState.SavedFarmPlots,
            FarmState.WaitingForChain and "⏳ ESPERANDO EXPANSIÓN" or "LISTO"
        ))
    end
end)

Window:SelectTab(1)
