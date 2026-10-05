-- ==============================================================================
-- AUDITOR Y SCANNER DE VEHÍCULOS (INSPECCIÓN DE REPARACIÓN Y PROMPTS) | 0% LAG
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function inspectNearestCar()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return "Error: No se encontró HumanoidRootPart." end

    local myPos = root.Position
    local report = {}
    local function log(t) table.insert(report, t) end

    log("=== REPORTE DE INSPECCIÓN DE VEHÍCULO ===")
    log("Fecha y Hora: " .. os.date("%X"))
    log(string.format("Posición Jugador: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z))

    -- 1. LOCALIZAR EL VEHÍCULO MÁS CERCANO
    local bestModel = nil
    local bestSeat = nil
    local minDist = 80

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("VehicleSeat") or (obj:IsA("Seat") and obj.Name:lower():find("drive")) then
            local dist = (obj.Position - myPos).Magnitude
            if dist < minDist then
                minDist = dist
                bestSeat = obj
                bestModel = obj:FindFirstAncestorOfClass("Model")
            end
        end
    end

    if not bestModel and not bestSeat then
        log("\n❌ NO SE ENCONTRÓ NINGÚN VEHÍCULO A MENOS DE 80 STUDS.")
        return table.concat(report, "\n")
    end

    log(string.format("\n--- [1. MODELO Y ESTRUCTURA] ---"))
    log("Nombre del Modelo: " .. (bestModel and bestModel.Name or "Sin Modelo"))
    log("Ruta Completa: " .. (bestModel and bestModel:GetFullName() or bestSeat:GetFullName()))
    log("Asiento Detectado: " .. bestSeat.Name .. " (Distancia: " .. string.format("%.1f", minDist) .. " studs)")

    -- 2. ATRIBUTOS DEL VEHÍCULO
    log("\n--- [2. ATRIBUTOS (VARIABLES OCULTAS DEL JUEGO)] ---")
    local attrCount = 0
    if bestModel then
        for k, v in pairs(bestModel:GetAttributes()) do
            attrCount = attrCount + 1
            log(string.format("  • Model_Attr [%s] = %s (%s)", k, tostring(v), typeof(v)))
        end
    end
    for k, v in pairs(bestSeat:GetAttributes()) do
        attrCount = attrCount + 1
        log(string.format("  • Seat_Attr [%s] = %s (%s)", k, tostring(v), typeof(v)))
    end
    if attrCount == 0 then log("  (Sin atributos encontrados)") end

    -- 3. VALUES (INTVALUE, NUMBERVALUE, CONFIGURATION)
    log("\n--- [3. VALORES CONFIGURADOS (VALUES / ESTADOS)] ---")
    local valCount = 0
    if bestModel then
        for _, v in ipairs(bestModel:GetDescendants()) do
            if v:IsA("ValueBase") then
                valCount = valCount + 1
                log(string.format("  • %s [%s] = %s (Parent: %s)", v.ClassName, v.Name, tostring(v.Value), v.Parent.Name))
            end
        end
    end
    if valCount == 0 then log("  (Sin objetos ValueBase encontrados)") end

    -- 4. TODOS LOS PROXIMITYPROMPTS DEL MODELO
    log("\n--- [4. PROXIMITY PROMPTS DENTRO DEL AUTO] ---")
    local promptCount = 0
    if bestModel then
        for _, p in ipairs(bestModel:GetDescendants()) do
            if p:IsA("ProximityPrompt") then
                promptCount = promptCount + 1
                local pPart = p.Parent
                local pPos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition)) or Vector3.zero
                local distToPlayer = (pPos - myPos).Magnitude

                log(string.format("  [Prompt #%d]:", promptCount))
                log(string.format("    - ActionText: '%s'", p.ActionText))
                log(string.format("    - ObjectText: '%s'", p.ObjectText))
                log(string.format("    - Name: '%s'", p.Name))
                log(string.format("    - Enabled: %s", tostring(p.Enabled)))
                log(string.format("    - HoldDuration: %.2f seg", p.HoldDuration))
                log(string.format("    - MaxActivationDistance: %.1f studs", p.MaxActivationDistance))
                log(string.format("    - RequiresLineOfSight: %s", tostring(p.RequiresLineOfSight)))
                log(string.format("    - KeyboardKeyCode: %s", p.KeyboardKeyCode.Name))
                log(string.format("    - Parent Part: %s (Ruta: %s)", pPart.Name, pPart:GetFullName()))
                log(string.format("    - Distancia al jugador: %.1f studs", distToPlayer))
            end
        end
    end
    if promptCount == 0 then log("  ❌ No hay ProximityPrompts hijos directos de este modelo.") end

    -- 5. ESCANEO RADIAL EXTERNO (POR SI EL PROMPT ESTÁ EN OTRA CARPETA DE WORKSPACE)
    log("\n--- [5. PROXIMITY PROMPTS CERCANOS EN TODO EL WORKSPACE (< 35 STUDS)] ---")
    local externalCount = 0
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("ProximityPrompt") then
            -- Excluir los ya listados si pertenecen al modelo
            local isInsideModel = bestModel and p:IsDescendantOf(bestModel)
            if not isInsideModel then
                local pPart = p.Parent
                local pPos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition))
                if pPos then
                    local d = (pPos - myPos).Magnitude
                    if d <= 35 then
                        externalCount = externalCount + 1
                        log(string.format("  [Prompt Externo #%d]:", externalCount))
                        log(string.format("    - ActionText: '%s' | ObjectText: '%s'", p.ActionText, p.ObjectText))
                        log(string.format("    - Enabled: %s | HoldDuration: %.2f", tostring(p.Enabled), p.HoldDuration))
                        log(string.format("    - Parent: %s (Ruta: %s)", pPart.Name, pPart:GetFullName()))
                        log(string.format("    - Distancia: %.1f studs", d))
                    end
                end
            end
        end
    end
    if externalCount == 0 then log("  (Sin prompts externos a menos de 35 studs)") end

    -- 6. REMOTEEVENTS / REMOTEFUNCTIONS VINCULADOS
    log("\n--- [6. REMOTES / COMUNICACIÓN CON SERVIDOR] ---")
    local remotes = 0
    if bestModel then
        for _, r in ipairs(bestModel:GetDescendants()) do
            if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
                remotes = remotes + 1
                log(string.format("  • %s [%s] en %s", r.ClassName, r.Name, r.Parent:GetFullName()))
            end
        end
    end
    if remotes == 0 then log("  (Sin Remotes locales dentro del auto; el juego usa ProximityPromptService o Remotes globales)") end

    log("\n=== FIN DE LA INSPECCIÓN ===")
    return table.concat(report, "\n")
