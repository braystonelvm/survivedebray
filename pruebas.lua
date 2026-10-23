-- ==============================================================================
-- ESCÁNER FORENSE Y CALIBRADOR DE OLEADAS NOCTURNAS (MAPEO EXACTO DE RONDAS)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

-- Historial y base de datos forense
local NightForensic = {
    StartTime = tick(),
    NightNumber = 0,
    TotalConfirmations = 0,
    Mismatches = 0,
    LogEntries = {},
    RecentSpawns = {}, -- Registro de dónde nacen en los últimos 10s
    AttributesSnapshot = {}
}

local CurrentDeduction = {
    ByAttribute = "N/A",
    ByLiveDensity = "N/A",
    BySpawnRate = "N/A",
    ScriptVerdict = "DESCONOCIDO",
    Confidence = 0
}

local LastUserConfirmedSector = "NINGUNO"

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        game:GetService("UserInputService").MouseIconEnabled = true
    end)
end)

-- ==============================================================================
-- 1. DETECTOR Y CLASIFICADOR DE CUADRANTES
-- ==============================================================================

local function getSectorFromVector(pos)
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
-- 2. ESCUCHA DE SPAWNS EN VIVO (DÓNDE NACEN EN TIEMPO REAL)
-- ==============================================================================

local charFolder = workspace:FindFirstChild("Characters") or workspace

charFolder.ChildAdded:Connect(function(child)
    task.wait(0.1)
    local valid, root = isValidZombie(child)
    if valid and root then
        local pos = root.Position
        local sector = getSectorFromVector(pos)
        table.insert(NightForensic.RecentSpawns, {
            Time = tick(),
            Pos = pos,
            Sector = sector,
            Name = child.Name
        })
    end
end)

-- Limpiar spawns viejos (> 12 segundos)
task.spawn(function()
    while true do
        task.wait(1)
        local now = tick()
        for i = #NightForensic.RecentSpawns, 1, -1 do
            if (now - NightForensic.RecentSpawns[i].Time) > 12 then
                table.remove(NightForensic.RecentSpawns, i)
            end
        end
    end
end)

-- ==============================================================================
-- 3. MOTOR DE DEDUCCIÓN EN TIEMPO REAL
-- ==============================================================================

local function analyzeCurrentGameState()
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local counts = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
    local centroids = {
        NORTE = Vector3.zero,
        SUR = Vector3.zero,
        ESTE = Vector3.zero,
        OESTE = Vector3.zero
    }
    local totalLiving = 0

    for _, ent in ipairs(charFolder:GetChildren()) do
        local valid, root = isValidZombie(ent)
        if valid and root then
            local pos = root.Position
            local dist = (pos - BaseCenter).Magnitude
            if dist <= 900 and dist >= 80 then
                totalLiving = totalLiving + 1
                local sec = getSectorFromVector(pos)
                counts[sec] = counts[sec] + 1
                centroids[sec] = centroids[sec] + pos
            end
        end
    end

    for s, c in pairs(counts) do
        if c > 0 then centroids[s] = centroids[s] / c end
    end

    -- 1. Deducción por Atributo de Servidor
    local incoming = workspace:GetAttribute("IncomingPosition")
    local incomingVec = parseVectorString(incoming)
    local attrSector = incomingVec and getSectorFromVector(incomingVec) or "N/A"
    CurrentDeduction.ByAttribute = attrSector

    -- 2. Deducción por Concentración de Densidad Actual
    local densitySector = "NINGUNO"
    local maxDensity = 0
    for s, c in pairs(counts) do
        if c > maxDensity then
            maxDensity = c
            densitySector = s
        end
    end
    CurrentDeduction.ByLiveDensity = (maxDensity >= 4) and densitySector or "INCIERTO"

    -- 3. Deducción por Tasa de Nacimiento (Spawns recientes)
    local spawnCounts = { NORTE = 0, SUR = 0, ESTE = 0, OESTE = 0 }
    for _, sp in ipairs(NightForensic.RecentSpawns) do
        spawnCounts[sp.Sector] = spawnCounts[sp.Sector] + 1
    end
    local spawnSector = "NINGUNO"
    local maxSpawns = 0
    for s, c in pairs(spawnCounts) do
        if c > maxSpawns then
            maxSpawns = c
            spawnSector = s
        end
    end
    CurrentDeduction.BySpawnRate = (maxSpawns >= 2) and spawnSector or "INCIERTO"

    -- Veredicto Combinado del Script
    if CurrentDeduction.BySpawnRate ~= "INCIERTO" and CurrentDeduction.BySpawnRate == CurrentDeduction.ByLiveDensity then
        CurrentDeduction.ScriptVerdict = CurrentDeduction.BySpawnRate
        CurrentDeduction.Confidence = 95
    elseif CurrentDeduction.ByAttribute ~= "N/A" and counts[CurrentDeduction.ByAttribute] >= 5 then
        CurrentDeduction.ScriptVerdict = CurrentDeduction.ByAttribute
        CurrentDeduction.Confidence = 80
    elseif CurrentDeduction.ByLiveDensity ~= "INCIERTO" then
        CurrentDeduction.ScriptVerdict = CurrentDeduction.ByLiveDensity
        CurrentDeduction.Confidence = 65
    elseif CurrentDeduction.ByAttribute ~= "N/A" then
        CurrentDeduction.ScriptVerdict = CurrentDeduction.ByAttribute
        CurrentDeduction.Confidence = 50
    else
        CurrentDeduction.ScriptVerdict = "DESCONOCIDO"
        CurrentDeduction.Confidence = 10
    end

    return counts, spawnCounts, totalLiving, centroids
