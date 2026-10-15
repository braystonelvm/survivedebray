-- ==============================================================================
-- ESCÁNER SIN-HOOK DE DISPARO 360° (MÓDULOS, CONSTANTES Y EVENTOS INTERNOS)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local ReportData = {
    ExecutorCapabilities = {},
    ToolHierarchy = {},
    ModuleAnalysis = {},
    ScriptConstants = {},
    LiveEvents = {}
}

local function serializeVal(v, depth)
    depth = depth or 0
    if depth > 2 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        return string.format("[%s: %s]", v.ClassName, v:GetFullName())
    elseif t == "Vector3" then
        return string.format("Vector3(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
    elseif t == "table" then
        local s = {}
        local count = 0
        for k, val in pairs(v) do
            count = count + 1
            if count <= 15 then
                table.insert(s, tostring(k) .. "=" .. serializeVal(val, depth + 1))
            end
        end
        return "{" .. table.concat(s, ", ") .. "}"
    elseif t == "function" then
        local infoStr = "function"
        pcall(function()
            if debug and debug.info then
                local name = debug.info(v, "n")
                local src = debug.info(v, "s")
                local line = debug.info(v, "l")
                infoStr = string.format("func '%s' (%s:%s)", tostring(name), tostring(src), tostring(line))
            end
        end)
        return infoStr
    else
        return tostring(v)
    end
end

-- ==============================================================================
-- 1. DETECTAR QUÉ FUNCIONES SOPORTA TU EJECUTOR
-- ==============================================================================
local function checkCapabilities()
    local caps = {
        ["getgc"] = (getgc ~= nil),
        ["getsenv"] = (getsenv ~= nil),
        ["decompile"] = (decompile ~= nil),
        ["debug.getconstants"] = (debug and debug.getconstants ~= nil) or (getconstants ~= nil),
        ["debug.getupvalues"] = (debug and debug.getupvalues ~= nil) or (getupvalues ~= nil),
        ["debug.getprotos"] = (debug and debug.getprotos ~= nil) or (getprotos ~= nil),
        ["fireproximityprompt"] = (fireproximityprompt ~= nil),
        ["mouse1click"] = (mouse1click ~= nil)
    }
    local list = {}
    for k, v in pairs(caps) do
        table.insert(list, string.format("%s: %s", k, tostring(v)))
    end
    ReportData.ExecutorCapabilities = list
end

-- ==============================================================================
-- 2. INSPECCIONAR TODOS LOS OBJETOS Y SCRIPTS DENTRO DE TUS ARMAS Y PODERES
-- ==============================================================================
local function scanToolsDeep()
    local list = {}
    local getConsts = (debug and debug.getconstants) or getconstants
    local getUpvals = (debug and debug.getupvalues) or getupvalues

    for _, cont in ipairs({lp.Character, lp:FindFirstChild("Backpack")}) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") then
                    table.insert(list, string.format("🔧 TOOL: '%s' (en %s)", tool.Name, cont.Name))
                    for k, v in pairs(tool:GetAttributes()) do
                        table.insert(list, string.format("   [Attr] %s = %s", k, tostring(v)))
                    end

                    for _, desc in ipairs(tool:GetDescendants()) do
                        table.insert(list, string.format("   • %s (%s)", desc.Name, desc.ClassName))

                        -- Si es un LocalScript o ModuleScript, intentar extraer su código o constantes
                        if desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
                            if decompile then
                                pcall(function()
                                    local src = decompile(desc)
                                    if src and #src > 5 then
                                        table.insert(ReportData.ScriptConstants, string.format("=== DECOMPILE: %s ===\n%s", desc:GetFullName(), src:sub(1, 1500)))
                                    end
                                end)
                            end

                            if getsenv and desc:IsA("LocalScript") then
                                pcall(function()
                                    local env = getsenv(desc)
                                    for k, v in pairs(env) do
                                        if k ~= "_G" and k ~= "shared" then
                                            table.insert(ReportData.ScriptConstants, string.format("SENV [%s] %s = %s", desc.Name, tostring(k), serializeVal(v)))
                                            if type(v) == "function" and getConsts then
                                                pcall(function()
                                                    local cList = {}
                                                    for _, c in pairs(getConsts(v)) do
                                                        if type(c) == "string" or type(c) == "number" then
                                                            table.insert(cList, tostring(c))
                                                        end
                                                    end
                                                    if #cList > 0 then
                                                        table.insert(ReportData.ScriptConstants, "   Consts: " .. table.concat(cList, ", "))
                                                    end
                                                end)
                                            end
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
    ReportData.ToolHierarchy = list
end

-- ==============================================================================
-- 3. INSPECCIONAR Y INTERCEPTAR MÓDULOS DE COMBATE EN REPLICATEDSTORAGE
-- ==============================================================================
local hookedModules = {}

local function scanAndHookCombatModules()
    local list = {}
    local getConsts = (debug and debug.getconstants) or getconstants

    local modulesFolder = ReplicatedStorage:FindFirstChild("Modules") or ReplicatedStorage
    for _, desc in ipairs(modulesFolder:GetDescendants()) do
        if desc:IsA("ModuleScript") then
            local n = desc.Name:lower()
            if n:find("proj") or n:find("gun") or n:find("combat") or n:find("weapon") or n:find("quicknet") or n:find("ability") or n:find("hit") then
                table.insert(list, string.format("📦 MODULE: %s (%s)", desc.Name, desc:GetFullName()))

                pcall(function()
                    local req = require(desc)
                    if type(req) == "table" then
                        for k, v in pairs(req) do
                            table.insert(list, string.format("   • [%s] = %s", tostring(k), serializeVal(v)))

                            -- Extraer constantes de cada función del módulo
                            if type(v) == "function" and getConsts then
                                pcall(function()
                                    local cList = {}
                                    for _, c in pairs(getConsts(v)) do
                                        if type(c) == "string" or type(c) == "number" then
                                            table.insert(cList, tostring(c))
                                        end
                                    end
                                    if #cList > 0 then
                                        table.insert(list, "      Consts: " .. table.concat(cList, ", "))
                                    end
                                end)
                            end

                            -- Interceptar llamadas a la función del módulo en vivo (Sin usar hookmetamethod)
                            local hookKey = desc:GetFullName() .. "." .. tostring(k)
                            if type(v) == "function" and not hookedModules[hookKey] then
                                hookedModules[hookKey] = true
                                local origFunc = v
                                req[k] = function(...)
                                    local args = {...}
                                    local aStr = {}
                                    for i, a in ipairs(args) do
                                        table.insert(aStr, string.format("Arg[%d]=%s", i, serializeVal(a)))
                                    end
                                    local msg = string.format("⚡ [MODULE CALL] %s.%s(%s)", desc.Name, tostring(k), table.concat(aStr, ", "))
                                    table.insert(ReportData.LiveEvents, 1, msg)
                                    return origFunc(...)
                                end
                            end
                        end
                    end
                end)
            end
        end
    end
    ReportData.ModuleAnalysis = list
end

-- ==============================================================================
-- 4. ESCUCHAR BINDABLE EVENTS NATIVOS DEL ARMA (SHOTFIRED / SHOTHIT)
-- ==============================================================================
local connectedBindables = {}

local function connectWeaponBindables()
    for _, cont in ipairs({lp.Character, lp:FindFirstChild("Backpack")}) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") then
                    for _, desc in ipairs(tool:GetDescendants()) do
                        if desc:IsA("BindableEvent") and not connectedBindables[desc] then
                            connectedBindables[desc] = true
                            desc.Event:Connect(function(...)
                                local args = {...}
                                local aStr = {}
                                for i, a in ipairs(args) do
                                    table.insert(aStr, string.format("Arg[%d]=%s", i, serializeVal(a)))
                                end
                                local msg = string.format("🎯 [BINDABLE] %s.%s -> %s", tool.Name, desc.Name, table.concat(aStr, " | "))
                                table.insert(ReportData.LiveEvents, 1, msg)
                            end)
                        end
                    end
                end
            end
        end
    end
end

connectWeaponBindables()
scanAndHookCombatModules()

-- ==============================================================================
-- 5. VENTANA VISUAL CON BOTÓN DE COPIA AL PORTAPAPELES
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NoHookWeaponScannerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 540, 0, 440)
MainFrame.Position = UDim2.new(0.5, -270, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 36)
Title.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
Title.Text = "  🔬 ESCÁNER SIN-HOOK: MÓDULOS DE DISPARO Y PODERES"
Title.TextColor3 = Color3.fromRGB(0, 255, 190)
Title.TextSize = 12
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 325)
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
OutputBox.Text = "1. Equipa tu Uzi o Pistol en la mano y dispara 1 o 2 balas a un zombie.\n2. Presiona el botón verde '1. EXTRAER DATOS DE DISPARO'.\n3. Presiona el botón azul '2. COPIAR REPORTE' y pégalo en el chat."
OutputBox.Parent = MainFrame

