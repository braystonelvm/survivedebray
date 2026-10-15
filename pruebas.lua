-- ==============================================================================
-- EXTRACTOR DE MEMORIA DE ZHUB (CLONACIÓN DE MECÁNICAS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local ZhubData = {
    FoundTables = {},
    FoundFunctions = {},
    RemotesFound = {}
}

-- Escanear la memoria global (getgc) en busca de rastros de ZHub
pcall(function()
    if getgc then
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" then
                -- Buscar tablas que tengan claves relacionadas con combate, aim, auto-shoot o zonas
                local keys = {}
                local hasRelevantKey = false
                for k, v in pairs(obj) do
                    local kStr = tostring(k):lower()
                    if kStr:find("zhub") or kStr:find("silent") or kStr:find("autogun") or kStr:find("aimbot") or kStr:find("gunmod") or kStr:find("fastfire") then
                        hasRelevantKey = true
                    end
                    table.insert(keys, kStr)
                end

                if hasRelevantKey and #ZhubData.FoundTables < 25 then
                    table.insert(ZhubData.FoundTables, "Tabla con claves: " .. table.concat(keys, ", "):sub(1, 120))
                end
            elseif type(obj) == "function" then
                -- Intentar ver el nombre de las funciones en memoria
                pcall(function()
                    if debug and debug.info then
                        local name = debug.info(obj, "n")
                        if name and name ~= "" and (name:lower():find("shoot") or name:lower():find("gun") or name:lower():find("fire") or name:lower():find("target")) then
                            if #ZhubData.FoundFunctions < 25 then
                                table.insert(ZhubData.FoundFunctions, "Función: " .. name)
                            end
                        end
                    end
                end)
            end
        end
    end
end)

-- Buscar también en el entorno global (_G o shared) si ZHub dejó alguna configuración expuesta
pcall(function()
    for k, v in pairs(_G) do
        table.insert(ZhubData.FoundTables, string.format("_G['%s'] = %s", tostring(k), typeof(v)))
    end
end)

-- Interfaz visual para ver el reporte de ZHub
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZhubExtractorGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 400)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 36)
Title.BackgroundColor3 = Color3.fromRGB(28, 34, 48)
Title.Text = "  🕵️ EXTRACTOR DE MECÁNICAS DE ZHUB"
Title.TextColor3 = Color3.fromRGB(0, 255, 190)
Title.TextSize = 12
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 290)
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

local reportLines = {
    "=== DATOS EXTRAÍDOS DE ZHUB EN MEMORIA ===",
    "\n[TABLAS Y CONFIGURACIONES ENCONTRADAS]:"
}
for _, t in ipairs(ZhubData.FoundTables) do table.insert(reportLines, " • " .. t) end
table.insert(reportLines, "\n[FUNCIONES DE COMBATE ENCONTRADAS]:")
for _, f in ipairs(ZhubData.FoundFunctions) do table.insert(reportLines, " • " .. f) end

OutputBox.Text = table.concat(reportLines, "\n")
OutputBox.Parent = MainFrame

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 345)
CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 180)
CopyBtn.Text = "📋 COPIAR DATOS DE ZHUB"
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
    CopyBtn.Text = "📋 COPIAR DATOS DE ZHUB"
end)
