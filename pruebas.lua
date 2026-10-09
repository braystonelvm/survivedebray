-- ==============================================================================
-- RADIOGRAFÍA DE VIDA: ESTRUCTURAS Y AUTOS (RANKING DE HP MÁXIMA EN VIVO)
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer

local VISUALS_FOLDER_NAME = "HealthVisualsFolder"
local VisualsFolder = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
if not VisualsFolder then
    VisualsFolder = Instance.new("Folder")
    VisualsFolder.Name = VISUALS_FOLDER_NAME
    VisualsFolder.Parent = workspace
end

local Config = {
    ScanRadius = 160, -- Radio alrededor de ti (studs)
}

local function getRootPos()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    return root and root.Position or Vector3.zero
end

-- RASTREADOR UNIVERSAL DE VIDA (Lee Atributos, NumberValues o Humanoids)
local function extractHealthData(model)
    local curHP, maxHP = nil, nil

    -- 1. Búsqueda en Atributos del Modelo
    local attrs = model:GetAttributes()
    for k, v in pairs(attrs) do
        local key = k:lower()
        if (key == "health" or key == "hp" or key == "vida" or key == "durability") and type(v) == "number" then
            curHP = v
        elseif (key == "maxhealth" or key == "maxhp" or key == "vidamaxima" or key == "maxdurability") and type(v) == "number" then
            maxHP = v
        end
    end

    -- 2. Búsqueda en Objetos Value (IntValue / NumberValue)
    if not curHP or not maxHP then
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("ValueBase") and type(desc.Value) == "number" then
                local dName = desc.Name:lower()
                if (dName == "health" or dName == "hp" or dName == "vida" or dName == "durability") and not curHP then
                    curHP = desc.Value
                elseif (dName == "maxhealth" or dName == "maxhp" or dName == "vidamaxima") and not maxHP then
                    maxHP = desc.Value
                end
            end
        end
    end

    -- 3. Búsqueda en Humanoid (si la estructura o el chasis usan uno)
    if not curHP or not maxHP then
        local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
        if hum then
            curHP = hum.Health
            maxHP = hum.MaxHealth
        end
    end

    -- Si solo se encontró uno de los dos valores, igualar el faltante
    if curHP and not maxHP then maxHP = curHP end
    if maxHP and not curHP then curHP = maxHP end

    return curHP, maxHP
end

-- Limpieza de etiquetas anteriores
local function clearVisuals()
    VisualsFolder:ClearAllChildren()
end

-- ESCÁNER Y GENERADOR DE RANKING
local function scanAndRankHealth()
    clearVisuals()
    local myPos = getRootPos()
    local results = {}

    local function inspectCandidate(model)
        if not model or not model:IsA("Model") then return end
        if model == lp.Character or Players:GetPlayerFromCharacter(model) then return end
        if model.Name:lower():find("drone") or model.Name:lower():find("dropped") then return end

        local cf, size = model:GetBoundingBox()
        local dist = (cf.Position - myPos).Magnitude
        if dist > Config.ScanRadius then return end

        local curHP, maxHP = extractHealthData(model)
        local isCar = model.Name:lower():find("car") or model.Name:lower():find("truck") or model:FindFirstChildWhichIsA("VehicleSeat", true) ~= nil

        -- Registrar objeto si tiene vida o si es una estructura/auto reconocido
        if curHP or maxHP or isCar or model.Parent.Name:lower():find("structure") then
            curHP = curHP or 0
            maxHP = maxHP or 0

            table.insert(results, {
                Model = model,
                Name = model.Name,
                IsCar = isCar,
                CurrentHP = curHP,
                MaxHP = maxHP,
                Dist = dist,
                CFrame = cf,
                Size = size
            })
        end
    end

    -- Revisar Structures y Workspace
    local structFolder = workspace:FindFirstChild("Structures")
    if structFolder then
        for _, m in ipairs(structFolder:GetChildren()) do inspectCandidate(m) end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m ~= structFolder then inspectCandidate(m) end
    end

    -- Ordenar de MAYOR a MENOR vida máxima
    table.sort(results, function(a, b)
        return a.MaxHP > b.MaxHP
    end)

    local lines = {}
    local function log(t) table.insert(lines, t) end

    log("==================================================")
    log("     RANKING DE VIDA: ESTRUCTURAS Y VEHÍCULOS     ")
    log("==================================================")
    log(string.format("Escaneados en radio de %d studs. Ordenados por Vida Máxima:", Config.ScanRadius))
    log("--------------------------------------------------")

    for rank, item in ipairs(results) do
        local tagType = item.IsCar and "🚗 VEHÍCULO" or "🏰 ESTRUCTURA"
        local hpString = string.format("%.0f / %.0f HP", item.CurrentHP, item.MaxHP)
        if item.MaxHP == 0 then hpString = "Sin dato de HP (Objeto estático)" end

        log(string.format("#%d [%s] %s | %s | Dist: %.1f studs", rank, tagType, item.Name, hpString, item.Dist))

        -- DIBUJAR ETIQUETA FLOTANTE (BILLBOARD) EN CADA UNO
        local anchor = Instance.new("Part")
        anchor.Name = "HP_Anchor_" .. item.Name
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.CFrame = item.CFrame
        anchor.Size = Vector3.new(1, 1, 1)
        anchor.Parent = VisualsFolder

        local box = Instance.new("SelectionBox")
        box.Adornee = anchor
        box.Color3 = item.IsCar and Color3.fromRGB(0, 200, 255) or (item.MaxHP >= 5000 and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(80, 255, 100))
        box.LineThickness = 0.04
        box.Parent = anchor

        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.new(0, 170, 0, 45)
        bb.AlwaysOnTop = true
        bb.Adornee = anchor
        bb.StudsOffset = Vector3.new(0, (item.Size.Y / 2) + 1.8, 0)
        bb.Parent = anchor

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = item.IsCar and Color3.fromRGB(100, 220, 255) or Color3.fromRGB(255, 255, 255)
        lbl.TextStrokeTransparency = 0.2
        lbl.TextSize = 11
        lbl.Font = Enum.Font.GothamBold
        lbl.Text = string.format("%s %s\n❤️ %s", item.IsCar and "🚗" or "🛡️", item.Name, hpString)
        lbl.Parent = bb
    end

    log("--------------------------------------------------")
    log(string.format("TOTAL REGISTRADOS: %d", #results))
    log("==================================================")

    local report = table.concat(lines, "\n")
    if setclipboard then setclipboard(report) elseif toclipboard then toclipboard(report) end

    StarterGui:SetCore("SendNotification", {
        Title = "📊 REPORTE DE VIDA LISTO",
        Text = string.format("%d analizados. Ranking copiado al portapapeles.", #results),
        Duration = 5
    })
end

-- ==============================================================================
-- BOTÓN FLOTANTE (ON / OFF / RECARGAR)
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HealthInspectorGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Active = false

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 140, 0, 36)
ToggleBtn.Position = UDim2.new(0.04, 0, 0.52, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
ToggleBtn.Text = "VIDAS: OFF"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 11
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Active = true
ToggleBtn.Draggable = true
ToggleBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 6)
UICorner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Active = not Active
    if Active then
        ToggleBtn.Text = "VIDAS: ON"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
        scanAndRankHealth()
    else
        ToggleBtn.Text = "VIDAS: OFF"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        clearVisuals()
    end
end)

StarterGui:SetCore("SendNotification", {
    Title = "INSPECTOR DE VIDA LISTO",
    Text = "Presiona el botón para encender y copiar el ranking.",
    Duration = 4
})
