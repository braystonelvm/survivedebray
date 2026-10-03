-- ==============================================================================
-- AUDITOR Y COMPARADOR DE FÍSICAS DE VEHÍCULO (NORMAL VS BUGGEADO)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local SnapshotNormal = nil
local SnapshotBug = nil

local function getCarAndSeat()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if seat and seat:IsA("VehicleSeat") then
        local car = seat:FindFirstAncestorOfClass("Model")
        return car, seat, hum, char
    end
    return nil, nil, nil, nil
end

-- EXTRAER TODAS LAS VARIABLES FÍSICAS Y DE RED DEL VEHÍCULO
local function captureVehicleData()
    local car, seat, hum, char = getCarAndSeat()
    if not seat or not car then return nil end

    local data = {}
    data.CarName = car.Name
    data.SeatName = seat.Name

    -- 1. FÍSICAS Y MASA
    data.SeatMass = seat.Mass
    data.AssemblyMass = seat.AssemblyMass
    data.RootPartName = seat.AssemblyRootPart and seat.AssemblyRootPart.Name or "None"
    data.Velocity = seat.AssemblyLinearVelocity
    data.AngularVelocity = seat.AssemblyAngularVelocity

    -- 2. PROPIEDADES FÍSICAS DE LA MATERIA
    local phys = seat.CurrentPhysicalProperties
    if phys then
        data.Density = phys.Density
        data.Friction = phys.Friction
        data.Elasticity = phys.Elasticity
        data.FrictionWeight = phys.FrictionWeight
        data.ElasticityWeight = phys.ElasticityWeight
    else
        data.Density = "Default"
    end

    -- 3. ESTADO DEL CONDUCTOR Y UNIONES (WELDS)
    data.HumanoidState = hum:GetState().Name
    data.PlatformStand = hum.PlatformStand
    data.SeatWeldExists = seat:FindFirstChildOfClass("Weld") ~= nil or seat:FindFirstChildOfClass("WeldConstraint") ~= nil

    -- 4. CONTEO DE UNIONES Y PIEZAS ADHERIDAS (ZOMBIES / RESTOS)
    local totalParts = 0
    local totalWelds = 0
    local totalConstraints = 0
    for _, desc in ipairs(car:GetDescendants()) do
        if desc:IsA("BasePart") then totalParts = totalParts + 1 end
        if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("Motor6D") then totalWelds = totalWelds + 1 end
        if desc:IsA("Constraint") then totalConstraints = totalConstraints + 1 end
    end
    data.TotalParts = totalParts
    data.TotalWelds = totalWelds
    data.TotalConstraints = totalConstraints

    -- 5. ATRIBUTOS DEL VEHÍCULO
    data.Attributes = {}
    for k, v in pairs(car:GetAttributes()) do
        data.Attributes[k] = tostring(v)
    end
    for k, v in pairs(seat:GetAttributes()) do
        data.Attributes["Seat_" .. k] = tostring(v)
    end

    -- 6. VALORES INTERNOS DE A-CHASSIS
    data.ChassisValues = {}
    local valuesFolder = car:FindFirstChild("Values", true)
    if valuesFolder then
        for _, val in ipairs(valuesFolder:GetChildren()) do
            if val:IsA("ValueBase") then
                data.ChassisValues[val.Name] = tostring(val.Value)
            end
        end
    end

    return data
end

