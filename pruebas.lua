-- ==============================================================================
-- HACKER GROUND COMBAT ASSISTANT V1: SOLO ATAQUE TERRESTRE (100 STUDS)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera

local Config = {
    Enabled = false,
    ScanRadius = 100,             -- Rango de análisis lateral (100 studs por defecto)

    -- 1. INFILTRARSE (CADA 15s AL ZOMBIE CON MENOS VIDA)
    AutoInfiltrate = true,
    InfiltrateRange = 50,         -- Rango máximo para lanzar Infiltrate

    -- 2. ANULACIÓN DEL SISTEMA (SOLO SI HAY > 7 INFECTADOS)
    AutoSystemOverride = true,
    MinInfectedForOverride = 7,   -- Activa solo cuando hay MÁS de 7 infectados (8+)

    -- 3. UZI INFILTRADOR / ARMA (AL INFECTADO CON MENOS VIDA)
    AutoGunVirus = true,
    GunRange = 100,               -- Rango de disparo (100 studs)
    ShotInterval = 0.25,          -- Tiempo entre cada bala
    MaxBurstShots = 4,            -- Balas máximas por ráfaga antes de verificar
    WaitAfterKill = 3.0,          -- Pausa en segundos tras matar al infectado
    AimCameraAtTarget = true      -- Apuntar cámara al disparar para asegurar impacto
}

local State = {
    InfectedCount = 0,
    TotalZombiesInRange = 0,
    LowestInfectedTarget = nil,
    LowestAnyTarget = nil,
    WaitingAfterKill = false,
    WaitUntilTick = 0,
    CurrentAction = "En espera"
}

local TargetHighlight = nil
local MainToggleInstance = nil

-- ==============================================================================
-- CURSOR SIEMPRE VISIBLE
-- ==============================================================================
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

-- ==============================================================================
-- 1. UTILIDADES DE PERSONAJE, HERRAMIENTAS Y DETECCIÓN DE VIRUS
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

-- Verifica si Infiltrate o System Override terminaron su enfriamiento
local function isAbilityReady(tool)
    if not tool then return false end
    local cd = tool:GetAttribute("Cooldown")
    return (cd == nil) or (type(cd) == "number" and cd <= 0.05)
end

-- Detecta si el zombie tiene el virus de Hacker activo
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

local function updateTargetHighlight(zombieModel)
    if TargetHighlight and TargetHighlight.Adornee == zombieModel then return end
    if TargetHighlight then TargetHighlight:Destroy(); TargetHighlight = nil end

    if zombieModel and Config.Enabled then
        TargetHighlight = Instance.new("Highlight")
        TargetHighlight.Name = "HackerTargetHighlight"
        TargetHighlight.FillColor = Color3.fromRGB(0, 255, 180)
        TargetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        TargetHighlight.FillTransparency = 0.45
        TargetHighlight.Adornee = zombieModel
        TargetHighlight.Parent = zombieModel
    end
end

-- ==============================================================================
-- 2. ESCÁNER HORIZONTAL EN 100 STUDS (INFECTADOS Y MENOR VIDA)
-- ==============================================================================