end

-- ==============================================================================
-- 4. CAPTURADOR DE SNAPSHOTS AL CONFIRMAR O CAMBIAR
-- ==============================================================================

local function getAllGameAttributes()
    local result = {}
    for k, v in pairs(workspace:GetAttributes()) do
        table.insert(result, string.format("Workspace.%s = %s", tostring(k), tostring(v)))
    end
    for k, v in pairs(Lighting:GetAttributes()) do
        table.insert(result, string.format("Lighting.%s = %s", tostring(k), tostring(v)))
    end
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    if rem then
        for k, v in pairs(rem:GetAttributes()) do
            table.insert(result, string.format("Remotes.%s = %s", tostring(k), tostring(v)))
        end
    end
    return result
end

local function logSectorConfirmation(userSector, actionNote)
    NightForensic.TotalConfirmations = NightForensic.TotalConfirmations + 1
    local nowTime = os.date("%X")
    local elapsed = math.floor(tick() - NightForensic.StartTime)

    local counts, spawnCounts, totalLiving, centroids = analyzeCurrentGameState()
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
        GuessByDensity = CurrentDeduction.ByLiveDensity,
        GuessBySpawns = CurrentDeduction.BySpawnRate,
        LivingCounts = string.format("N:%d | S:%d | E:%d | O:%d (Total: %d)", counts.NORTE, counts.SUR, counts.ESTE, counts.OESTE, totalLiving),
        Spawns10s = string.format("N:%d | S:%d | E:%d | O:%d", spawnCounts.NORTE, spawnCounts.SUR, spawnCounts.ESTE, spawnCounts.OESTE),
        IncomingPosAttr = tostring(workspace:GetAttribute("IncomingPosition") or "N/A"),
        RemainingMobsAttr = tostring(workspace:GetAttribute("RemainingMobs") or "N/A"),
        ClockTime = string.format("%.2f", Lighting.ClockTime),
        Attributes = getAllGameAttributes()
    }

    table.insert(NightForensic.LogEntries, 1, entry)
    if #NightForensic.LogEntries > 60 then
        table.remove(NightForensic.LogEntries)
    end

    print(string.format("📌 [RADAR LOG]: Confirmado=%s | Script=%s | Coincide=%s", userSector, entry.ScriptGuess, tostring(isMatch)))
end

-- ==============================================================================
-- 5. GENERADOR DE REPORTE COMPLETO EN TEXTO
-- ==============================================================================

