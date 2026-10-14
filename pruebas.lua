-- ==============================================================================
-- HACKER UNDERGROUND AUTO-FARM V2: BURBUJA ANTI-GOLPE + BÚNKER EN ROCA + VIRUS
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
    UseRockBunker = false,        -- Si se activa, se mete dentro de la roca grande más cercana
    UndergroundDepth = -5.5,      -- Profundidad en campo abierto
    RockBunkerDepth = -1.8,       -- Profundidad dentro de roca (NO activa rollback del server)
    SafeMoveSpeed = 26,           -- Debajo de KM_MAX_PLAYER_SPEED (28)
    ScanRadius = 200,

    -- BURBUJA HORIZONTAL (IMPIDE QUE SE PAREN ENCIMA DE TI)
    NormalZombieSafeDist = 20,    -- Ningún zombie normal a menos de 20 studs en X,Z
    LethalZombieSafeDist = 42,    -- Bloaters / Hazmats a más de 42 studs en X,Z

    -- PODERES DE HACKER
    AutoInfiltrate = true,        -- Cada 15s al zombie con menos vida
    AutoSystemOverride = true,    -- Cada 120s
    AutoGunVirusChain = true,     -- Disparar al infectado con menos vida
    WaitAfterKill = 3.0,          -- Pausa de 3s tras matar al infectado
    ShotInterval = 0.28,
    MaxAbilityRange = 48,

    -- COMIDA (ZANAHORIAS)
    AutoEatEnabled = true,
    HungryThreshold = 30,
    FullHungerThreshold = 85
}

