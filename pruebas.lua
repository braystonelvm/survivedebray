-- ==============================================================================
-- VEHICLE FORENSICS V3: 3 MÉTODOS DE DESATASCAR SEGURO + SURTIDOR + GALONES
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

-- Mantener cursor visible
RunService.RenderStepped:Connect(function()
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
end)

local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function getVehicle()
    local _, _, hum = getCharacterParts()
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local car = seat:FindFirstAncestorOfClass("Model") or seat.Parent
        return car, seat
    end
    return nil, nil
end

-- ==============================================================================
-- 1. INSPECTOR AVANZADO DEL SURTIDOR DE GASOLINERA
-- ==============================================================================

local function inspectNearbyGasPump()
    local car, seat = getVehicle()
    local _, root = getCharacterParts()
    local center = (seat and seat.Position) or (root and root.Position) or Vector3.zero

    local lines = {
        "==================================================================",
        "             INSPECCIÓN PROFUNDA DE LA GASOLINERA / BOMBA         ",
        "==================================================================",
        string.format("Posición de Escaneo: Vector3.new(%.1f, %.1f, %.1f)", center.X, center.Y, center.Z)
    }

    local foundInteractives = {}

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") or desc:IsA("ClickDetector") or desc:IsA("TouchTransmitter") then
            local part = desc.Parent
            local pPos = part:IsA("BasePart") and part.Position or (part:IsA("Attachment") and part.WorldPosition or nil)

            if pPos and (pPos - center).Magnitude <= 50 then
                table.insert(foundInteractives, {
                    Type = desc.ClassName,
                    Name = desc.Name,
                    ParentName = part.Name,
                    Path = desc:GetFullName(),
                    Dist = math.floor((pPos - center).Magnitude),
                    PromptText = desc:IsA("ProximityPrompt") and (desc.ObjectText .. " | " .. desc.ActionText) or "N/A",
                    Enabled = desc:IsA("ProximityPrompt") and tostring(desc.Enabled) or "N/A"
                })
            end
        end
    end

    if #foundInteractives == 0 then
        table.insert(lines, "\n⚠️ No se encontraron Prompts ni ClickDetectors en un radio de 50 studs.")
        table.insert(lines, "Buscando modelos con nombre 'Gas', 'Pump', 'Fuel' cerca...")

        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and (obj.Position - center).Magnitude <= 35 then
                local n = obj.Name:lower()
                if n:find("pump") or n:find("gas") or n:find("fuel") or n:find("boton") or n:find("button") then
                    table.insert(lines, string.format(" • Parte sospechosa: '%s' | Padre: '%s' | Ruta: %s", obj.Name, obj.Parent.Name, obj:GetFullName()))
                end
            end
        end
    else
        table.insert(lines, string.format("\n🎯 SE ENCONTRARON %d ELEMENTOS INTERACTIVOS:", #foundInteractives))
        for idx, item in ipairs(foundInteractives) do
            table.insert(lines, string.format(
                "[%d] Tipo: %s ('%s') en '%s' (Dist: %d studs)\n     • Texto: %s | Enabled: %s\n     • Ruta: %s",
                idx, item.Type, item.Name, item.ParentName, item.Dist, item.PromptText, item.Enabled, item.Path
            ))
        end
    end

    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 2. INSPECCIÓN DE GALONES DE GASOLINA
-- ==============================================================================

local function inspectNearbyCanComponents()
    local car, seat = getVehicle()
    local _, root = getCharacterParts()
    local center = (seat and seat.Position) or (root and root.Position) or Vector3.zero

    local lines = {
        "==================================================================",
        "               ANÁLISIS ESTRUCTURAL DE GALONES CERCANOS           ",
        "=================================================================="
    }

    local dropped = workspace:FindFirstChild("DroppedItems") or workspace
    local count = 0

    for _, item in ipairs(dropped:GetChildren()) do
        local n = item.Name:lower()
        if n == "fuel" or n == "refined fuel" then
            local mainPart = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if mainPart then
                local dist = math.floor((mainPart.Position - center).Magnitude)
                if dist <= 30 then
                    count = count + 1
                    table.insert(lines, string.format("[%d] '%s' (%s) | Dist: %d studs", count, item.Name, item.ClassName, dist))
                    table.insert(lines, string.format("     • Anchored: %s | CanCollide: %s | Mass: %.1f", tostring(mainPart.Anchored), tostring(mainPart.CanCollide), mainPart:GetMass()))
                    
                    local prompts = {}
                    for _, d in ipairs(item:GetDescendants()) do
                        if d:IsA("ProximityPrompt") then
                            table.insert(prompts, string.format("Prompt('%s' | Action: '%s')", d.Name, d.ActionText))
                        elseif d:IsA("ClickDetector") then
                            table.insert(prompts, "ClickDetector")
                        end
                    end
                    if #prompts > 0 then
                        table.insert(lines, "     • Interactivos: " .. table.concat(prompts, ", "))
                    else
                        table.insert(lines, "     • Interactivos: (Sin prompts directos, se usa por contacto físico)")
                    end
                end
            end
        end
    end

    if count == 0 then
        table.insert(lines, "⚠️ No hay galones a menos de 30 studs de tu auto.")
    end

    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 3. LOS 3 MÉTODOS DE DESATASCAR (CERO DAÑO A RUEDAS / SUSPENSIÓN)
-- ==============================================================================

-- MÉTODO 1: PIVOT TO (Teletransporte Matricial Directo + Nivelado Horizontal)
local function unstuckMethod1_Pivot()
    local car, seat = getVehicle()
    if not car or not seat then return "⚠️ Debes estar sentado en el auto." end

    local currentCF = car:GetPivot()
    local currentPos = currentCF.Position

    -- Eliminar inclinaciones y vuelcos manteniendo hacia dónde apunta la trompa
    local look = currentCF.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.1 then flatLook = Vector3.new(0, 0, 1) else flatLook = flatLook.Unit end

    -- Elevar 5 studs en bloque limpio
    local safeCF = CFrame.lookAt(currentPos + Vector3.new(0, 5.0, 0), currentPos + Vector3.new(0, 5.0, 0) + flatLook)
    car:PivotTo(safeCF)

    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then
            p.AssemblyLinearVelocity = Vector3.zero
            p.AssemblyAngularVelocity = Vector3.zero
        end
    end

    return "✅ [MÉTODO 1: PIVOT] Auto enderezado y elevado +5 studs en bloque."
end

-- MÉTODO 2: IMPULSO CINÉTICO (LinearVelocity Ascendente + Retroceso)
local function unstuckMethod2_Velocity()
    local car, seat = getVehicle()
    if not car or not seat then return "⚠️ Debes estar sentado en el auto." end

    local primary = car.PrimaryPart or seat
    local look = primary.CFrame.LookVector
    local backDir = Vector3.new(-look.X, 0, -look.Z).Unit

    -- Impulso vertical fuerte de 40 studs/s combinado con empuje hacia atrás
    primary.AssemblyLinearVelocity = Vector3.new(backDir.X * 25, 42, backDir.Z * 25)
    primary.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

    return "✅ [MÉTODO 2: IMPULSO] Impulso físico de 42 Y y retroceso aplicado al chasis."
end

-- MÉTODO 3: RESORTE / LEVITACIÓN SUAVE TEMPORAL (VectorForce + BodyGyro)
local function unstuckMethod3_Spring()
    local car, seat = getVehicle()
    if not car or not seat then return "⚠️ Debes estar sentado en el auto." end

    local primary = car.PrimaryPart or seat
    local mass = 0
    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then mass = mass + p:GetMass() end
    end

    -- Crear fuerza ascendente temporal que anule la gravedad y lo suba suave
    local bodyPos = Instance.new("BodyPosition")
    bodyPos.Name = "UnstuckTempBP"
    bodyPos.MaxForce = Vector3.new(mass * 200, mass * 600, mass * 200)
    bodyPos.P = 15000
    bodyPos.D = 1200
    bodyPos.Position = primary.Position + Vector3.new(0, 6.0, 0)
    bodyPos.Parent = primary

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "UnstuckTempBG"
    bodyGyro.MaxTorque = Vector3.new(mass * 400, mass * 400, mass * 400)
    bodyGyro.CFrame = CFrame.new(primary.Position, primary.Position + Vector3.new(primary.CFrame.LookVector.X, 0, primary.CFrame.LookVector.Z))
    bodyGyro.Parent = primary

    task.spawn(function()
        task.wait(0.65)
        if bodyPos then bodyPos:Destroy() end
        if bodyGyro then bodyGyro:Destroy() end
    end)

    return "✅ [MÉTODO 3: RESORTE] Levitación magnética de 0.65s para sacarlo del suelo sin golpes secos."
end

-- ==============================================================================
-- 4. INTERFAZ GRÁFICA FORENSE
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VehicleForensicsV3Gui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 530, 0, 510)
MainFrame.Position = UDim2.new(0.5, -265, 0.5, -255)
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
TitleBar.Text = "  🔬 FORENSE V3: SURTIDOR + 3 MÉTODOS DE RESCATE"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 270)
OutputBox.Position = UDim2.new(0, 10, 0, 44)
OutputBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
OutputBox.TextColor3 = Color3.fromRGB(225, 225, 225)
OutputBox.TextSize = 9
OutputBox.Font = Enum.Font.Code
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextEditable = false
OutputBox.Text = "Prueba los 3 métodos de rescate o inspecciona el surtidor..."
OutputBox.Parent = MainFrame