local function compileFullReport()
    local counts, spawnCounts, totalLiving = analyzeCurrentGameState()
    local lines = {
        "==================================================================",
        "      REPORTE DIAGNÓSTICO: DETECCIÓN DE OLEADAS NOCTURNAS         ",
        "==================================================================",
        string.format("Fecha de Registro: %s", os.date("%Y-%m-%d %X")),
        string.format("Confirmaciones Totales: %d | Errores del Script: %d", NightForensic.TotalConfirmations, NightForensic.Mismatches),
        string.format("Precisión Actual del Script: %.1f%%", NightForensic.TotalConfirmations > 0 and ((NightForensic.TotalConfirmations - NightForensic.Mismatches) / NightForensic.TotalConfirmations * 100) or 0),
        "\n[ESTADO ACTUAL EN VIVO]:",
        string.format(" • Veredicto Actual del Script: %s (Confianza: %d%%)", CurrentDeduction.ScriptVerdict, CurrentDeduction.Confidence),
        string.format(" • Vía IncomingPosition: %s", CurrentDeduction.ByAttribute),
        string.format(" • Vía Densidad de Horda: %s", CurrentDeduction.ByLiveDensity),
        string.format(" • Vía Spawns Recientes (10s): %s", CurrentDeduction.BySpawnRate),
        string.format(" • Zombies Vivos por Cuadrante: NORTE: %d | SUR: %d | ESTE: %d | OESTE: %d", counts.NORTE, counts.SUR, counts.ESTE, counts.OESTE),
        string.format(" • Spawns últimos 10s: NORTE: %d | SUR: %d | ESTE: %d | OESTE: %d", spawnCounts.NORTE, spawnCounts.SUR, spawnCounts.ESTE, spawnCounts.OESTE),
        string.format(" • Hora de Lighting: %.2f | IncomingPosition: %s | RemainingMobs: %s", Lighting.ClockTime, tostring(workspace:GetAttribute("IncomingPosition") or "N/A"), tostring(workspace:GetAttribute("RemainingMobs") or "N/A")),
        "\n[ATRIBUTOS COMPLETOS DEL JUEGO DETECTADOS]:"
    }

    local attrs = getAllGameAttributes()
    for _, a in ipairs(attrs) do
        table.insert(lines, "   • " .. a)
    end

    table.insert(lines, "\n[HISTORIAL DE EVENTOS Y CAMBIOS DE SECTOR]:")
    if #NightForensic.LogEntries == 0 then
        table.insert(lines, " (No has registrado confirmaciones aún. Presiona los botones del menú cuando vengan zombies).")
    else
        for i, log in ipairs(NightForensic.LogEntries) do
            table.insert(lines, string.format("\n--- EVENTO #%d [%s | +%ds] -> Acción: %s ---", (#NightForensic.LogEntries - i + 1), log.Timestamp, log.ElapsedSec, log.Action))
            table.insert(lines, string.format(" • SECTOR REAL (Tú): %s | PREDICCIÓN SCRIPT: %s | ¿Coincidió?: %s", log.UserConfirmed, log.ScriptGuess, log.IsMatch and "✅ SÍ" or "❌ NO (FALLÓ)"))
            table.insert(lines, string.format(" • Desglose: Attr=%s | Densidad=%s | Spawns=%s", log.GuessByAttr, log.GuessByDensity, log.GuessBySpawns))
            table.insert(lines, string.format(" • Conteo Horda: %s", log.LivingCounts))
            table.insert(lines, string.format(" • Nacimientos 10s: %s", log.Spawns10s))
            table.insert(lines, string.format(" • Workspace.IncomingPosition: %s", log.IncomingPosAttr))
            table.insert(lines, string.format(" • Workspace.RemainingMobs: %s | ClockTime: %s", log.RemainingMobsAttr, log.ClockTime))
        end
    end

    table.insert(lines, "\n==================================================================")
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 6. INTERFAZ GRÁFICA TÁCTIL Y MENÚ DE CONFIRMACIÓN (DELTA / MÓVIL)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NightWaveDiagnosticGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 490, 0, 480)
MainFrame.Position = UDim2.new(0.5, -245, 0.5, -240)
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
TitleBar.Text = "  📡 DIAGNÓSTICO Y CALIBRADOR DE OLEADAS NOCTURNAS"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Monitor en Vivo
local MonitorBox = Instance.new("TextLabel")
MonitorBox.Size = UDim2.new(1, -20, 0, 95)
MonitorBox.Position = UDim2.new(0, 10, 0, 44)
MonitorBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
MonitorBox.TextColor3 = Color3.fromRGB(255, 255, 255)
MonitorBox.TextSize = 10
MonitorBox.Font = Enum.Font.Code
MonitorBox.TextXAlignment = Enum.TextXAlignment.Left
MonitorBox.TextYAlignment = Enum.TextYAlignment.Top
MonitorBox.Text = "Iniciando análisis..."
MonitorBox.Parent = MainFrame

local MonitorCorner = Instance.new("UICorner")
MonitorCorner.CornerRadius = UDim.new(0, 6)
MonitorCorner.Parent = MonitorBox

-- Sección: Confirmación Manual del Usuario
local PromptLabel = Instance.new("TextLabel")
PromptLabel.Size = UDim2.new(1, -20, 0, 22)
PromptLabel.Position = UDim2.new(0, 10, 0, 146)
PromptLabel.BackgroundTransparency = 1
PromptLabel.Text = "🎯 ¿POR DÓNDE VIENEN REALMENTE? (TOCA PARA CONFIRMAR/CORREGIR):"
PromptLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
PromptLabel.TextSize = 9
PromptLabel.Font = Enum.Font.GothamBold
PromptLabel.TextXAlignment = Enum.TextXAlignment.Left
PromptLabel.Parent = MainFrame

local function createSectorBtn(name, color, pos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.23, -4, 0, 38)
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
        logSectorConfirmation(name, "Selección Manual de Sector")
        btn.Text = "✅ " .. name
        task.wait(0.6)
        btn.Text = name
    end)
    return btn
end

createSectorBtn("NORTE", Color3.fromRGB(40, 100, 180), UDim2.new(0, 10, 0, 172))
createSectorBtn("SUR", Color3.fromRGB(180, 50, 40), UDim2.new(0.25, 6, 0, 172))
createSectorBtn("ESTE", Color3.fromRGB(40, 140, 90), UDim2.new(0.50, 2, 0, 172))
createSectorBtn("OESTE", Color3.fromRGB(160, 100, 30), UDim2.new(0.75, -2, 0, 172))

-- Botón especial: "ACABA DE CAMBIAR DE LUGAR"
local ShiftBtn = Instance.new("TextButton")
ShiftBtn.Size = UDim2.new(1, -20, 0, 32)
ShiftBtn.Position = UDim2.new(0, 10, 0, 218)
ShiftBtn.BackgroundColor3 = Color3.fromRGB(130, 40, 150)
ShiftBtn.Text = "⚡ ¡ACABA DE CAMBIAR DE LUGAR! (REGISTRAR MOMENTO EXACTO)"
ShiftBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ShiftBtn.TextSize = 10
ShiftBtn.Font = Enum.Font.GothamBold
ShiftBtn.Parent = MainFrame

local ShiftCorner = Instance.new("UICorner")
ShiftCorner.CornerRadius = UDim.new(0, 6)
ShiftCorner.Parent = ShiftBtn

ShiftBtn.MouseButton1Click:Connect(function()
    logSectorConfirmation(CurrentDeduction.ScriptVerdict, "🚨 ALERTA: Usuario reportó cambio de frente")
    ShiftBtn.Text = "✅ ¡CAMBIO REGISTRADO!"
    task.wait(1)
    ShiftBtn.Text = "⚡ ¡ACABA DE CAMBIAR DE LUGAR! (REGISTRAR MOMENTO EXACTO)"
end)

-- Visor de Historial en la UI
local HistoryLabel = Instance.new("TextLabel")
HistoryLabel.Size = UDim2.new(1, -20, 0, 20)
HistoryLabel.Position = UDim2.new(0, 10, 0, 256)
HistoryLabel.BackgroundTransparency = 1
HistoryLabel.Text = "HISTORIAL DE EVENTOS REGISTRADOS:"
HistoryLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
HistoryLabel.TextSize = 9
HistoryLabel.Font = Enum.Font.GothamBold
HistoryLabel.TextXAlignment = Enum.TextXAlignment.Left
HistoryLabel.Parent = MainFrame

local HistoryBox = Instance.new("TextBox")
HistoryBox.Size = UDim2.new(1, -20, 0, 146)
HistoryBox.Position = UDim2.new(0, 10, 0, 278)
HistoryBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
HistoryBox.TextColor3 = Color3.fromRGB(220, 220, 220)
HistoryBox.TextSize = 9
HistoryBox.Font = Enum.Font.Code
HistoryBox.TextXAlignment = Enum.TextXAlignment.Left
HistoryBox.TextYAlignment = Enum.TextYAlignment.Top
HistoryBox.MultiLine = true
HistoryBox.ClearTextOnFocus = false
HistoryBox.TextEditable = false
HistoryBox.Text = "(Los eventos confirmados aparecerán aquí...)"
HistoryBox.Parent = MainFrame

local HistoryCorner = Instance.new("UICorner")
HistoryCorner.CornerRadius = UDim.new(0, 6)
HistoryCorner.Parent = HistoryBox

-- Botones de Copiar Reporte y Limpiar
local CopyReportBtn = Instance.new("TextButton")
CopyReportBtn.Size = UDim2.new(0.68, -8, 0, 38)
CopyReportBtn.Position = UDim2.new(0, 10, 0, 432)
CopyReportBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyReportBtn.Text = "📋 GENERAR Y COPIAR REPORTE COMPLETO"
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
    CopyReportBtn.Text = "✅ ¡REPORTE COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyReportBtn.Text = "📋 GENERAR Y COPIAR REPORTE COMPLETO"
end)

