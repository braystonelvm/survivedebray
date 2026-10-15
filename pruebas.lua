-- ==============================================================================
-- MENÚ COMPLETO DE MAPEO Y HIGHLIGHT PRO (NOMBRES, FILTROS Y TELEPORT)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local MarkedObjects = {}

-- Función para limpiar todos los highlights actuales
local function clearAllHighlights()
    for _, obj in ipairs(MarkedObjects) do
        if obj.Highlight and obj.Highlight.Parent then
            obj.Highlight:Destroy()
        end
    end
    MarkedObjects = {}
end

-- Función de búsqueda por nombre o filtro parcial
local function scanElementsByName(keyword)
    clearAllHighlights()
    local baseCenter = Vector3.new(0, 0, 0)
    keyword = keyword:lower()

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 350 then
                local nameLower = desc.Name:lower()
                -- Si coincide con el filtro o si el filtro está vacío (busca grandes por defecto)
                if keyword == "" or nameLower:find(keyword) then
                    local hl = Instance.new("Highlight")
                    hl.Name = "CustomHighlight"
                    hl.Adornee = desc
                    hl.FillColor = Color3.fromRGB(0, 220, 255)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.4
                    hl.OutlineTransparency = 0
                    hl.Parent = CoreGui

                    table.insert(MarkedObjects, {
                        Part = desc,
                        Name = desc.Name,
                        Class = desc.ClassName,
                        Pos = pos,
                        Highlight = hl
                    })
                end
            end
        end
    end
    print(string.format("🌐 [MAPPER PRO]: Se marcaron %d elementos con el filtro '%s'.", #MarkedObjects, keyword))
end

-- ==============================================================================
-- INTERFAZ FLOTANTE Y MENÚ TÁCTIL COMPLETO
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AdvancedMapperMenuGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 52, 0, 52)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 120, 110)
FloatBtn.Text = "🛠️\nMAP"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 440)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -220)
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
TitleBar.Text = "  🛠️ MENÚ PRO: MAPEO Y FILTRO DE NOMBRES"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 180)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Caja de Texto para escribir el nombre o palabra clave a buscar
local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(0.65, -10, 0, 34)
SearchBox.Position = UDim2.new(0, 10, 0, 46)
SearchBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
SearchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBox.PlaceholderText = "Escribe nombre (ej. rock, tree)..."
SearchBox.Text = "rock"
SearchBox.TextSize = 10
SearchBox.Font = Enum.Font.Code
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = MainFrame

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 6)
SearchCorner.Parent = SearchBox

-- Botón de Buscar / Iluminar
local SearchBtn = Instance.new("TextButton")
SearchBtn.Size = UDim2.new(0.35, -15, 0, 34)
SearchBtn.Position = UDim2.new(0.65, 5, 0, 46)
SearchBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 90)
SearchBtn.Text = "🔍 FILTRAR"
SearchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBtn.TextSize = 10
SearchBtn.Font = Enum.Font.GothamBold
SearchBtn.Parent = MainFrame

local SearchCornerBtn = Instance.new("UICorner")
SearchCornerBtn.CornerRadius = UDim.new(0, 6)
SearchCornerBtn.Parent = SearchBtn

-- Contenedor de la Lista
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 0, 310)
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

local function populateList()
    for _, child in ipairs(ScrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    for _, obj in ipairs(MarkedObjects) do
        local tpBtn = Instance.new("TextButton")
        tpBtn.Size = UDim2.new(1, -4, 0, 32)
        tpBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
        tpBtn.Text = string.format("[%s] %s | Pos: (%.0f, %.0f, %.0f)", obj.Class, obj.Name, obj.Pos.X, obj.Pos.Y, obj.Pos.Z)
        tpBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
        tpBtn.TextSize = 9
        tpBtn.Font = Enum.Font.Code
        tpBtn.TextXAlignment = Enum.TextXAlignment.Left
        tpBtn.Parent = ScrollFrame

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = tpBtn

        tpBtn.MouseButton1Click:Connect(function()
            local _, root = lp.Character, lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(obj.Pos + Vector3.new(0, 5, 0))
                root.AssemblyLinearVelocity = Vector3.zero
            end
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #MarkedObjects * 36)
end

SearchBtn.MouseButton1Click:Connect(function()
    SearchBtn.Text = "⏳ BUSCANDO..."
    scanElementsByName(SearchBox.Text)
    populateList()
    SearchBtn.Text = string.format("✅ (%d) ENCONTRADOS", #MarkedObjects)
    task.wait(1.5)
    SearchBtn.Text = "🔍 FILTRAR"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Búsqueda inicial por defecto con la palabra "rock"
scanElementsByName("rock")
populateList()
