-- ==============================================================================
-- AUDITOR DE FÍSICAS Y ESTADO POST-MORTEM (VUELO VS SIN VUELO)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local DataSinVuelo = nil
local DataConVuelo = nil

local function captureCharacterData(stateLabel)
    local char = lp.Character
    if not char then return nil, "No se encontró Character" end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart

    local report = {}
    local function log(txt) table.insert(report, txt) end

    log(string.format("=== REPORTE DE ESTADO: [%s] ===", string.upper(stateLabel)))
    log("Fecha y Hora: " .. os.date("%X"))
    log("Character Name: " .. char.Name)
    log("Character Parent: " .. tostring(char.Parent and char.Parent:GetFullName() or "Nil"))

    -- 1. HUMANOID Y SALUD
    log("\n--- [1. ESTADO DEL HUMANOID] ---")
    if hum then
        log(string.format("Vida: %.1f / %.1f", hum.Health, hum.MaxHealth))
        log("HumanoidState: " .. hum:GetState().Name)
        log("PlatformStand: " .. tostring(hum.PlatformStand))
        log("Sit: " .. tostring(hum.Sit))
        log("FloorMaterial: " .. hum.FloorMaterial.Name)
        log("RequiresNeck: " .. tostring(hum.RequiresNeck))
        log("BreakJointsOnDeath: " .. tostring(hum.BreakJointsOnDeath))
        log("EvaluateStateMachine: " .. tostring(hum.EvaluateStateMachine))
    else
        log("Humanoid: NO EXISTE O FUE DESTRUIDO")
    end

    -- 2. PARTE RAÍZ Y FÍSICAS (CLAVE PARA VUELO)
    log("\n--- [2. ANÁLISIS DEL HUMANODROOTPART / RAÍZ] ---")
    if root then
        log("RootPart Detectado: " .. root.Name)
        log("RootPart Exists in Char: " .. tostring(root.Parent == char))
        log("Anchored: " .. tostring(root.Anchored))
        log("CanCollide: " .. tostring(root.CanCollide))
        log("Mass individual: " .. string.format("%.2f", root.Mass))
        log("AssemblyMass (Masa Total del Ensamble): " .. string.format("%.2f", root.AssemblyMass))
        log("AssemblyRootPart (Pieza que manda en físicas): " .. tostring(root.AssemblyRootPart and root.AssemblyRootPart.Name or "None"))
        log("AssemblyLinearVelocity: " .. tostring(root.AssemblyLinearVelocity))
        log("AssemblyAngularVelocity: " .. tostring(root.AssemblyAngularVelocity))
        log("Posición: " .. tostring(root.Position))
    else
        log("RootPart: NO EXISTE")
    end

    -- 3. MOTORES, WELDS Y ARTICULACIONES (RAGDOLL / MUERTE)
    log("\n--- [3. ARTICULACIONES Y WELDS] ---")
    local totalMotors = 0
    local brokenMotors = 0
    local motorList = {}

    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("Motor6D") then
            totalMotors = totalMotors + 1
            local status = (desc.Part0 and desc.Part1 and desc.Enabled) and "Activo" or "ROTO/DESHABILITADO"
            if status ~= "Activo" then brokenMotors = brokenMotors + 1 end
            table.insert(motorList, string.format("  • Motor6D [%s]: %s (Part0: %s | Part1: %s)", desc.Name, status, tostring(desc.Part0 and desc.Part0.Name or "None"), tostring(desc.Part1 and desc.Part1.Name or "None")))
        end
    end
    log(string.format("Motores Totales: %d | Motores Rotos: %d", totalMotors, brokenMotors))
    for _, line in ipairs(motorList) do log(line) end

    -- 4. CONSTRAINTS (FÍSICA DE CUERPO SUELTO / RAGDOLL)
    log("\n--- [4. CONSTRAINTS Y RAGDOLL] ---")
    local constraints = {}
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("Constraint") or desc:IsA("Attachment") then
            if desc:IsA("Constraint") then
                table.insert(constraints, string.format("  • %s [%s] (Enabled: %s)", desc.ClassName, desc.Name, tostring(desc.Enabled)))
            end
        end
    end
    log("Total Constraints: " .. #constraints)
    for _, line in ipairs(constraints) do log(line) end

    -- 5. FUERZAS Y BODYMOVERS APLICADOS
    log("\n--- [5. OBJETOS DE FÍSICA / BODYMOVERS] ---")
    local movers = {}
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BodyMover") or desc:IsA("AlignPosition") or desc:IsA("AlignOrientation") or desc:IsA("LinearVelocity") or desc:IsA("VectorForce") then
            table.insert(movers, string.format("  • %s [%s] en %s", desc.ClassName, desc.Name, desc.Parent and desc.Parent.Name or "Nil"))
        end
    end
    if #movers > 0 then
        for _, m in ipairs(movers) do log(m) end
    else
        log("No hay BodyMovers ni Fuerzas activas en el personaje.")
    end

    -- 6. ATRIBUTOS DEL PERSONAJE Y HUMANOID
    log("\n--- [6. ATRIBUTOS OCULTOS (GAME SCRIPTS)] ---")
    local attrCount = 0
    for k, v in pairs(char:GetAttributes()) do
        attrCount = attrCount + 1
        log(string.format("  • Char_Attr [%s] = %s", k, tostring(v)))
    end
    if hum then
        for k, v in pairs(hum:GetAttributes()) do
            attrCount = attrCount + 1
            log(string.format("  • Hum_Attr [%s] = %s", k, tostring(v)))
        end
    end
    if attrCount == 0 then log("Sin atributos detectados.") end

    log("=== FIN DEL REPORTE ===")
    return table.concat(report, "\n")
end

-- ================= INTERFAZ MINIMALISTA (PLAYERGUI) =================
local existing = lp.PlayerGui:FindFirstChild("DeadFlyAuditorGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DeadFlyAuditorGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 560, 0, 520)
Frame.Position = UDim2.new(0.5, -280, 0.5, -260)
Frame.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 34)
Title.Position = UDim2.new(0, 14, 0, 4)
Title.Text = "🔬 AUDITOR DE VUELO POST-MORTEM (ANÁLISIS DE DATOS)"
Title.TextColor3 = Color3.fromRGB(0, 230, 150)
Title.TextSize = 13
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = Frame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -34, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.TextSize = 13
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
CloseBtn.Parent = Frame
local cCorner = Instance.new("UICorner")
cCorner.CornerRadius = UDim.new(0, 6)
cCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- CONTENEDOR BOTONES DE CAPTURA
local BtnCapNoFly = Instance.new("TextButton")
BtnCapNoFly.Size = UDim2.new(0.47, 0, 0, 34)
BtnCapNoFly.Position = UDim2.new(0, 14, 0, 42)
BtnCapNoFly.BackgroundColor3 = Color3.fromRGB(170, 40, 40)
BtnCapNoFly.Text = "1. Capturar: SIN Vuelo"
BtnCapNoFly.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnCapNoFly.Font = Enum.Font.GothamBold
BtnCapNoFly.TextSize = 12
BtnCapNoFly.Parent = Frame
local b1Corner = Instance.new("UICorner")
b1Corner.CornerRadius = UDim.new(0, 6)
b1Corner.Parent = BtnCapNoFly

local BtnCapFly = Instance.new("TextButton")
BtnCapFly.Size = UDim2.new(0.47, 0, 0, 34)
BtnCapFly.Position = UDim2.new(0.505, 0, 0, 42)
BtnCapFly.BackgroundColor3 = Color3.fromRGB(0, 140, 90)
BtnCapFly.Text = "2. Capturar: CON Vuelo"
BtnCapFly.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnCapFly.Font = Enum.Font.GothamBold
BtnCapFly.TextSize = 12
BtnCapFly.Parent = Frame
local b2Corner = Instance.new("UICorner")
b2Corner.CornerRadius = UDim.new(0, 6)
b2Corner.Parent = BtnCapFly

-- CONTENEDOR BOTONES DE COPIA INDEPENDIENTES
local BtnCopyNoFly = Instance.new("TextButton")
BtnCopyNoFly.Size = UDim2.new(0.47, 0, 0, 30)
BtnCopyNoFly.Position = UDim2.new(0, 14, 0, 82)
BtnCopyNoFly.BackgroundColor3 = Color3.fromRGB(80, 25, 25)
BtnCopyNoFly.Text = "📋 Copiar Solo 'SIN Vuelo'"
BtnCopyNoFly.TextColor3 = Color3.fromRGB(220, 220, 220)
BtnCopyNoFly.Font = Enum.Font.Gotham
BtnCopyNoFly.TextSize = 11
BtnCopyNoFly.Parent = Frame
local bc1Corner = Instance.new("UICorner")
bc1Corner.CornerRadius = UDim.new(0, 6)
bc1Corner.Parent = BtnCopyNoFly

local BtnCopyFly = Instance.new("TextButton")
BtnCopyFly.Size = UDim2.new(0.47, 0, 0, 30)
BtnCopyFly.Position = UDim2.new(0.505, 0, 0, 82)
BtnCopyFly.BackgroundColor3 = Color3.fromRGB(20, 75, 50)
BtnCopyFly.Text = "📋 Copiar Solo 'CON Vuelo'"
BtnCopyFly.TextColor3 = Color3.fromRGB(220, 220, 220)
BtnCopyFly.Font = Enum.Font.Gotham
BtnCopyFly.TextSize = 11
BtnCopyFly.Parent = Frame
local bc2Corner = Instance.new("UICorner")
bc2Corner.CornerRadius = UDim.new(0, 6)
bc2Corner.Parent = BtnCopyFly

-- ÁREA DE VISTA PREVIA
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -28, 0, 310)
Scroll.Position = UDim2.new(0, 14, 0, 120)
Scroll.BackgroundColor3 = Color3.fromRGB(11, 12, 16)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.Parent = Frame
local sCorner = Instance.new("UICorner")
sCorner.CornerRadius = UDim.new(0, 6)
sCorner.Parent = Scroll

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -12, 1, 0)
TextBox.Position = UDim2.new(0, 6, 0, 6)
TextBox.Text = "Pasos para analizar:\n1. Quédate derribado/muerto cuando NO PUEDAS VOLAR y dale a '1. Capturar: SIN Vuelo'.\n2. En otra partida o momento en que quedes muerto y SÍ PUEDAS VOLAR, dale a '2. Capturar: CON Vuelo'.\n3. Usa los botones correspondientes para copiar cada registro de forma independiente y pegarlo."
TextBox.TextColor3 = Color3.fromRGB(210, 210, 210)
TextBox.TextSize = 11
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

