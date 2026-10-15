-- ==============================================================================
-- EXPLORADOR FORENSE DE TERRENO V6 (CLICK-INSPECTOR + RANKING DE PROFUNDIDAD)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()
local cam = workspace.CurrentCamera

local State = {
    ClickInspect = false,
    CurrentInspected = nil,
    InspectedHighlight = nil,
    MassHighlights = {},
    FilteredObjects = {}
}

-- Cursor siempre activo para dispositivos móviles/emuladores
RunService.RenderStepped:Connect(function()
    UserInputService.MouseIconEnabled = true
end)

local function clearMassHighlights()
    for _, hl in ipairs(State.MassHighlights) do
        if hl and hl.Parent then hl:Destroy() end
    end
    State.MassHighlights = {}
end

local function setInspectHighlight(targetPart)
    if State.InspectedHighlight and State.InspectedHighlight.Parent then
        State.InspectedHighlight:Destroy()
        State.InspectedHighlight = nil
    end

    if targetPart then
        local hl = Instance.new("Highlight")
        hl.Name = "InspectedHighlight"
        hl.Adornee = targetPart
        hl.FillColor = Color3.fromRGB(255, 230, 0)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.35
        hl.OutlineTransparency = 0
        hl.Parent = CoreGui
        State.InspectedHighlight = hl
    end
end

-- ==============================================================================
-- 1. CLASIFICADOR Y RANKING DE PROFUNDIDAD (Y MÁS BAJA = MÁS ENTERRADO)
-- ==============================================================================

local function getPartBottomDepth(part)
    -- Calcula el punto físico más bajo de la pieza (Posición Y menos la mitad de su altura)
    return part.Position.Y - (part.Size.Y * 0.5)
end

local function scanAndRankTerrain(keyword)
    clearMassHighlights()
    State.FilteredObjects = {}
    local baseCenter = Vector3.new(0, 0, 0)
    keyword = (keyword or ""):lower()

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 350 then
                local nLower = desc.Name:lower()
                local isCharacterPart = desc:FindFirstAncestorOfClass("Model") == lp.Character
                
                if not isCharacterPart and (keyword == "" or nLower:find(keyword)) then
                    local bottomY = getPartBottomDepth(desc)
                    table.insert(State.FilteredObjects, {
                        Part = desc,
                        Name = desc.Name,
                        Class = desc.ClassName,
                        Pos = pos,
                        Size = desc.Size,
                        BottomY = bottomY,
                        CenterY = pos.Y
                    })
                end
            end
        end
    end

    -- Ordenar de mayor profundidad a menor (los más enterrados primero: valores de Y más negativos arriba)
    table.sort(State.FilteredObjects, function(a, b)
        return a.BottomY < b.BottomY
    end)

    -- Iluminar los primeros 40 más enterrados del filtro
    for i = 1, math.min(40, #State.FilteredObjects) do
        local obj = State.FilteredObjects[i]
        local hl = Instance.new("Highlight")
        hl.Name = "RankHighlight"
        hl.Adornee = obj.Part
        hl.FillColor = Color3.fromRGB(0, 190, 255)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
        hl.Parent = CoreGui
        table.insert(State.MassHighlights, hl)
    end
end

-- ==============================================================================
-- 2. INTERFAZ GRÁFICA FLOTANTE (ESTILO TÁCTIL / DELTA)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TerrainInspectorGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 54, 0, 54)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 120, 110)
FloatBtn.Text = "🔍\nTOOL"
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
MainFrame.Size = UDim2.new(0, 510, 0, 480)
MainFrame.Position = UDim2.new(0.5, -255, 0.5, -240)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
TitleBar.Text = "  🔍 INSPECTOR CON CLICK & RANKING DE PROFUNDIDAD"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 190)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Panel de información del objeto seleccionado con el mouse
local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -20, 0, 80)
InfoCard.Position = UDim2.new(0, 10, 0, 44)
InfoCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
InfoCard.Parent = MainFrame

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 6)
InfoCorner.Parent = InfoCard

