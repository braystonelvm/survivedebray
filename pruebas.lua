-- ==============================================================================
-- CALIBRADOR DE OLEADAS NOCTURNAS V2 (ENFOQUE EXCLUSIVO EN DIRECCIÓN Y CAMBIOS)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local NightForensic = {
    StartTime = tick(),
    TotalConfirmations = 0,
    Mismatches = 0,
    SectorShiftCount = 0,
    LogEntries = {},
    RecentSpawns = {}
}

local CurrentDeduction = {
    ByAttribute = "N/A",
    BySpawnRate = "N/A",
    ScriptVerdict = "DESCONOCIDO",
    Confidence = 0
}

local LastUserConfirmedSector = "NINGUNO"
local LastRecordedScriptSector = "DESCONOCIDO"

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        game:GetService("UserInputService").MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. DETECCIÓN Y CLASIFICACIÓN CON EJES CALIBRADOS
-- ==============================================================================

-- Calibración validada: X(-)=ESTE, X(+)=OESTE, Z(-)=SUR, Z(+)=NORTE
local function parseSectorFromGameCoords(vec)
    if not vec then return "DESCONOCIDO" end

    if math.abs(vec.Z) > math.abs(vec.X) then
        return (vec.Z > 0) and "NORTE" or "SUR"
    else
        return (vec.X > 0) and "OESTE" or "ESTE"
    end
end

-- Posición real de la entidad respecto a la base
local function getSectorFromEntityPos(pos)
    local rel = pos - BaseCenter
    if math.abs(rel.Z) > math.abs(rel.X) then
        return (rel.Z > 0) and "SUR" or "NORTE"
    else
        return (rel.X > 0) and "ESTE" or "OESTE"
    end
end

local function parseVectorString(val)
    if typeof(val) == "Vector3" then return val end
    if type(val) == "string" then
        local x, y, z = val:match("([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)")
        if x and y and z then
            return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
        end
    end
    return nil
end

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
    if not hum or hum.Health <= 0 then return false end
    local root = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
    return root ~= nil, root
end

-- ==============================================================================
-- 2. ESCUCHA DE SPAWNS EN VIVO
-- ==============================================================================

local charFolder = workspace:FindFirstChild("Characters") or workspace

charFolder.ChildAdded:Connect(function(child)
    task.wait(0.1)
    local valid, root = isValidZombie(child)
    if valid and root then
        local pos = root.Position
        local sector = getSectorFromEntityPos(pos)
        table.insert(NightForensic.RecentSpawns, {
            Time = tick(),
            Sector = sector
        })
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        local now = tick()
        for i = #NightForensic.RecentSpawns, 1, -1 do
            if (now - NightForensic.RecentSpawns[i].Time) > 8 then
                table.remove(NightForensic.RecentSpawns, i)
            end
        end
    end
end)

-- ==============================================================================
-- 3. MOTOR DE DEDUCCIÓN EXCLUSIVO DE DIRECCIÓN
-- ==============================================================================

local function analyzeWaveDirection()
    -- 1. Deducción por Atributo de Servidor (IncomingPosition calibrado)
    local incoming = workspace:GetAttribute("IncomingPosition")
    local incomingVec = parseVectorString(incoming)
    local attrSector = incomingVec and parseSectorFromGameCoords(incomingVec) or "N/A"
    CurrentDeduction.ByAttribute = attrSector

    -- 2. Deducción por Nacimientos Recientes (Últimos 8 segundos)
    local spawnCounts = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
    for _, sp in ipairs(NightForensic.RecentSpawns) do
        spawnCounts[sp.Sector] = spawnCounts[sp.Sector] + 1
    end

    local spawnSector = "INCIERTO"
    local maxSpawns = 0
    for s, c in pairs(spawnCounts) do
        if c > maxSpawns then
            maxSpawns = c
            spawnSector = s
        end
    end
    CurrentDeduction.BySpawnRate = (maxSpawns >= 2) and spawnSector or "INCIERTO"

    -- Veredicto del Script: Atributo calibrado como fuente principal
    if CurrentDeduction.ByAttribute ~= "N/A" and CurrentDeduction.ByAttribute ~= "DESCONOCIDO" then
        CurrentDeduction.ScriptVerdict = CurrentDeduction.ByAttribute
        CurrentDeduction.Confidence = (CurrentDeduction.BySpawnRate == CurrentDeduction.ByAttribute) and 98 or 85
    elseif CurrentDeduction.BySpawnRate ~= "INCIERTO" then
        CurrentDeduction.ScriptVerdict = CurrentDeduction.BySpawnRate
        CurrentDeduction.Confidence = 70
    else
        CurrentDeduction.ScriptVerdict = "DESCONOCIDO"
        CurrentDeduction.Confidence = 0
    end