-- ================= INTERFAZ VISUAL EN PANTALLA =================
local existing = lp.PlayerGui:FindFirstChild("CarAuditorGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarAuditorGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 440)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 36)
Title.Position = UDim2.new(0, 15, 0, 4)
Title.Text = "🔬 AUDITOR DE FÍSICAS (NORMAL VS BUGGEADO)"
Title.TextColor3 = Color3.fromRGB(255, 180, 0)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.TextSize = 14
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
CloseBtn.Parent = MainFrame
local cCorner = Instance.new("UICorner")
cCorner.CornerRadius = UDim.new(0, 6)
cCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- BOTÓN 1: MUESTRA NORMAL
local BtnNormal = Instance.new("TextButton")
BtnNormal.Size = UDim2.new(0.46, 0, 0, 36)
BtnNormal.Position = UDim2.new(0, 15, 0, 44)
BtnNormal.BackgroundColor3 = Color3.fromRGB(0, 140, 90)
BtnNormal.Text = "1. Muestra NORMAL"
BtnNormal.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnNormal.Font = Enum.Font.GothamBold
BtnNormal.TextSize = 13
BtnNormal.Parent = MainFrame
local bnCorner = Instance.new("UICorner")
bnCorner.CornerRadius = UDim.new(0, 6)
bnCorner.Parent = BtnNormal

-- BOTÓN 2: MUESTRA BUGGEADO
local BtnBug = Instance.new("TextButton")
BtnBug.Size = UDim2.new(0.46, 0, 0, 36)
BtnBug.Position = UDim2.new(0.52, 0, 0, 44)
BtnBug.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
BtnBug.Text = "2. Muestra BUGGEADO"
BtnBug.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnBug.Font = Enum.Font.GothamBold
BtnBug.TextSize = 13
BtnBug.Parent = MainFrame
local bbCorner = Instance.new("UICorner")
bbCorner.CornerRadius = UDim.new(0, 6)
bbCorner.Parent = BtnBug

-- ÁREA DE TEXTO DE RESULTADOS
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -30, 0, 300)
Scroll.Position = UDim2.new(0, 15, 0, 88)
Scroll.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.Parent = MainFrame
local sCorner = Instance.new("UICorner")
sCorner.CornerRadius = UDim.new(0, 6)
sCorner.Parent = Scroll

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -10, 1, 0)
TextBox.Position = UDim2.new(0, 5, 0, 5)
TextBox.Text = "Instrucciones:\n1. Súbete al auto en estado normal y presiona el botón '1. Muestra NORMAL'.\n2. Cuando ocurra la Luna Roja y notes que las explosiones YA NO TE EMPUJAN, presiona '2. Muestra BUGGEADO'.\n3. El script comparará ambos estados y te mostrará exactamente qué cambió."
TextBox.TextColor3 = Color3.fromRGB(220, 220, 220)
TextBox.TextSize = 12
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

-- BOTÓN COPIAR
local BtnCopy = Instance.new("TextButton")
BtnCopy.Size = UDim2.new(1, -30, 0, 36)
BtnCopy.Position = UDim2.new(0, 15, 1, -44)
BtnCopy.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
BtnCopy.Text = "COPIAR COMPARATIVA AL PORTAPAPELES"
BtnCopy.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnCopy.Font = Enum.Font.GothamBold
BtnCopy.TextSize = 13
BtnCopy.Parent = MainFrame
local bcCorner = Instance.new("UICorner")
bcCorner.CornerRadius = UDim.new(0, 6)
bcCorner.Parent = BtnCopy

