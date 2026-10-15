-- ==============================================================================
-- INTERCEPTADOR FORENSE: DISPAROS (SILENT AIM), PODERES HACKER Y SLOTS 5/6
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local CapturedLogs = {
    RemoteCalls = {},
    HotbarSlots = {},
    WeaponStats = {}
}

local MaxLogs = 40

local function serializeArg(val, depth)
    depth = depth or 0
    if depth > 2 then return "..." end
    local t = typeof(val)

    if t == "Instance" then
        return string.format("[Instance: %s (%s) -> %s]", val.Name, val.ClassName, val:GetFullName())
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.2f, %.2f, %.2f)", val.X, val.Y, val.Z)
    elseif t == "CFrame" then
        local p = val.Position
        return string.format("CFrame(Pos: %.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
    elseif t == "string" then
        return '"' .. val .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            table.insert(parts, string.format("[%s] = %s", tostring(k), serializeArg(v, depth + 1)))
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    else
        return string.format("[%s: %s]", t, tostring(val))
    end
end

local function addRemoteLog(txt)
    table.insert(CapturedLogs.RemoteCalls, 1, txt)
    if #CapturedLogs.RemoteCalls > MaxLogs then
        table.remove(CapturedLogs.RemoteCalls)
    end
end

-- ==============================================================================
-- 1. ESCÁNER DE HOTBAR (CÓMO SE GUARDAN LOS SLOTS 1 AL 6)
-- ==============================================================================
local function scanHotbarAndSlots()
    local list = {}
    local pGui = lp:FindFirstChild("PlayerGui")

    -- Revisar toda la interfaz buscando los slots del inventario (1 al 9)
    if pGui then
        for _, desc in ipairs(pGui:GetDescendants()) do
            local n = desc.Name:lower()
            if n:find("hotbar") or n:find("toolbar") or n:find("inventory") or n:find("slot") or tonumber(desc.Name) ~= nil then
                if desc:IsA("GuiObject") then
                    local extra = ""
                    for k, v in pairs(desc:GetAttributes()) do
                        extra = extra .. string.format(" [%s=%s]", k, tostring(v))
                    end
                    for _, sub in ipairs(desc:GetChildren()) do
                        if sub:IsA("TextLabel") and sub.Text ~= "" then
                            extra = extra .. string.format(" (Txt: '%s')", sub.Text)
                        elseif sub:IsA("ObjectValue") then
                            extra = extra .. string.format(" (ObjVal: %s=%s)", sub.Name, tostring(sub.Value))
                        end
                    end
                    if extra ~= "" or n:find("hotbar") or n:find("slot") then
                        table.insert(list, string.format("🎒 UI: %s (%s) -> %s%s", desc.Name, desc.ClassName, desc:GetFullName(), extra))
                    end
                end
            end
        end
    end

    -- Revisar atributos de las herramientas en Backpack y Character por si tienen número de Slot
    for _, cont in ipairs({lp.Character, lp:FindFirstChild("Backpack")}) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") then
                    local attrs = {}
                    for k, v in pairs(tool:GetAttributes()) do
                        table.insert(attrs, string.format("%s=%s", k, tostring(v)))
                    end
                    table.insert(list, string.format("🔧 Tool '%s' (en %s) | Attrs: %s", tool.Name, cont.Name, table.concat(attrs, ", ")))
                end
            end
        end
    end

    CapturedLogs.HotbarSlots = list
end

-- ==============================================================================
-- 2. ESCÁNER DE STATS DE ARMAS Y HABILIDADES
-- ==============================================================================
local function scanWeaponStats()
    local list = {}
    for _, cont in ipairs({lp.Character, lp:FindFirstChild("Backpack")}) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") then
                    table.insert(list, string.format("=== TOOL: %s ===", tool.Name))
                    local stats = tool:FindFirstChild("Stats")
                    if stats then
                        for k, v in pairs(stats:GetAttributes()) do
                            table.insert(list, string.format("   Stats [Attr] %s = %s", k, tostring(v)))
                        end
                        for _, child in ipairs(stats:GetChildren()) do
                            if child:IsA("ValueBase") then
                                table.insert(list, string.format("   Stats [Val] %s = %s", child.Name, tostring(child.Value)))
                            end
                        end
                    end
                end
            end
        end
    end
    CapturedLogs.WeaponStats = list
end

-- ==============================================================================
-- 3. HOOK METAMETHOD (__NAMECALL) PARA CAPTURAR LOS ARGUMENTOS DE DISPARO
-- ==============================================================================
local hookInstalled = false

pcall(function()
    if hookmetamethod and getnamecallmethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
                local name = self.Name
                local fullName = self:GetFullName()

                -- Filtrar eventos de armas, disparos y habilidades
                if name == "Shoot" or name == "ProjectileHit" or name == "Use" or name == "Reload" 
                   or name == "ReloadOne" or name == "ChargeRemote" or name == "Swing" or name == "HitTargets" 
                   or fullName:find("Tools") or fullName:find("Abilities") then

                    local args = {...}
                    local argStrings = {}
                    for i, a in ipairs(args) do
                        table.insert(argStrings, string.format("Arg[%d]: %s", i, serializeArg(a)))
                    end

                    -- Si el remote está dentro de un Tool, anotar también su RandomKey actual
                    local parentTool = self:FindFirstAncestorOfClass("Tool")
                    local keyInfo = ""
                    if parentTool then
                        keyInfo = string.format(" | Tool: '%s' (RandomKey: %s)", parentTool.Name, tostring(parentTool:GetAttribute("RandomKey")))
                    end

                    local logEntry = string.format(
                        "📡 [%s] %s%s\n   Ruta: %s\n   %s",
                        method, name, keyInfo, fullName,
                        (#argStrings > 0) and table.concat(argStrings, "\n   ") or "(Sin argumentos)"
                    )
                    addRemoteLog(logEntry)
                end
            end
            return oldNamecall(self, ...)
        end)
        hookInstalled = true
    end
end)

-- ==============================================================================
-- 4. INTERFAZ VISUAL DE CAPTURA
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GunSpyForensicGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 540, 0, 430)
MainFrame.Position = UDim2.new(0.5, -270, 0.5, -215)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 36)
Title.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
Title.Text = "  🔫 INTERCEPTADOR DE DISPAROS (SILENT AIM) + SLOTS 5 Y 6"
Title.TextColor3 = Color3.fromRGB(0, 255, 190)
Title.TextSize = 12
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 320)
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
OutputBox.Text = string.format(
    "Estado del Hook __namecall: %s\n\nPASOS:\n1. Equipa tu arma del Slot 5 o 6 y dispárale 1 o 2 balas a un zombie.\n2. Usa 1 vez tu poder 'Infiltrate' sobre un zombie.\n3. Presiona 'COPIAR REPORTE COMPLETO' abajo y pégalo en el chat.",
    hookInstalled and "✅ ACTIVO (Interceptando en vivo)" or "⚠️ No soportado en este executor"
)
OutputBox.Parent = MainFrame