local function scanZombiesInRadius()
    local _, root = getCharParts()
    if not root then return 0, nil, nil, nil end

    local charFolder = workspace:FindFirstChild("Characters")
    if not charFolder then return 0, nil, nil, nil end

    local myXZ = Vector3.new(root.Position.X, 0, root.Position.Z)

    local infectedCount = 0
    local totalInRange = 0

    -- Para el Uzi: Zombie INFECTADO con menos vida dentro del rango de arma
    local lowestInfected = nil
    local lowestInfectedHP = math.huge

    -- Para Infiltrate: Zombie con menos vida dentro del rango de Infiltrate (prioriza no infectados para propagar)
    local lowestUninfected = nil
    local lowestUninfectedHP = math.huge

    local lowestOverallInfiltrate = nil
    local lowestOverallHP = math.huge

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and ent:GetAttribute("Zombie") == true then
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
            local hum = ent:FindFirstChildOfClass("Humanoid")

            if eRoot and hum and hum.Health > 0 then
                local zXZ = Vector3.new(eRoot.Position.X, 0, eRoot.Position.Z)
                local dist = (zXZ - myXZ).Magnitude

                if dist <= Config.ScanRadius then
                    totalInRange = totalInRange + 1
                    local isInfected = hasHackerVirus(ent)

                    -- Candidato general para Infiltrate en su rango
                    if dist <= Config.InfiltrateRange and hum.Health < lowestOverallHP then
                        lowestOverallHP = hum.Health
                        lowestOverallInfiltrate = { Model = ent, Root = eRoot, Hum = hum, Dist = dist }
                    end

                    if isInfected then
                        infectedCount = infectedCount + 1
                        if dist <= Config.GunRange and hum.Health < lowestInfectedHP then
                            lowestInfectedHP = hum.Health
                            lowestInfected = { Model = ent, Root = eRoot, Hum = hum, Dist = dist }
                        end
                    else
                        if dist <= Config.InfiltrateRange and hum.Health < lowestUninfectedHP then
                            lowestUninfectedHP = hum.Health
                            lowestUninfected = { Model = ent, Root = eRoot, Hum = hum, Dist = dist }
                        end
                    end
                end
            end
        end
    end

    State.InfectedCount = infectedCount
    State.TotalZombiesInRange = totalInRange
    State.LowestInfectedTarget = lowestInfected

    local bestInfiltrateTarget = lowestUninfected or lowestOverallInfiltrate
    State.LowestAnyTarget = bestInfiltrateTarget

    return infectedCount, lowestInfected, bestInfiltrateTarget
end

-- ==============================================================================
-- 3. EJECUCIÓN DE PODERES Y DISPARO QUIRÚRGICO
-- ==============================================================================

local function activateAbility(tool, targetRoot)
    local char, root, hum = getCharParts()
    if not char or not hum or not tool then return end

    if tool.Parent ~= char then
        hum:EquipTool(tool)
        task.wait(0.06)
    end

    if targetRoot and Config.AimCameraAtTarget then
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
        task.wait(0.12)
        if not Config.Enabled then
            State.CurrentAction = "Apagado"
            updateTargetHighlight(nil)
        else
            local char, root, hum = getCharParts()
            if char and root and hum and hum.Health > 0 then
                local infectedCount, lowestInfected, bestInfiltrateTarget = scanZombiesInRadius()

                -- =============================================================
                -- 1. ANULACIÓN DEL SISTEMA: SOLO SI HAY MÁS DE 7 INFECTADOS
                -- =============================================================
                local usedOverride = false
                if Config.AutoSystemOverride and infectedCount > Config.MinInfectedForOverride then
                    local sysTool = findPlayerTool("System Override")
                    if sysTool and isAbilityReady(sysTool) then
                        State.CurrentAction = string.format("💥 System Override (%d infectados)", infectedCount)
                        activateAbility(sysTool, nil)
                        usedOverride = true
                        task.wait(0.25)
                    end
                end

                -- =============================================================
                -- 2. INFILTRARSE: SIEMPRE AL ZOMBIE CON MENOS VIDA
                -- =============================================================
                local usedInfiltrate = false
                if not usedOverride and Config.AutoInfiltrate and bestInfiltrateTarget then
                    local infTool = findPlayerTool("Infiltrate")
                    if infTool and isAbilityReady(infTool) then
                        State.CurrentAction = string.format("🦠 Infiltrate -> %s (%.0f HP)", bestInfiltrateTarget.Model.Name, bestInfiltrateTarget.Hum.Health)
                        updateTargetHighlight(bestInfiltrateTarget.Model)
                        activateAbility(infTool, bestInfiltrateTarget.Root)
                        usedInfiltrate = true
                        task.wait(0.2)
                    end
                end

                -- =============================================================
                -- 3. UZI INFILTRADOR: DISPARAR AL INFECTADO CON MENOS VIDA
                -- =============================================================
                if not usedOverride and not usedInfiltrate and Config.AutoGunVirus then
                    if State.WaitingAfterKill then
                        local remaining = State.WaitUntilTick - tick()
                        if remaining <= 0 then
                            State.WaitingAfterKill = false
                        else
                            State.CurrentAction = string.format("⏳ Expansión viral (%.1fs)", remaining)
                        end
                    elseif lowestInfected and lowestInfected.Hum and lowestInfected.Hum.Health > 0 then
                        local gun = findPlayerTool("Infiltrator Uzi") or findPlayerTool(nil, "Gun")
                        if gun then
                            local ammo = gun:GetAttribute("Ammo")
                            if type(ammo) == "number" and ammo <= 0 then
                                State.CurrentAction = "🔄 Recargando arma..."
                                local reloadFunc = gun:FindFirstChild("Reload")
                                if reloadFunc and reloadFunc:IsA("RemoteFunction") then
                                    task.spawn(function() pcall(function() reloadFunc:InvokeServer() end) end)
                                    task.wait(1.1)
                                end
                            else
                                if gun.Parent ~= char then
                                    hum:EquipTool(gun)
                                    task.wait(0.08)
                                end

                                local tModel = lowestInfected.Model
                                local tHum = lowestInfected.Hum
                                local tRoot = lowestInfected.Root
                                updateTargetHighlight(tModel)

                                local shots = 0
                                while shots < Config.MaxBurstShots and tHum and tHum.Parent and tHum.Health > 0 and Config.Enabled do
                                    shots = shots + 1
                                    State.CurrentAction = string.format("🔫 Disparando a infectado (%.0f HP)", tHum.Health)

                                    if Config.AimCameraAtTarget and tRoot then
                                        local aimPos = tRoot.Position + Vector3.new(0, 0.5, 0)
                                        cam.CFrame = CFrame.new(cam.CFrame.Position, aimPos)
                                    end

                                    pcall(function() gun:Activate() end)
                                    task.wait(Config.ShotInterval)

                                    if tHum.Health <= 0 then
                                        State.WaitingAfterKill = true
                                        State.WaitUntilTick = tick() + Config.WaitAfterKill
                                        State.CurrentAction = "💥 Infectado eliminado. Esperando expansión..."
                                        break
                                    end
                                end
                            end
                        end
                    else
                        State.CurrentAction = "Escaneando objetivos (100 studs)..."
                        updateTargetHighlight(nil)
                    end
                end
            end
        end
    end
