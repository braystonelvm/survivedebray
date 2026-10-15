-- ==============================================================================
-- ESCÁNER FORENSE DE PROFUNDIDADES SUBTERRÁNEAS, ROCAS Y SALTO 3D (300 STUDS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local ScannerData = {
    DeepZones = {},
    RocksFound = {},
    Logs = {}
}

local function addLog(txt)
    local entry = string.format("[%s] %s", os.date("%X"), txt)
    table.insert(ScannerData.Logs, 1, entry)
    if #ScannerData.Logs > 30 then table.remove(ScannerData.Logs) end
    print("[MAPA SUBTERRÁNEO]: " .. entry)
end

-- ==============================================================================
-- 1. ANALIZADOR DE PARTES PROFUNDAS Y ROCAS (300 STUDS DESDE LA BASE 0,0,0)
-- ==============================================================================
local function scanUndergroundTerrain()
    local deepList = {}
    local rockList = {}
    local baseCenter = Vector3.new(0, 0, 0)

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 300 then
                local nameLower = desc.Name:lower()

                -- Identificar rocas y elementos sólidos bajo tierra o en superficie
                if nameLower:find("rock") or nameLower:find("stone") or nameLower:find("boulder") or nameLower:find("piedra") or nameLower:find("roca") or nameLower:find("cliff") then
                    table.insert(rockList, {
                        Part = desc,
                        Name = desc.Name,
                        Pos = pos,
                        Size = desc.Size,
                        Depth = pos.Y
                    })

                    -- Colorear temporalmente las rocas de un tono brillante para verlas claramente
                    pcall(function()
                        desc.Color = Color3.fromRGB(0, 255, 120)
                        desc.Material = Enum.Material.Neon
                    end)
                end

                -- Identificar zonas bajas / profundas (Y < 0)
                if pos.Y <= -2.0 then
                    table.insert(deepList, {
                        Part = desc,
                        Name = desc.Name,
                        Pos = pos,
                        Depth = pos.Y,
                        CanCollide = desc.CanCollide
                    })
                end
            end
        end
    end

    ScannerData.DeepZones = deepList
    ScannerData.RocksFound = rockList
    addLog(string.format("Escaneo completado: %d rocas resaltadas, %d zonas profundas (Y < -2) halladas.", #rockList, #deepList))
end

-- ==============================================================================
-- 2. TELETRANSPORTE DE PRUEBA A LA PROFUNDIDAD SELECCIONADA
-- ==============================================================================
local function testTeleportToDepth(targetY)
    local char, root = lp.Character, lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    -- Mantener noclip durante el test
    for _, p in ipairs(lp.Character:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end

    root.CFrame = CFrame.new(root.Position.X, targetY, root.Position.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    addLog(string.format("Teletransportado a Y = %.1f para probar respuesta del servidor...", targetY))
end

-- ==============================================================================
-- 3. INTERFAZ VISUAL (FLUENT STYLE / NATIVA)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UndergroundDeepScannerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 540, 0, 460)
MainFrame.Position = UDim2.new(0.5, -270, 0.5, -230)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 36)
Title.BackgroundColor3 = Color3.fromRGB(26, 30, 42)
Title.Text = "  🗺️ ESCÁNER DE PROFUNDIDADES Y ROCAS (300 STUDS)"
Title.TextColor3 = Color3.fromRGB(0, 255, 180)
Title.TextSize = 11
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 310)
OutputBox.Position = UDim2.new(0, 10, 0, 44)
OutputBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
OutputBox.TextColor3 = Color3.fromRGB(220, 220, 220)
OutputBox.TextSize = 10
OutputBox.Font = Enum.Font.Code
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextEditable = false
OutputBox.Text = "Instrucciones:\n1. Presiona 'ESCANEAR ROCAS Y PROFUNDIDADES' para iluminar de verde las rocas subterráneas.\n2. Revisa el reporte para ver qué zonas permiten saltar o teletransportarte."
OutputBox.Parent = MainFrame

local function buildReportText()
    local out = {
        "==================================================================",
        "       REPORTE DE PROFUNDIDADES Y ROCAS SUBTERRÁNEAS (300m)       ",
        "==================================================================",
        string.format("Total de Rocas Coloreadas: %d", #ScannerData.RocksFound),
        string.format("Total de Partes Profundas (Y < -2): %d", #ScannerData.DeepZones),
        "\n[TOP 10 ROCAS / ESTRUCTURAS MÁS CERCANAS Y SUS PROFUNDIDADES]:"
    }

    for i = 1, math.min(10, #ScannerData.RocksFound) do
        local r = ScannerData.RocksFound[i]
        table.insert(out, string.format(" • '%s' | Pos: (%.1f, %.1f, %.1f) | Profundidad Y: %.1f", r.Name, r.Pos.X, r.Pos.Y, r.Pos.Z, r.Depth))
    end

    table.insert(out, "\n[HISTORIAL DE ACCIONES]:")
    for _, l in ipairs(ScannerData.Logs) do table.insert(out, " " .. l) end

    return table.concat(out, "\n")
end

-- Botón 1: Escanear y Colorear
local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -10, 0, 38)
ScanBtn.Position = UDim2.new(0, 10, 0, 365)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
ScanBtn.Text = "🔍 ESCANEAR ROCAS Y PROFUNDIDADES"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 10
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ ESCANEANDO..."
    scanUndergroundTerrain()
    OutputBox.Text = buildReportText()
    ScanBtn.Text = "✅ ¡ESCANEO Y COLORACIÓN LISTOS!"
    task.wait(1.5)
    ScanBtn.Text = "🔍 ESCANEAR ROCAS Y PROFUNDIDADES"
end)

-- Botón 2: Teletransporte de prueba a Y = -15
local TeleportBtn = Instance.new("TextButton")
TeleportBtn.Size = UDim2.new(0.48, -10, 0, 38)
TeleportBtn.Position = UDim2.new(0.52, 0, 0, 365)
TeleportBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 180)
TeleportBtn.Text = "⚡ TELEPORT DE PRUEBA (Y = -15)"
TeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportBtn.TextSize = 10
TeleportBtn.Font = Enum.Font.GothamBold
TeleportBtn.Parent = MainFrame

TeleportBtn.MouseButton1Click:Connect(function()
    testTeleportToDepth(-15.0)
    TeleportBtn.Text = "⚡ ¡TELEPORT REALIZADO!"
    task.wait(1.5)
    TeleportBtn.Text = "⚡ TELEPORT DE PRUEBA (Y = -15)"
end)

-- Botón flotante para abrir/cerrar
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 120)
FloatBtn.Text = "🗺️"
FloatBtn.TextSize = 20
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