end

-- ================= INTERFAZ VISUAL FLOTANTE =================
local existing = lp.PlayerGui:FindFirstChild("CarDataScannerGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarDataScannerGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 520, 0, 480)
Frame.Position = UDim2.new(0.5, -260, 0.5, -240)
Frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 36)
Title.Position = UDim2.new(0, 14, 0, 4)
Title.Text = "🔍 ESCÁNER DE DATOS Y REPARACIÓN DEL AUTO"
Title.TextColor3 = Color3.fromRGB(0, 220, 140)
Title.TextSize = 13
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = Frame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0, 8)
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

-- BOTÓN ESCANEAR
local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, 0, 0, 36)
ScanBtn.Position = UDim2.new(0, 14, 0, 44)
ScanBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 90)
ScanBtn.Text = "1. Escanear Auto Frente a Mí"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.TextSize = 12
ScanBtn.Parent = Frame
local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 6)
sbCorner.Parent = ScanBtn

-- BOTÓN COPIAR
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, 0, 0, 36)
CopyBtn.Position = UDim2.new(0.50, 0, 0, 44)
CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 110, 190)
CopyBtn.Text = "📋 Copiar Reporte"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.TextSize = 12
CopyBtn.Parent = Frame
local cbCorner = Instance.new("UICorner")
cbCorner.CornerRadius = UDim.new(0, 6)
cbCorner.Parent = CopyBtn

-- ÁREA DE TEXTO / VISTA PREVIA
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -28, 1, -96)
Scroll.Position = UDim2.new(0, 14, 0, 86)
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
TextBox.Text = "Párate justo frente al auto roto (donde sale el botón de 'Reparar') y presiona '1. Escanear Auto Frente a Mí'."
TextBox.TextColor3 = Color3.fromRGB(215, 215, 215)
TextBox.TextSize = 11
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

local LastReport = ""

ScanBtn.MouseButton1Click:Connect(function()
    LastReport = inspectNearestCar()
    TextBox.Text = LastReport
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #LastReport:split("\n") * 16)
    ScanBtn.Text = "✅ ¡Escaneado Listo!"
    task.wait(1.2)
    ScanBtn.Text = "1. Escanear Auto Frente a Mí"
end)

CopyBtn.MouseButton1Click:Connect(function()
    if LastReport == "" then
        TextBox.Text = "⚠️ Primero debes presionar '1. Escanear Auto Frente a Mí'."
        return
    end
    if setclipboard then setclipboard(LastReport) elseif toclipboard then toclipboard(LastReport) end
    CopyBtn.Text = "✅ ¡Copiado al Portapapeles!"
    task.wait(1.5)
    CopyBtn.Text = "📋 Copiar Reporte"
end)
