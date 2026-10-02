-- ==============================================================================
-- AUDITOR DE VEHÍCULO: FÍSICAS, MASA, TOUCH Y VARIABLES DE DAÑO
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function getHum()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local report = {}
local function log(str) table.insert(report, str) end

log("================ AUDITORÍA DE VEHÍCULO Y COLISIONES ================")
log("Fecha/Hora: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("Jugador: " .. lp.Name)

local hum = getHum()
local seat = hum and hum.SeatPart

if not (seat and seat:IsA("VehicleSeat")) then
    log("\n⚠️ ERROR: Debes estar sentado en el asiento del auto (VehicleSeat) para ejecutar este script.")
else
    local car = seat:FindFirstAncestorOfClass("Model")
    log(string.format("\n--- [1. INFORMACIÓN GENERAL DEL VEHÍCULO] ---"))
    log(string.format("Modelo: [%s] | Clase: %s", car and car.Name or "Desconocido", car and car.ClassName or "N/A"))
    log(string.format("Asiento: [%s] | Masa Asiento: %.1f | AssemblyMass Total: %.1f", seat.Name, seat.Mass, seat.AssemblyMass))
    log(string.format("Velocidad Actual (AssemblyLinearVelocity): (%.1f, %.1f, %.1f) - Magnitud: %.1f", 
        seat.AssemblyLinearVelocity.X, seat.AssemblyLinearVelocity.Y, seat.AssemblyLinearVelocity.Z, seat.AssemblyLinearVelocity.Magnitude))

    -- Atributos del vehículo
    log("\n--- [2. ATRIBUTOS DEL AUTO] ---")
    local carAttrCount = 0
    if car then
        for k, v in pairs(car:GetAttributes()) do
            carAttrCount = carAttrCount + 1
            log(string.format("   Auto Attr: [%s] = %s", k, tostring(v)))
        end
    end
    if carAttrCount == 0 then log("   Sin atributos registrados en el modelo.") end

    -- Variables internas (Valores de vida, daño o velocidad)
    log("\n--- [3. OBJETOS DE VALOR Y SCRIPTS DENTRO DEL AUTO] ---")
    if car then
        for _, desc in ipairs(car:GetDescendants()) do
            if desc:IsA("ValueBase") then
                log(string.format("   Valor: [%s] (%s) = %s | Ruta: %s", desc.Name, desc.ClassName, tostring(desc.Value), desc:GetFullName()))
            elseif desc:IsA("Script") or desc:IsA("LocalScript") then
                log(string.format("   Script Interno: [%s] (%s) | Habilitado: %s", desc.Name, desc.ClassName, tostring(desc.Enabled)))
            end
        end
    end

    -- Partes de choque y detección de toques (Bumper, Body, Wheels)
    log("\n--- [4. AUDITORÍA DE PIEZAS DE COLISIÓN (TOUCH & MASS)] ---")
    if car then
        for _, part in ipairs(car:GetDescendants()) do
            if part:IsA("BasePart") then
                local hasTouch = part:FindFirstChildWhichIsA("TouchTransmitter") ~= nil
                local pName = part.Name:lower()
                local isFront = pName:find("bumper") or pName:find("front") or pName:find("hood") or pName:find("body") or pName:find("chassis")

                if hasTouch or isFront then
                    log(string.format("Parte: [%s] | Masa: %.1f | CanCollide: %s | CanTouch: %s | TouchTransmitter: %s", 
                        part.Name, part.Mass, tostring(part.CanCollide), tostring(part.CanTouch), tostring(hasTouch)))
                end
            end
        end
    end

    -- Comprobación de remotes relacionados a vehículos en ReplicatedStorage
    log("\n--- [5. REMOTES DE VEHÍCULO / DAÑO ASOCIADOS] ---")
    local repStorage = game:GetService("ReplicatedStorage")
    for _, r in ipairs(repStorage:GetDescendants()) do
        if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
            local n = r.Name:lower()
            if n:find("car") or n:find("vehic") or n:find("drive") or n:find("ram") or n:find("hit") or n:find("damage") then
                log(string.format("   Remote: [%s] -> %s", r.Name, r:GetFullName()))
            end
        end
    end
end

log("\n=================== FIN DEL REPORTE ===================")

local fullText = table.concat(report, "\n")
if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end

-- Interfaz visual segura en PlayerGui
local existing = lp.PlayerGui:FindFirstChild("CarInspectorGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarInspectorGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = lp:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 380)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 40)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.Text = "🚗 AUDITORÍA DE VEHÍCULO & DAÑO"
Title.TextColor3 = Color3.fromRGB(0, 200, 255)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -38, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
CloseBtn.Parent = MainFrame
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -30, 0, 260)
Scroll.Position = UDim2.new(0, 15, 0, 45)
Scroll.BackgroundColor3 = Color3.fromRGB(13, 14, 17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.Parent = MainFrame
local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 8)
ScrollCorner.Parent = Scroll

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -10, 1, 0)
TextBox.Position = UDim2.new(0, 5, 0, 5)
TextBox.Text = fullText
TextBox.TextColor3 = Color3.fromRGB(230, 230, 230)
TextBox.TextSize = 12
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

Scroll.CanvasSize = UDim2.new(0, 0, 0, #report * 18)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -30, 0, 42)
CopyBtn.Position = UDim2.new(0, 15, 1, -52)
CopyBtn.Text = "COPIAR REPORTE AL PORTAPAPELES"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 14
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 220)
CopyBtn.Parent = MainFrame
local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 8)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end
    CopyBtn.Text = "¡COPIADO!"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    task.wait(1.5)
    CopyBtn.Text = "COPIAR REPORTE AL PORTAPAPELES"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 220)
end)