-- COMPARADOR
local function generateComparisonReport()
    if not SnapshotNormal or not SnapshotBug then return end

    local r = {}
    local function add(txt) table.insert(r, txt) end

    add("================ REPORTE COMPARATIVO DE FÍSICAS ================")
    add("Vehículo: " .. SnapshotNormal.CarName)
    add("\n--- [1. ANÁLISIS DE MASA Y ENSAMBLAJE] ---")
    add(string.format("AssemblyMass (Masa Total): NORMAL = %.1f  -->  BUG = %.1f", SnapshotNormal.AssemblyMass, SnapshotBug.AssemblyMass))
    add(string.format("AssemblyRootPart (Pieza Raíz): NORMAL = [%s]  -->  BUG = [%s]", SnapshotNormal.RootPartName, SnapshotBug.RootPartName))
    add(string.format("Total de Piezas en el Auto: NORMAL = %d  -->  BUG = %d", SnapshotNormal.TotalParts, SnapshotBug.TotalParts))
    add(string.format("Total de Uniones (Welds): NORMAL = %d  -->  BUG = %d", SnapshotNormal.TotalWelds, SnapshotBug.TotalWelds))
    add(string.format("Total de Constraints: NORMAL = %d  -->  BUG = %d", SnapshotNormal.TotalConstraints, SnapshotBug.TotalConstraints))

    add("\n--- [2. PROPIEDADES FÍSICAS DE COLISIÓN] ---")
    add(string.format("Densidad: NORMAL = %s  -->  BUG = %s", tostring(SnapshotNormal.Density), tostring(SnapshotBug.Density)))
    add(string.format("Fricción: NORMAL = %s  -->  BUG = %s", tostring(SnapshotNormal.Friction), tostring(SnapshotBug.Friction)))
    add(string.format("Elasticidad: NORMAL = %s  -->  BUG = %s", tostring(SnapshotNormal.Elasticity), tostring(SnapshotBug.Elasticity)))

    add("\n--- [3. ESTADO DEL CONDUCTOR Y ASIENTO] ---")
    add(string.format("HumanoidState: NORMAL = %s  -->  BUG = %s", SnapshotNormal.HumanoidState, SnapshotBug.HumanoidState))
    add(string.format("SeatWeld Activo: NORMAL = %s  -->  BUG = %s", tostring(SnapshotNormal.SeatWeldExists), tostring(SnapshotBug.SeatWeldExists)))
    add(string.format("PlatformStand: NORMAL = %s  -->  BUG = %s", tostring(SnapshotNormal.PlatformStand), tostring(SnapshotBug.PlatformStand)))

    add("\n--- [4. DIFERENCIAS EN ATRIBUTOS DEL AUTO] ---")
    local diffAttrs = 0
    for k, v in pairs(SnapshotBug.Attributes) do
        if SnapshotNormal.Attributes[k] ~= v then
            diffAttrs = diffAttrs + 1
            add(string.format("Atributo alterado: [%s] era '%s'  -->  ahora es '%s'", k, tostring(SnapshotNormal.Attributes[k]), v))
        end
    end
    if diffAttrs == 0 then add("Sin cambios en los atributos del auto.") end

    add("\n--- [5. DIFERENCIAS EN VALORES DE A-CHASSIS] ---")
    local diffVals = 0
    for k, v in pairs(SnapshotBug.ChassisValues) do
        if SnapshotNormal.ChassisValues[k] ~= v then
            diffVals = diffVals + 1
            add(string.format("Valor Chassis alterado: [%s] era '%s'  -->  ahora es '%s'", k, tostring(SnapshotNormal.ChassisValues[k]), v))
        end
    end
    if diffVals == 0 then add("Sin cambios en los valores internos de A-Chassis.") end

    add("\n==================== FIN DE LA COMPARATIVA ====================")

    local fullText = table.concat(r, "\n")
    TextBox.Text = fullText
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #r * 18)
    if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end
end

BtnNormal.MouseButton1Click:Connect(function()
    local data = captureVehicleData()
    if data then
        SnapshotNormal = data
        BtnNormal.Text = "✅ NORMAL (Guardado)"
        TextBox.Text = string.format("Muestra NORMAL guardada con éxito.\nVehículo: %s\nMasa Total: %.1f\nTotal Piezas: %d\n\nAhora espera a que ocurra el bug en Luna Roja y presiona '2. Muestra BUGGEADO'.", data.CarName, data.AssemblyMass, data.TotalParts)
    else
        TextBox.Text = "⚠️ ERROR: Debes estar sentado en el vehículo para tomar la muestra."
    end
end)

BtnBug.MouseButton1Click:Connect(function()
    local data = captureVehicleData()
    if data then
        SnapshotBug = data
        BtnBug.Text = "✅ BUG (Guardado)"
        if SnapshotNormal then
            generateComparisonReport()
        else
            TextBox.Text = "Muestra BUGGEADO guardada. Falta tomar la muestra NORMAL para comparar."
        end
    else
        TextBox.Text = "⚠️ ERROR: Debes estar sentado en el vehículo para tomar la muestra."
    end
end)

BtnCopy.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(TextBox.Text) elseif toclipboard then toclipboard(TextBox.Text) end
    BtnCopy.Text = "¡COPIADO!"
    task.wait(1.5)
    BtnCopy.Text = "COPIAR COMPARATIVA AL PORTAPAPELES"
end)