-- BOTÓN COMPARATIVO GENERAL
local BtnCompare = Instance.new("TextButton")
BtnCompare.Size = UDim2.new(1, -28, 0, 36)
BtnCompare.Position = UDim2.new(0, 14, 1, -44)
BtnCompare.BackgroundColor3 = Color3.fromRGB(0, 110, 180)
BtnCompare.Text = "GENERAR Y COPIAR COMPARATIVA COMPLETA"
BtnCompare.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnCompare.Font = Enum.Font.GothamBold
BtnCompare.TextSize = 12
BtnCompare.Parent = Frame
local bCompCorner = Instance.new("UICorner")
bCompCorner.CornerRadius = UDim.new(0, 6)
bCompCorner.Parent = BtnCompare

-- ACCIONES
BtnCapNoFly.MouseButton1Click:Connect(function()
    DataSinVuelo = captureCharacterData("Muerto SIN Vuelo")
    TextBox.Text = DataSinVuelo
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #DataSinVuelo:split("\n") * 16)
    BtnCapNoFly.Text = "✅ SIN Vuelo (Guardado)"
end)

BtnCapFly.MouseButton1Click:Connect(function()
    DataConVuelo = captureCharacterData("Muerto CON Vuelo")
    TextBox.Text = DataConVuelo
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #DataConVuelo:split("\n") * 16)
    BtnCapFly.Text = "✅ CON Vuelo (Guardado)"
end)

