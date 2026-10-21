-- ==============================================================================
-- ESCÁNER FORENSE: COMIDA EN EL SUELO (DROPPEDITEMS) E INTERACCIÓN DE CONSUMO
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local ForensicLog = {
    NearbyItems = {},
    LiveInteractions = {},
    RemotesCaptured = {}
}

local function addLiveLog(msg)
    local entry = string.format("[%s] %s", os.date("%X"), msg)
    table.insert(ForensicLog.LiveInteractions, 1, entry)
    if #ForensicLog.LiveInteractions > 25 then table.remove(ForensicLog.LiveInteractions) end
    print("🥕 [FOOD FORENSIC]: " .. entry)
end

-- ==============================================================================
-- 1. ESCUCHAR INTERACCIONES EN VIVO (REMOTES DE COMER / AGARRAR)
-- ==============================================================================
local function monitorInteractionRemotes()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotesFolder then return end

    for _, desc in ipairs(remotesFolder:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            local n = desc.Name:lower()
            if n:find("eat") or n:find("food") or n:find("consume") or n:find("pickup") or n:find("interact") or n:find("drag") or n:find("item") then
                table.insert(ForensicLog.RemotesCaptured, string.format("⚡ Remote hallado: %s (%s)", desc:GetFullName(), desc.ClassName))
                
                if desc:IsA("RemoteEvent") then
                    -- Escuchar si el juego lo dispara localmente
                    pcall(function()
                        desc.OnClientEvent:Connect(function(...)
                            local args = {...}
                            addLiveLog(string.format("RemoteEvent OnClientEvent '%s' (Args: %d)", desc.Name, #args))
                        end)
                    end)
                end
            end
        end
    end
end

-- ==============================================================================
-- 2. ESCANEAR OBJETOS EN EL SUELO (WORKSPACE.DROPPEDITEMS / 25 STUDS)
-- ==============================================================================
local function scanDroppedFood()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return "⚠️ No se detectó a tu personaje." end

    local myPos = root.Position
    local report = {
        "==================================================================",
        "      REPORTE DE COMIDA EN EL SUELO Y MECÁNICAS DE CONSUMO       ",
        "==================================================================",
        string.format("Mi Posición: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z),
        "\n[1. OBJETOS CERCANOS EN DROPPEDITEMS O SUELO (25 STUDS)]:"
    }

    local searchRoots = {
        workspace:FindFirstChild("DroppedItems"),
        workspace:FindFirstChild("Map"),
        workspace
    }

    local foundCount = 0

    for _, container in ipairs(searchRoots) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if (item:IsA("Model") or item:IsA("BasePart")) and item ~= char then
                    local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                    if part then
                        local dist = (part.Position - myPos).Magnitude
                        if dist <= 25 then
                            foundCount = foundCount + 1
                            table.insert(report, string.format("\n🥕 OBJETO #%d: '%s' (%s)", foundCount, item.Name, item.ClassName))
                            table.insert(report, "   Ruta: " .. item:GetFullName())
                            table.insert(report, string.format("   Distancia: %.1f studs | Pos: (%.1f, %.1f, %.1f)", dist, part.Position.X, part.Position.Y, part.Position.Z))

                            -- Atributos
                            local attrs = {}
                            for k, v in pairs(item:GetAttributes()) do
                                table.insert(attrs, string.format("%s = %s", tostring(k), tostring(v)))
                            end
                            if #attrs > 0 then
                                table.insert(report, "   [Atributos]: " .. table.concat(attrs, " | "))
                            else
                                table.insert(report, "   [Atributos]: (Sin atributos)")
                            end

                            -- Componentes interactivos
                            local comps = {}
                            for _, desc in ipairs(item:GetDescendants()) do
                                if desc:IsA("ProximityPrompt") then
                                    table.insert(comps, string.format("ProximityPrompt('%s' | Action: '%s' | Key: %s | Enabled: %s)", desc.Name, desc.ActionText, tostring(desc.KeyboardKeyCode), tostring(desc.Enabled)))
                                elseif desc:IsA("ClickDetector") then
                                    table.insert(comps, string.format("ClickDetector('%s' | MaxDist: %d)", desc.Name, desc.MaxActivationDistance))
                                elseif desc:IsA("ValueBase") then
                                    table.insert(comps, string.format("%s('%s' = %s)", desc.ClassName, desc.Name, tostring(desc.Value)))
                                elseif desc:IsA("LocalScript") or desc:IsA("Script") then
                                    table.insert(comps, string.format("Script('%s')", desc.Name))
                                end
                            end

                            if #comps > 0 then
                                table.insert(report, "   [Interacciones]:\n     • " .. table.concat(comps, "\n     • "))
                            end
                        end
                    end
                end
            end
        end
    end

    if foundCount == 0 then
        table.insert(report, "\n⚠️ No se detectó ningún objeto tirado a menos de 25 studs. Párate cerca de la comida.")
    end

    -- Revisar UI móvil de interacción (ej. InteractMobile)
    table.insert(report, "\n[2. UI DE INTERACCIÓN MÓVIL EN PLAYERGUI]:")
    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        local foundUI = false
        for _, gui in ipairs(pGui:GetChildren()) do
            local gName = gui.Name:lower()
            if gName:find("interact") or gName:find("mobile") or gName:find("prompt") or gName:find("item") then
                foundUI = true
                table.insert(report, string.format(" 📱 GUI: '%s' (%s) [Enabled: %s]", gui.Name, gui.ClassName, tostring(gui.Enabled)))
                for _, desc in ipairs(gui:GetDescendants()) do
                    if desc:IsA("TextButton") or desc:IsA("ImageButton") then
                        table.insert(report, string.format("    ↳ Botón: '%s' | Texto: '%s'", desc.Name, desc:IsA("TextButton") and desc.Text or "(Image)"))
                    end
                end
            end
        end
        if not foundUI then
            table.insert(report, " (No se detectaron GUIs de interacción específicas activas)")
        end
    end

    table.insert(report, "\n[3. REMOTES DE INTERACCIÓN REGISTRADOS]:")
    for _, rem in ipairs(ForensicLog.RemotesCaptured) do table.insert(report, " " .. rem) end

    table.insert(report, "\n[4. HISTORIAL DE INTERACCIONES EN VIVO]:")
    if #ForensicLog.LiveInteractions == 0 then
        table.insert(report, " (Ninguna acción registrada aún. Intenta comer o interactuar con una zanahoria).")
    else
        for _, l in ipairs(ForensicLog.LiveInteractions) do table.insert(report, " " .. l) end
    end

    return table.concat(report, "\n")
end

monitorInteractionRemotes()

-- ==============================================================================
-- 3. VENTANA FLOTANTE Y COPIADO
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FoodForensicScannerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 440)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -220)
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
Title.Text = "  🥕 REGISTRADOR FORENSE DE COMIDA EN EL SUELO"
Title.TextColor3 = Color3.fromRGB(255, 160, 40)
Title.TextSize = 11
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 330)
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
OutputBox.Text = scanDroppedFood()
OutputBox.Parent = MainFrame

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 38)
CopyBtn.Position = UDim2.new(0, 10, 0, 385)
CopyBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 30)
CopyBtn.Text = "📋 COPIAR DATOS DE COMIDA"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0.48, -10, 0, 38)
RefreshBtn.Position = UDim2.new(0.52, 0, 0, 385)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 80)
RefreshBtn.Text = "🔄 ACTUALIZAR ESCANEO"
RefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RefreshBtn.TextSize = 10
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.Parent = MainFrame

local RefreshCorner = Instance.new("UICorner")
RefreshCorner.CornerRadius = UDim.new(0, 6)
RefreshCorner.Parent = RefreshBtn

CopyBtn.MouseButton1Click:Connect(function()
    local txt = scanDroppedFood()
    OutputBox.Text = txt
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR DATOS DE COMIDA"
end)

RefreshBtn.MouseButton1Click:Connect(function()
    OutputBox.Text = scanDroppedFood()
    RefreshBtn.Text = "✅ ¡ACTUALIZADO!"
    task.wait(1)
    RefreshBtn.Text = "🔄 ACTUALIZAR ESCANEO"
end)

-- Botón flotante / minimizador
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 30)
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
