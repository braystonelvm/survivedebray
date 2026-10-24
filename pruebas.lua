-- ==============================================================================
-- VEHICLE FORENSICS: FUEL TELEMETRY, CAN SCANNER & COLLISION BLACKBOX
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
-- 1. ANÁLISIS DE GASOLINA DEL VEHÍCULO
-- ==============================================================================

local function analyzeVehicleFuel(car, seat)
    if not car then return "Sin auto detectado (siéntate en el asiento)" end

    local currentFuel, maxFuel = nil, nil
    local srcPath = "Desconocido"

    -- 1. Búsqueda en Configuration
    local config = car:FindFirstChild("Configuration", true) or car:FindFirstChild("Config", true)
    if config then
        for _, attr in ipairs({"Fuel", "Gas", "Gasoline", "Petrol", "Combustible"}) do
            local val = config:GetAttribute(attr)
            if val and type(val) == "number" then
                currentFuel = val
                maxFuel = config:GetAttribute("Max" .. attr) or config:GetAttribute("MaxFuel")
                srcPath = "Config.Attr (" .. attr .. ")"
                break
            end
        end
        if not currentFuel then
            for _, child in ipairs(config:GetChildren()) do
                if child:IsA("ValueBase") then
                    local n = child.Name:lower()
                    if n:find("fuel") or n:find("gas") then
                        currentFuel = tonumber(child.Value)
                        srcPath = "Config.Value (" .. child.Name .. ")"
                    elseif n:find("maxfuel") or n:find("maxgas") then
                        maxFuel = tonumber(child.Value)
                    end
                end
            end
        end
    end

    -- 2. Búsqueda directa en atributos del modelo/asiento
    if not currentFuel then
        for _, obj in ipairs({car, car.PrimaryPart, seat}) do
            if obj then
                for _, attr in ipairs({"Fuel", "Gas", "Gasoline", "Petrol"}) do
                    local val = obj:GetAttribute(attr)
                    if val and type(val) == "number" then
                        currentFuel = val
                        maxFuel = obj:GetAttribute("Max" .. attr) or obj:GetAttribute("MaxFuel")
                        srcPath = obj.Name .. ".Attr (" .. attr .. ")"
                        break
                    end
                end
            end
            if currentFuel then break end
        end
    end

    -- 3. Búsqueda en descendientes
    if not currentFuel then
        for _, desc in ipairs(car:GetDescendants()) do
            if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                local n = desc.Name:lower()
                if n == "fuel" or n == "gas" or n == "gasoline" then
                    currentFuel = desc.Value
                    srcPath = "Descendant (" .. desc:GetFullName() .. ")"
                    break
                end
            end
        end
    end

    currentFuel = currentFuel or 0
    maxFuel = maxFuel or (currentFuel > 100 and currentFuel or 100)
    local pct = math.floor((currentFuel / math.max(maxFuel, 1)) * 100)

    return string.format("Gasolina: %.1f / %.1f (%d%%)\nOrigen: %s", currentFuel, maxFuel, pct, srcPath)
end

-- ==============================================================================
-- 2. ANÁLISIS DE GALONES EN EL SUELO Y DISTANCIA
-- ==============================================================================