end

-- ==============================================================================
-- 4. REGISTRO FORENSE AL CONFIRMAR O CAMBIAR
-- ==============================================================================

local function logSectorConfirmation(userSector, actionNote)
    NightForensic.TotalConfirmations = NightForensic.TotalConfirmations + 1
    local nowTime = os.date("%X")
    local elapsed = math.floor(tick() - NightForensic.StartTime)

    analyzeWaveDirection()
    local isMatch = (userSector == CurrentDeduction.ScriptVerdict)
    if not isMatch then
        NightForensic.Mismatches = NightForensic.Mismatches + 1
    end

    LastUserConfirmedSector = userSector

    local entry = {
        Timestamp = nowTime,
        ElapsedSec = elapsed,
        Action = actionNote or "Confirmación Manual",
        UserConfirmed = userSector,
        ScriptGuess = CurrentDeduction.ScriptVerdict,
        Confidence = CurrentDeduction.Confidence,
        IsMatch = isMatch,
        GuessByAttr = CurrentDeduction.ByAttribute,
        GuessBySpawns = CurrentDeduction.BySpawnRate,
        IncomingPosAttr = tostring(workspace:GetAttribute("IncomingPosition") or "N/A"),
        ClockTime = string.format("%.2f", Lighting.ClockTime)
    }

    table.insert(NightForensic.LogEntries, 1, entry)
    if #NightForensic.LogEntries > 60 then
        table.remove(NightForensic.LogEntries)
    end

    print(string.format("📌 [RADAR]: Confirmado=%s | Script=%s | Coincide=%s", userSector, entry.ScriptGuess, tostring(isMatch)))
end

-- ==============================================================================
-- 5. GENERADOR DE REPORTE COMPLETO
-- ==============================================================================

local function compileFullReport()
    analyzeWaveDirection()
    local lines = {
        "==================================================================",
        "      REPORTE DE DIRECCIÓN Y CAMBIOS DE OLEADAS NOCTURNAS        ",
        "==================================================================",
        string.format("Fecha de Registro: %s", os.date("%Y-%m-%d %X")),
        string.format("Confirmaciones: %d | Errores: %d | Cambios Registrados: %d", NightForensic.TotalConfirmations, NightForensic.Mismatches, NightForensic.SectorShiftCount),
        string.format("Precisión del Script Calibrado: %.1f%%", NightForensic.TotalConfirmations > 0 and ((NightForensic.TotalConfirmations - NightForensic.Mismatches) / NightForensic.TotalConfirmations * 100) or 0),
        "\n[ESTADO ACTUAL EN VIVO]:",
        string.format(" • Veredicto Actual: %s (Confianza: %d%%)", CurrentDeduction.ScriptVerdict, CurrentDeduction.Confidence),
        string.format(" • Por IncomingPosition (Calibrado): %s", CurrentDeduction.ByAttribute),
        string.format(" • Por Spawns Recientes: %s", CurrentDeduction.BySpawnRate),
        string.format(" • Valor Bruto IncomingPosition: %s", tostring(workspace:GetAttribute("IncomingPosition") or "N/A")),
        string.format(" • Hora del Juego (ClockTime): %.2f", Lighting.ClockTime),
        "\n[HISTORIAL DE DETECCIONES Y CAMBIOS DE FRENTE]:"
    }

    if #NightForensic.LogEntries == 0 then
        table.insert(lines, " (Sin registros aún. Usa los botones al detectar o cambiar de sector).")
    else
        for i, log in ipairs(NightForensic.LogEntries) do
            table.insert(lines, string.format("\n--- EVENTO #%d [%s | +%ds] -> %s ---", (#NightForensic.LogEntries - i + 1), log.Timestamp, log.ElapsedSec, log.Action))
            table.insert(lines, string.format(" • TU SECTOR REAL: %s | PREDICCIÓN SCRIPT: %s | Coincide: %s", log.UserConfirmed, log.ScriptGuess, log.IsMatch and "✅ SÍ" or "❌ NO"))
            table.insert(lines, string.format(" • IncomingPosition Bruto: %s -> Interpretado como: %s", log.IncomingPosAttr, log.GuessByAttr))
            table.insert(lines, string.format(" • Spawns Recientes indicaban: %s", log.GuessBySpawns))
        end
    end

    table.insert(lines, "\n==================================================================")
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 6. INTERFAZ GRÁFICA FOCALIZADA EN DIRECCIÓN Y CAMBIOS
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WaveDirectionDiagnosticGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 450)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -225)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "  📡 RADAR CALIBRADO: DIRECCIÓN Y CAMBIOS DE FRENTE"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel Central de Veredicto
local VerdictFrame = Instance.new("Frame")
VerdictFrame.Size = UDim2.new(1, -20, 0, 80)
VerdictFrame.Position = UDim2.new(0, 10, 0, 44)
VerdictFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
VerdictFrame.Parent = MainFrame

local VerdictCorner = Instance.new("UICorner")
VerdictCorner.CornerRadius = UDim.new(0, 8)
VerdictCorner.Parent = VerdictFrame

local VerdictLabel = Instance.new("TextLabel")
VerdictLabel.Size = UDim2.new(1, 0, 0, 42)
VerdictLabel.Position = UDim2.new(0, 0, 0, 4)
VerdictLabel.BackgroundTransparency = 1
VerdictLabel.Text = "CARGANDO..."
VerdictLabel.TextColor3 = Color3.fromRGB(0, 255, 170)
VerdictLabel.TextSize = 22
VerdictLabel.Font = Enum.Font.GothamBold
VerdictLabel.Parent = VerdictFrame

local SubVerdictLabel = Instance.new("TextLabel")
SubVerdictLabel.Size = UDim2.new(1, -20, 0, 26)
SubVerdictLabel.Position = UDim2.new(0, 10, 0, 48)
SubVerdictLabel.BackgroundTransparency = 1
SubVerdictLabel.Text = "IncomingPosition: N/A | Spawns: N/A"
SubVerdictLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
SubVerdictLabel.TextSize = 10
SubVerdictLabel.Font = Enum.Font.Code
SubVerdictLabel.Parent = VerdictFrame

-- Selector Manual de Confirmación
local PromptLabel = Instance.new("TextLabel")
PromptLabel.Size = UDim2.new(1, -20, 0, 20)
PromptLabel.Position = UDim2.new(0, 10, 0, 132)
PromptLabel.BackgroundTransparency = 1
PromptLabel.Text = "¿DE DÓNDE VIENEN REALMENTE? (TOCA PARA CONFIRMAR):"
PromptLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
PromptLabel.TextSize = 9
PromptLabel.Font = Enum.Font.GothamBold
PromptLabel.TextXAlignment = Enum.TextXAlignment.Left
PromptLabel.Parent = MainFrame

local function createSectorBtn(name, color, pos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.23, -4, 0, 36)
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        logSectorConfirmation(name, "Confirmación de Sector")
        btn.Text = "✅ " .. name
        task.wait(0.5)
        btn.Text = name
    end)
    return btn