local function generateFullText()
    checkCapabilities()
    scanToolsDeep()
    scanAndHookCombatModules()
    connectWeaponBindables()

    local out = {
        "==================================================================",
        "       REPORTE PROFUNDO SIN-HOOK: ARMAS, MÓDULOS Y EVENTOS        ",
        "==================================================================",
        "\n[1. CAPACIDADES DEL EJECUTOR]:"
    }
    for _, v in ipairs(ReportData.ExecutorCapabilities) do table.insert(out, " " .. v) end

    table.insert(out, "\n[2. EVENTOS EN VIVO CAPTURADOS AL DISPARAR]:")
    if #ReportData.LiveEvents == 0 then
        table.insert(out, " (Ningún evento en vivo aún. Equipa el arma y dispara 1 bala).")
    else
        for _, v in ipairs(ReportData.LiveEvents) do table.insert(out, " " .. v) end
    end

    table.insert(out, "\n[3. MÓDULOS DE COMBATE Y PROYECTILES]:")
    for _, v in ipairs(ReportData.ModuleAnalysis) do table.insert(out, " " .. v) end

    table.insert(out, "\n[4. ESTRUCTURA DE ARMAS Y PODERES]:")
    for _, v in ipairs(ReportData.ToolHierarchy) do table.insert(out, " " .. v) end

    table.insert(out, "\n[5. CONSTANTES Y CÓDIGO INTERNO DE SCRIPTS]:")
    for _, v in ipairs(ReportData.ScriptConstants) do table.insert(out, " " .. v) end

    return table.concat(out, "\n")
end

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -10, 0, 38)
ScanBtn.Position = UDim2.new(0, 10, 0, 380)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
ScanBtn.Text = "🔍 1. EXTRAER DATOS DE DISPARO"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 11
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ EXTRAYENDO..."
    OutputBox.Text = generateFullText()
    ScanBtn.Text = "✅ ¡DATOS EXTRAÍDOS!"
    task.wait(1)
    ScanBtn.Text = "🔍 1. EXTRAER DATOS DE DISPARO"
end)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 38)
CopyBtn.Position = UDim2.new(0.52, 0, 0, 380)
CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 105, 180)
CopyBtn.Text = "📋 2. COPIAR REPORTE"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

CopyBtn.MouseButton1Click:Connect(function()
    local txt = OutputBox.Text
    if txt == "" or txt:find("^1%. Equipa") then
        txt = generateFullText()
        OutputBox.Text = txt
    end
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 2. COPIAR REPORTE"
end)