BtnCopyNoFly.MouseButton1Click:Connect(function()
    if not DataSinVuelo then
        TextBox.Text = "⚠️ Primero debes capturar el estado 'SIN Vuelo'."
        return
    end
    if setclipboard then setclipboard(DataSinVuelo) elseif toclipboard then toclipboard(DataSinVuelo) end
    BtnCopyNoFly.Text = "✅ ¡Copiado SIN Vuelo!"
    task.wait(1.5)
    BtnCopyNoFly.Text = "📋 Copiar Solo 'SIN Vuelo'"
end)

BtnCopyFly.MouseButton1Click:Connect(function()
    if not DataConVuelo then
        TextBox.Text = "⚠️ Primero debes capturar el estado 'CON Vuelo'."
        return
    end
    if setclipboard then setclipboard(DataConVuelo) elseif toclipboard then toclipboard(DataConVuelo) end
    BtnCopyFly.Text = "✅ ¡Copiado CON Vuelo!"
    task.wait(1.5)
    BtnCopyFly.Text = "📋 Copiar Solo 'CON Vuelo'"
end)

BtnCompare.MouseButton1Click:Connect(function()
    if not DataSinVuelo or not DataConVuelo then
        TextBox.Text = "⚠️ Necesitas capturar AMBOS estados para comparar."
        return
    end

    local compText = string.format([[
================ COMPARATIVA DIRECTA (SIN VUELO VS CON VUELO) ================

[REGISTRO 1: CUANDO NO VUELA]:
%s

--------------------------------------------------------------------------------

[REGISTRO 2: CUANDO SÍ VUELA]:
%s
================================================================================
]], DataSinVuelo, DataConVuelo)

    TextBox.Text = compText
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #compText:split("\n") * 16)
    if setclipboard then setclipboard(compText) elseif toclipboard then toclipboard(compText) end
    BtnCompare.Text = "✅ ¡COMPARATIVA COPIADA AL PORTAPAPELES!"
    task.wait(1.5)
    BtnCompare.Text = "GENERAR Y COPIAR COMPARATIVA COMPLETA"
end)
