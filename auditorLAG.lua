-- ==============================================================================
-- AUDITOR Y COMPARADOR DE FUGAS DE MEMORIA (MEMORY LEAK DETECTOR)
-- ==============================================================================

local StatsService = game:GetService("Stats")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Snapshot1 = nil
local Snapshot2 = nil
local CurrentFPS = 60

-- Monitor de FPS
local frameCount = 0
local lastFpsUpdate = tick()
RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    local now = tick()
    if now - lastFpsUpdate >= 1.0 then
        CurrentFPS = math.floor(frameCount / (now - lastFpsUpdate))
        frameCount = 0
        lastFpsUpdate = now
    end
end)

-- Obtener memoria desglosada
local function getDetailedMemory()
    local memData = {
        TotalMB = math.floor(StatsService:GetTotalMemoryUsageMb()),
        LuaHeapMB = math.floor(collectgarbage("count") / 1024)
    }

    local tags = {
        "Internal", "HttpCache", "Instances", "Signals", "LuaHeap",
        "Script", "PhysicsParts", "GeometryCSG", "Sounds", "SpatialHash",
        "Lighting", "Terrain", "Gui", "Animation"
    }

    for _, tag in ipairs(tags) do
        pcall(function()
            local enumVal = Enum.DeveloperMemoryTag[tag]
            if enumVal then
                memData[tag] = math.floor(StatsService:GetMemoryUsageMbForTag(enumVal))
            end
        end)
    end

    return memData
end

