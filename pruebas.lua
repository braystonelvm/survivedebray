-- ==============================================================================
-- ESCÁNER FORENSE SIN-HOOK: CAPTURA DE DISPARO 360°, RECARGA Y MÓDULO PROJECTILE
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local Diagnostic = {
    LiveShots = {},
    AttrChanges = {},
    ModulesDump = {},
    ScriptsDump = {},
    Capabilities = {}
}

local function addLiveLog(list, msg)
    table.insert(list, 1, string.format("[%s] %s", os.date("%X"), msg))
    if #list > 35 then table.remove(list) end
end

local function formatValue(v, depth)
    depth = depth or 0
    if depth > 2 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        return string.format("[%s: %s]", v.ClassName, v:GetFullName())
    elseif t == "Vector3" then
        return string.format("Vector3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        local lv = v.LookVector
        return string.format("CFrame(Pos: %.1f,%.1f,%.1f | Look: %.2f,%.2f,%.2f)", p.X, p.Y, p.Z, lv.X, lv.Y, lv.Z)
    elseif t == "table" then
        local parts = {}
        local c = 0
        for k, val in pairs(v) do
            c = c + 1
            if c <= 12 then
                table.insert(parts, string.format("[%s]=%s", tostring(k), formatValue(val, depth + 1)))
            end
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    else
        return string.format("%s (%s)", tostring(v), t)
    end
end

-- ==============================================================================
-- 1. VERIFICAR FUNCIONES DISPONIBLES EN TU EJECUTOR
-- ==============================================================================
local function scanCapabilities()
    local funcs = {
        "decompile", "getscriptbytecode", "dumpstring", "getsenv",
        "getgc", "hookfunction", "replaceclosure", "debug.getconstants",
        "debug.getupvalues", "debug.getprotos", "debug.info"
    }
    local out = {}
    for _, fn in ipairs(funcs) do
        local ok = false
        if fn:find("^debug%.") then
            local sub = fn:match("^debug%.(.+)$")
            ok = (debug and debug[sub] ~= nil) or (_G[sub] ~= nil)
        else
            ok = (_G[fn] ~= nil) or (getfenv()[fn] ~= nil)
        end
        table.insert(out, string.format("%s = %s", fn, tostring(ok)))
    end
    Diagnostic.Capabilities = out
end

-- ==============================================================================
-- 2. INTERCEPTAR MÓDULOS DE COMBATE EN REPLICATEDSTORAGE (100% LUA NATIVO)
-- ==============================================================================
local wrappedFunctions = {}

local function hookAllCombatModules()
    local modDump = {}
    local getConsts = (debug and debug.getconstants) or getconstants

    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("ModuleScript") then
            local path = desc:GetFullName()
            local n = desc.Name:lower()
            if path:find("Combat") or path:find("QuickNet") or path:find("Tools") or path:find("Abilities") 
               or n:find("proj") or n:find("gun") or n:find("weapon") or n:find("hit") or n:find("net") then

                table.insert(modDump, string.format("📦 MODULE: %s", path))
                pcall(function()
                    local modTable = require(desc)
                    if type(modTable) == "table" then
                        for k, v in pairs(modTable) do
                            table.insert(modDump, string.format("   • [%s] = %s", tostring(k), typeof(v)))

                            if type(v) == "function" then
                                -- Extraer constantes si el ejecutor lo permite
                                if getConsts then
                                    pcall(function()
                                        local cList = {}
                                        for _, c in pairs(getConsts(v)) do
                                            if type(c) == "string" or type(c) == "number" then
                                                table.insert(cList, tostring(c))
                                            end
                                        end
                                        if #cList > 0 then
                                            table.insert(modDump, "      Consts: " .. table.concat(cList, ", "))
                                        end
                                    end)
                                end

                                -- Envolver la función para capturar cuando el juego la llame al disparar
                                local id = path .. "." .. tostring(k)
                                if not wrappedFunctions[id] then
                                    wrappedFunctions[id] = true
                                    local originalFn = v
                                    modTable[k] = function(...)
                                        local args = {...}
                                        local argList = {}
                                        for i = 1, select("#", ...) do
                                            table.insert(argList, string.format("Arg[%d]: %s", i, formatValue(args[i])))
                                        end
                                        addLiveLog(Diagnostic.LiveShots, string.format("⚡ %s.%s(\n      %s\n   )", desc.Name, tostring(k), table.concat(argList, ",\n      ")))
                                        return originalFn(...)
                                    end
                                end
                            end
                        end
                    elseif type(modTable) == "function" then
                        table.insert(modDump, "   • (El módulo devuelve una función directa)")
                    end
                end)
            end
        end
    end
    Diagnostic.ModulesDump = modDump
end

-- ==============================================================================
-- 3. MONITOREAR BINDABLE EVENTS (SHOTFIRED / SHOTHIT) Y ATRIBUTOS DEL ARMA
-- ==============================================================================
local watchedTools = {}

local function watchToolEvents(tool)
    if not tool or not tool:IsA("Tool") or watchedTools[tool] then return end
    watchedTools[tool] = true

    -- Vigilar cambios en atributos (Ammo, RandomKey, Cooldown, Reloading, etc.)
    tool.AttributeChanged:Connect(function(attrName)
        local val = tool:GetAttribute(attrName)
        addLiveLog(Diagnostic.AttrChanges, string.format("🔧 [%s] Attr '%s' cambió a: %s", tool.Name, attrName, tostring(val)))
    end)

    -- Vigilar BindableEvents internos (ShotFired, ShotHit, SwingEvent)
    for _, desc in ipairs(tool:GetDescendants()) do
        if desc:IsA("BindableEvent") then
            desc.Event:Connect(function(...)
                local args = {...}
                local argList = {}
                for i = 1, select("#", ...) do
                    table.insert(argList, string.format("Arg[%d]: %s", i, formatValue(args[i])))
                end
                addLiveLog(Diagnostic.LiveShots, string.format("🎯 Bindable %s.%s -> %s", tool.Name, desc.Name, table.concat(argList, " | ")))
            end)
        end
    end
end

local function scanAndWatchAllTools()
    for _, cont in ipairs({lp.Character, lp:FindFirstChild("Backpack")}) do
        if cont then
            for _, t in ipairs(cont:GetChildren()) do
                watchToolEvents(t)
            end
            cont.ChildAdded:Connect(watchToolEvents)
        end
    end
end

-- ==============================================================================
-- 4. EXTRAER STRINGS DE BYTECODE / DECOMPILE DE LOS SCRIPTS DE ARMAS
-- ==============================================================================
local function extractStringsFromBytecode(scriptObj)
    local getBytecode = getscriptbytecode or dumpstring
    if not getBytecode then return nil end

    local ok, raw = pcall(getBytecode, scriptObj)
    if not ok or type(raw) ~= "string" or #raw == 0 then return nil end

    -- Extraer palabras legibles (ASCII >= 4 caracteres) del bytecode compilado
    local words = {}
    local seen = {}
    for word in raw:gmatch("[%w_%./:%-%s]{4,40}") do
        local clean = word:match("^%s*(.-)%s*$")
        if clean and #clean >= 4 and not seen[clean] then
            if clean:find("Shoot") or clean:find("Hit") or clean:find("Reload") or clean:find("Key") 
               or clean:find("Ammo") or clean:find("Proj") or clean:find("Fire") or clean:find("Use") 
               or clean:find("Virus") or clean:find("Target") or clean:find("Ray") or clean:find("Mouse") 
               or clean:find("Cam") or clean:find("Origin") or clean:find("Dir") or clean:find(" Pos") then
                seen[clean] = true
                table.insert(words, clean)
            end
        end
    end
    return words
end

local function inspectGunScripts()
    local sDump = {}
    local getConsts = (debug and debug.getconstants) or getconstants

    -- Buscar todos los LocalScripts dentro de Tools, PlayerGui.ToolUI y PlayerScripts
    local searchRoots = {
        lp.Character,
        lp:FindFirstChild("Backpack"),
        lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("ToolUI"),
        lp:FindFirstChild("PlayerScripts"),
        ReplicatedStorage:FindFirstChild("Modules")
    }

    for _, root in ipairs(searchRoots) do
        if root then
            for _, desc in ipairs(root:GetDescendants()) do
                if desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
                    local n = desc.Name:lower()
                    local full = desc:GetFullName()
                    if full:find("Uzi") or full:find("Pistol") or full:find("Infiltrate") or full:find("Override") 
                       or full:find("Projectile") or full:find("Gun") or full:find("QuickNet") or n:find("client") or n:find("weapon") then

                        table.insert(sDump, string.format("📜 SCRIPT: %s (%s)", full, desc.ClassName))

                        -- Intento A: Decompile directo
                        if decompile then
                            pcall(function()
                                local src = decompile(desc)
                                if src and #src > 10 then
                                    table.insert(sDump, "--- DECOMPILED SOURCE ---")
                                    table.insert(sDump, src:sub(1, 1800))
                                end
                            end)
                        end

                        -- Intento B: Bytecode String Extraction
                        local bcWords = extractStringsFromBytecode(desc)
                        if bcWords and #bcWords > 0 then
                            table.insert(sDump, "   [Bytecode Strings]: " .. table.concat(bcWords, " | "))
                        end

                        -- Intento C: getsenv
                        if getsenv and desc:IsA("LocalScript") then
                            pcall(function()
                                local env = getsenv(desc)
                                for k, v in pairs(env) do
                                    if k ~= "_G" and k ~= "shared" then
                                        table.insert(sDump, string.format("   [senv] %s = %s", tostring(k), formatValue(v)))
                                        if type(v) == "function" and getConsts then
                                            pcall(function()
                                                local cl = {}
                                                for _, c in pairs(getConsts(v)) do
                                                    if type(c) == "string" or type(c) == "number" then
                                                        table.insert(cl, tostring(c))
                                                    end
                                                end
                                                if #cl > 0 then
                                                    table.insert(sDump, "      Consts: " .. table.concat(cl, ", "))
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

    -- Intento D: Buscar funciones en getgc() que contengan "ProjectileHit" o "RandomKey"
    if getgc and getConsts then
        pcall(function()
            table.insert(sDump, "\n=== FUNCIONES EN MEMORIA (GETGC) CON SHOOT / PROJECTILEHIT / RANDOMKEY ===")
            local gcCount = 0
            for _, v in ipairs(getgc(false)) do
                if type(v) == "function" and islclosure and islclosure(v) then
                    local ok, consts = pcall(getConsts, v)
                    if ok and type(consts) == "table" then
                        local match = false
                        local cStr = {}
                        for _, c in pairs(consts) do
                            if type(c) == "string" then
                                table.insert(cStr, c)
                                if c == "ProjectileHit" or c == "RandomKey" or c == "ReloadOne" or c == "Infiltrate" or c == "DrawProjectile" then
                                    match = true
                                end
                            elseif type(c) == "number" then
                                table.insert(cStr, tostring(c))
                            end
                        end
                        if match then
                            gcCount = gcCount + 1
                            if gcCount <= 20 then
                                local fName = (debug and debug.info and debug.info(v, "n")) or "anon"
                                local fSrc = (debug and debug.info and debug.info(v, "s")) or "?"
                                local fLine = (debug and debug.info and debug.info(v, "l")) or "?"
                                table.insert(sDump, string.format("🔍 GC Func '%s' (%s:%s)\n   Consts: %s", tostring(fName), tostring(fSrc), tostring(fLine), table.concat(cStr, ", ")))
                            end
                        end
                    end
                end
            end
        end)
    end

    Diagnostic.ScriptsDump = sDump
end

-- Iniciar escuchas en vivo
scanCapabilities()
hookAllCombatModules()
scanAndWatchAllTools()

-- ==============================================================================
-- 5. VENTANA VISUAL PARA EXTRAER Y COPIAR
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAimForensicV2"
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
Title.Text = "  🔬 ESCÁNER DE DISPARO SIN AIM (CAPTURA DE MÓDULOS Y GC)"
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
OutputBox.Text = "INSTRUCCIONES:\n1. Equipa tu Infiltrator Uzi o Pistol en la mano.\n2. Dispárale 2 balas a un zombie manualmente y recarga (R).\n3. Toca el botón verde '1. EXTRAER DATOS CAPTURADOS'.\n4. Toca el botón azul '2. COPIAR REPORTE' y pégalo en el chat."
OutputBox.Parent = MainFrame

local function buildReportText()
    scanCapabilities()
    scanAndWatchAllTools()
    inspectGunScripts()

    local out = {
        "==================================================================",
        "     REPORTE DE INGENIERÍA INVERSA: DISPARO Y RECARGA (SIN HOOK)  ",
        "==================================================================",
        "\n[1. CAPACIDADES DEL EJECUTOR]:",
        " " .. table.concat(Diagnostic.Capabilities, " | "),
        "\n[2. DISPAROS Y LLAMADAS A MÓDULOS CAPTURADOS EN VIVO]:"
    }

    if #Diagnostic.LiveShots == 0 then
        table.insert(out, " (Ningún disparo registrado aún. Equipa tu arma y dispara 1 o 2 veces manualmente).")
    else
        for _, s in ipairs(Diagnostic.LiveShots) do table.insert(out, " " .. s) end
    end

    table.insert(out, "\n[3. CAMBIOS DE ATRIBUTOS AL DISPARAR / RECARGAR]:")
    if #Diagnostic.AttrChanges == 0 then
        table.insert(out, " (Sin cambios de atributos aún).")
    else
        for _, a in ipairs(Diagnostic.AttrChanges) do table.insert(out, " " .. a) end
    end

    table.insert(out, "\n[4. MÓDULOS DE COMBATE EN REPLICATEDSTORAGE]:")
    for _, m in ipairs(Diagnostic.ModulesDump) do table.insert(out, " " .. m) end

    table.insert(out, "\n[5. SCRIPTS, BYTECODE Y FUNCIONES GC DE ARMAS]:")
    for _, sc in ipairs(Diagnostic.ScriptsDump) do table.insert(out, " " .. sc) end

    return table.concat(out, "\n")
end

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -10, 0, 38)
ScanBtn.Position = UDim2.new(0, 10, 0, 380)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 80)
ScanBtn.Text = "🔍 1. EXTRAER DATOS CAPTURADOS"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 11
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ EXTRAYENDO..."
    task.wait(0.05)
    OutputBox.Text = buildReportText()
    ScanBtn.Text = "✅ ¡DATOS LISTOS!"
    task.wait(1)
    ScanBtn.Text = "🔍 1. EXTRAER DATOS CAPTURADOS"
end)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 38)
CopyBtn.Position = UDim2.new(0.52, 0, 0, 380)
CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 105, 180)
CopyBtn.Text = "📋 2. COPIAR REPORTE"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = ScreenGui.MainFrame

CopyBtn.MouseButton1Click:Connect(function()
    local txt = buildReportText()
    OutputBox.Text = txt
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 2. COPIAR REPORTE"
end)
