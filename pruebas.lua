-- ==============================================================================
-- INSPECTOR INTERNO DE REPAIR HAMMER & ESPÍA UNIVERSAL DE REMOTES
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local SpyLogs = {}
local ToolClicks = 0
local LastTargetName = "Ninguno"

-- 1. DETECTOR DE CLICS Y ACTIVACIÓN DEL MARTILLO EN EL CLIENTE
local function hookToolEvents()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))

    if hammer then
        hammer.Activated:Connect(function()
            ToolClicks = ToolClicks + 1
            local target = mouse.Target
            LastTargetName = target and string.format("%s (%s)", target.Name, target.ClassName) or "Aire"
            print(string.format("[MARTILLO CLICK #%d] Apuntando a: %s", ToolClicks, LastTargetName))
        end)
    end
end
hookToolEvents()
lp.CharacterAdded:Connect(function() task.wait(1); hookToolEvents() end)

-- 2. ESPÍA UNIVERSAL DE CUALQUIER REMOTE (CAPTURA TODO LO QUE SALGA)
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if method == "FireServer" then
            local rName = tostring(self.Name)
            -- Capturar cualquier remote del martillo o relacionado con acciones
            local pName = self.Parent and self.Parent.Name or ""
            local isFromHammer = pName == "Repair Hammer" or self:IsDescendantOf(lp.Character)
            
            if isFromHammer or rName:lower():find("repair") or rName:lower():find("hit") or rName:lower():find("interact") or rName == "Impact" then
                local argDetails = {}
                for idx, v in ipairs(args) do
                    local t = typeof(v)
                    local str = tostring(v)
                    if t == "Instance" then
                        str = string.format("%s (%s, Ruta: %s)", v.Name, v.ClassName, v:GetFullName())
                    elseif t == "Vector3" then
                        str = string.format("Vector3.new(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
                    end
                    table.insert(argDetails, string.format("Arg[%d] (%s): %s", idx, t, str))
                end

                local entry = string.format("[%s] %s -> %s\n      %s", os.date("%X"), self:GetFullName(), rName, table.concat(argDetails, "\n      "))
                table.insert(SpyLogs, entry)
                print("[ESPÍA CAPTURA]:\n" .. entry)
            end
        end

        return oldNamecall(self, ...)
    end)
end

-- 3. EXTRACCIÓN DE CONSTANTES Y VARIABLES DE REPAIRHAMMERCLIENT
local function dumpClientScriptMemory()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))
    local clientScript = hammer and hammer:FindFirstChild("RepairHammerClient")

    local dumpLines = {}

    if not clientScript then
        return "No se encontró RepairHammerClient dentro del martillo."
    end

    table.insert(dumpLines, "• Script encontrado: " .. clientScript:GetFullName())

    -- Descompilación completa si el ejecutor la soporta
    if decompile then
        local s, code = pcall(function() return decompile(clientScript) end)
        if s and code and #code > 10 then
            table.insert(dumpLines, "\n[CÓDIGO FUENTE DECOMPILADO]:\n" .. code)
            return table.concat(dumpLines, "\n")
        end
    end

    -- Si no soporta decompile, extraer las constantes internas (Strings y Nombres de variables)
    if getconstants then
        local consts = getconstants(clientScript)
        local stringsFound = {}
        for _, val in pairs(consts) do
            if type(val) == "string" and #val > 1 then
                table.insert(stringsFound, '"' .. val .. '"')
            end
        end
        table.insert(dumpLines, "\n• Palabras clave y strings en el script:")
        table.insert(dumpLines, table.concat(stringsFound, ", "))
    else
        table.insert(dumpLines, "• El ejecutor no soporta getconstants ni decompile.")
    end

    return table.concat(dumpLines, "\n")
end

-- 4. INTERFAZ NATIVA (CERO DEPENDENCIAS EXTERNAS)
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NativeInspectorGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(1, 0)
BtnCorner.Parent = FloatBtn

