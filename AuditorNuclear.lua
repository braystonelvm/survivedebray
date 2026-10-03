-- ==============================================================================
-- AUDITOR MAESTRO: PUERTA DEL REACTOR & VULNERABILIDAD POST-MORTEM (0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function getRoot()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

-- ================= 1. RECOLECTOR DE DATOS DE LA PUERTA Y REACTOR =================
local function scanNuclearSystem()
    local report = {}
    local function log(txt) table.insert(report, txt) end

    log("================ REPORTE DEL SISTEMA NUCLEAR ================")
    log("Hora del escaneo: " .. os.date("%X"))

    -- Buscar modelo del Reactor
    local reactorModel = nil
    local map = workspace:FindFirstChild("Map")
    local tiles = map and map:FindFirstChild("Tiles")
    if tiles and tiles:FindFirstChild("Nuclear Reactor") then
        reactorModel = tiles["Nuclear Reactor"]
    else
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name == "Nuclear Reactor" then
                reactorModel = obj
                break
            end
        end
    end

    if reactorModel then
        log("\n--- [1. MODELO PRINCIPAL: NUCLEAR REACTOR] ---")
        log("Ubicación: " .. reactorModel:GetFullName())
        
        -- Atributos del Reactor
        local attrs = reactorModel:GetAttributes()
        local attrCount = 0
        for k, v in pairs(attrs) do
            attrCount = attrCount + 1
            log(string.format("  • Atributo [%s] = %s (%s)", k, tostring(v), type(v)))
        end
        if attrCount == 0 then log("  • Sin Atributos directos en el modelo.") end

        -- Valores (IntValue, StringValue, BoolValue)
        local valCount = 0
        for _, child in ipairs(reactorModel:GetChildren()) do
            if child:IsA("ValueBase") then
                valCount = valCount + 1
                log(string.format("  • Valor [%s] (%s) = %s", child.Name, child.ClassName, tostring(child.Value)))
            end
        end
        if valCount == 0 then log("  • Sin objetos ValueBase en la raíz.") end
    else
        log("⚠️ No se encontró el modelo 'Nuclear Reactor' en workspace.")
    end

    -- Buscar la parte Entrada (Entrance)
    local entrancePart = nil
    if reactorModel and reactorModel:FindFirstChild("Entrance") then
        entrancePart = reactorModel.Entrance
    else
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "Entrance" and obj.Parent and obj.Parent.Name == "Nuclear Reactor" then
                entrancePart = obj
                break
            end
        end
    end

    if entrancePart then
        log("\n--- [2. ENTRADA Y CONTADOR (ENTRANCE)] ---")
        log("Posición exacta: " .. tostring(entrancePart.Position))
        log("CanCollide: " .. tostring(entrancePart.CanCollide) .. " | CanTouch: " .. tostring(entrancePart.CanTouch))

        -- Atributos de Entrance
        for k, v in pairs(entrancePart:GetAttributes()) do
            log(string.format("  • Atributo Entrance [%s] = %s", k, tostring(v)))
        end

        -- SurfaceGuis y TextLabels (El Timer)
        local guisFound = 0
        for _, desc in ipairs(entrancePart:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                guisFound = guisFound + 1
                log(string.format("  • Texto detectado [%s]: '%s' | Visible: %s | Color: %s", 
                    desc.Name, desc.Text, tostring(desc.Visible), tostring(desc.TextColor3)))
            elseif desc:IsA("SurfaceGui") then
                log(string.format("  • SurfaceGui [%s] | Enabled: %s | Adornee: %s", 
                    desc.Name, tostring(desc.Enabled), tostring(desc.Adornee or entrancePart.Name)))
            end
        end
        if guisFound == 0 then log("  • No se detectaron TextLabels dentro de Entrance.") end

        -- ProximityPrompts en Entrance
        log("\n--- [3. PROXIMITY PROMPTS EN LA ENTRADA] ---")
        local promptFound = 0
        for _, desc in ipairs(entrancePart:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                promptFound = promptFound + 1
                log(string.format("  • Prompt [%s]: Action='%s' | Object='%s' | Enabled=%s | HoldTime=%.1f | Dist=%d",
                    desc.Name, desc.ActionText, desc.ObjectText, tostring(desc.Enabled), desc.HoldDuration, desc.MaxActivationDistance))
            end
        end
        if promptFound == 0 then log("  • Sin ProximityPrompts en la pieza Entrance.") end
    else
        log("⚠️ No se encontró la pieza 'Entrance' en workspace.")
    end

    -- Zombies vivos en la zona
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local glowingCount = 0
    local totalMonsters = 0
    local center = Vector3.new(-1.4, 2.7, 1120.5)

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and not Players:GetPlayerFromCharacter(ent) then
            local hum = ent:FindFirstChildOfClass("Humanoid")
            local root = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso")
            if root and (not hum or hum.Health > 0) then
                local dist = (root.Position - center).Magnitude
                if dist <= 400 then
                    totalMonsters = totalMonsters + 1
                    local isGlow = ent:FindFirstChildOfClass("Highlight") ~= nil or ent:GetAttribute("Reactor") == true
                    if isGlow then glowingCount = glowingCount + 1 end
                end
            end
        end
    end

    log("\n--- [4. RECUENTO DE ENTIDADES (RADIO 400)] ---")
    log(string.format("Zombies totales vivos en el reactor: %d (Con resplandor: %d)", totalMonsters, glowingCount))
    log("================ FIN DEL REPORTE NUCLEAR ================")

    return table.concat(report, "\n")
end

-- ================= 2. RECOLECTOR DE VULNERABILIDADES DE ARMAS / MUERTE =================
local CachedRemotes = {}

local function scanWeaponsAndRemotes()
    local report = {}
    local function log(txt) table.insert(report, txt) end

    log("================ REPORTE DE ARMAS Y DAÑO POST-MORTEM ================")
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local bp = lp:FindFirstChild("Backpack")

    log("Estado del Jugador:")
    log(string.format("  • Vida Actual: %.1f / %.1f", hum and hum.Health or 0, hum and hum.MaxHealth or 100))
    log(string.format("  • Estado Humanoid: %s", hum and hum:GetState().Name or "Desconocido"))
    log(string.format("  • ¿Está Muerto?: %s", tostring(not hum or hum.Health <= 0)))

    table.clear(CachedRemotes)

    local function inspectFolder(folder, locationName)
        if not folder then return end
        for _, item in ipairs(folder:GetChildren()) do
            if item:IsA("Tool") then
                log(string.format("\nHerramienta en %s: [%s]", locationName, item.Name))
                for _, sub in ipairs(item:GetDescendants()) do
                    if sub:IsA("RemoteEvent") or sub:IsA("RemoteFunction") then
                        log(string.format("  -> Remote [%s] (%s) en: %s", sub.Name, sub.ClassName, sub.Parent.Name))
                        table.insert(CachedRemotes, {
                            Remote = sub,
                            Tool = item,
                            Name = sub.Name
                        })
                    end
                end
            end
        end
    end

    inspectFolder(char, "Mano / Personaje")
    inspectFolder(bp, "Mochila (Backpack)")

    log(string.format("\nTotal de Remotes de ataque memorizados en caché: %d", #CachedRemotes))
    log("Diagnóstico:")
    if #CachedRemotes > 0 then
        log("✅ Los remotes han sido cacheados en memoria RAM. Aunque mueras y se borre tu mochila,")
        log("   el script retiene los punteros a los Remotes para intentar disparar daño desde la muerte.")
    else
        log("⚠️ No se hallaron armas con RemoteEvents en la mochila o personaje.")
    end
    log("================ FIN REPORTE DE ARMAS ================")

    return table.concat(report, "\n")
end

-- ================= INTERFAZ VISUAL EN PANTALLA =================
local existing = lp.PlayerGui:FindFirstChild("ReactorAuditorMasterGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReactorAuditorMasterGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 560, 0, 480)
Frame.Position = UDim2.new(0.5, -280, 0.5, -240)
Frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 0, 36)
Title.Position = UDim2.new(0, 16, 0, 4)
Title.Text = "🔬 AUDITOR NUCLEAR & ANÁLISIS DE DAÑO"
Title.TextColor3 = Color3.fromRGB(0, 255, 170)
Title.TextSize = 13
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = Frame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.TextSize = 14
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
CloseBtn.Parent = Frame
local cCorner = Instance.new("UICorner")
cCorner.CornerRadius = UDim.new(0, 6)
cCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- BOTÓN 1: ESCANEAR REACTOR
local BtnScanNuclear = Instance.new("TextButton")
BtnScanNuclear.Size = UDim2.new(0.46, 0, 0, 36)
BtnScanNuclear.Position = UDim2.new(0, 16, 0, 44)
BtnScanNuclear.BackgroundColor3 = Color3.fromRGB(0, 130, 90)
BtnScanNuclear.Text = "1. Escanear Puerta y Reactor"
BtnScanNuclear.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnScanNuclear.Font = Enum.Font.GothamBold
BtnScanNuclear.TextSize = 12
BtnScanNuclear.Parent = Frame
local b1Corner = Instance.new("UICorner")
b1Corner.CornerRadius = UDim.new(0, 6)
b1Corner.Parent = BtnScanNuclear

-- BOTÓN 2: ESCANEAR ARMAS / POST-MORTEM
local BtnScanWeapons = Instance.new("TextButton")
BtnScanWeapons.Size = UDim2.new(0.46, 0, 0, 36)
BtnScanWeapons.Position = UDim2.new(0.51, 0, 0, 44)
BtnScanWeapons.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
BtnScanWeapons.Text = "2. Escanear Armas / Remotes"
BtnScanWeapons.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnScanWeapons.Font = Enum.Font.GothamBold
BtnScanWeapons.TextSize = 12
BtnScanWeapons.Parent = Frame
local b2Corner = Instance.new("UICorner")
b2Corner.CornerRadius = UDim.new(0, 6)
b2Corner.Parent = BtnScanWeapons

-- ÁREA DE TEXTO
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -32, 0, 330)
Scroll.Position = UDim2.new(0, 16, 0, 88)
Scroll.BackgroundColor3 = Color3.fromRGB(11, 12, 15)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.Parent = Frame
local sCorner = Instance.new("UICorner")
sCorner.CornerRadius = UDim.new(0, 6)
sCorner.Parent = Scroll

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -12, 1, 0)
TextBox.Position = UDim2.new(0, 6, 0, 6)
TextBox.Text = "Presiona '1. Escanear Puerta y Reactor' ahora que limpiaste la sala para volcar todos sus valores internos.\n\nPresiona '2. Escanear Armas / Remotes' para auditar tus armas y evaluar el disparo post-mortem."
TextBox.TextColor3 = Color3.fromRGB(220, 220, 220)
TextBox.TextSize = 11
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

-- BOTÓN COPIAR AL PORTAPAPELES
local BtnCopy = Instance.new("TextButton")
BtnCopy.Size = UDim2.new(1, -32, 0, 36)
BtnCopy.Position = UDim2.new(0, 16, 1, -44)
BtnCopy.BackgroundColor3 = Color3.fromRGB(0, 110, 180)
BtnCopy.Text = "COPIAR REPORTE COMPLETO AL PORTAPAPELES"
BtnCopy.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnCopy.Font = Enum.Font.GothamBold
BtnCopy.TextSize = 12
BtnCopy.Parent = Frame
local bcCorner = Instance.new("UICorner")
bcCorner.CornerRadius = UDim.new(0, 6)
bcCorner.Parent = BtnCopy

-- ACCIONES DE BOTONES
BtnScanNuclear.MouseButton1Click:Connect(function()
    local text = scanNuclearSystem()
    TextBox.Text = text
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #text:split("\n") * 16)
end)

BtnScanWeapons.MouseButton1Click:Connect(function()
    local text = scanWeaponsAndRemotes()
    TextBox.Text = text
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #text:split("\n") * 16)
end)

BtnCopy.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(TextBox.Text) elseif toclipboard then toclipboard(TextBox.Text) end
    BtnCopy.Text = "✅ ¡REPORTE COPIADO!"
    task.wait(1.5)
    BtnCopy.Text = "COPIAR REPORTE COMPLETO AL PORTAPAPELES"
end)
