-- ==============================================================================
-- REGISTRADOR FORENSE DE ARMAS & HOTBAR (DIAGNÓSTICO TOTAL 1-10)
-- 100% Nativo Roblox | Compatible con Delta / Móvil | 0% Lag
-- ==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local function getSafeGuiParent()
    local success, res = pcall(function()
        if gethui then return gethui() end
        return CoreGui
    end)
    if success and res then return res end
    return lp:WaitForChild("PlayerGui")
end

local GuiParent = getSafeGuiParent()

local existing = GuiParent:FindFirstChild("WeaponForensicGui")
if existing then existing:Destroy() end

local ForensicLogs = {}
local WeaponHistory = {}

-- ==============================================================================
-- 1. MOTOR DE ESCANEO PROFUNDO DE ARMAS Y HOTBAR
-- ==============================================================================

local function scanToolsDeep()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local toolsList = {}

    -- Herramienta actualmente en la mano
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(toolsList, { Tool = item, Container = "Character (En Mano)", Equipped = true })
            end
        end
    end

    -- Herramientas en el Backpack
    if bp then
        for idx, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(toolsList, { Tool = item, Container = string.format("Backpack [#%d]", idx), Equipped = false })
            end
        end
    end

    return toolsList
end

local function scanHotbarInterface()
    local hotbarData = {}

    -- 1. Intento de escaneo en CoreGui.RobloxGui.Backpack
    pcall(function()
        local rbxGui = CoreGui:FindFirstChild("RobloxGui")
        local backpackGui = rbxGui and rbxGui:FindFirstChild("Backpack")
        local hotbar = backpackGui and backpackGui:FindFirstChild("Hotbar")
        if hotbar then
            for _, slot in ipairs(hotbar:GetChildren()) do
                if slot:IsA("GuiObject") and slot.Visible then
                    local num = slot:FindFirstChild("NumberLabel") and slot.NumberLabel.Text or slot.Name
                    local toolRef = slot:FindFirstChild("Tool") and slot.Tool.Value
                    local toolName = toolRef and toolRef.Name or "Sin ToolValue"
                    table.insert(hotbarData, string.format("CoreGui Hotbar -> Slot: '%s' | Asignado: '%s' | Frame: %s", tostring(num), tostring(toolName), slot.Name))
                end
            end
        end
    end)

    -- 2. Escaneo en PlayerGui (Interfaces de inventario personalizadas)
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled then
                for _, desc in ipairs(gui:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Visible then
                        local txt = desc.Text:gsub("%s+", "")
                        if txt:match("^[1-9]$") or txt == "0" or txt == "10" then
                            local parent = desc.Parent
                            local assignedTool = "No detectado"
                            for _, child in ipairs(parent:GetChildren()) do
                                if child:IsA("TextLabel") and child ~= desc and child.Text ~= "" then
                                    assignedTool = child.Text
                                    break
                                elseif child:IsA("ObjectValue") and child.Value and child.Value:IsA("Tool") then
                                    assignedTool = child.Value.Name
                                    break
                                end
                            end
                            table.insert(hotbarData, string.format("Custom Hotbar [%s] -> Slot: '%s' | Texto/Asignado: '%s' | Frame: %s", gui.Name, txt, assignedTool, parent.Name))
                        end
                    end
                end
            end
        end
    end

    return hotbarData
end

local function compileWeaponReport()
    local lines = {
        "==================================================================",
        "          REPORTE FORENSE DE ARMAS & ACCESO DIRECTO (HOTBAR)       ",
        "==================================================================",
        string.format("Fecha/Hora: %s", os.date("%Y-%m-%d %X")),
        string.format("Jugador: %s", lp.Name)
    }

    local tools = scanToolsDeep()
    table.insert(lines, string.format("\n[1. ARMAS E INVENTARIO DETECTADOS (%d TOTAL)]:", #tools))

    if #tools == 0 then
        table.insert(lines, "  (No se encontraron herramientas en Character ni Backpack)")
    else
        for i, data in ipairs(tools) do
            local t = data.Tool
            table.insert(lines, "------------------------------------------------------------------")
            table.insert(lines, string.format("#%d | Nombre: '%s' | Ubicación: %s", i, t.Name, data.Container))
            table.insert(lines, string.format("   • ClassName: %s | ToolTip: '%s' | RequiresHandle: %s", t.ClassName, t.ToolTip, tostring(t.RequiresHandle)))

            -- Atributos del servidor
            local attrs = {}
            for k, v in pairs(t:GetAttributes()) do
                table.insert(attrs, string.format("%s = %s", tostring(k), tostring(v)))
            end
            table.insert(lines, string.format("   • Atributos: %s", #attrs > 0 and table.concat(attrs, ", ") or "Ninguno"))

            -- Componentes internos (Values, Configurations, Remotes)
            local innerComponents = {}
            for _, child in ipairs(t:GetChildren()) do
                if child:IsA("ValueBase") then
                    table.insert(innerComponents, string.format("%s('%s' = %s)", child.ClassName, child.Name, tostring(child.Value)))
                elseif child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    table.insert(innerComponents, string.format("%s('%s')", child.ClassName, child.Name))
                end
            end
            table.insert(lines, string.format("   • Componentes: %s", #innerComponents > 0 and table.concat(innerComponents, " | ") or "Sin componentes clave"))
        end
    end

    -- Mapeo visual de la Hotbar
    table.insert(lines, "\n[2. ANÁLISIS DE LA BARRA HOTBAR (1 AL 0)]:")
    local hotbar = scanHotbarInterface()
    if #hotbar == 0 then
        table.insert(lines, "  (No se encontraron casillas de hotbar activas en este momento)")
    else
        for _, entry in ipairs(hotbar) do
            table.insert(lines, "   • " .. entry)
        end
    end

    -- Historial reciente de cambios
    table.insert(lines, "\n[3. HISTORIAL DE EQUIPADO RECIENTE]:")
    if #WeaponHistory == 0 then
        table.insert(lines, "  (Sin cambios de arma registrados aún en esta sesión)")
    else
        for _, h in ipairs(WeaponHistory) do
            table.insert(lines, string.format("   • [%s] %s -> '%s'", h.Time, h.Action, h.ToolName))
        end
    end

    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 2. ESCUCHA ACTIVA DE CAMBIOS DE ARMA EN MANO
-- ==============================================================================

local function hookCharacter(char)
    if not char then return end

    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            table.insert(WeaponHistory, 1, {
                Time = os.date("%X"),
                Action = "EQUIPADA (En Mano)",
                ToolName = child.Name
            })
            if #WeaponHistory > 20 then table.remove(WeaponHistory) end
        end
    end)

    char.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            table.insert(WeaponHistory, 1, {
                Time = os.date("%X"),
                Action = "DESEQUIPADA",
                ToolName = child.Name
            })
            if #WeaponHistory > 20 then table.remove(WeaponHistory) end
        end
    end)
end

if lp.Character then hookCharacter(lp.Character) end
lp.CharacterAdded:Connect(hookCharacter)

-- ==============================================================================
-- 3. INTERFAZ GRÁFICA NATIVA
-- ==============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WeaponForensicGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 420)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "   🔫 REGISTRADOR FORENSE DE ARMAS & HOTBAR"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 260)
OutputBox.Position = UDim2.new(0, 10, 0, 44)
OutputBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
OutputBox.TextColor3 = Color3.fromRGB(225, 225, 225)
OutputBox.TextSize = 10
OutputBox.Font = Enum.Font.Code
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextEditable = false
OutputBox.Text = "Presiona 'ESCANEAR ARMAS AHORA' para extraer la telemetría..."
OutputBox.Parent = MainFrame

local OutputCorner = Instance.new("UICorner")
OutputCorner.CornerRadius = UDim.new(0, 6)
OutputCorner.Parent = OutputBox

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -5, 0, 36)
ScanBtn.Position = UDim2.new(0, 10, 0, 314)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 75)
ScanBtn.Text = "🔍 ESCANEAR ARMAS AHORA"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 10
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

local ScanCorner = Instance.new("UICorner")
ScanCorner.CornerRadius = UDim.new(0, 6)
ScanCorner.Parent = ScanBtn

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -5, 0, 36)
CopyBtn.Position = UDim2.new(0.52, 0, 0, 314)
CopyBtn.BackgroundColor3 = Color3.fromRGB(210, 130, 20)
CopyBtn.Text = "📋 COPIAR REPORTE"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(1, -20, 0, 28)
ClearBtn.Position = UDim2.new(0, 10, 0, 356)
ClearBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
ClearBtn.Text = "🗑️ LIMPIAR HISTORIAL"
ClearBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
ClearBtn.TextSize = 9
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.Parent = MainFrame

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 6)
ClearCorner.Parent = ClearBtn

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
FloatBtn.Text = "🔫\nLOG"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

-- ==============================================================================
-- 4. EVENTOS DE LOS BOTONES
-- ==============================================================================

ScanBtn.MouseButton1Click:Connect(function()
    local report = compileWeaponReport()
    OutputBox.Text = report
end)

CopyBtn.MouseButton1Click:Connect(function()
    local report = compileWeaponReport()
    OutputBox.Text = report
    local copied = false
    if setclipboard then
        pcall(function() setclipboard(report); copied = true end)
    elseif toclipboard then
        pcall(function() toclipboard(report); copied = true end)
    end
    CopyBtn.Text = copied and "✅ ¡REPORTE COPIADO!" or "⚠️ Copia manual desde el cuadro"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR REPORTE"
end)

ClearBtn.MouseButton1Click:Connect(function()
    table.clear(WeaponHistory)
    OutputBox.Text = "(Historial limpiado)"
end)

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