end

createSectorBtn("NORTE", Color3.fromRGB(40, 100, 180), UDim2.new(0, 10, 0, 156))
createSectorBtn("SUR", Color3.fromRGB(180, 50, 40), UDim2.new(0.25, 6, 0, 156))
createSectorBtn("ESTE", Color3.fromRGB(40, 140, 90), UDim2.new(0.50, 2, 0, 156))
createSectorBtn("OESTE", Color3.fromRGB(160, 100, 30), UDim2.new(0.75, -2, 0, 156))

-- Botón de Registro de Cambio de Lugar
local ShiftBtn = Instance.new("TextButton")
ShiftBtn.Size = UDim2.new(1, -20, 0, 34)
ShiftBtn.Position = UDim2.new(0, 10, 0, 200)
ShiftBtn.BackgroundColor3 = Color3.fromRGB(130, 40, 150)
ShiftBtn.Text = "⚡ ¡CAMBIÓ DE LUGAR! (REGISTRAR CAMBIO)"
ShiftBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ShiftBtn.TextSize = 11
ShiftBtn.Font = Enum.Font.GothamBold
ShiftBtn.Parent = MainFrame

local ShiftCorner = Instance.new("UICorner")
ShiftCorner.CornerRadius = UDim.new(0, 6)
ShiftCorner.Parent = ShiftBtn

ShiftBtn.MouseButton1Click:Connect(function()
    NightForensic.SectorShiftCount = NightForensic.SectorShiftCount + 1
    logSectorConfirmation(CurrentDeduction.ScriptVerdict, "🚨 REGISTRO DE CAMBIO DE FRENTE")
    ShiftBtn.Text = "✅ ¡CAMBIO GUARDADO!"
    task.wait(0.8)
    ShiftBtn.Text = "⚡ ¡CAMBIÓ DE LUGAR! (REGISTRAR CAMBIO)"
end)

-- Historial
local HistoryBox = Instance.new("TextBox")
HistoryBox.Size = UDim2.new(1, -20, 0, 140)
HistoryBox.Position = UDim2.new(0, 10, 0, 244)
HistoryBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
HistoryBox.TextColor3 = Color3.fromRGB(220, 220, 220)
HistoryBox.TextSize = 9
HistoryBox.Font = Enum.Font.Code
HistoryBox.TextXAlignment = Enum.TextXAlignment.Left
HistoryBox.TextYAlignment = Enum.TextYAlignment.Top
HistoryBox.MultiLine = true
HistoryBox.ClearTextOnFocus = false
HistoryBox.TextEditable = false
HistoryBox.Text = "(Registra confirmaciones o cambios para comparar...)"
HistoryBox.Parent = MainFrame

