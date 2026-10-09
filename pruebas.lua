-- ==============================================================================
-- VISUALIZADOR DE VIDA EN NÚMEROS GIGANTES (ESTRUCTURAS Y VEHÍCULOS)
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer

local VISUALS_FOLDER_NAME = "BigHPNumbersFolder"
local VisualFolder = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
if not VisualFolder then
    VisualFolder = Instance.new("Folder")
    VisualFolder.Name = VISUALS_FOLDER_NAME
    VisualFolder.Parent = workspace
end

local Config = {
    ScanRadius = 180, -- Radio a la redonda (studs)
}

local IsActive = false

-- Formatear números con comas (ej: 15000 -> 15,000)
local function formatNumber(n)
    local formatted = tostring(math.floor(n))
    while true do
        local k
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

local function getRootPos()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    return root and root.Position or Vector3.zero
end

-- Extraer exclusivamente la vida numérica
local function getHealth(model)
    local curHP, maxHP = nil, nil

    -- 1. Atributos
    for k, v in pairs(model:GetAttributes()) do
        local key = k:lower()
        if (key == "maxhealth" or key == "maxhp" or key == "maxdurability") and type(v) == "number" then
            maxHP = v
        elseif (key == "health" or key == "hp" or key == "durability") and type(v) == "number" then
            curHP = v
        end
    end

    -- 2. Values internos
    if not maxHP then
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("ValueBase") and type(desc.Value) == "number" then
                local dName = desc.Name:lower()
                if (dName == "maxhealth" or dName == "maxhp") and not maxHP then
                    maxHP = desc.Value
                elseif (dName == "health" or dName == "hp") and not curHP then
                    curHP = desc.Value
                end
            end
        end
    end

    -- 3. Humanoid
    if not maxHP then
        local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
        if hum then
            maxHP = hum.MaxHealth
            curHP = hum.Health
        end
    end

    if maxHP and not curHP then curHP = maxHP end
    if curHP and not maxHP then maxHP = curHP end

    return curHP, maxHP
end

local function clearVisuals()
    if VisualFolder then
        VisualFolder:ClearAllChildren()
    end
end

local function renderBigNumbers()
    clearVisuals()
    local myPos = getRootPos()
    local list = {}

    local function inspect(model)
        if not model or not model:IsA("Model") then return end
        if model == lp.Character or Players:GetPlayerFromCharacter(model) then return end
        if model.Name:lower():find("drone") or model.Name:lower():find("dropped") then return end

        local cf, size = model:GetBoundingBox()
        local dist = (cf.Position - myPos).Magnitude
        if dist > Config.ScanRadius then return end

        local curHP, maxHP = getHealth(model)
        local isCar = model.Name:lower():find("car") or model.Name:lower():find("truck") or model:FindFirstChildWhichIsA("VehicleSeat", true) ~= nil
        local isStruct = model.Parent and model.Parent.Name:lower():find("structure")

        if maxHP or isCar or isStruct then
            table.insert(list, {
                Model = model,
                Name = model.Name,
                MaxHP = maxHP or 0,
                CurHP = curHP or 0,
                CFrame = cf,
                Size = size,
                IsCar = isCar,
                Dist = dist
            })
        end
    end

    local structFolder = workspace:FindFirstChild("Structures")
    if structFolder then
        for _, m in ipairs(structFolder:GetChildren()) do inspect(m) end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m ~= structFolder then inspect(m) end
    end

    -- Dibujar en pantalla con números gigantes
    for _, item in ipairs(list) do
        local anchor = Instance.new("Part")
        anchor.Name = "HP_" .. item.Name
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.CFrame = item.CFrame
        anchor.Size = Vector3.new(1, 1, 1)
        anchor.Parent = VisualFolder

        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.new(0, 240, 0, 75)
        bb.AlwaysOnTop = true -- Visible a través de paredes y estructuras
        bb.Adornee = anchor
        bb.StudsOffset = Vector3.new(0, (item.Size.Y / 2) + 2.5, 0)
        bb.Parent = anchor

        local lblName = Instance.new("TextLabel")
        lblName.Size = UDim2.new(1, 0, 0, 20)
        lblName.Position = UDim2.new(0, 0, 0, 0)
        lblName.BackgroundTransparency = 1
        lblName.TextColor3 = Color3.fromRGB(220, 220, 220)
        lblName.TextStrokeTransparency = 0
        lblName.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lblName.TextSize = 13
        lblName.Font = Enum.Font.GothamMedium
        lblName.Text = item.Name
        lblName.Parent = bb

        -- NÚMERO GIGANTE DE VIDA
        local lblHP = Instance.new("TextLabel")
        lblHP.Size = UDim2.new(1, 0, 0, 50)
        lblHP.Position = UDim2.new(0, 0, 0, 20)
        lblHP.BackgroundTransparency = 1
        lblHP.TextStrokeTransparency = 0
        lblHP.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lblHP.TextSize = 34
        lblHP.Font = Enum.Font.GothamBlack

        if item.MaxHP > 0 then
            lblHP.Text = formatNumber(item.MaxHP) .. " HP"
            if item.IsCar then
                lblHP.TextColor3 = Color3.fromRGB(0, 230, 255)    -- Azul Neón para autos
            elseif item.MaxHP >= 10000 then
                lblHP.TextColor3 = Color3.fromRGB(255, 215, 0)    -- Dorado para torres / muros top
            elseif item.MaxHP >= 3000 then
                lblHP.TextColor3 = Color3.fromRGB(50, 255, 120)   -- Verde para defensas medias
            else
                lblHP.TextColor3 = Color3.fromRGB(255, 120, 50)   -- Naranja para vallas bajas
            end
        else
            lblHP.Text = "SIN HP"
            lblHP.TextSize = 22
            lblHP.TextColor3 = Color3.fromRGB(160, 160, 160)
        end

        lblHP.Parent = bb
    end

    -- Copiar ranking al portapapeles
    table.sort(list, function(a, b) return a.MaxHP > b.MaxHP end)
    local report = {"=== RANKING DE VIDA MÁXIMA ==="}
    for i, it in ipairs(list) do
        table.insert(report, string.format("#%d %s: %s HP (Dist: %.1f)", i, it.Name, formatNumber(it.MaxHP), it.Dist))
    end
    local text = table.concat(report, "\n")
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end

    StarterGui:SetCore("SendNotification", {
        Title = "VIDAS VISIBLES",
        Text = string.format("%d objetos analizados. Ranking copiado.", #list),
        Duration = 3
    })
end

-- ==============================================================================
-- BOTÓN FLOTANTE (ON / OFF)
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BigHPToggleGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(0, 140, 0, 38)
Btn.Position = UDim2.new(0.04, 0, 0.40, 0)
Btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
Btn.Text = "VER VIDA: OFF"
Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Btn.TextSize = 12
Btn.Font = Enum.Font.GothamBold
Btn.Active = true
Btn.Draggable = true
Btn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 6)
UICorner.Parent = Btn

Btn.MouseButton1Click:Connect(function()
    IsActive = not IsActive
    if IsActive then
        Btn.Text = "VER VIDA: ON"
        Btn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
        renderBigNumbers()
    else
        Btn.Text = "VER VIDA: OFF"
        Btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        clearVisuals()
    end
end)