local FarmState = {
    Mode = "IDLE",
    AnchorPos = Vector3.new(0, 0, 120),
    NearestRockPos = nil,
    SavedFarmPlots = {},
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
-- 2. ESCÁNER DE PARCELAS (FARM PLOTS) Y ROCAS GRANDES (BÚNKER)
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

local function findBestRockBunker()
    local _, root = getCharParts()
    local myPos = root and root.Position or Vector3.zero
    local mapFolder = workspace:FindFirstChild("Map") or workspace

    local bestPos = nil
    local shortestDist = 250

    for _, desc in ipairs(mapFolder:GetDescendants()) do
        if desc:IsA("BasePart") then
            local n = desc.Name:lower()
            -- Busca rocas grandes (como las de 14x10x15 del reporte)
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
-- 3. ESCÁNER DE ZOMBIES EN 200 STUDS (NORMALES, LETALES E INFECTADOS)
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

local function analyzeLocalZombies(originPos)
    local charFolder = workspace:FindFirstChild("Characters")
    if not charFolder then return {}, {}, nil, nil, 0 end

    local normalPositions = {}
    local lethalPositions = {}

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
                    if isLethalZombie(ent) then
                        table.insert(lethalPositions, eRoot.Position)
                    else
                        table.insert(normalPositions, eRoot.Position)
                    end

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

    FarmState.InfectedCount = infectedTotal
    return normalPositions, lethalPositions, lowestInfected, lowestUninfected, infectedTotal
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
                local _, _, lowestInfected, lowestUninfected, infectedCount = analyzeLocalZombies(root.Position)

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
-- 5. SISTEMA DE HAMBRE (ZANAHORIAS)
-- ==============================================================================

local function harvestAndEatCarrot(plotObj)
    local char, _, hum = getCharParts()
    if not char or not hum then return end

    if plotObj then
        for _, desc in ipairs(plotObj:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled and fireproximityprompt then
                pcall(function() fireproximityprompt(desc) end)
                pcall(function() fireproximityprompt(desc, 0) end)
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
                    if #FarmState.SavedFarmPlots > 0 then
                        FarmState.Mode = "EATING"
                        Fluent:Notify({
                            Title = "🥕 YENDO A COMER (" .. math.floor(hunger) .. "%)",
                            Content = "Desplazándose esquivando zombies hacia tus Farm Plots...",
                            Duration = 3
                        })
                    end
                elseif FarmState.Mode == "EATING" and hunger >= Config.FullHungerThreshold then
                    FarmState.Mode = "FARMING"
                    Fluent:Notify({
                        Title = "✅ HAMBRE RECUPERADA",
                        Content = "Volviendo a tu punto de ataque.",
                        Duration = 3
                    })
                end
            end
        end
    end
end)

-- ==============================================================================
-- 6. MOTOR DOBLE CAPA (STEPPED + HEARTBEAT) CON BURBUJA HORIZONTAL 360°
-- ==============================================================================

local DesiredCFrame = nil

-- En Stepped (Antes de las físicas): Anula inmediatamente cualquier subida a Y=1.6
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

-- En Heartbeat: Calcula el Kiting Horizontal para que NINGÚN zombie esté sobre tu (X, Z)
RunService.Heartbeat:Connect(function(dt)
    if not Config.Enabled then
        DesiredCFrame = nil
        return
    end

    local _, root, hum = getCharParts()
    if not root or not hum or hum.Health <= 0 then return end

    local baseGoalXZ = Vector3.new(FarmState.AnchorPos.X, 0, FarmState.AnchorPos.Z)
    local targetY = Config.UndergroundDepth

    -- Si el modo Búnker de Roca está activo, usa la roca y una profundidad suave (-1.8) que no da rollback
    if Config.UseRockBunker and FarmState.NearestRockPos then
        baseGoalXZ = Vector3.new(FarmState.NearestRockPos.X, 0, FarmState.NearestRockPos.Z)
        targetY = Config.RockBunkerDepth
    end

    -- Si está comiendo, el objetivo es la parcela de zanahorias
    if FarmState.Mode == "EATING" and #FarmState.SavedFarmPlots > 0 then
        local plot = FarmState.SavedFarmPlots[1]
        baseGoalXZ = Vector3.new(plot.Position.X, 0, plot.Position.Z)
        targetY = -3.2

        local distToPlot = (Vector3.new(root.Position.X, 0, root.Position.Z) - baseGoalXZ).Magnitude
        if distToPlot <= 8.0 then
            harvestAndEatCarrot(plot.Instance)
        end
    end

    -- CALCULAR REPULSIÓN HORIZONTAL CONTRA TODOS LOS ZOMBIES (EVITA GOLPES EN ROLLBACK)
    local normalZombies, lethalZombies = analyzeLocalZombies(root.Position)
    local myXZ = Vector3.new(root.Position.X, 0, root.Position.Z)
    local repulseVec = Vector3.zero

    -- 1. Alejarse 42 studs de Bloaters y Hazmats
    for _, lPos in ipairs(lethalZombies) do
        local diff = myXZ - Vector3.new(lPos.X, 0, lPos.Z)
        local d = diff.Magnitude
        if d < Config.LethalZombieSafeDist then
            local pushDir = (d > 0.1) and diff.Unit or Vector3.new(1, 0, 0)
            repulseVec = repulseVec + (pushDir * (Config.LethalZombieSafeDist - d) * 2.5)
        end
    end

    -- 2. Alejarse 20 studs de zombies normales (Si no estás dentro de un Búnker de Roca)
    if not (Config.UseRockBunker and FarmState.NearestRockPos and (myXZ - baseGoalXZ).Magnitude < 6) then
        for _, nPos in ipairs(normalZombies) do
            local diff = myXZ - Vector3.new(nPos.X, 0, nPos.Z)
            local d = diff.Magnitude
            if d < Config.NormalZombieSafeDist then
                local pushDir = (d > 0.1) and diff.Unit or Vector3.new(0, 0, 1)
                repulseVec = repulseVec + (pushDir * (Config.NormalZombieSafeDist - d) * 1.8)
            end
        end
    end

    local finalTargetXZ = baseGoalXZ
    if repulseVec.Magnitude > 0.5 then
        if FarmState.Mode ~= "EATING" then FarmState.Mode = "EVADING" end
        finalTargetXZ = myXZ + repulseVec
    else
        if FarmState.Mode ~= "EATING" then FarmState.Mode = "FARMING" end
    end

    -- Movimiento continuo a velocidad segura (<= 26 studs/s)
    local toGoal = finalTargetXZ - myXZ
    local dist = toGoal.Magnitude
    local nextXZ = myXZ

    if dist > 0.5 then
        local step = math.min(dist, Config.SafeMoveSpeed * dt)
        nextXZ = myXZ + (toGoal.Unit * step)
    end

    DesiredCFrame = CFrame.new(nextXZ.X, targetY, nextXZ.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = DesiredCFrame
end)

-- ==============================================================================
-- 7. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "HACKER UNDERGROUND | FARM V2",
    SubTitle = "Burbuja Anti-Golpe + Búnker en Roca + Virus",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 490),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Farmeo Hacker", Icon = "terminal" }),
    Safety = Window:AddTab({ Title = "Burbuja & Roca", Icon = "shield" }),
    Food = Window:AddTab({ Title = "Auto-Zanahorias", Icon = "apple" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Monitor en Vivo",
    Content = "Esperando activación..."
})

Tabs.Main:AddToggle("EnableHackerFarm", {
    Title = "💻 Activar Farmeo Hacker V2",
    Default = false,
    Callback = function(v)
        Config.Enabled = v
        local _, root = getCharParts()
        if v and root then
            FarmState.AnchorPos = root.Position
            scanAndSaveFarmPlots()
            findBestRockBunker()
        elseif not v and root then
            DesiredCFrame = nil
            root.CFrame = CFrame.new(root.Position.X, 3.5, root.Position.Z)
        end
    end
})

Tabs.Main:AddToggle("RockBunkerToggle", {
    Title = "🪨 Modo Búnker en Roca Grande (Recomendado - 0 Rollback)",
    Description = "Se mete dentro de la roca grande más cercana a Y=-1.8 donde los zombies chocan",
    Default = false,
    Callback = function(v)
        Config.UseRockBunker = v
        if v then
            local rPos = findBestRockBunker()
            if rPos then
                Fluent:Notify({ Title = "🪨 Roca Encontrada", Content = "Moviéndose al interior de la roca.", Duration = 3 })
            else
                Fluent:Notify({ Title = "⚠️ Sin Roca Cerca", Content = "Acércate a menos de 200 studs de una roca grande.", Duration = 3 })
            end
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

Tabs.Safety:AddSlider("NormalSafeSlider", {
    Title = "Burbuja contra Zombies Normales (Studs)",
    Description = "Impide que se paren encima de ti cuando ocurre un rollback",
    Default = 20,
    Min = 12,
    Max = 35,
    Rounding = 0,
    Callback = function(v) Config.NormalZombieSafeDist = v end
})

Tabs.Safety:AddSlider("LethalSafeSlider", {
    Title = "Burbuja contra Bloaters / Hazmats (Studs)",
    Default = 42,
    Min = 25,
    Max = 70,
    Rounding = 0,
    Callback = function(v) Config.LethalZombieSafeDist = v end
})

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

task.spawn(function()
    while true do
        task.wait(0.4)
        StatusParagraph:SetDesc(string.format(
            "Estado: %s | Infectados: %d\nVida: %.0f%% | Hambre: %.0f%%\nBúnker Roca: %s | Pausa 3s Post-Kill: %s",
            FarmState.Mode, FarmState.InfectedCount,
            FarmState.CurrentHP, FarmState.CurrentHunger,
            (Config.UseRockBunker and FarmState.NearestRockPos) and "🟢 ACTIVO" or "OFF (Kiting Abierto)",
            FarmState.WaitingForChain and "⏳ ESPERANDO 3s" or "LISTO"
        ))
    end
end)

Window:SelectTab(1)
