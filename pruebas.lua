-- ==============================================================================
-- HACKER GROUND COMBAT V2: SLOTS 5 & 6 + DISPARO 360° + PAUSA 2s POST-KILL
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera

local Config = {
    Enabled = false,
    ScanRadius = 100,             -- Escaneo de 100 studs a los lados

    -- SLOTS DE ARMAS A UTILIZAR
    UseSlot5 = true,              -- Usar arma en Slot 5 (ej. Infiltrator Uzi)
    UseSlot6 = true,              -- Usar arma en Slot 6 (ej. Pistol)

    -- 1. INFILTRARSE (CADA 15s AL DE MENOS VIDA)
    AutoInfiltrate = true,
    InfiltrateRange = 50,

    -- 2. ANULACIÓN DEL SISTEMA (SOLO SI HAY > 7 INFECTADOS)
    AutoSystemOverride = true,
    MinInfectedForOverride = 7,   -- Más de 7 infectados (8+)

    -- 3. DISPARO PAUSADO AL INFECTADO CON MENOS VIDA
    AutoGunVirus = true,
    GunRange = 100,
    ShotInterval = 0.22,          -- Tiempo entre cada bala al disparar
    WaitAfterKill = 2.0,          -- Espera 2 segundos tras matar al infectado
    MaxShotsPerTarget = 5,        -- Balas máximas seguidas antes de re-evaluar
    Silent360Mode = true          -- Disparar sin rotar tu vista (o micro-flick de 0.01s)
}