local InfoTitle = Instance.new("TextLabel")
InfoTitle.Size = UDim2.new(1, -12, 0, 20)
InfoTitle.Position = UDim2.new(0, 6, 0, 4)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = "📌 Objeto Seleccionado: (Ninguno)"
InfoTitle.TextColor3 = Color3.fromRGB(255, 230, 80)
InfoTitle.TextSize = 10
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.TextXAlignment = Enum.TextXAlignment.Left
InfoTitle.Parent = InfoCard

local InfoDetails = Instance.new("TextLabel")
InfoDetails.Size = UDim2.new(1, -12, 0, 48)
InfoDetails.Position = UDim2.new(0, 6, 0, 26)
InfoDetails.BackgroundTransparency = 1
InfoDetails.Text = "Haz click en 'MODO CLICK' y toca cualquier cosa en la pantalla (árbol, roca, pasto, suelo) para extraer su nombre exacto y profundidad."
InfoDetails.TextColor3 = Color3.fromRGB(200, 200, 200)
InfoDetails.TextSize = 9
InfoDetails.Font = Enum.Font.Code
InfoDetails.TextWrapped = true
InfoDetails.TextXAlignment = Enum.TextXAlignment.Left
InfoDetails.TextYAlignment = Enum.TextYAlignment.Top
InfoDetails.Parent = InfoCard

-- Botones de acción rápida
local ClickModeBtn = Instance.new("TextButton")
ClickModeBtn.Size = UDim2.new(0.48, -10, 0, 32)
ClickModeBtn.Position = UDim2.new(0, 10, 0, 130)
ClickModeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
ClickModeBtn.Text = "🎯 MODO CLICK: OFF"
ClickModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClickModeBtn.TextSize = 10
ClickModeBtn.Font = Enum.Font.GothamBold
ClickModeBtn.Parent = MainFrame

local ClickCorner = Instance.new("UICorner")
ClickCorner.CornerRadius = UDim.new(0, 6)
ClickCorner.Parent = ClickModeBtn

local CopyNameBtn = Instance.new("TextButton")
CopyNameBtn.Size = UDim2.new(0.48, -10, 0, 32)
CopyNameBtn.Position = UDim2.new(0.52, 0, 0, 130)
CopyNameBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 170)
CopyNameBtn.Text = "📋 COPIAR NOMBRE EXACTO"
CopyNameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyNameBtn.TextSize = 10
CopyNameBtn.Font = Enum.Font.GothamBold
CopyNameBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyNameBtn

-- Barra de filtro y búsqueda
local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(0.55, -10, 0, 32)
SearchBox.Position = UDim2.new(0, 10, 0, 168)
SearchBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
SearchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBox.PlaceholderText = "Filtrar (ej. rock, tree, ground)..."
SearchBox.Text = ""
SearchBox.TextSize = 10
SearchBox.Font = Enum.Font.Code
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = MainFrame

local SearchBoxCorner = Instance.new("UICorner")
SearchBoxCorner.CornerRadius = UDim.new(0, 6)
SearchBoxCorner.Parent = SearchBox

local FilterBtn = Instance.new("TextButton")
FilterBtn.Size = UDim2.new(0.45, -10, 0, 32)
FilterBtn.Position = UDim2.new(0.55, 0, 0, 168)
FilterBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
FilterBtn.Text = "📊 ORDENAR POR PROFUNDIDAD"
FilterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FilterBtn.TextSize = 9
FilterBtn.Font = Enum.Font.GothamBold
FilterBtn.Parent = MainFrame

local FilterBtnCorner = Instance.new("UICorner")
FilterBtnCorner.CornerRadius = UDim.new(0, 6)
FilterBtnCorner.Parent = FilterBtn

-- Lista con Scroll
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 0, 260)
ScrollFrame.Position = UDim2.new(0, 10, 0, 206)
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

-- ==============================================================================
-- 3. FUNCIONES DE ACTUALIZACIÓN DE LISTA Y CLICKS
-- ==============================================================================