-- Auditoría exhaustiva de instancias en el mapa
local function scanWorldInstances()
    local data = {
        TotalInstances = 0,
        WorkspaceCount = #workspace:GetDescendants(),
        ReplicatedCount = #game:GetService("ReplicatedStorage"):GetDescendants(),
        GuiCount = (lp:FindFirstChild("PlayerGui") and #lp.PlayerGui:GetDescendants()) or 0,
        
        Classes = {},
        Keywords = {
            Blood = 0,
            Scrap = 0,
            Zombie = 0,
            Bullet = 0,
            Debris = 0,
            Corpse = 0,
            Smoke = 0,
            Sound = 0,
            Highlight = 0
        }
    }

    for _, inst in ipairs(workspace:GetDescendants()) do
        data.TotalInstances = data.TotalInstances + 1

        -- Contar por clase
        local cName = inst.ClassName
        data.Classes[cName] = (data.Classes[cName] or 0) + 1

        -- Contar por palabras clave de lag común
        local lowerName = inst.Name:lower()
        if lowerName:find("blood") or lowerName:find("sangre") or lowerName:find("splat") then
            data.Keywords.Blood = data.Keywords.Blood + 1
        end
        if lowerName:find("scrap") or lowerName:find("chatarra") or lowerName:find("metal") or lowerName:find("barrel") then
            data.Keywords.Scrap = data.Keywords.Scrap + 1
        end
        if lowerName:find("zombie") or lowerName:find("phaser") or lowerName:find("crawler") or lowerName:find("bloat") then
            data.Keywords.Zombie = data.Keywords.Zombie + 1
        end
        if lowerName:find("bullet") or lowerName:find("proj") or lowerName:find("tracer") then
            data.Keywords.Bullet = data.Keywords.Bullet + 1
        end
        if lowerName:find("debris") or lowerName:find("gib") or lowerName:find("ragdoll") then
            data.Keywords.Debris = data.Keywords.Debris + 1
        end
        if lowerName:find("corpse") or lowerName:find("dead") or lowerName:find("body") then
            data.Keywords.Corpse = data.Keywords.Corpse + 1
        end
        if inst:IsA("ParticleEmitter") or inst:IsA("Smoke") or inst:IsA("Fire") then
            data.Keywords.Smoke = data.Keywords.Smoke + 1
        end
        if inst:IsA("Sound") then
            data.Keywords.Sound = data.Keywords.Sound + 1
        end
        if inst:IsA("Highlight") then
            data.Keywords.Highlight = data.Keywords.Highlight + 1
        end
    end

    return data
end

-- Capturar un registro completo
local function takeSnapshot(label)
    local snap = {
        Label = label,
        Timestamp = os.date("%H:%M:%S"),
        FPS = CurrentFPS,
        Memory = getDetailedMemory(),
        World = scanWorldInstances()
    }
    return snap
end

-- Generar reporte comparativo
local function generateComparisonReport()
    if not Snapshot1 then
        return "ERROR: Falta tomar el Registro 1 (Inicio Limpio)."
    end
    if not Snapshot2 then
        return "ERROR: Falta tomar el Registro 2 (Con Lag tras explorar)."
    end

    local r = {}
    local function add(str) table.insert(r, str) end

    add("================ REPORTE COMPARATIVO DE MEMORIA ================")
    add(string.format("Registro 1 [%s]: %d FPS | RAM: %d MB", Snapshot1.Timestamp, Snapshot1.FPS, Snapshot1.Memory.TotalMB))
    add(string.format("Registro 2 [%s]: %d FPS | RAM: %d MB", Snapshot2.Timestamp, Snapshot2.FPS, Snapshot2.Memory.TotalMB))
    
    local ramDiff = Snapshot2.Memory.TotalMB - Snapshot1.Memory.TotalMB
    local instDiff = Snapshot2.World.TotalInstances - Snapshot1.World.TotalInstances
    add(string.format("\n-> DIFERENCIA TOTAL RAM: %+d MB", ramDiff))
    add(string.format("-> DIFERENCIA INSTANCIAS: %+d objetos en Workspace", instDiff))

    add("\n--- [1. DESGLOSE DE FUGA DE MEMORIA (RAM TAGS)] ---")
    for tag, val2 in pairs(Snapshot2.Memory) do
        local val1 = Snapshot1.Memory[tag] or 0
        local diff = val2 - val1
        if diff ~= 0 then
            add(string.format("   [%s]: %d MB -> %d MB  (Delta: %+d MB)", tag, val1, val2, diff))
        end
    end

    add("\n--- [2. OBJETOS SOSPECHOSOS MULTIPLICADOS (PALABRAS CLAVE)] ---")
    for kw, count2 in pairs(Snapshot2.World.Keywords) do
        local count1 = Snapshot1.World.Keywords[kw] or 0
        local diff = count2 - count1
        add(string.format("   %s: Inicial=%d -> Final=%d (Delta: %+d)", kw, count1, count2, diff))
    end

    add("\n--- [3. TOP CLASES QUE MÁS SE DUPLICARON] ---")
    local classDiffs = {}
    for cName, count2 in pairs(Snapshot2.World.Classes) do
        local count1 = Snapshot1.World.Classes[cName] or 0
        local diff = count2 - count1
        if diff > 0 then
            table.insert(classDiffs, {Class = cName, Delta = diff, Now = count2})
        end
    end
    table.sort(classDiffs, function(a, b) return a.Delta > b.Delta end)

    for i = 1, math.min(10, #classDiffs) do
        local item = classDiffs[i]
        add(string.format("   #%d [%s]: %+d creados (Total actual: %d)", i, item.Class, item.Delta, item.Now))
    end

    add("\n================ FIN DEL REPORTE ================")
    return table.concat(r, "\n")
end

-- ================= INTERFAZ GRÁFICA VISUAL =================
local existing = game:GetService("CoreGui"):FindFirstChild("MemAuditGUI") or lp.PlayerGui:FindFirstChild("MemAuditGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MemAuditGUI"
ScreenGui.ResetOnSpawn = false

if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 440)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 40)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.Text = "⚡ AUDITOR DE FUGA DE MEMORIA & LAG"
Title.TextColor3 = Color3.fromRGB(0, 220, 255)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -38, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
CloseBtn.Parent = MainFrame
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- Medidor en vivo
local LiveBar = Instance.new("TextLabel")
LiveBar.Size = UDim2.new(1, -30, 0, 30)
LiveBar.Position = UDim2.new(0, 15, 0, 42)
LiveBar.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
LiveBar.TextColor3 = Color3.fromRGB(0, 255, 170)
LiveBar.Font = Enum.Font.Code
LiveBar.TextSize = 13
LiveBar.Text = "RAM: 0 MB | FPS: 60 | Workspace: 0 partes"
LiveBar.Parent = MainFrame
local LiveCorner = Instance.new("UICorner")
LiveCorner.CornerRadius = UDim.new(0, 6)
LiveCorner.Parent = LiveBar

task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.5)
        LiveBar.Text = string.format("RAM: %d MB | FPS: %d | Workspace: %d partes", 
            math.floor(StatsService:GetTotalMemoryUsageMb()), 
            CurrentFPS, 
            #workspace:GetDescendants()
        )
    end
end)