end)

-- ==============================================================================
-- 4. INTERFAZ FLUENT (MENÚ DE CONFIGURACIÓN DE RANGOS Y TIEMPOS)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "HACKER COMBAT | TIERRA V1",
    SubTitle = "Asistente de Poderes y Virus (100 Studs)",
    TabWidth = 155,
    Size = UDim2.fromOffset(560, 470),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Poderes & Arma", Icon = "zap" }),
    Ranges = Window:AddTab({ Title = "Rangos & Tiempos", Icon = "sliders" })
}

local StatusParagraph = Tabs.Combat:AddParagraph({
    Title = "Monitor de Virus en Tiempo Real",
    Content = "Esperando activación..."
})

MainToggleInstance = Tabs.Combat:AddToggle("MainEnableToggle", {
    Title = "⚡ Activar Asistente de Ataque Hacker",
    Default = false,
    Callback = function(v)
        Config.Enabled = v
        if not v then updateTargetHighlight(nil) end
    end
})

Tabs.Combat:AddToggle("InfiltrateToggle", {
    Title = "🦠 Auto-Infiltrarse (Al zombie con menos vida)",
    Default = true,
    Callback = function(v) Config.AutoInfiltrate = v end
})

Tabs.Combat:AddToggle("OverrideToggle", {
    Title = "💥 Auto-Anulación del Sistema (> 7 infectados)",
    Default = true,
    Callback = function(v) Config.AutoSystemOverride = v end
})

Tabs.Combat:AddToggle("UziToggle", {
    Title = "🔫 Auto-Disparo Uzi (Al infectado con menos vida)",
    Default = true,
    Callback = function(v) Config.AutoGunVirus = v end
})

Tabs.Combat:AddToggle("AimCamToggle", {
    Title = "🎯 Apuntar Cámara al Zombie al Disparar",
    Default = true,
    Callback = function(v) Config.AimCameraAtTarget = v end
})

-- PESTAÑA DE RANGOS Y TIEMPOS
Tabs.Ranges:AddSection("Configuración de Distancias (Studs)")