local State = {
    InfectedCount = 0,
    TotalZombiesInRange = 0,
    Slot5WeaponName = "Detectando...",
    Slot6WeaponName = "Detectando...",
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
-- 1. LECTURA AUTOMÁTICA DE LOS SLOTS 5 Y 6 EN EL HOTBAR
-- ==============================================================================

local function getCharParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function findToolByName(toolName)
    if not toolName or toolName == "" then return nil end
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    for _, cont in ipairs({char, bp}) do
        if cont then
            for _, item in ipairs(cont:GetChildren()) do
                if item:IsA("Tool") and item.Name:lower() == toolName:lower() then
                    return item
                end
            end
        end
    end
    return nil
end

-- Lee qué arma está asignada al botón 5 o 6 en PlayerGui.BackpackGui.Backpack.Hotbar
local function getToolFromHotbarSlot(slotNumber)
    local pGui = lp:FindFirstChild("PlayerGui")
    local bpGui = pGui and pGui:FindFirstChild("BackpackGui")
    local bpFrame = bpGui and bpGui:FindFirstChild("Backpack")
    local hotbar = bpFrame and bpFrame:FindFirstChild("Hotbar")
    local slotBtn = hotbar and hotbar:FindFirstChild(tostring(slotNumber))

    if slotBtn then
        for _, child in ipairs(slotBtn:GetDescendants()) do
            if child:IsA("TextLabel") then
                local txt = child.Text
                -- Ignorar el número del slot ('5', '6') y cantidades ('x1')
                if txt ~= "" and txt ~= tostring(slotNumber) and not txt:match("^x%d+$") and not txt:match("^%d+s$") then
                    local foundTool = findToolByName(txt)
                    if foundTool then
                        return foundTool, txt
                    end
                end
            end
        end
    end
    return nil, "Vacío"
end

-- Selecciona la mejor arma disponible entre el Slot 5 y el Slot 6
local function getBestSlotWeapon()
    local tool5, name5 = getToolFromHotbarSlot(5)
    local tool6, name6 = getToolFromHotbarSlot(6)

    State.Slot5WeaponName = name5
    State.Slot6WeaponName = name6

    -- Priorizar Slot 5 si tiene balas
    if Config.UseSlot5 and tool5 then
        local ammo5 = tool5:GetAttribute("Ammo")
        if type(ammo5) ~= "number" or ammo5 > 0 then
            return tool5
        end
    end

    -- Si Slot 5 está vacío o sin balas, usar Slot 6
    if Config.UseSlot6 and tool6 then
        local ammo6 = tool6:GetAttribute("Ammo")
        if type(ammo6) ~= "number" or ammo6 > 0 then
            return tool6
        end
    end

    -- Si ambas están en 0 balas, devolver la del Slot 5 o 6 para que el script la recargue
    if Config.UseSlot5 and tool5 then return tool5 end
    if Config.UseSlot6 and tool6 then return tool6 end

    return nil
end

local function isAbilityReady(tool)
    if not tool then return false end
    local cd = tool:GetAttribute("Cooldown")
    return (cd == nil) or (type(cd) == "number" and cd <= 0.05)
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
-- 2. ESCÁNER DE ZOMBIES EN 100 STUDS
-- ==============================================================================

local function scanZombiesIn100Studs()
    local _, root = getCharParts()
    if not root then return 0, nil, nil end

    local charFolder = workspace:FindFirstChild("Characters")
    if not charFolder then return 0, nil, nil end

    local myXZ = Vector3.new(root.Position.X, 0, root.Position.Z)

    local infectedCount = 0
    local totalInRange = 0

    local lowestInfected = nil
    local lowestInfectedHP = math.huge

    local lowestUninfected = nil
    local lowestUninfectedHP = math.huge

    local lowestAnyInfiltrate = nil
    local lowestAnyHP = math.huge

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

                    if dist <= Config.InfiltrateRange and hum.Health < lowestAnyHP then
                        lowestAnyHP = hum.Health
                        lowestAnyInfiltrate = { Model = ent, Root = eRoot, Hum = hum, Dist = dist }
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

    local bestInfiltrateTarget = lowestUninfected or lowestAnyInfiltrate
    return infectedCount, lowestInfected, bestInfiltrateTarget
end

-- ==============================================================================
-- 3. MOTOR DE DISPARO 360° (REMOTE + MICRO-FLICK INSTANTÁNEO)
-- ==============================================================================

local function fireWeaponAtTarget(gun, targetModel, targetRoot, targetHum)
    local char, root, hum = getCharParts()
    if not char or not root or not gun or not targetRoot then return end

    local head = targetModel:FindFirstChild("Head") or targetRoot
    local originPos = (root.CFrame * CFrame.new(0, 1.5, 0)).Position
    local hitPos = head.Position
    local dirVec = (hitPos - originPos).Unit
    local rKey = gun:GetAttribute("RandomKey")

    -- 1. Disparo por RemoteEvents directos (Con RandomKey para cuando estás de espaldas)
    local shootRemote = gun:FindFirstChild("Shoot")
    local hitRemote = gun:FindFirstChild("ProjectileHit")

    if shootRemote and shootRemote:IsA("RemoteEvent") then
        pcall(function() shootRemote:FireServer(originPos, dirVec, rKey) end)
        pcall(function() shootRemote:FireServer(hitPos, rKey) end)
        pcall(function() shootRemote:FireServer(rKey, originPos, dirVec) end)
    end

    if hitRemote and hitRemote:IsA("RemoteEvent") then
        pcall(function() hitRemote:FireServer(head, hitPos, dirVec, rKey) end)
        pcall(function() hitRemote:FireServer(targetModel, head, hitPos, rKey) end)
        pcall(function() hitRemote:FireServer(rKey, head, hitPos) end)
    end

    -- 2. Micro-Flick de 1 fotograma + Input Virtual (Hace que el script local del arma dispare con su propia RandomKey sin girar tu pantalla visualmente)
    local savedCamCF = cam.CFrame
    local savedRootCF = root.CFrame

    -- Orientar personaje y cámara hacia el objetivo durante 1 frame antes del disparo
    cam.CFrame = CFrame.new(savedCamCF.Position, hitPos)
    root.CFrame = CFrame.new(root.Position, Vector3.new(hitPos.X, root.Position.Y, hitPos.Z))

    pcall(function() gun:Activate() end)
    if mouse1click then
        pcall(mouse1click)
    else
        pcall(function()
            local vp = cam.ViewportSize
            VirtualInputManager:SendMouseButtonEvent(vp.X * 0.5, vp.Y * 0.5, 0, true, game, 1)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(vp.X * 0.5, vp.Y * 0.5, 0, false, game, 1)
        end)
    end

    -- Si Silent360Mode está activo, restaurar tu cámara original al instante para que no sientas el giro
    if Config.Silent360Mode then
        RunService.RenderStepped:Wait()
        cam.CFrame = savedCamCF
    end
end

local function useHackerAbility(tool, targetRoot)
    local char, root, hum = getCharParts()
    if not char or not root or not hum or not tool then return end

    if tool.Parent ~= char then
        hum:EquipTool(tool)
        task.wait(0.06)
    end

    local savedCamCF = cam.CFrame
    if targetRoot then
        cam.CFrame = CFrame.new(savedCamCF.Position, targetRoot.Position)
        root.CFrame = CFrame.new(root.Position, Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z))
    end

    pcall(function() tool:Activate() end)
    local useRem = tool:FindFirstChild("Use")
    if useRem and useRem:IsA("RemoteEvent") then
        if targetRoot then
            pcall(function() useRem:FireServer(targetRoot.Parent) end)
            pcall(function() useRem:FireServer(targetRoot.Position) end)
        else
            pcall(function() useRem:FireServer() end)
        end
    end

    if mouse1click then pcall(mouse1click) end

    if targetRoot and Config.Silent360Mode then
        RunService.RenderStepped:Wait()
        cam.CFrame = savedCamCF
    end
