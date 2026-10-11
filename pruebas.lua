-- ==============================================================================
-- ESPÍA FORENSE NATIVO: REPAIR HAMMER & REMOTE SPY (SIN DEPENDENCIAS EXTERNAS)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local CapturedEvents = {}
local TotalCalls = 0
local LastCallTime = 0

-- 1. INTERCEPTOR HOOKMETAMETHOD (REMOTE SPY)
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if method == "FireServer" then
            local rName = tostring(self.Name)
            if rName == "Repair" or rName == "Deconstruct" or rName == "Impact" or rName:lower():find("repair") then
                TotalCalls = TotalCalls + 1
                local now = tick()
                local diff = LastCallTime > 0 and string.format("%.3fs", now - LastCallTime) or "Inicio"
                LastCallTime = now

                local argList = {}
                for idx, val in ipairs(args) do
                    local vType = typeof(val)
                    local vStr = tostring(val)
                    if vType == "Instance" then
                        vStr = string.format("%s (%s, Ruta: %s)", val.Name, val.ClassName, val:GetFullName())
                    elseif vType == "Vector3" then
                        vStr = string.format("Vector3.new(%.2f, %.2f, %.2f)", val.X, val.Y, val.Z)
                    elseif vType == "CFrame" then
                        vStr = string.format("CFrame.new(%.2f, %.2f, %.2f)", val.Position.X, val.Position.Y, val.Position.Z)
                    end
                    table.insert(argList, string.format("Arg[%d] (%s): %s", idx, vType, vStr))
                end

                local entry = {
                    Remote = rName,
                    Path = self:GetFullName(),
                    Time = os.date("%X"),
                    Interval = diff,
                    Args = argList
                }
                table.insert(CapturedEvents, entry)

                -- Imprimir directo en consola F9 de respaldo
                print(string.format("[ESPÍA] %s disparado (%s):", rName, diff))
                for _, a in ipairs(argList) do
                    print("   " .. a)
                end
            end
        end

        return oldNamecall(self, ...)
    end)
else
    warn("[ESPÍA]: Tu ejecutor no soporta hookmetamethod.")
end

-- 2. DETECTOR DE ESTADO FÍSICO DEL MARTILLO Y AGARRE
local function getPhysicalHammerState()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))

    local lines = {}
    table.insert(lines, string.format("• Personaje sentado: %s", tostring(hum and hum.Sit or false)))
    if hum and hum.SeatPart then
        table.insert(lines, string.format("• Asiento actual: %s (%s)", hum.SeatPart.Name, hum.SeatPart.ClassName))
    end

    if hammer then
        table.insert(lines, string.format("• Ubicación: %s", hammer.Parent and hammer.Parent.Name or "Desconocida"))
        local handle = hammer:FindFirstChild("Handle")
        if handle then
            table.insert(lines, string.format("• Handle: Anchored=%s | CanCollide=%s", tostring(handle.Anchored), tostring(handle.CanCollide)))
        else
            table.insert(lines, "• ALERTA: No existe 'Handle' en el martillo.")
        end

        local grip = char and char:FindFirstChild("RightGrip", true)
        if grip then
            table.insert(lines, string.format("• Agarre: CONECTADO (%s con %s)", tostring(grip.Part0), tostring(grip.Part1)))
        else
            table.insert(lines, "• ALERTA AGARRE: No existe 'RightGrip' (se soltó de las manos y cayó al piso).")
        end
    else
        table.insert(lines, "• No se encontró 'Repair Hammer' en Character ni Backpack.")
    end

    return table.concat(lines, "\n")
end

-- 3. CREACIÓN DE INTERFAZ 100% NATIVA ROBLOX (SIN LIBRERÍAS EXTERNAS)
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NativeRepairSpyGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- Botón Flotante (Widget Rojo Arrastrable)
local FloatBtn = Instance.new("ImageButton")
FloatBtn.Name = "FloatingWidget"
FloatBtn.Size = UDim2.new(0, 50, 0, 50)
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
BtnText.Text = "🔧"
BtnText.TextSize = 24
BtnText.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnText.Parent = FloatBtn

