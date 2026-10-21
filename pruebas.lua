-- ==============================================================================
-- ESCÁNER FORENSE DE COFRE CERCANO (30 STUDS - CON BOTÓN COPIAR)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local function getRoot()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function scanNearbyChest()
    local root = getRoot()
    if not root then return "⚠️ No se detectó a tu personaje." end

    local myPos = root.Position
    local report = {
        "==================================================================",
        "          REPORTE DE OBJETOS CERCANOS AL JUGADOR (30 STUDS)       ",
        "==================================================================",
        string.format("Mi Posición: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z),
        "\n[OBJETOS / MODELOS CERCANOS DETECTADOS]:"
    }

    local foundCount = 0

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("Model") and desc ~= lp.Character then
            local part = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")
            if part then
                local dist = (part.Position - myPos).Magnitude
                if dist <= 30 then
                    foundCount = foundCount + 1
                    table.insert(report, string.format("\n📦 MODELO #%d: '%s' (ClassName: %s)", foundCount, desc.Name, desc.ClassName))
                    table.insert(report, "   Ruta completa: " .. desc:GetFullName())
                    table.insert(report, string.format("   Distancia: %.1f studs | Pos: (%.1f, %.1f, %.1f)", dist, part.Position.X, part.Position.Y, part.Position.Z))

                    -- Atributos del modelo
                    local attrs = {}
                    for k, v in pairs(desc:GetAttributes()) do
                        table.insert(attrs, string.format("%s = %s", tostring(k), tostring(v)))
                    end
                    if #attrs > 0 then
                        table.insert(report, "   [Atributos]: " .. table.concat(attrs, " | "))
                    else
                        table.insert(report, "   [Atributos]: (Sin atributos directos)")
                    end

                    -- Descendientes relevantes (Prompts, Values, Gui, Scripts)
                    local internals = {}
                    for _, sub in ipairs(desc:GetDescendants()) do
                        local sName = sub.Name
                        local sClass = sub.ClassName

                        if sub:IsA("ProximityPrompt") then
                            table.insert(internals, string.format("ProximityPrompt('%s' | Action: '%s' | Enabled: %s)", sName, sub.ActionText, tostring(sub.Enabled)))
                        elseif sub:IsA("ValueBase") then
                            table.insert(internals, string.format("%s('%s' = %s)", sClass, sName, tostring(sub.Value)))
                        elseif sub:IsA("ClickDetector") then
                            table.insert(internals, string.format("ClickDetector('%s' | MaxDist: %d)", sName, sub.MaxActivationDistance))
                        elseif sClass:find("Script") then
                            table.insert(internals, string.format("%s('%s')", sClass, sName))
                        end
                    end

                    if #internals > 0 then
                        table.insert(report, "   [Componentes de Interacción]:\n     • " .. table.concat(internals, "\n     • "))
                    end
                end
            end
        end
    end

    if foundCount == 0 then
        table.insert(report, "\n⚠️ No se encontró ningún Model a menos de 30 studs. Asegúrate de estar pegado al cofre.")
    end

    return table.concat(report, "\n")
end

-- ==============================================================================
-- INTERFAZ VISUAL CON BOTÓN DE COPIADO
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChestForensicScannerGui"
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
Title.Text = "  📦 ESCÁNER DE VARIABLES DEL COFRE CERCANO"
Title.TextColor3 = Color3.fromRGB(255, 60, 60)
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
OutputBox.Text = scanNearbyChest()
OutputBox.Parent = MainFrame

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 38)
CopyBtn.Position = UDim2.new(0, 10, 0, 365)
CopyBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CopyBtn.Text = "📋 COPIAR DATOS DEL COFRE"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local txt = OutputBox.Text
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR DATOS DEL COFRE"
end)

-- Botón flotante para minimizar
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
FloatBtn.Text = "📦"
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