end

-- ==============================================================================
-- 4. BUCLE PRINCIPAL DE PRIORIDADES (OVERRIDE > INFILTRATE > SLOTS 5/6)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.12)
        if not Config.Enabled then
            State.CurrentAction = "Apagado"
            updateTargetHighlight(nil)
        else
            local char, root, hum = getCharParts()
            if char and root and hum and hum.Health > 0 then
                local infectedCount, lowestInfected, bestInfiltrateTarget = scanZombiesIn100Studs()

                -- =============================================================
                -- 1. ANULACIÓN DEL SISTEMA: SOLO SI HAY MÁS DE 7 INFECTADOS
                -- =============================================================
                local didOverride = false
                if Config.AutoSystemOverride and infectedCount > Config.MinInfectedForOverride then
                    local sysTool = findToolByName("System Override")
                    if sysTool and isAbilityReady(sysTool) then
                        State.CurrentAction = string.format("💥 System Override (%d infectados)", infectedCount)
                        useHackerAbility(sysTool, nil)
                        didOverride = true
                        task.wait(0.25)
                    end
                end

                -- =============================================================
                -- 2. INFILTRARSE: SIEMPRE AL ZOMBIE CON MENOS VIDA
                -- =============================================================
                local didInfiltrate = false
                if not didOverride and Config.AutoInfiltrate and bestInfiltrateTarget then
                    local infTool = findToolByName("Infiltrate")
                    if infTool and isAbilityReady(infTool) then
                        State.CurrentAction = string.format("🦠 Infiltrate -> %s (%.0f HP)", bestInfiltrateTarget.Model.Name, bestInfiltrateTarget.Hum.Health)
                        updateTargetHighlight(bestInfiltrateTarget.Model)
                        useHackerAbility(infTool, bestInfiltrateTarget.Root)
                        didInfiltrate = true
                        task.wait(0.22)
                    end
                end

                -- =============================================================
                -- 3. ARMAS EN SLOTS 5 Y 6: DISPARAR AL INFECTADO CON MENOS VIDA
                -- =============================================================
                if not didOverride and not didInfiltrate and Config.AutoGunVirus then
                    if State.WaitingAfterKill then
                        local rem = State.WaitUntilTick - tick()
                        if rem <= 0 then
                            State.WaitingAfterKill = false
                        else
                            State.CurrentAction = string.format("⏳ Pausa post-kill (%.1fs)", rem)
                        end
                    elseif lowestInfected and lowestInfected.Hum and lowestInfected.Hum.Health > 0 then
                        local gun = getBestSlotWeapon()
                        if gun then
                            local ammo = gun:GetAttribute("Ammo")
                            if type(ammo) == "number" and ammo <= 0 then
                                State.CurrentAction = "🔄 Recargando " .. gun.Name .. "..."
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

                                local tModel = lowestInfected.Model
                                local tRoot = lowestInfected.Root
                                local tHum = lowestInfected.Hum
                                updateTargetHighlight(tModel)

                                local shotsFired = 0
                                while shotsFired < Config.MaxShotsPerTarget and tHum and tHum.Parent and tHum.Health > 0 and Config.Enabled do
                                    shotsFired = shotsFired + 1
                                    State.CurrentAction = string.format("🔫 [%s] -> Infectado (%.0f HP)", gun.Name, tHum.Health)

                                    fireWeaponAtTarget(gun, tModel, tRoot, tHum)
                                    task.wait(Config.ShotInterval)

                                    -- Si el zombie infectado murió, esperar 2 segundos antes de atacar al siguiente
                                    if tHum.Health <= 0 then
                                        State.WaitingAfterKill = true
                                        State.WaitUntilTick = tick() + Config.WaitAfterKill
                                        State.CurrentAction = string.format("💥 Muerto. Esperando %.1fs...", Config.WaitAfterKill)
                                        break
                                    end
                                end
                            end
                        else
                            State.CurrentAction = "⚠️ Sin armas en Slot 5 o 6"
                        end
                    else
                        State.CurrentAction = "Escaneando infectados (100 studs)..."
                        updateTargetHighlight(nil)
                    end
                end
            end
        end
    end
end)