-- Ventana Principal
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 380)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
TitleBar.Text = "  ESPÍA FORENSE: REPAIR HAMMER"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 14
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Contenedor de Información
local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, -20, 0, 110)
InfoLabel.Position = UDim2.new(0, 10, 0, 44)
InfoLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
InfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
InfoLabel.TextSize = 12
InfoLabel.Font = Enum.Font.Code
InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
InfoLabel.TextYAlignment = Enum.TextYAlignment.Top
InfoLabel.Text = "Analizando martillo..."
InfoLabel.Parent = MainFrame

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 6)
InfoCorner.Parent = InfoLabel

-- Lista de Eventos Capturados
local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size = UDim2.new(1, -20, 0, 155)
LogScroll.Position = UDim2.new(0, 10, 0, 162)
LogScroll.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LogScroll.ScrollBarThickness = 6
LogScroll.Parent = MainFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogScroll

local LogText = Instance.new("TextLabel")
LogText.Size = UDim2.new(1, -10, 1, 0)
LogText.Position = UDim2.new(0, 5, 0, 5)
LogText.BackgroundTransparency = 1
LogText.TextColor3 = Color3.fromRGB(0, 255, 170)
LogText.TextSize = 11
LogText.Font = Enum.Font.Code
LogText.TextXAlignment = Enum.TextXAlignment.Left
LogText.TextYAlignment = Enum.TextYAlignment.Top
LogText.Text = "Esperando que des un martillazo manual..."
LogText.Parent = LogScroll

-- Botón de Copiar Reporte
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 42)
CopyBtn.Position = UDim2.new(0, 10, 1, -50)
CopyBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
CopyBtn.Text = "📋 COPIAR REPORTE COMPLETO AL PORTAPAPELES"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 13
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 8)
CopyCorner.Parent = CopyBtn

-- Función Toggle Ventana
local isVisible = true
FloatBtn.MouseButton1Click:Connect(function()
    isVisible = not isVisible
    MainFrame.Visible = isVisible
end)

-- Actualización periódica de texto
task.spawn(function()
    while true do
        task.wait(0.5)
        InfoLabel.Text = " " .. getPhysicalHammerState():gsub("\n", "\n ")

        if #CapturedEvents > 0 then
            local display = {}
            for i = #CapturedEvents, math.max(1, #CapturedEvents - 5), -1 do
                local ev = CapturedEvents[i]
                table.insert(display, string.format("[%s] %s (%s):", ev.Time, ev.Remote, ev.Interval))
                for _, a in ipairs(ev.Args) do
                    table.insert(display, "  " .. a)
                end
            end
            LogText.Text = table.concat(display, "\n")
            LogScroll.CanvasSize = UDim2.new(0, 0, 0, #display * 16)
        end
    end
end)

-- Copiado al Portapapeles
CopyBtn.MouseButton1Click:Connect(function()
    local rLines = {}
    table.insert(rLines, "==================================================================")
    table.insert(rLines, "           INFORME FORENSE: CAPTURA DE REMOTE REPAIR              ")
    table.insert(rLines, "==================================================================")
    table.insert(rLines, "Hora: " .. os.date("%X"))
    table.insert(rLines, "\n[1. ESTADO FÍSICO DEL MARTILLO Y AGARRE]:")
    table.insert(rLines, getPhysicalHammerState())
    table.insert(rLines, "\n------------------------------------------------------------------")
    table.insert(rLines, string.format("[2. LLAMADAS CAPTURADAS AL REMOTE (Total: %d)]:", TotalCalls))

    if #CapturedEvents > 0 then
        for i, ev in ipairs(CapturedEvents) do
            table.insert(rLines, string.format("\n• Disparo #%d [%s] -> %s (Intervalo: %s)", i, ev.Time, ev.Remote, ev.Interval))
            for _, arg in ipairs(ev.Args) do
                table.insert(rLines, "   " .. arg)
            end
        end
    else
        table.insert(rLines, ">> No se registraron disparos manuales.")
    end
    table.insert(rLines, "==================================================================")

    local fullText = table.concat(rLines, "\n")
    if setclipboard then
        setclipboard(fullText)
    elseif toclipboard then
        toclipboard(fullText)
    end
    print(fullText)

    CopyBtn.Text = "✅ ¡REPORTE COPIADO! PEGA AQUÍ"
    task.wait(2)
    CopyBtn.Text = "📋 COPIAR REPORTE COMPLETO AL PORTAPAPELES"
end)
