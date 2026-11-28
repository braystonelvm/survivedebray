-- ==============================================================================
-- REGISTRADOR FORENSE DE JEFES & PROYECTILES (TYRANT / EXPERIMENT / SPITTER)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local Recorder = {
    Active = false,
    StartTime = 0,
    Logs = {},
    BossCount = 0,
    ProjCount = 0,
    InspectedModels = {},
    TrackedProjectiles = {}
}

local UIStatusLabel = nil
local UICounterLabel = nil

-- ==============================================================================
-- 1. UTILIDADES DE SERIALIZACIÓN Y EXTRACCIÓN DE PODERES INTERNOS
-- ==============================================================================

local function fmtVec(v)
    return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function addLog(tag, msg)
    if not Recorder.Active then return end
    local elapsed = tick() - Recorder.StartTime
    local line = string.format("[t+%06.2fs] [%s] %s", elapsed, tag, msg)
    table.insert(Recorder.Logs, line)

    if UIStatusLabel then
        UIStatusLabel.Text = line
    end
    if UICounterLabel then
        UICounterLabel.Text = string.format("Eventos: %d | Jefes: %d | Proyectiles: %d", #Recorder.Logs, Recorder.BossCount, Recorder.ProjCount)
    end
end

local function getAttributesString(inst)
    local attrs = inst:GetAttributes()
    local out = {}
    for k, v in pairs(attrs) do
        table.insert(out, tostring(k) .. "=" .. tostring(v))
    end
    return (#out > 0) and ("{" .. table.concat(out, ", ") .. "}") or "{}"
end

local function isTargetBossName(nameStr)
    local low = nameStr:lower()
    return low:find("tyrant", 1, true)
        or low:find("experiment", 1, true)
        or low:find("spitter", 1, true)
        or low:find("splitter", 1, true)
        or low:find("boss", 1, true)
        or low:find("cyborg", 1, true)
end

-- Inspecciona un jefe (Tyrant, Experiment, Spitter) para extraer sus poderes asignados
local function inspectBossModel(model)
    if not Recorder.Active or not model or not model:IsA("Model") then return end
    if Recorder.InspectedModels[model] then return end
    if model == lp.Character or Players:GetPlayerFromCharacter(model) then return end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local isNamedBoss = isTargetBossName(model.Name)
    local isHighHpBoss = (hum and hum.MaxHealth >= 3000)

    if not isNamedBoss and not isHighHpBoss then return end

    Recorder.InspectedModels[model] = true
    Recorder.BossCount = Recorder.BossCount + 1

    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    local posStr = root and fmtVec(root.Position) or "N/A"
    local hpStr = hum and string.format("%.0f/%.0f", hum.Health, hum.MaxHealth) or "N/A"

    local abilities = {}
    local anims = {}
    local values = {}

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Tool") or desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") or desc:IsA("BindableEvent") then
            table.insert(abilities, desc.ClassName .. ":" .. desc.Name)
        elseif desc:IsA("Animation") then
            table.insert(anims, desc.Name .. "(" .. tostring(desc.AnimationId) .. ")")
        elseif desc:IsA("ValueBase") then
            pcall(function()
                table.insert(values, desc.Name .. "=" .. tostring(desc.Value))
            end)
        end
    end

    addLog("BOSS_FOUND", string.format(
        "Nombre='%s' | HP=%s | Pos=%s | Attrs=%s",
        model.Name, hpStr, posStr, getAttributesString(model)
    ))
    addLog("BOSS_POWERS", string.format(
        "'%s' -> Tools/Remotes=[%s] | Values=[%s] | Anims=[%s]",
        model.Name,
        (#abilities > 0 and table.concat(abilities, ", ") or "Ninguno"),
        (#values > 0 and table.concat(values, ", ") or "Ninguno"),
        (#anims > 0 and table.concat(anims, ", ") or "Ninguna")
    ))

    -- Vigilar cambios de atributos del jefe mientras ataca (ej. Attacking, Cooldown, State)
    local attrConn
    attrConn = model.AttributeChanged:Connect(function(attrName)
        if not Recorder.Active or not model.Parent then
            if attrConn then attrConn:Disconnect() end
            return
        end
        addLog("BOSS_ATTR", string.format("'%s' -> %s = %s", model.Name, attrName, tostring(model:GetAttribute(attrName))))
    end)
end

-- ==============================================================================
-- 2. RASTREADOR DE OBJETOS VOLADORES, MISILES Y ÁCIDO (0% LAG)
-- ==============================================================================

local function getMoversAndForces(part)
    local list = {}
    for _, desc in ipairs(part:GetDescendants()) do
        if desc:IsA("BodyMover") or desc:IsA("Constraint") or desc:IsA("LinearVelocity") or desc:IsA("AlignPosition") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
            table.insert(list, desc.ClassName .. ":" .. desc.Name)
        end
    end
    return (#list > 0) and table.concat(list, ",") or "Ninguno"
end

local function registerFlyingObject(obj)
    if not Recorder.Active or not obj or not obj.Parent then return end

    -- Ignorar mapa estático, carpeta de personajes/zombis y jugadores para 0% lag
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder and obj:IsDescendantOf(mapFolder) then return end
    local charsFolder = workspace:FindFirstChild("Characters")
    if charsFolder and obj:IsDescendantOf(charsFolder) then return end
    if lp.Character and obj:IsDescendantOf(lp.Character) then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and obj:IsDescendantOf(plr.Character) then return end
    end

    local part = obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")))
    if not part then return end
    if Recorder.TrackedProjectiles[part] then return end

    -- Esperar 1 frame para que el servidor asigne velocidad y posición inicial
    task.defer(function()
        if not Recorder.Active or not part or not part.Parent then return end
        if Recorder.TrackedProjectiles[part] then return end

        local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local distToMe = myRoot and (part.Position - myRoot.Position).Magnitude or -1

        -- Registrar si está en movimiento, no anclado, o tiene nombre/efecto de proyectil/ácido
        local lowName = obj.Name:lower()
        local parentName = obj.Parent and obj.Parent.Name:lower() or ""
        local isNamedHazard = lowName:find("missile") or lowName:find("rocket") or lowName:find("acid")
            or lowName:find("spit") or lowName:find("goo") or lowName:find("proj")
            or lowName:find("tyrant") or lowName:find("experiment") or lowName:find("bomb")
            or parentName:find("projectile") or parentName:find("effect") or parentName:find("debris")

        if (not part.Anchored) or part.AssemblyLinearVelocity.Magnitude > 1.0 or isNamedHazard then
            Recorder.ProjCount = Recorder.ProjCount + 1
            local id = Recorder.ProjCount
            Recorder.TrackedProjectiles[part] = {
                Id = id,
                Name = obj.Name,
                FullName = obj:GetFullName(),
                SpawnTime = tick(),
                SpawnPos = part.Position,
                LastPos = part.Position,
                Part = part
            }

            addLog("PROJ_SPAWN", string.format(
                "#%d Nombre='%s' | Ruta=%s | Size=%s | Pos=%s | Vel=%s (%.1f studs/s) | DistATi=%.1f | Anchored=%s | Color=%s | Fuerzas/FX=[%s] | Attrs=%s",
                id,
                obj.Name,
                obj:GetFullName(),
                fmtVec(part.Size),
                fmtVec(part.Position),
                fmtVec(part.AssemblyLinearVelocity),
                part.AssemblyLinearVelocity.Magnitude,
                distToMe,
                tostring(part.Anchored),
                tostring(part.BrickColor),
                getMoversAndForces(obj),
                getAttributesString(obj)
            ))
        end
    end)
end

-- Bucle de seguimiento de trayectoria de los proyectiles activos (cada 0.25s)
task.spawn(function()
    while true do
        task.wait(0.25)
        if not Recorder.Active then continue end

        local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local myPos = myRoot and myRoot.Position

        for part, info in pairs(Recorder.TrackedProjectiles) do
            if not part or not part.Parent then
                local life = tick() - info.SpawnTime
                local dEnd = myPos and (info.LastPos - myPos).Magnitude or -1
                addLog("PROJ_END", string.format(
                    "#%d '%s' desapareció tras %.2fs | ÚltimaPos=%s | DistATi=%.1f",
                    info.Id, info.Name, life, fmtVec(info.LastPos), dEnd
                ))
                Recorder.TrackedProjectiles[part] = nil
            else
                info.LastPos = part.Position
                local vel = part.AssemblyLinearVelocity
                local distMe = myPos and (part.Position - myPos).Magnitude or -1
                if vel.Magnitude > 0.5 or distMe <= 45 then
                    addLog("PROJ_FLY", string.format(
                        "#%d '%s' | Pos=%s | Vel=%s (%.1f studs/s) | DistATi=%.1f",
                        info.Id, info.Name, fmtVec(part.Position), fmtVec(vel), vel.Magnitude, distMe
                    ))
                end
            end
        end
    end
end)

-- ==============================================================================
-- 3. CONEXIÓN DE EVENTOS Y CONTROL PLAY / STOP / COPIAR
-- ==============================================================================

local Conns = {}

local function disconnectAll()
    for _, c in ipairs(Conns) do
        if c then c:Disconnect() end
    end
    table.clear(Conns)
end

local function startRecording()
    disconnectAll()
    Recorder.Logs = {}
    Recorder.BossCount = 0
    Recorder.ProjCount = 0
    Recorder.InspectedModels = {}
    Recorder.TrackedProjectiles = {}
    Recorder.StartTime = tick()
    Recorder.Active = true

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    addLog("START", string.format(
        "Grabación iniciada | TuPos=%s | TuHP=%s",
        root and fmtVec(root.Position) or "N/A",
        hum and string.format("%.0f/%.0f", hum.Health, hum.MaxHealth) or "N/A"
    ))

    -- 1. Escanear jefes ya presentes en Characters o workspace
    local charsFolder = workspace:FindFirstChild("Characters") or workspace
    for _, ch in ipairs(charsFolder:GetChildren()) do
        inspectBossModel(ch)
    end

    -- 2. Detectar nuevos jefes que aparezcan
    table.insert(Conns, charsFolder.ChildAdded:Connect(function(ch)
        task.wait(0.1)
        inspectBossModel(ch)
    end))

    -- 3. Detectar proyectiles, misiles y ácido al crearse en workspace
    table.insert(Conns, workspace.DescendantAdded:Connect(registerFlyingObject))

    -- 4. Registrar cuando recibas daño o cambie BeingAttackedBy
    if hum then
        local lastHp = hum.Health
        table.insert(Conns, hum.HealthChanged:Connect(function(newHp)
            if newHp < lastHp then
                local r = char:FindFirstChild("HumanoidRootPart")
                addLog("DAMAGE_TAKEN", string.format(
                    "Recibiste %.1f de daño (HP: %.0f -> %.0f) | TuPos=%s",
                    lastHp - newHp, lastHp, newHp, r and fmtVec(r.Position) or "N/A"
                ))
            end
            lastHp = newHp
        end))
    end

    if char then
        table.insert(Conns, char.AttributeChanged:Connect(function(attr)
            if attr == "BeingAttackedBy" then
                addLog("AGGRO_ATTR", string.format("BeingAttackedBy = %s", tostring(char:GetAttribute(attr))))
            end
        end))
    end
end

local function stopRecording()
    if Recorder.Active then
        addLog("STOP", string.format(
            "Fin de captura | Duración=%.2fs | Jefes=%d | Proyectiles=%d",
            tick() - Recorder.StartTime, Recorder.BossCount, Recorder.ProjCount
        ))
        Recorder.Active = false
    end
    disconnectAll()
end

local function buildReportText()
    local out = {
        "==================================================================",
        "REPORTE FORENSE DE JEFES & PROYECTILES (TYRANT / EXPERIMENT / SPITTER)",
        string.format("Eventos: %d | Jefes Analizados: %d | Objetos Voladores: %d", #Recorder.Logs, Recorder.BossCount, Recorder.ProjCount),
        "=================================================================="
    }
    if #Recorder.Logs == 0 then
        table.insert(out, "(No hay eventos registrados todavía)")
    else
        for _, line in ipairs(Recorder.Logs) do
            table.insert(out, line)
        end
    end
    return table.concat(out, "\n")
end

local function copyTextSafe(txt)
    if setclipboard then
        setclipboard(txt)
        return true
    elseif toclipboard then
        toclipboard(txt)
        return true
    elseif Clipboard and Clipboard.set then
        Clipboard.set(txt)
        return true
    end
    return false
end

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA FLOTANTE NATIVA (PLAY / STOP / COPIAR DATOS)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local existing = GuiParent:FindFirstChild("BossProjectileScannerGui")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BossProjectileScannerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.22, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(185, 55, 65)
FloatBtn.Text = "🎯\nSCAN"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 490, 0, 225)
MainFrame.Position = UDim2.new(0.5, -245, 0.12, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 32)
TitleBar.BackgroundColor3 = Color3.fromRGB(26, 31, 44)
TitleBar.Text = "  🎯 ANALIZADOR JEFES & MISILES (TYRANT / EXPERIMENT / SPITTER)"
TitleBar.TextColor3 = Color3.fromRGB(255, 110, 110)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

UICounterLabel = Instance.new("TextLabel")
UICounterLabel.Size = UDim2.new(1, -20, 0, 22)
UICounterLabel.Position = UDim2.new(0, 10, 0, 38)
UICounterLabel.BackgroundTransparency = 1
UICounterLabel.Text = "Eventos: 0 | Jefes: 0 | Proyectiles: 0"
UICounterLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
UICounterLabel.TextSize = 10
UICounterLabel.Font = Enum.Font.Code
UICounterLabel.TextXAlignment = Enum.TextXAlignment.Left
UICounterLabel.Parent = MainFrame

local PlayBtn = Instance.new("TextButton")
PlayBtn.Size = UDim2.new(0.32, -8, 0, 38)
PlayBtn.Position = UDim2.new(0, 10, 0, 66)
PlayBtn.BackgroundColor3 = Color3.fromRGB(30, 155, 80)
PlayBtn.Text = "▶️ PLAY"
PlayBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PlayBtn.TextSize = 11
PlayBtn.Font = Enum.Font.GothamBold
PlayBtn.Parent = MainFrame
Instance.new("UICorner", PlayBtn).CornerRadius = UDim.new(0, 6)

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(0.32, -8, 0, 38)
StopBtn.Position = UDim2.new(0.32, 6, 0, 66)
StopBtn.BackgroundColor3 = Color3.fromRGB(185, 45, 55)
StopBtn.Text = "⏹️ STOP"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.TextSize = 11
StopBtn.Font = Enum.Font.GothamBold
StopBtn.Parent = MainFrame
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 6)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.36, -12, 0, 38)
CopyBtn.Position = UDim2.new(0.64, 4, 0, 66)
CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 125, 200)
CopyBtn.Text = "📋 COPIAR DATOS"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame
Instance.new("UICorner", CopyBtn).CornerRadius = UDim.new(0, 6)

local LiveBox = Instance.new("Frame")
LiveBox.Size = UDim2.new(1, -20, 0, 102)
LiveBox.Position = UDim2.new(0, 10, 0, 112)
LiveBox.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
LiveBox.Parent = MainFrame
Instance.new("UICorner", LiveBox).CornerRadius = UDim.new(0, 6)

UIStatusLabel = Instance.new("TextLabel")
UIStatusLabel.Size = UDim2.new(1, -12, 1, -8)
UIStatusLabel.Position = UDim2.new(0, 6, 0, 4)
UIStatusLabel.BackgroundTransparency = 1
UIStatusLabel.Text = "Pulsa PLAY mientras te atacan el Tyrant, Experiment o Spitter..."
UIStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 175)
UIStatusLabel.TextSize = 9
UIStatusLabel.Font = Enum.Font.Code
UIStatusLabel.TextWrapped = true
UIStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UIStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
UIStatusLabel.Parent = LiveBox

PlayBtn.MouseButton1Click:Connect(function()
    startRecording()
    PlayBtn.Text = "🔴 GRABANDO..."
end)

StopBtn.MouseButton1Click:Connect(function()
    stopRecording()
    PlayBtn.Text = "▶️ PLAY"
end)

CopyBtn.MouseButton1Click:Connect(function()
    if Recorder.Active then
        stopRecording()
        PlayBtn.Text = "▶️ PLAY"
    end
    local report = buildReportText()
    local ok = copyTextSafe(report)
    if ok then
        CopyBtn.Text = "✅ ¡COPIADO!"
        UIStatusLabel.Text = string.format("✅ %d líneas copiadas al portapapeles. Pégalas aquí.", #Recorder.Logs)
    else
        print(report)
        CopyBtn.Text = "⚠️ VER F9"
    end
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR DATOS"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