local OutputCorner = Instance.new("UICorner")
OutputCorner.CornerRadius = UDim.new(0, 8)
OutputCorner.Parent = OutputBox

local function createBtn(title, color, pos, size, callback)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.Text = title
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- Fila 1: Inspecciones
createBtn("🚰 INSPECCIONAR SURTIDOR", Color3.fromRGB(30, 120, 180), UDim2.new(0, 10, 0, 324), UDim2.new(0.48, -5, 0, 34), function()
    local res = inspectNearbyGasPump()
    OutputBox.Text = res
end)

createBtn("⛽ INSPECCIONAR GALÓN", Color3.fromRGB(40, 140, 90), UDim2.new(0.52, 0, 0, 324), UDim2.new(0.48, -10, 0, 34), function()
    local res = inspectNearbyCanComponents()
    OutputBox.Text = res
end)

-- Fila 2: Los 3 Métodos de Rescate
createBtn("🚀 RESCATE 1: PIVOT", Color3.fromRGB(180, 50, 40), UDim2.new(0, 10, 0, 366), UDim2.new(0.31, 0, 0, 36), function()
    local res = unstuckMethod1_Pivot()
    OutputBox.Text = res
end)

createBtn("⚡ RESCATE 2: IMPULSO", Color3.fromRGB(190, 110, 20), UDim2.new(0.345, 0, 0, 366), UDim2.new(0.31, 0, 0, 36), function()
    local res = unstuckMethod2_Velocity()
    OutputBox.Text = res
end)

createBtn("🧲 RESCATE 3: RESORTE", Color3.fromRGB(130, 40, 160), UDim2.new(0.69, 0, 0, 366), UDim2.new(0.31, -10, 0, 36), function()
    local res = unstuckMethod3_Spring()
    OutputBox.Text = res
end)

-- Fila 3: Copiar
createBtn("📋 COPIAR DATOS", Color3.fromRGB(60, 65, 80), UDim2.new(0, 10, 0, 410), UDim2.new(1, -20, 0, 32), function()
    local txt = OutputBox.Text
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 180)
FloatBtn.Text = "🔬\nSCAN"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