-- ==============================================================================
-- 5. INTERFAZ FLUENT (CONFIGURACIÓN DE RANGOS, SLOTS Y TIEMPOS)
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "HACKER COMBAT | SLOTS 5 & 6",
    SubTitle = "Disparo 360° + Virus + Pausa Configurable",
    TabWidth = 155,
    Size = UDim2.fromOffset(560, 480),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Poderes & Slots", Icon = "zap" }),
    Settings = Window:AddTab({ Title = "Rangos & Tiempos", Icon = "sliders" })
}

local StatusParagraph = Tabs.Combat:AddParagraph({
    Title = "Monitor Hacker (Tierra)",
    Content = "Esperando activación..."
})

MainToggleInstance = Tabs.Combat:AddToggle("MainEnableToggle", {
    Title = "⚡ Activar Asistente Hacker Terrestre",
    Default = false,
    Callback = function(v)
        Config.Enabled = v
        if not v then updateTargetHighlight(nil) end
    end
})

Tabs.Combat:AddToggle("Slot5Toggle", {
    Title = "🔫 Usar Arma del Slot 5 (Prioridad 1)",
    Default = true,
    Callback = function(v) Config.UseSlot5 = v end
})

Tabs.Combat:AddToggle("Slot6Toggle", {
    Title = "🔫 Usar Arma del Slot 6 (Respaldo / Secundaria)",
    Default = true,
    Callback = function(v) Config.UseSlot6 = v end
})

Tabs.Combat:AddToggle("Silent360Toggle", {
    Title = "🔄 Disparo 360° Sin Girar Tu Cámara (Silent Flick)",
    Description = "Dispara aunque estés de espaldas manteniendo tu vista fija",
    Default = true,
    Callback = function(v) Config.Silent360Mode = v end
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

-- PESTAÑA DE RANGOS Y TIEMPOS
Tabs.Settings:AddSection("Tiempos de Disparo y Expansión")

Tabs.Settings:AddSlider("WaitKillSlider", {
    Title = "Espera Tras Matar a un Infectado (Segundos)",
    Description = "Pausa antes de disparar al siguiente infectado (Por defecto 2s)",
    Default = 2.0,
    Min = 0.5,
    Max = 6.0,
    Rounding = 1,
    Callback = function(v) Config.WaitAfterKill = v end
})

Tabs.Settings:AddSlider("ShotIntervalSlider", {
    Title = "Tiempo Entre Cada Bala (Segundos)",
    Default = 0.22,
    Min = 0.08,
    Max = 0.80,
    Rounding = 2,
    Callback = function(v) Config.ShotInterval = v end
})

Tabs.Settings:AddSection("Rangos y Condiciones")

Tabs.Settings:AddSlider("ScanRadiusSlider", {
    Title = "Rango de Análisis y Disparo (Studs)",
    Default = 100,
    Min = 40,
    Max = 200,
    Rounding = 0,
    Callback = function(v)
        Config.ScanRadius = v
        Config.GunRange = v
    end
})

Tabs.Settings:AddSlider("InfiltrateRangeSlider", {
    Title = "Rango de Infiltrarse (Studs)",
    Default = 50,
    Min = 20,
    Max = 100,
    Rounding = 0,
    Callback = function(v) Config.InfiltrateRange = v end
})

Tabs.Settings:AddSlider("MinInfectedSlider", {
    Title = "Mínimo de Infectados para Anulación (> X)",
    Default = 7,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Callback = function(v) Config.MinInfectedForOverride = v end
})

-- ==============================================================================
-- 6. LOS 2 BOTONES FLOTANTES (1: MENÚ DE CONFIGURACIÓN | 2: ON / OFF)
-- ==============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HackerGroundV2Gui"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

-- BOTÓN 1: ABRIR / CERRAR MENÚ
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

-- BOTÓN 2: ON / OFF RÁPIDO
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

local function refreshButtonVisual()
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
    refreshButtonVisual()
end)

task.spawn(function()
    while true do
        task.wait(0.35)
        getBestSlotWeapon()
        refreshButtonVisual()
        StatusParagraph:SetDesc(string.format(
            "Estado: %s | Slot 5: [%s] | Slot 6: [%s]\nZombies (100m): %d | Infectados: %d (Override > %d)\nAcción: %s",
            Config.Enabled and "🟢 ACTIVO" or "🔴 OFF",
            State.Slot5WeaponName, State.Slot6WeaponName,
            State.TotalZombiesInRange, State.InfectedCount, Config.MinInfectedForOverride,
            State.CurrentAction
        ))
    end
end)

Window:SelectTab(1)