local function buildFullReport()
    scanHotbarAndSlots()
    scanWeaponStats()

    local out = {
        "==================================================================",
        "     REPORTE DE ARGUMENTOS DE DISPARO, PODERES Y SLOTS 5/6        ",
        "==================================================================",
        "Hook Activo: " .. tostring(hookInstalled),
        "\n[1. PAQUETES INTERCEPTADOS AL DISPARAR / USAR PODER]:"
    }

    if #CapturedLogs.RemoteCalls == 0 then
        table.insert(out, " (Aún no se han registrado disparos. Dispara 1 bala y usa Infiltrate).")
    else
        for _, entry in ipairs(CapturedLogs.RemoteCalls) do
            table.insert(out, entry)
            table.insert(out, "--------------------------------------------------")
        end
    end

    table.insert(out, "\n[2. ESTRUCTURA DE SLOTS / HOTBAR (1 AL 6)]:")
    for _, s in ipairs(CapturedLogs.HotbarSlots) do
        table.insert(out, " " .. s)
    end

    table.insert(out, "\n[3. STATS DE ARMAS Y PODERES]:")
    for _, w in ipairs(CapturedLogs.WeaponStats) do
        table.insert(out, " " .. w)
    end

    return table.concat(out, "\n")
end

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0.48, -10, 0, 38)
RefreshBtn.Position = UDim2.new(0, 10, 0, 375)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 85)
RefreshBtn.Text = "🔄 VER CAPTURAS EN PANTALLA"
RefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RefreshBtn.TextSize = 11
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.Parent = MainFrame

RefreshBtn.MouseButton1Click:Connect(function()
    OutputBox.Text = buildFullReport()
end)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 38)
CopyBtn.Position = UDim2.new(0.52, 0, 0, 375)
CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 105, 180)
CopyBtn.Text = "📋 COPIAR REPORTE COMPLETO"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

CopyBtn.MouseButton1Click:Connect(function()
    local txt = buildFullReport()
    OutputBox.Text = txt
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR REPORTE COMPLETO"
end)

-- Botón flotante para minimizar
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(45, 105, 180)
FloatBtn.Text = "🔫"
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
