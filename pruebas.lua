-- ==============================================================================
-- ESCÁNER FORENSE: COMPARADOR DE ZANAHORIAS (NORMAL VS DORADA)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local function scanCarrotsAround()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return "⚠️ No se detectó a tu personaje." end

    local myPos = root.Position
    local report = {
        "==================================================================",
        "      REPORTE DE ZANAHORIAS EN EL SUELO (NORMAL VS DORADA)        ",
        "==================================================================",
        string.format("Mi Posición: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z),
        "\n[ZANAHORIAS Y ALIMENTOS DETECTADOS A MENOS DE 20 STUDS]:"
    }

    local dropped = workspace:FindFirstChild("DroppedItems") or workspace
    local foundCount = 0

    for _, item in ipairs(dropped:GetChildren()) do
        if (item:IsA("Model") or item:IsA("BasePart")) and item ~= char then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part then
                local dist = (part.Position - myPos).Magnitude
                if dist <= 20 then
                    local nameLower = item.Name:lower()
                    local isCarrot = nameLower:find("carrot") or nameLower:find("zanahoria") or item:GetAttribute("ItemType") == "Food"

                    if isCarrot then
                        foundCount = foundCount + 1
                        table.insert(report, string.format("\n🥕 OBJETO #%d: '%s' (ClassName: %s)", foundCount, item.Name, item.ClassName))
                        table.insert(report, "   Ruta: " .. item:GetFullName())
                        table.insert(report, string.format("   Distancia: %.1f studs | Pos: (%.1f, %.1f, %.1f)", dist, part.Position.X, part.Position.Y, part.Position.Z))

                        -- 1. Atributos del Servidor (Tier, Golden, Rarity, Heal, Variant, etc.)
                        local attrs = {}
                        for k, v in pairs(item:GetAttributes()) do
                            table.insert(attrs, string.format("%s = %s", tostring(k), tostring(v)))
                        end
                        if #attrs > 0 then
                            table.insert(report, "   [Atributos]: " .. table.concat(attrs, " | "))
                        else
                            table.insert(report, "   [Atributos]: (Sin atributos directos)")
                        end

                        -- 2. Colores y Materiales de sus partes físicas
                        local visualProps = {}
                        for _, p in ipairs(item:GetDescendants()) do
                            if p:IsA("BasePart") then
                                local c = p.Color
                                table.insert(visualProps, string.format("Part '%s' -> Color(%.2f, %.2f, %.2f) | Mat: %s", p.Name, c.R, c.G, c.B, tostring(p.Material.Name)))
                            end
                        end
                        if #visualProps > 0 then
                            table.insert(report, "   [Piezas Visuales]:\n     • " .. table.concat(visualProps, "\n     • "))
                        end

                        -- 3. Valores internos (StringValue, BoolValue, etc.)
                        local valList = {}
                        for _, vDesc in ipairs(item:GetDescendants()) do
                            if vDesc:IsA("ValueBase") then
                                table.insert(valList, string.format("%s('%s' = %s)", vDesc.ClassName, vDesc.Name, tostring(vDesc.Value)))
                            end
                        end
                        if #valList > 0 then
                            table.insert(report, "   [Valores Internos]: " .. table.concat(valList, " | "))
                        end
                    end
                end
            end
        end
    end

    if foundCount == 0 then
        table.insert(report, "\n⚠️ No se detectó ninguna zanahoria a menos de 20 studs. Acércate a las zanahorias.")
    end

    return table.concat(report, "\n")
end

-- ==============================================================================
-- INTERFAZ VISUAL FLOTANTE
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarrotCompareGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 420)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -210)
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
Title.Text = "  🥕 COMPARADOR FORENSE DE ZANAHORIAS"
Title.TextColor3 = Color3.fromRGB(255, 200, 40)
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
OutputBox.Text = scanCarrotsAround()
OutputBox.Parent = MainFrame

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 38)
CopyBtn.Position = UDim2.new(0, 10, 0, 365)
CopyBtn.BackgroundColor3 = Color3.fromRGB(210, 160, 20)
CopyBtn.Text = "📋 COPIAR DATOS DE ZANAHORIAS"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local txt = scanCarrotsAround()
    OutputBox.Text = txt
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR DATOS DE ZANAHORIAS"
end)

-- Botón flotante para minimizar
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(210, 160, 20)
FloatBtn.Text = "🥕"
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