local BtnText = Instance.new("TextLabel")
BtnText.Size = UDim2.new(1, 0, 1, 0)
BtnText.BackgroundTransparency = 1
BtnText.Text = "🔍"
BtnText.TextSize = 22
BtnText.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnText.Parent = FloatBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 380)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
TitleBar.Text = "  INSPECTOR DE CÓDIGO DEL MARTILLO"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -20, 0, 60)
StatusLbl.Position = UDim2.new(0, 10, 0, 42)
StatusLbl.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
StatusLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
StatusLbl.TextSize = 12
StatusLbl.Font = Enum.Font.Code
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.Text = " Monitoreando clics del martillo..."
StatusLbl.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusLbl

local LogBox = Instance.new("TextBox")
LogBox.Size = UDim2.new(1, -20, 0, 210)
LogBox.Position = UDim2.new(0, 10, 0, 108)
LogBox.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
LogBox.TextColor3 = Color3.fromRGB(0, 255, 170)
LogBox.TextSize = 11
LogBox.Font = Enum.Font.Code
LogBox.TextXAlignment = Enum.TextXAlignment.Left
LogBox.TextYAlignment = Enum.TextYAlignment.Top
LogBox.ClearTextOnFocus = false
LogBox.TextEditable = false
LogBox.MultiLine = true
LogBox.Text = "Presiona el botón de abajo para extraer el código y constantes..."
LogBox.Parent = MainFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogBox

local ActionBtn = Instance.new("TextButton")
ActionBtn.Size = UDim2.new(1, -20, 0, 42)
ActionBtn.Position = UDim2.new(0, 10, 1, -50)
ActionBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
ActionBtn.Text = "📋 EXTRAER MEMORIA DEL MARTILLO Y COPIAR"
ActionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ActionBtn.TextSize = 13
ActionBtn.Font = Enum.Font.GothamBold
ActionBtn.Parent = MainFrame

local ActionCorner = Instance.new("UICorner")
ActionCorner.CornerRadius = UDim.new(0, 8)
ActionCorner.Parent = ActionBtn

local isVis = true
FloatBtn.MouseButton1Click:Connect(function()
    isVis = not isVis
    MainFrame.Visible = isVis
end)

-- Actualizador de estado de clics
task.spawn(function()
    while true do
        task.wait(0.3)
        StatusLbl.Text = string.format(" Clics con martillo: %d | Último objetivo: %s\n Remotes interceptados: %d", ToolClicks, LastTargetName, #SpyLogs)
    end
end)

ActionBtn.MouseButton1Click:Connect(function()
    local report = {}
    table.insert(report, "==================================================================")
    table.insert(report, "       EXTRACCIÓN FORENSE DE MEMORIA: REPAIRHAMMERCLIENT          ")
    table.insert(report, "==================================================================")
    table.insert(report, "Hora: " .. os.date("%X"))
    table.insert(report, string.format("Clics registrados con el martillo: %d (Último objetivo: %s)", ToolClicks, LastTargetName))
    table.insert(report, "\n[1. ANÁLISIS DE CÓDIGO INTERNO]:")
    table.insert(report, dumpClientScriptMemory())
    table.insert(report, "\n------------------------------------------------------------------")
    table.insert(report, string.format("[2. REMOTES INTERCEPTADOS EN TOTAL: %d]:", #SpyLogs))
    if #SpyLogs > 0 then
        table.insert(report, table.concat(SpyLogs, "\n\n"))
    else
        table.insert(report, ">> No se disparó ningún RemoteEvent al hacer clic.")
    end
    table.insert(report, "==================================================================")

    local fullText = table.concat(report, "\n")
    LogBox.Text = fullText
    if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end
    print(fullText)

    ActionBtn.Text = "✅ ¡MEMORIA EXTRAÍDA Y COPIADA!"
    task.wait(2)
    ActionBtn.Text = "📋 EXTRAER MEMORIA DEL MARTILLO Y COPIAR"
end)