local function scanNearbyFuelCans()
    local _, root = getCharacterParts()
    local car, seat = getVehicle()
    local originPos = car and (car.PrimaryPart and car.PrimaryPart.Position or seat.Position) or (root and root.Position or Vector3.zero)

    local foundCans = {}
    local folders = {workspace:FindFirstChild("DroppedItems"), workspace:FindFirstChild("Structures"), workspace}

    for _, f in ipairs(folders) do
        if f then
            for _, item in ipairs(f:GetChildren()) do
                if (item:IsA("Model") or item:IsA("BasePart")) and item ~= car and item ~= lp.Character then
                    local n = item.Name:lower()
                    local itemType = tostring(item:GetAttribute("ItemType") or ""):lower()
                    local isGas = n:find("gas") or n:find("fuel") or n:find("jerry") or n:find("canister") or n:find("galon") or n:find("bidon") or itemType:find("fuel") or itemType:find("gas")

                    if isGas then
                        local p = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                        if p then
                            local dist = math.floor((p.Position - originPos).Magnitude)
                            if dist <= 120 then
                                local amount = item:GetAttribute("Fuel") or item:GetAttribute("Amount") or item:GetAttribute("Gas") or "No definido"
                                local capacity = item:GetAttribute("MaxFuel") or item:GetAttribute("Capacity") or "No definido"
                                table.insert(foundCans, {
                                    Name = item.Name,
                                    Distance = dist,
                                    Amount = amount,
                                    Capacity = capacity,
                                    IsAnchored = p.Anchored,
                                    Instance = item
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(foundCans, function(a, b) return a.Distance < b.Distance end)
    return foundCans
end

-- ==============================================================================
-- 3. DISPARADOR DEL SURTIDOR DE GASOLINERA
-- ==============================================================================

local function triggerGasStationPump()
    local _, root = getCharacterParts()
    local car, seat = getVehicle()
    local originPos = car and (car.PrimaryPart and car.PrimaryPart.Position or seat.Position) or (root and root.Position or Vector3.zero)

    local triggeredCount = 0
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local pPart = prompt.Parent
            local pPos = pPart and (pPart:IsA("BasePart") and pPart.Position or (pPart:IsA("Attachment") and pPart.WorldPosition))

            if pPos and (pPos - originPos).Magnitude <= 35 then
                local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
                local pName = pPart and pPart.Name:lower() or ""

                if text:find("gas") or text:find("fuel") or text:find("surtidor") or text:find("usar") or text:find("bomba") or pName:find("pump") then
                    prompt.HoldDuration = 0
                    prompt.RequiresLineOfSight = false
                    if fireproximityprompt then
                        pcall(function() fireproximityprompt(prompt) end)
                        pcall(function() fireproximityprompt(prompt, 0) end)
                    end
                    triggeredCount = triggeredCount + 1
                end
            end
        end
    end
    return triggeredCount
end

-- ==============================================================================
-- 4. REGISTRADOR DE COLISIONES Y SOLAPAMIENTOS
-- ==============================================================================

local function inspectCollisions()
    local car, seat = getVehicle()
    if not car then return "Súbete al auto para registrar con qué está colisionando." end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {car, lp.Character}

    local lines = {
        "==================================================================",
        "             REGISTRO DE PARTES COLISIONANDO / SOLAPADAS          ",
        "==================================================================",
        string.format("Auto: %s | Modelo: %s", car.Name, car.ClassName)
    }

    local collidingParts = {}
    local checked = {}

    for _, myPart in ipairs(car:GetDescendants()) do
        if myPart:IsA("BasePart") then
            local touching = workspace:GetPartsInPart(myPart, overlapParams)
            for _, hit in ipairs(touching) do
                if not checked[hit] then
                    checked[hit] = true
                    table.insert(collidingParts, hit)
                end
            end
        end
    end

    if #collidingParts == 0 then
        table.insert(lines, "\n✅ No hay colisiones sólidas ni solapamientos en este momento.")
    else
        table.insert(lines, string.format("\n⚠️ SE DETECTARON %d PARTES ATRAVESANDO / COLISIONANDO:", #collidingParts))
        for idx, hit in ipairs(collidingParts) do
            local parentModel = hit:FindFirstAncestorOfClass("Model")
            local modelName = parentModel and parentModel.Name or hit.Parent.Name
            table.insert(lines, string.format(
                "[%d] Parte: '%s' | Modelo Padre: '%s'\n     • Anchored: %s | CanCollide: %s | Material: %s\n     • Ruta: %s",
                idx, hit.Name, modelName, tostring(hit.Anchored), tostring(hit.CanCollide), hit.Material.Name, hit:GetFullName()
            ))
        end
    end

    -- Revisar si hay joints/welds externos soldados al coche
    local externalWelds = {}
    for _, desc in ipairs(car:GetDescendants()) do
        if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("ManualWeld") then
            local p0, p1 = desc.Part0, desc.Part1
            local isP0External = p0 and not p0:IsDescendantOf(car)
            local isP1External = p1 and not p1:IsDescendantOf(car)
            if isP0External or isP1External then
                table.insert(externalWelds, string.format("Weld '%s' pegado a: %s", desc.Name, isP0External and p0:GetFullName() or p1:GetFullName()))
            end
        end
    end

    if #externalWelds > 0 then
        table.insert(lines, "\n🚨 UNIONES FÍSICAS (WELDS) EXTERNAS DETECTADAS:")
        for _, w in ipairs(externalWelds) do
            table.insert(lines, "   • " .. w)
        end
    end

    table.insert(lines, "==================================================================")
    return table.concat(lines, "\n")
end

-- ==============================================================================
-- 5. DESOLDADOR / LIBERADOR FÍSICO DE EMERGENCIA
-- ==============================================================================

local function unstickVehicle()
    local car, seat = getVehicle()
    if not car then return "Debes estar montado en el auto para desoldarlo." end

    local primary = car.PrimaryPart or seat
    local removedWelds = 0

    -- 1. Destruir cualquier unión o soldadura con partes fuera del coche
    for _, desc in ipairs(car:GetDescendants()) do
        if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("ManualWeld") or desc:IsA("Snap") then
            local p0, p1 = desc.Part0, desc.Part1
            if (p0 and not p0:IsDescendantOf(car)) or (p1 and not p1:IsDescendantOf(car)) then
                desc:Destroy()
                removedWelds = removedWelds + 1
            end
        end
    end

    -- 2. Desactivar temporalmente CanCollide en el chasis para salir de tierra/estructuras
    for _, part in ipairs(car:GetDescendants()) do
        if part:IsA("BasePart") and not part.Name:lower():find("wheel") and part ~= seat then
            part.CanCollide = false
        end
    end

    -- 3. Impulso físico de desenterramiento (elevación + rebote)
    primary.AssemblyLinearVelocity = Vector3.new(0, 45, 0)
    primary.AssemblyAngularVelocity = Vector3.zero
    primary.CFrame = primary.CFrame + Vector3.new(0, 3.5, 0)

    task.spawn(function()
        task.wait(0.6)
        for _, part in ipairs(car:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end)

    return string.format("✅ Desoldado ejecutado: %d uniones externas rotas, colisión aliviada y auto elevado 3.5 studs.", removedWelds)
end

-- ==============================================================================
-- 6. INTERFAZ GRÁFICA FORENSE
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VehicleForensicsGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 490)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -245)
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
TitleBar.Text = "  🔬 DIAGNÓSTICO DE COMBUSTIBLE, SURTIDOR Y COLISIONES"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 11
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Caja de Texto de Lectura
local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 310)
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
OutputBox.Text = "Presiona los botones inferiores para analizar combustible, surtidor o colisiones..."
OutputBox.Parent = MainFrame

local OutputCorner = Instance.new("UICorner")
OutputCorner.CornerRadius = UDim.new(0, 8)
OutputCorner.Parent = OutputBox

-- Botones de Acción
local function createActionBtn(title, color, pos, size, callback)
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

-- 1. Botón Escanear Gasolina y Galones
createActionBtn("⛽ ANALIZAR COMBUSTIBLE", Color3.fromRGB(40, 110, 190), UDim2.new(0, 10, 0, 362), UDim2.new(0.48, -5, 0, 34), function()
    local car, seat = getVehicle()
    local carFuelText = analyzeVehicleFuel(car, seat)
    local cans = scanNearbyFuelCans()

    local lines = {
        "==================================================================",
        "                 ESTADO DE COMBUSTIBLE DEL VEHÍCULO               ",
        "==================================================================",
        carFuelText,
        "\n[GALONES DE GASOLINA CERCANOS ENCONTRADOS]:"
    }

    if #cans == 0 then
        table.insert(lines, "   (No hay galones en un radio de 120 studs)")
    else
        for idx, c in ipairs(cans) do
            table.insert(lines, string.format(
                "[%d] %s | Distancia: %d studs\n     • Contenido: %s / Capacidad: %s | Anchored: %s\n     • Ruta: %s",
                idx, c.Name, c.Distance, tostring(c.Amount), tostring(c.Capacity), tostring(c.IsAnchored), c.Instance:GetFullName()
            ))
        end
    end
    lines[#lines + 1] = "=================================================================="
    OutputBox.Text = table.concat(lines, "\n")
end)

-- 2. Botón Activar Surtidor
createActionBtn("🚰 BOTÓN SURTIDOR", Color3.fromRGB(30, 140, 80), UDim2.new(0.52, 0, 0, 362), UDim2.new(0.48, -10, 0, 34), function()
    local count = triggerGasStationPump()
    if count > 0 then
        OutputBox.Text = string.format("✅ Se activaron %d surtidores/botones de gasolina cercanos.", count)
    else
        OutputBox.Text = "⚠️ No se detectó ningún ProximityPrompt de surtidor a menos de 35 studs."
    end
end)

-- 3. Botón Registrar Colisiones (Caja Negra)
createActionBtn("📦 REGISTRAR COLISIÓN", Color3.fromRGB(190, 100, 30), UDim2.new(0, 10, 0, 404), UDim2.new(0.48, -5, 0, 34), function()
    local result = inspectCollisions()
    OutputBox.Text = result
end)

-- 4. Botón Desoldar / Desenterrar Auto
createActionBtn("🛠️ DESOLDAR / LIBERAR AUTO", Color3.fromRGB(180, 40, 50), UDim2.new(0.52, 0, 0, 404), UDim2.new(0.48, -10, 0, 34), function()
    local result = unstickVehicle()
    OutputBox.Text = result
end)

-- 5. Botón Copiar al Portapapeles
createActionBtn("📋 COPIAR DATOS", Color3.fromRGB(60, 65, 80), UDim2.new(0, 10, 0, 446), UDim2.new(1, -20, 0, 32), function()
    local txt = OutputBox.Text
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 130, 30)
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