Tabs.Ranges:AddSlider("ScanRadiusSlider", {
    Title = "Rango General de Escaneo Lateral (Studs)",
    Default = 100,
    Min = 40,
    Max = 200,
    Rounding = 0,
    Callback = function(v)
        Config.ScanRadius = v
        Config.GunRange = v
    end
})

Tabs.Ranges:AddSlider("InfiltrateRangeSlider", {
    Title = "Rango de Alcance para Infiltrarse (Studs)",
    Default = 50,
    Min = 20,
    Max = 100,
    Rounding = 0,
    Callback = function(v) Config.InfiltrateRange = v end
})

Tabs.Ranges:AddSection("Condiciones y Tiempos de Disparo")

Tabs.Ranges:AddSlider("MinInfectedSlider", {
    Title = "Mínimo de Infectados para Anulación (> X)",
    Description = "Por defecto 7 (dispara cuando hay 8 o más infectados)",
    Default = 7,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Callback = function(v) Config.MinInfectedForOverride = v end
})

Tabs.Ranges:AddSlider("WaitKillSlider", {
    Title = "Pausa Tras Matar a un Infectado (Segundos)",
    Description = "Tiempo para dejar que el virus explote e infecte al resto",
    Default = 3.0,
    Min = 0.5,
    Max = 8.0,
    Rounding = 1,
    Callback = function(v) Config.WaitAfterKill = v end
})

Tabs.Ranges:AddSlider("ShotIntervalSlider", {
    Title = "Tiempo Entre Cada Bala (Segundos)",
    Default = 0.25,
    Min = 0.08,
    Max = 0.80,
    Rounding = 2,
    Callback = function(v) Config.ShotInterval = v end
})

-- ==============================================================================
-- 5. LOS 2 BOTONES FLOTANTES (1: MENÚ DE AJUSTES | 2: ON / OFF RÁPIDO)
-- ==============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HackerGroundAssistantGui"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

-- BOTÓN 1: ABRIR / CERRAR MENÚ DE RANGOS Y TIEMPOS
local MenuBtn = Instance.new("TextButton")
MenuBtn.Size = UDim2.new(0, 50, 0, 50)
MenuBtn.Position = UDim2.new(0.04, 0, 0.55, 0)
MenuBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 55)
MenuBtn.Text = "⚙️\nMENÚ"
MenuBtn.TextColor3 = Color3.fromRGB(0, 255, 190)
MenuBtn.TextSize = 11
MenuBtn.Font = Enum.Font.GothamBold
MenuBtn.Active = true
MenuBtn.Draggable = true
MenuBtn.Parent = ScreenGui

local MenuCorner = Instance.new("UICorner")
MenuCorner.CornerRadius = UDim.new(1, 0)
MenuCorner.Parent = MenuBtn

local isMenuOpen = true
MenuBtn.MouseButton1Click:Connect(function()
    isMenuOpen = not isMenuOpen
    Window.Root.Visible = isMenuOpen
end)

-- BOTÓN 2: ENCENDIDO / APAGADO RÁPIDO (ON / OFF)
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Position = UDim2.new(0.04, 0, 0.46, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
ToggleBtn.Text = "💻\nOFF"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 11
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Active = true
ToggleBtn.Draggable = true
ToggleBtn.Parent = ScreenGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = ToggleBtn

local function updateToggleVisuals()
    if Config.Enabled then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(25, 160, 75)
        ToggleBtn.Text = "💻\nON"
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 40)
        ToggleBtn.Text = "💻\nOFF"
    end
end

ToggleBtn.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled
    pcall(function() MainToggleInstance:SetValue(Config.Enabled) end)
    updateToggleVisuals()
end)

-- Sincronizar color del botón si lo cambias desde adentro del menú
task.spawn(function()
    while true do
        task.wait(0.3)
        updateToggleVisuals()
        StatusParagraph:SetDesc(string.format(
            "Estado: %s\nZombies en %d studs: %d | Infectados con Virus: %d (Req > %d)\nAcción Actual: %s",
            Config.Enabled and "🟢 ACTIVO" or "🔴 APAGADO",
            Config.ScanRadius, State.TotalZombiesInRange,
            State.InfectedCount, Config.MinInfectedForOverride,
            State.CurrentAction
        ))
    end
end)

Window:SelectTab(1)
