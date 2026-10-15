-- ==============================================================================
-- ESCÁNER UNIVERSAL DE TERRENO Y ROCAS PROFUNDAS (BRILLO NEÓN + TELEPORT)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local AllElements = {}

-- 1. Escaneo masivo sin importar el nombre (detecta cualquier roca o elemento grande)
local function scanAllTerrainObjects()
    AllElements = {}
    local baseCenter = Vector3.new(0, 0, 0)

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pos = desc.Position
            local dist = (pos - baseCenter).Magnitude

            if dist <= 300 then
                -- Seleccionamos elementos grandes o pesados que forman parte del mapa/rocas
                if desc.Size.X >= 4 or desc.Size.Y >= 4 or desc.Size.Z >= 4 then
                    local nameLower = desc.Name:lower()
                    -- Excluir partes del jugador o de la interfaz
                    if not nameLower:find("humanoid") and not nameLower:find("torso") and not nameLower:find("head") then
                        table.insert(AllElements, {
                            Part = desc,
                            Name = desc.Name,
                            Pos = pos,
                            Size = desc.Size,
                            Depth = pos.Y
                        })

                        -- Iluminar automáticamente de color neón brillante para verlos desde lejos
                        pcall(function()
                            desc.Material = Enum.Material.Neon
                            desc.Color = Color3.fromRGB(0, 255, 200)
                            desc.Transparency = 0.3 -- Semitranslúcido para ver a través
                        end)
                    end
                end
            end
        end
    end
    print(string.format("🗺️ [MAPPER UNIVERSAL]: %d elementos detectados e iluminados.", #AllElements))
end

-- ==============================================================================
-- 2. INTERFAZ FLOTANTE CON LISTA Y TELETRANSPORTE
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UniversalMapMenuGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 52, 0, 52)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 120)
FloatBtn.Text = "🌐\nMAPA"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 11
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

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
TitleBar.Text = "  🌐 MAPEO TOTAL: ELEMENTOS Y ROCAS ILUMINADAS"
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
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 90)
ScanBtn.Text = "🔍 ESCANEAR E ILUMINAR TODO EL MAPA"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 10
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

local ScanCorner = Instance.new("UICorner")
ScanCorner.CornerRadius = UDim.new(0, 6)
ScanCorner.Parent = ScanBtn

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

local function populateList()
    for _, child in ipairs(ScrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    for _, obj in ipairs(AllElements) do
        local tpBtn = Instance.new("TextButton")
        tpBtn.Size = UDim2.new(1, -4, 0, 32)
        tpBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
        tpBtn.Text = string.format("🪨 %s | Pos: (%.0f, %.0f, %.0f) | Y: %.1f", obj.Name, obj.Pos.X, obj.Pos.Y, obj.Pos.Z, obj.Depth)
        tpBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
        tpBtn.TextSize = 10
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

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #AllElements * 36)
end

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ ESCANEANDO TODO..."
    scanAllTerrainObjects()
    populateList()
    ScanBtn.Text = string.format("✅ %d ELEMENTOS ILUMINADOS", #AllElements)
    task.wait(1.5)
    ScanBtn.Text = "🔍 ESCANEAR E ILUMINAR TODO EL MAPA"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Ejecutar escaneo inicial al arrancar
scanAllTerrainObjects()
populateList()