-- Botón 1: Registro Inicial
local Btn1 = Instance.new("TextButton")
Btn1.Size = UDim2.new(0.48, -15, 0, 36)
Btn1.Position = UDim2.new(0, 15, 0, 80)
Btn1.Text = "1️⃣ Registro Limpio (Inicio)"
Btn1.TextColor3 = Color3.fromRGB(255, 255, 255)
Btn1.TextSize = 12
Btn1.Font = Enum.Font.GothamBold
Btn1.BackgroundColor3 = Color3.fromRGB(0, 150, 90)
Btn1.Parent = MainFrame
local B1Corner = Instance.new("UICorner")
B1Corner.CornerRadius = UDim.new(0, 6)
B1Corner.Parent = Btn1

-- Botón 2: Registro con Lag
local Btn2 = Instance.new("TextButton")
Btn2.Size = UDim2.new(0.48, -15, 0, 36)
Btn2.Position = UDim2.new(0.52, 5, 0, 80)
Btn2.Text = "2️⃣ Registro con Lag (Final)"
Btn2.TextColor3 = Color3.fromRGB(255, 255, 255)
Btn2.TextSize = 12
Btn2.Font = Enum.Font.GothamBold
Btn2.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
Btn2.Parent = MainFrame
local B2Corner = Instance.new("UICorner")
B2Corner.CornerRadius = UDim.new(0, 6)
B2Corner.Parent = Btn2

-- Área de texto para visualizar
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -30, 0, 215)
Scroll.Position = UDim2.new(0, 15, 0, 125)
Scroll.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.Parent = MainFrame
local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 8)
ScrollCorner.Parent = Scroll

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -10, 1, 0)
TextBox.Position = UDim2.new(0, 5, 0, 5)
TextBox.Text = "INSTRUCCIONES:\n1. Al entrar a una partida fresca, presiona '1️⃣ Registro Limpio (Inicio)'.\n2. Ponte a jugar, explorar o patrullar hasta que sientas el bajón de FPS o suba la RAM.\n3. Presiona '2️⃣ Registro con Lag (Final)'.\n4. Presiona el botón verde de abajo para copiar la comparación y pégala aquí."
TextBox.TextColor3 = Color3.fromRGB(220, 220, 220)
TextBox.TextSize = 12
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -30, 0, 42)
CopyBtn.Position = UDim2.new(0, 15, 1, -52)
CopyBtn.Text = "⚖️ COMPARAR Y COPIAR AL PORTAPAPELES"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 13
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
CopyBtn.Parent = MainFrame
local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 8)
CopyCorner.Parent = CopyBtn

-- Acciones de botones
Btn1.MouseButton1Click:Connect(function()
    Btn1.Text = "Analizando..."
    task.wait(0.1)
    Snapshot1 = takeSnapshot("Inicio Limpio")
    Btn1.Text = string.format("✅ R1: %d MB (%d Partes)", Snapshot1.Memory.TotalMB, Snapshot1.World.TotalInstances)
    Btn1.BackgroundColor3 = Color3.fromRGB(30, 100, 60)
    TextBox.Text = string.format("Registro 1 guardado con éxito a las %s.\nMemoria inicial: %d MB | FPS: %d\nAhora sal a explorar o patrullar hasta que sientas el lag.", Snapshot1.Timestamp, Snapshot1.Memory.TotalMB, Snapshot1.FPS)
end)

Btn2.MouseButton1Click:Connect(function()
    if not Snapshot1 then
        TextBox.Text = "⚠️ Primero debes tomar el 'Registro Limpio' antes de tomar el de lag."
        return
    end
    Btn2.Text = "Analizando..."
    task.wait(0.1)
    Snapshot2 = takeSnapshot("Con Lag")
    Btn2.Text = string.format("✅ R2: %d MB (%d Partes)", Snapshot2.Memory.TotalMB, Snapshot2.World.TotalInstances)
    Btn2.BackgroundColor3 = Color3.fromRGB(130, 40, 40)
    
    local reportText = generateComparisonReport()
    TextBox.Text = reportText
    Scroll.CanvasSize = UDim2.new(0, 0, 0, 700)
end)

CopyBtn.MouseButton1Click:Connect(function()
    local text = generateComparisonReport()
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "¡REPORTE COMPARATIVO COPIADO!"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    task.wait(1.5)
    CopyBtn.Text = "⚖️ COMPARAR Y COPIAR AL PORTAPAPELES"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
end)