local function updateScrollList()
    for _, child in ipairs(ScrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    for rank, obj in ipairs(State.FilteredObjects) do
        local itemBtn = Instance.new("TextButton")
        itemBtn.Size = UDim2.new(1, -6, 0, 36)
        itemBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
        itemBtn.Text = string.format("#%d [%s] Base Y: %.1f | Centro: (%.0f, %.0f, %.0f)", rank, obj.Name, obj.BottomY, obj.Pos.X, obj.CenterY, obj.Pos.Z)
        itemBtn.TextColor3 = (obj.BottomY <= -5) and Color3.fromRGB(0, 255, 180) or Color3.fromRGB(220, 220, 220)
        itemBtn.TextSize = 9
        itemBtn.Font = Enum.Font.Code
        itemBtn.TextXAlignment = Enum.TextXAlignment.Left
        itemBtn.Parent = ScrollFrame

        local itemCorner = Instance.new("UICorner")
        itemCorner.CornerRadius = UDim.new(0, 4)
        itemCorner.Parent = itemBtn

        -- Al hacer click en la lista: iluminar y teletransportarse encima
        itemBtn.MouseButton1Click:Connect(function()
            State.CurrentInspected = obj.Part
            setInspectHighlight(obj.Part)
            InfoTitle.Text = string.format("📌 #%d: '%s' (%s)", rank, obj.Name, obj.Class)
            InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)\nRuta: %s", obj.BottomY, obj.CenterY, obj.Size.X, obj.Size.Y, obj.Size.Z, obj.Part:GetFullName())

            local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(obj.Pos + Vector3.new(0, (obj.Size.Y * 0.5) + 3.5, 0))
                root.AssemblyLinearVelocity = Vector3.zero
            end
        end)
    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #State.FilteredObjects * 40)
end

-- Lógica para seleccionar con el cursor en pantalla
local function handleWorldClick()
    if not State.ClickInspect then return end

    local targetPart = mouse.Target
    if targetPart and targetPart:IsA("BasePart") then
        local isSelf = targetPart:FindFirstAncestorOfClass("Model") == lp.Character
        if isSelf then return end

        State.CurrentInspected = targetPart
        setInspectHighlight(targetPart)

        local bottomY = getPartBottomDepth(targetPart)
        InfoTitle.Text = string.format("📌 Click en: '%s' (%s)", targetPart.Name, targetPart.ClassName)
        InfoDetails.Text = string.format("Base Y: %.2f | Centro Y: %.2f | Tamaño: (%.1f, %.1f, %.1f)\nRuta: %s", bottomY, targetPart.Position.Y, targetPart.Size.X, targetPart.Size.Y, targetPart.Size.Z, targetPart:GetFullName())
        SearchBox.Text = targetPart.Name
    end
end

mouse.Button1Down:Connect(handleWorldClick)

-- Botón Activar / Desactivar Inspección por Click
ClickModeBtn.MouseButton1Click:Connect(function()
    State.ClickInspect = not State.ClickInspect
    if State.ClickInspect then
        ClickModeBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
        ClickModeBtn.Text = "🎯 MODO CLICK: ACTIVO"
    else
        ClickModeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 50)
        ClickModeBtn.Text = "🎯 MODO CLICK: OFF"
    end
end)

-- Botón Copiar Nombre
CopyNameBtn.MouseButton1Click:Connect(function()
    if State.CurrentInspected then
        local txt = State.CurrentInspected.Name
        if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
        CopyNameBtn.Text = "✅ ¡COPIADO!"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE EXACTO"
    else
        CopyNameBtn.Text = "⚠️ NADA SELECCIONADO"
        task.wait(1.2)
        CopyNameBtn.Text = "📋 COPIAR NOMBRE EXACTO"
    end
end)

-- Botón Ordenar y Filtrar
FilterBtn.MouseButton1Click:Connect(function()
    FilterBtn.Text = "⏳ ANALIZANDO..."
    scanAndRankTerrain(SearchBox.Text)
    updateScrollList()
    FilterBtn.Text = string.format("✅ %d ORDENADOS", #State.FilteredObjects)
    task.wait(1.2)
    FilterBtn.Text = "📊 ORDENAR POR PROFUNDIDAD"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Carga inicial completa
scanAndRankTerrain("")
updateScrollList()