local HistoryCorner = Instance.new("UICorner")
HistoryCorner.CornerRadius = UDim.new(0, 6)
HistoryCorner.Parent = HistoryBox

-- Botones Inferiores
local CopyReportBtn = Instance.new("TextButton")
CopyReportBtn.Size = UDim2.new(0.68, -8, 0, 36)
CopyReportBtn.Position = UDim2.new(0, 10, 0, 396)
CopyReportBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyReportBtn.Text = "📋 COPIAR REPORTE"
CopyReportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyReportBtn.TextSize = 10
CopyReportBtn.Font = Enum.Font.GothamBold
CopyReportBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyReportBtn

CopyReportBtn.MouseButton1Click:Connect(function()
    local fullText = compileFullReport()
    if setclipboard then
        setclipboard(fullText)
    elseif toclipboard then
        toclipboard(fullText)
    end
    CopyReportBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyReportBtn.Text = "📋 COPIAR REPORTE"
end)

local ResetBtn = Instance.new("TextButton")
ResetBtn.Size = UDim2.new(0.32, -8, 0, 36)
ResetBtn.Position = UDim2.new(0.68, 6, 0, 396)
ResetBtn.BackgroundColor3 = Color3.fromRGB(140, 35, 40)
ResetBtn.Text = "🗑️ REINICIAR"
ResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetBtn.TextSize = 10
ResetBtn.Font = Enum.Font.GothamBold
ResetBtn.Parent = MainFrame

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 6)
ResetCorner.Parent = ResetBtn

ResetBtn.MouseButton1Click:Connect(function()
    table.clear(NightForensic.LogEntries)
    NightForensic.TotalConfirmations = 0
    NightForensic.Mismatches = 0
    NightForensic.SectorShiftCount = 0
    NightForensic.StartTime = tick()
    HistoryBox.Text = "(Historial reiniciado)"
    ResetBtn.Text = "✅ LISTO"
    task.wait(0.8)
    ResetBtn.Text = "🗑️ REINICIAR"
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "📡\nRADAR"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==============================================================================
-- 7. BUCLE DE ACTUALIZACIÓN EN TIEMPO REAL (SIN LAG)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.3)
        analyzeWaveDirection()

        -- Alerta visual si ocurre un cambio en vivo
        if CurrentDeduction.ScriptVerdict ~= "DESCONOCIDO" and CurrentDeduction.ScriptVerdict ~= LastRecordedScriptSector then
            LastRecordedScriptSector = CurrentDeduction.ScriptVerdict
        end

        local verdictColor = (CurrentDeduction.ScriptVerdict == "NORTE" and Color3.fromRGB(80, 150, 255))
            or (CurrentDeduction.ScriptVerdict == "SUR" and Color3.fromRGB(255, 90, 80))
            or (CurrentDeduction.ScriptVerdict == "ESTE" and Color3.fromRGB(80, 220, 130))
            or (CurrentDeduction.ScriptVerdict == "OESTE" and Color3.fromRGB(255, 180, 60))
            or Color3.fromRGB(180, 180, 180)

        VerdictLabel.TextColor3 = verdictColor
        VerdictLabel.Text = string.format("VIENEN DE: %s (%d%%)", CurrentDeduction.ScriptVerdict, CurrentDeduction.Confidence)

        SubVerdictLabel.Text = string.format(
            "IncomingPosition: %s | Spawns Recientes: %s\nTu Confirmación: %s | Precisión: %.0f%% (Fallos: %d)",
            CurrentDeduction.ByAttribute,
            CurrentDeduction.BySpawnRate,
            LastUserConfirmedSector,
            NightForensic.TotalConfirmations > 0 and ((NightForensic.TotalConfirmations - NightForensic.Mismatches) / NightForensic.TotalConfirmations * 100) or 0,
            NightForensic.Mismatches
        )

        if #NightForensic.LogEntries > 0 then
            local summaryLines = {}
            for i = 1, math.min(5, #NightForensic.LogEntries) do
                local entry = NightForensic.LogEntries[i]
                table.insert(summaryLines, string.format("[%s] Real: %s | Script: %s -> %s", entry.Timestamp, entry.UserConfirmed, entry.ScriptGuess, entry.IsMatch and "✅ OK" or "❌ FALLÓ"))
            end
            HistoryBox.Text = table.concat(summaryLines, "\n")
        end
    end
end)
