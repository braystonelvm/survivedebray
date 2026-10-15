-- ==============================================================================
-- MENÚ TÁCTIL DE MAPEO SUBTERRÁNEO, TRANSPARENCIA Y TELEPORT (300 STUDS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local MapObjects = {}
local isTransparentActive = false

-- ==============================================================================
-- 1. ESCÁNER DE ELEMENTOS GRANDES BAJO TIERRA
-- ==============================================================================
local function scanLargeObjects()
    MapObjects = {}
    local baseCenter = Vector3.new(0, 0, 0)

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 300 then
                local nameLower = desc.Name:lower()
                -- Filtrar rocas y estructuras grandes (evitar piezas diminutas de pasto o suelo)
                if (nameLower:find("rock") or nameLower:find("stone") or nameLower:find("boulder") or nameLower:find("piedra") or nameLower:find("roca") or nameLower:find("cliff")) and (desc.Size.X >= 5 or desc.Size.Z >= 5) then
                    table.insert(MapObjects, {
                        Part = desc,
                        Name = desc.Name,
                        Pos = pos,
                        Size = desc.Size
                    })
                end
            end
        end
    end
    print(string.format("🗺️ [MAPPER]: Se encontraron %d rocas/elementos grandes.", #MapObjects))
end

-- ==============================================================================
-- 2. ALTERNAR TRANSPARENCIA (GHOST RENDER) Y BRILLO NEON
-- ==============================================================================
local function toggleTransparency(state)
    isTransparentActive = state
    for _, obj in ipairs(MapObjects) do
        if obj.Part and obj.Part.Parent then
            if state then
                obj.Part.Transparency = 0.65 -- Translúcido para ver a través
                obj.Part.Material = Enum.Material.Neon
                obj.Part.Color = Color3.fromRGB(0, 220, 255)
            else
                obj.Part.Transparency = 0 -- Estado original
                obj.Part.Material = Enum.Material.SmoothPlastic
            end
        end
    end
end

-- ==============================================================================
-- 3. INTERFAZ GRÁFICA FLOTANTE (MENÚ TÁCTIL COMPATIBLE CON DELTA)
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UndergroundMapMenuGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón flotante para abrir/cerrar el menú
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 52, 0, 52)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 130, 110)
FloatBtn.Text = "🗺️\nMAPA"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 11
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

-- Ventana Principal del Menú
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 400)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "  🗺️ MAPEO SUBTERRÁNEO & TELEPORT DE ROCAS"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 180)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Botón de Escaneo
local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -10, 0, 34)
ScanBtn.Position = UDim2.new(0, 10, 0, 46)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 75)
ScanBtn.Text = "🔍 1. ESCANEAR ELEMENTOS"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 10
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

local ScanCorner = Instance.new("UICorner")
ScanCorner.CornerRadius = UDim.new(0, 6)
ScanCorner.Parent = ScanBtn

-- Botón de Transparencia
local GhostBtn = Instance.new("TextButton")
GhostBtn.Size = UDim2.new(0.48, -10, 0, 34)
GhostBtn.Position = UDim2.new(0.52, 0, 0, 46)
GhostBtn.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
GhostBtn.Text = "👻 2. MODO TRANSLÚCIDO: OFF"
GhostBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
GhostBtn.TextSize = 10
GhostBtn.Font = Enum.Font.GothamBold
GhostBtn.Parent = MainFrame

local GhostCorner = Instance.new("UICorner")
GhostCorner.CornerRadius = UDim.new(0, 6)
GhostCorner.Parent = GhostBtn

GhostBtn.MouseButton1Click:Connect(function()
    toggleTransparency(not isTransparentActive)
    if isTransparentActive then
        GhostBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 80)
        GhostBtn.Text = "👻 2. MODO TRANSLÚCIDO: ON"
    else
        GhostBtn.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
        GhostBtn.Text = "👻 2. MODO TRANSLÚCIDO: OFF"
    end
end)

-- Contenedor Scrollable con la lista de rocas para teletransporte
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 0, 290)
ScrollFrame.Position = UDim2.new(0, 10, 0, 92)
ScrollFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = MainFrame

local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 6)
ScrollCorner.Parent = ScrollFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)
UIListLayout.Parent = ScrollFrame

-- Función para actualizar la lista de botones en el menú
local function populateObjectList()
    for _, child in ipairs(ScrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    for i, obj in ipairs(MapObjects) do
        local tpBtn = Instance.new("TextButton")
        tpBtn.Size = UDim2.new(1, -4, 0, 32)
        tpBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
        tpBtn.Text = string.format("🪨 %s | Pos: (%.0f, %.0f, %.0f) | Y: %.1f", obj.Name, obj.Pos.X, obj.Pos.Y, obj.Pos.Z, obj.Pos.Y)
        tpBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
        tpBtn.TextSize = 10
        tpBtn.Font = Enum.Font.Code
        tpBtn.TextXAlignment = Enum.TextXAlignment.Left
        tpBtn.Parent = ScrollFrame

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = tpBtn

        -- Acción de Teletransporte al hacer clic en la roca de la lista
        tpBtn.MouseButton1Click:Connect(function()
            local char, root = lp.Character, lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if root then
                -- Elevar ligeramente sobre la roca seleccionada
                root.CFrame = CFrame.new(obj.Pos + Vector3.new(0, 5, 0))
                root.AssemblyLinearVelocity = Vector3.zero
                print(string.Format("⚡ Teletransportado a la roca: %s en Y=%.1f", obj.Name, obj.Pos.Y))
            end
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #MapObjects * 36)
end

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ ESCANEANDO..."
    scanLargeObjects()
    populateObjectList()
    ScanBtn.Text = string.format("✅ %d ELEMENTOS CARGADOS", #MapObjects)
    task.wait(1.5)
    ScanBtn.Text = "🔍 1. ESCANEAR ELEMENTOS"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Escaneo inicial automático al cargar el script
scanLargeObjects()
populateObjectList()
