-- ==============================================================================
-- ESCÁNER DE ROCAS CON HIGHLIGHT (SIN CIEGOS, 100% VISIBLE)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local FoundRocks = {}

local function scanRealRocks()
    -- Limpiar highlights anteriores si ya se habían creado
    for _, obj in ipairs(FoundRocks) do
        if obj.Highlight and obj.Highlight.Parent then
            obj.Highlight:Destroy()
        end
    end
    FoundRocks = {}

    local baseCenter = Vector3.new(0, 0, 0)

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 300 then
                local nameLower = desc.Name:lower()
                -- Detectar rocas reales por nombre o tamaño específico de piedra
                if nameLower:find("rock") or nameLower:find("stone") or nameLower:find("boulder") or nameLower:find("piedra") or nameLower:find("roca") then
                    
                    -- Crear el Highlight limpio (efecto tipo Roblox studio / ESP)
                    local hl = Instance.new("Highlight")
                    hl.Name = "RockHighlight"
                    hl.Adornee = desc
                    hl.FillColor = Color3.fromRGB(0, 255, 180)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5
                    hl.OutlineTransparency = 0
                    hl.Parent = CoreGui

                    table.insert(FoundRocks, {
                        Part = desc,
                        Name = desc.Name,
                        Pos = pos,
                        Highlight = hl
                    })
                end
            end
        end
    end
    print(string.format("🪨 [ROCAS]: Se detectaron y marcaron %d rocas.", #FoundRocks))
end

-- Interfaz flotante de control
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RockScannerMenuGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 52, 0, 52)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 100)
FloatBtn.Text = "🪨\nROCKS"
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
MainFrame.Size = UDim2.new(0, 460, 0, 380)
MainFrame.Position = UDim2.new(0.5, -230, 0.5, -190)
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
TitleBar.Text = "  🪨 MAPEO DE ROCAS CON HIGHLIGHT"
TitleBar.TextColor3 = Color3.fromRGB(0, 255, 180)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(1, -20, 0, 34)
ScanBtn.Position = UDim2.new(0, 10, 0, 46)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
ScanBtn.Text = "🔍 ESCANEAR Y MARCAR ROCAS"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 10
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

local ScanCorner = Instance.new("UICorner")
ScanCorner.CornerRadius = UDim.new(0, 6)
ScanCorner.Parent = ScanBtn

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 0, 270)
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

    for _, obj in ipairs(FoundRocks) do
        local tpBtn = Instance.new("TextButton")
        tpBtn.Size = UDim2.new(1, -4, 0, 30)
        tpBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
        tpBtn.Text = string.format("🪨 %s | Pos: (%.0f, %.0f, %.0f)", obj.Name, obj.Pos.X, obj.Pos.Y, obj.Pos.Z)
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

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #FoundRocks * 34)
end

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ ESCANEANDO..."
    scanRealRocks()
    populateList()
    ScanBtn.Text = string.format("✅ %d ROCAS MARCADAS", #FoundRocks)
    task.wait(1.5)
    ScanBtn.Text = "🔍 ESCANEAR Y MARCAR ROCAS"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Escaneo inicial
scanRealRocks()
populateList()
