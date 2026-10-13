-- ==============================================================================
-- DETECTOR FORENSE DE ROLLBACK SUBTERRÁNEO & ANALIZADOR DE TELETRANSPORTE
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local ForensicData = {
    RollbackDetected = 0,
    LastDetectedScript = "Ninguno",
    LastTouchPart = "Ninguno",
    Logs = {},
    FreezeUnderground = false,
    IgnoreTouchInterests = false
}

local function addLog(txt)
    local entry = string.format("[%s] %s", os.date("%X"), txt)
    table.insert(ForensicData.Logs, 1, entry)
    if #ForensicData.Logs > 35 then table.remove(ForensicData.Logs) end
    print("[FORENSE SUBTERRÁNEO]: " .. entry)
end

-- ==============================================================================
-- 1. DETECCIÓN EN VIVO DE CAMBIO BRUSCO DE POSICIÓN (TELETRANSPORTE / ROLLBACK)
-- ==============================================================================
task.spawn(function()
    local char = lp.Character or lp.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    local lastY = root.Position.Y
    local lastPos = root.Position

    RunService.Heartbeat:Connect(function()
        char = lp.Character
        root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local curPos = root.Position
        local curY = curPos.Y

        -- Si el personaje estaba bajo tierra (o bajando) y de golpe sube más de 4 studs en un solo frame:
        local yDiff = curY - lastY
        if yDiff > 3.5 and lastY < 2.0 then
            ForensicData.RollbackDetected = ForensicData.RollbackDetected + 1
            
            -- Intentar rastrear el script culpable en el stack
            local caller = "Desconocido (Física o Servidor)"
            if debug and debug.info then
                local sName = debug.info(2, "s")
                if sName and sName ~= "" then caller = sName end
            end

            -- Revisar partes que colisionaron o estaban cerca en ese punto
            local touching = ""
            for _, p in ipairs(workspace:GetPartsInPart(root)) do
                if p.Parent ~= char and not p:IsDescendantOf(char) then
                    touching = touching .. p.Name .. " (" .. p.Parent.Name .. "), "
                end
            end

            addLog(string.format("🚨 ¡ROLLBACK DETECTADO! De Y=%.1f a Y=%.1f (+%.1f studs)", lastY, curY, yDiff))
            if touching ~= "" then
                addLog("   Partes en contacto: " .. touching)
                ForensicData.LastTouchPart = touching
            end
            addLog("   Origen del cambio: " .. caller)
            ForensicData.LastDetectedScript = caller

            -- Si la opción de forzar permanencia subterránea está encendida:
            if ForensicData.FreezeUnderground then
                root.AssemblyLinearVelocity = Vector3.zero
                root.CFrame = CFrame.new(lastPos)
            end
        end

        lastY = curY
        lastPos = curPos
    end)
end)

-- ==============================================================================
-- 2. ESCÁNER DE SCRIPTS LOCALES SOSPECHOSOS DE "UNSTUCK"
-- ==============================================================================
local function scanSuspiciousLocalScripts()
    local suspicious = {}
    local containers = { lp.PlayerGui, lp:FindFirstChild("PlayerScripts"), lp.Character }

    for _, cont in ipairs(containers) do
        if cont then
            for _, desc in ipairs(cont:GetDescendants()) do
                if desc:IsA("LocalScript") then
                    local n = desc.Name:lower()
                    if n:find("stuck") or n:find("ground") or n:find("teleport") or n:find("terrain") 
                       or n:find("car") or n:find("vehicle") or n:find("reset") or n:find("void") or n:find("fall") then
                        table.insert(suspicious, desc:GetFullName())
                    end
                end
            end
        end
    end
    return suspicious
end

-- ==============================================================================
-- 3. ESCÁNER DE DISPARADORES INVISIBLES BAJO EL SUELO
-- ==============================================================================
local function scanUndergroundBarriers()
    local barriers = {}
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            -- Piezas invisibles ubicadas a baja altura con CanTouch o CanCollide
            if desc.Position.Y < 5 and desc.Transparency >= 0.8 then
                local n = desc.Name:lower()
                if n:find("kill") or n:find("void") or n:find("barrier") or n:find("reset") or n:find("unstuck") or n:find("trigger") or desc:FindFirstChildWhichIsA("TouchTransmitter") then
                    table.insert(barriers, string.format("• %s | Y=%.1f | %s", desc.Name, desc.Position.Y, desc:GetFullName()))
                end
            end
        end
    end
    return barriers
end

