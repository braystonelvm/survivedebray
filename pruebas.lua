-- ==============================================================================
-- ESPÍA FORENSE: REPAIR HAMMER, GRIP, ARGUMENTOS Y REMOTE SPY (CON WIDGET)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local SpyData = {
    LastRemoteArgs = {},
    LastCallTime = 0,
    CallsCount = 0,
    ToolDropCause = "Monitoreando...",
    DecompiledClient = "No disponible"
}

local lines = {}
local function log(t) table.insert(lines, t) end

-- 1. REMOTE SPY DEDICADO AL MARTILLO
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if method == "FireServer" and (self.Name == "Repair" or self.Name == "Deconstruct") then
            SpyData.CallsCount = SpyData.CallsCount + 1
            local now = tick()
            local interval = SpyData.LastCallTime > 0 and (now - SpyData.LastCallTime) or 0
            SpyData.LastCallTime = now

            local argDetails = {}
            for i, v in ipairs(args) do
                table.insert(argDetails, string.format("Arg[%d]: (%s) %s", i, typeof(v), tostring(v)))
            end

            SpyData.LastRemoteArgs = argDetails

            print(string.format("[ESPÍA MARTILLO] %s disparado | Intervalo: %.3fs", self.Name, interval))
            for _, d in ipairs(argDetails) do
                print("   -> " .. d)
            end
        end

        return oldNamecall(self, ...)
    end)
end

-- 2. DETECTOR DE CAÍDA Y ESTADO DEL AGARRE (GRIP / HANDLE)
local function checkHammerPhysicalState()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))

    local report = {}
    table.insert(report, string.format("• ¿Personaje sentado?: %s", tostring(hum and hum.Sit or false)))
    if hum and hum.SeatPart then
        table.insert(report, string.format("• Asiento actual: %s (Clase: %s)", hum.SeatPart.Name, hum.SeatPart.ClassName))
    end

    if hammer then
        table.insert(report, string.format("• Ubicación actual del martillo: %s", hammer.Parent and hammer.Parent.Name or "Nil"))
        local handle = hammer:FindFirstChild("Handle")
        if handle then
            table.insert(report, string.format("• Handle: Anchored = %s | CanCollide = %s", tostring(handle.Anchored), tostring(handle.CanCollide)))
        else
            table.insert(report, "• ALERTA: El martillo NO tiene Handle o fue destruido.")
        end

        -- Revisar si el Grip existe en la mano
        local grip = (char and char:FindFirstChild("RightGrip", true)) or (handle and handle:FindFirstChildOfClass("Weld"))
        if grip then
            table.insert(report, string.format("• Agarre (Grip/Weld): ACTIVO (%s conectando %s con %s)", grip.ClassName, tostring(grip.Part0), tostring(grip.Part1)))
        else
            table.insert(report, "• ALERTA CRÍTICA: No existe 'RightGrip'. El martillo se soltó de las manos y cayó por física.")
        end
    else
        table.insert(report, "• No se detectó 'Repair Hammer' en Character ni en Backpack.")
    end

    return table.concat(report, "\n")
end

-- 3. EXTRAER CÓDIGO FUENTE DE REPAIRHAMMERCLIENT
local function tryExtractClientCode()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))
    local clientScript = hammer and hammer:FindFirstChild("RepairHammerClient")

    if not clientScript then
        return "No se encontró el LocalScript RepairHammerClient."
    end

    -- Si el ejecutor soporta decompile()
    if decompile then
        local success, code = pcall(function() return decompile(clientScript) end)
        if success and code and #code > 10 then
            return code
        end
    end

    -- Respaldo: volcar constantes si decompile no está soportado
    if getconstants then
        local consts = getconstants(clientScript)
        local cList = {}
        for k, v in pairs(consts) do
            table.insert(cList, tostring(v))
        end
        return "Constantes del script: " .. table.concat(cList, ", ")
    end

    return "Tu ejecutor no soporta funciones de decompilación de código."
end

-- ==============================================================================
-- 4. INTERFAZ Y WIDGET FLOTANTE
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "ESPÍA FORENSE DE REPARACIÓN",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local TabSpy = Window:AddTab({ Title = "Espía Martillo", Icon = "file-search" })

local LiveStatusParagraph = TabSpy:AddParagraph({
    Title = "Captura de Golpes del Martillo",
    Content = "Equipa tu martillo y dale 1 o 2 golpes manuales al camión o a una valla..."
})

local GripStatusParagraph = TabSpy:AddParagraph({
    Title = "Estado Físico del Agarre (Grip)",
    Content = "Analizando..."
})

TabSpy:AddButton({
    Title = "📋 COPIAR REPORTE COMPLETO AL PORTAPAPELES",
    Description = "Copia argumentos exactos, estado del Grip y código del cliente",
    Callback = function()
        table.clear(lines)
        log("==================================================================")
        log("           INFORME FORENSE: CAPTURA DE REMOTE REPAIR              ")
        log("==================================================================")
        log("Hora: " .. os.date("%X"))
        log("\n[1. ESTADO FÍSICO DEL MARTILLO Y AGARRE]:")
        log(checkHammerPhysicalState())
        log("\n------------------------------------------------------------------")
        log(string.format("[2. LLAMADAS CAPTURADAS AL REMOTE (Total: %d)]:", SpyData.CallsCount))
        if #SpyData.LastRemoteArgs > 0 then
            for _, arg in ipairs(SpyData.LastRemoteArgs) do
                log("   " .. arg)
            end
        else
            log(">> Aún no has dado ningún martillazo manual desde que ejecutaste el script.")
        end
        log("\n------------------------------------------------------------------")
        log("[3. ANÁLISIS DE CÓDIGO (RepairHammerClient)]:")
        log(tryExtractClientCode())
        log("==================================================================")

        local fullReport = table.concat(lines, "\n")
        if setclipboard then setclipboard(fullReport) elseif toclipboard then toclipboard(fullReport) end

        Fluent:Notify({
            Title = "Reporte Copiado",
            Content = "Pega los datos aquí para ver qué argumentos pide el martillo.",
            Duration = 4
        })
    end
end)

-- WIDGET FLOTANTE CIRCULAR (ROJO)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpyWidgetScreenGui"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- ACTUALIZACIÓN EN VIVO DE LA INTERFAZ
task.spawn(function()
    while true do
        task.wait(0.5)
        GripStatusParagraph:SetDesc(checkHammerPhysicalState())

        if #SpyData.LastRemoteArgs > 0 then
            LiveStatusParagraph:SetDesc(string.format(
                "Golpes registrados: %d\nÚltimos argumentos:\n%s",
                SpyData.CallsCount,
                table.concat(SpyData.LastRemoteArgs, "\n")
            ))
        end
    end
end)

Fluent:Notify({
    Title = "ESPÍA DE MARTILLO ACTIVO",
    Content = "Toca el widget si se cierra. Da 1 golpe normal con el martillo.",
    Duration = 4
})