local ResetBtn = Instance.new("TextButton")
ResetBtn.Size = UDim2.new(0.32, -8, 0, 38)
ResetBtn.Position = UDim2.new(0.68, 6, 0, 432)
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
    NightForensic.StartTime = tick()
    HistoryBox.Text = "(Historial reiniciado)"
    ResetBtn.Text = "✅ LISTO"
    task.wait(1)
    ResetBtn.Text = "🗑️ REINICIAR"
end)

-- Widget flotante para abrir/minimizar en Delta
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
-- 7. BUCLE DE ACTUALIZACIÓN VISUAL (CERO LAG: CADA 0.4s)
-- ==============================================================================

local lastDetectedChangeSector = "N/A"

task.spawn(function()
    while true do
        task.wait(0.4)
        local counts, spawnCounts, totalLiving = analyzeCurrentGameState()

        -- Detección automática de cambio de frente
        if CurrentDeduction.ScriptVerdict ~= "DESCONOCIDO" and CurrentDeduction.ScriptVerdict ~= lastDetectedChangeSector then
            lastDetectedChangeSector = CurrentDeduction.ScriptVerdict
        end

        MonitorBox.Text = string.format(
            " SCRIPT DICE: [%s] (Confianza: %d%%)\n" ..
            "  ↳ Vía Atributo: %s | Densidad: %s | Spawns 10s: %s\n" ..
            " CONTEO EN VIVO: N: %d | S: %d | E: %d | O: %d (Vivos: %d)\n" ..
            " NACIMIENTOS 10s: N: %d | S: %d | E: %d | O: %d\n" ..
            " ÚLTIMA CONFIRMACIÓN TUYA: %s (Registros: %d | Mismatches: %d)",
            CurrentDeduction.ScriptVerdict, CurrentDeduction.Confidence,
            CurrentDeduction.ByAttribute, CurrentDeduction.ByLiveDensity, CurrentDeduction.BySpawnRate,
            counts.NORTE, counts.SUR, counts.ESTE, counts.OESTE, totalLiving,
            spawnCounts.NORTE, spawnCounts.SUR, spawnCounts.ESTE, spawnCounts.OESTE,
            LastUserConfirmedSector, NightForensic.TotalConfirmations, NightForensic.Mismatches
        )

        -- Actualizar caja de texto del historial breve
        if #NightForensic.LogEntries > 0 then
            local summaryLines = {}
            for i = 1, math.min(6, #NightForensic.LogEntries) do
                local entry = NightForensic.LogEntries[i]
                table.insert(summaryLines, string.format("[%s] Real: %s | Script: %s -> %s", entry.Timestamp, entry.UserConfirmed, entry.ScriptGuess, entry.IsMatch and "OK" or "FALLÓ"))
            end
            HistoryBox.Text = table.concat(summaryLines, "\n")
        end
    end
end)