-- ==============================================================================
-- 4. INTERFAZ VISUAL NATIVA
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UndergroundDiagnosticGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 70, 20)
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local BtnText = Instance.new("TextLabel")
BtnText.Size = UDim2.new(1, 0, 1, 0)
BtnText.BackgroundTransparency = 1
BtnText.Text = "⛏️"
BtnText.TextSize = 20
BtnText.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnText.Parent = FloatBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 420)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
TitleBar.Text = "  ANALIZADOR FORENSE: ROLLBACK SUBTERRÁNEO"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusPanel = Instance.new("TextLabel")
StatusPanel.Size = UDim2.new(1, -20, 0, 75)
StatusPanel.Position = UDim2.new(0, 10, 0, 44)
StatusPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
StatusPanel.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusPanel.TextSize = 11
StatusPanel.Font = Enum.Font.Code
StatusPanel.TextXAlignment = Enum.TextXAlignment.Left
StatusPanel.TextYAlignment = Enum.TextYAlignment.Top
StatusPanel.Text = " Monitor en espera..."
StatusPanel.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusPanel

local LogBox = Instance.new("TextBox")
LogBox.Size = UDim2.new(1, -20, 0, 210)
LogBox.Position = UDim2.new(0, 10, 0, 126)
LogBox.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
LogBox.TextColor3 = Color3.fromRGB(220, 220, 220)
LogBox.TextSize = 10
LogBox.Font = Enum.Font.Code
LogBox.TextXAlignment = Enum.TextXAlignment.Left
LogBox.TextYAlignment = Enum.TextYAlignment.Top
LogBox.ClearTextOnFocus = false
LogBox.MultiLine = true
LogBox.TextEditable = false
LogBox.Text = "Baja bajo tierra con tu fly/noclip para registrar el empuje..."
LogBox.Parent = MainFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogBox

-- Botón 1: Bloqueo de Posición (Prueba si el rollback se puede anular)
local BypassBtn = Instance.new("TextButton")
BypassBtn.Size = UDim2.new(0.48, -10, 0, 34)
BypassBtn.Position = UDim2.new(0, 10, 0, 345)
BypassBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
BypassBtn.Text = "🔒 FORZAR QUEDAR BAJO TIERRA: OFF"
BypassBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BypassBtn.TextSize = 10
BypassBtn.Font = Enum.Font.GothamBold
BypassBtn.Parent = MainFrame

local BypassCorner = Instance.new("UICorner")
BypassCorner.CornerRadius = UDim.new(0, 6)
BypassCorner.Parent = BypassBtn

BypassBtn.MouseButton1Click:Connect(function()
    ForensicData.FreezeUnderground = not ForensicData.FreezeUnderground
    if ForensicData.FreezeUnderground then
        BypassBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 70)
        BypassBtn.Text = "🔒 FORZAR QUEDAR BAJO TIERRA: ON"
        addLog("Prueba de anclaje subterráneo activada.")
    else
        BypassBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
        BypassBtn.Text = "🔒 FORZAR QUEDAR BAJO TIERRA: OFF"
        addLog("Prueba de anclaje desactivada.")
    end
end)

-- Botón 2: Copiar Reporte
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 34)
CopyBtn.Position = UDim2.new(0.52, 5, 0, 345)
CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 160)
CopyBtn.Text = "📋 COPIAR REPORTE AL PORTAPAPELES"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

local function generateReport()
    local dump = {
        "=== REPORTE DE ROLLBACK SUBTERRÁNEO ===",
        "Veces que el juego te empujó hacia arriba: " .. ForensicData.RollbackDetected,
        "Último script/origen detectado: " .. ForensicData.LastDetectedScript,
        "Partes tocadas durante el tirón: " .. ForensicData.LastTouchPart,
        "\n[SCRIPTS LOCALES SOSPECHOSOS DETECTADOS]:"
    }

    local scriptsFound = scanSuspiciousLocalScripts()
    if #scriptsFound == 0 then
        table.insert(dump, " • Ningún LocalScript con nombres obvios (stuck/void/teleport/car).")
    else
        for _, s in ipairs(scriptsFound) do table.insert(dump, " • " .. s) end
    end

    table.insert(dump, "\n[BARRERAS/DISPARADORES INVISIBLES BAJO TIERRA]:")
    local barriersFound = scanUndergroundBarriers()
    if #barriersFound == 0 then
        table.insert(dump, " • No se hallaron partes invisibles con 'Touch' bajo el suelo.")
    else
        for i = 1, math.min(#barriersFound, 15) do table.insert(dump, barriersFound[i]) end
    end

    table.insert(dump, "\n[HISTORIAL DE EVENTOS RECIENTES]:")
    for _, l in ipairs(ForensicData.Logs) do table.insert(dump, " " .. l) end

    return table.concat(dump, "\n")
end

CopyBtn.MouseButton1Click:Connect(function()
    local text = generateReport()
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡COPIADO!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR REPORTE AL PORTAPAPELES"
end)

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

task.spawn(function()
    while true do
        task.wait(0.3)
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local currentY = root and root.Position.Y or 0

        StatusPanel.Text = string.format(
            " Altura actual (Y): %.1f\n Rollbacks registrados: %d\n Último origen detectado: %s",
            currentY, ForensicData.RollbackDetected, ForensicData.LastDetectedScript
        )

        LogBox.Text = table.concat(ForensicData.Logs, "\n")
    end
end)
