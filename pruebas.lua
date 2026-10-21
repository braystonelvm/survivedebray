-- ==============================================================================
-- RADAR EXCLUSIVO PARA COFRES CERRADOS (ROJO / MAP.CRATES / 0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function getCratePrompt(model)
    return model:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function isCrateClosed(model)
    if not model or not model.Parent then return false end

    -- Si ya no tiene el atributo Crate, descartar
    if model:GetAttribute("Crate") ~= true and not model:FindFirstChild("CrateServer") then
        return false
    end

    -- Revisar si el Prompt de abrir sigue habilitado
    local prompt = getCratePrompt(model)
    if prompt and prompt.Enabled and prompt.ActionText:lower():find("open") then
        return true
    end

    return false
end

local function removeCrateESP(model)
    local hl = model:FindFirstChild("CrateESP_Highlight")
    if hl then hl:Destroy() end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc.Name == "CrateESP_Tag" then
            desc:Destroy()
        end
    end
end

local function tagCrate(model)
    if not model:IsA("Model") then return end

    -- Filtro exacto según el reporte forense
    local isCrateModel = (model:GetAttribute("Crate") == true) 
        or (model.Parent and model.Parent.Name == "Crates")
        or model:FindFirstChild("CrateServer") ~= nil

    if not isCrateModel then return end

    -- Si ya está abierto, no poner ESP
    if not isCrateClosed(model) then
        removeCrateESP(model)
        return
    end

    if model:FindFirstChild("CrateESP_Highlight") then return end

    -- 1. Resaltado en rojo a través de paredes
    local hl = Instance.new("Highlight")
    hl.Name = "CrateESP_Highlight"
    hl.FillColor = Color3.fromRGB(255, 25, 25)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model

    -- 2. Etiqueta flotante con nombre y rareza
    local anchorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if anchorPart and not anchorPart:FindFirstChild("CrateESP_Tag") then
        local rarity = tostring(model:GetAttribute("Rarity") or model.Name)
        local tier = tostring(model:GetAttribute("Tier") or "1")

        local bb = Instance.new("BillboardGui")
        bb.Name = "CrateESP_Tag"
        bb.Size = UDim2.new(0, 110, 0, 26)
        bb.StudsOffset = Vector3.new(0, 2.5, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = anchorPart
        bb.Parent = anchorPart

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = string.format("📦 COFRE [%s T%s]", rarity:upper(), tier)
        lbl.TextColor3 = Color3.fromRGB(255, 50, 50)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0.2
        lbl.TextSize = 12
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
    end

    -- 3. Monitorear apertura para apagar inmediatamente
    local prompt = getCratePrompt(model)
    if prompt then
        prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not prompt.Enabled then
                removeCrateESP(model)
            end
        end)
        prompt.Triggered:Connect(function()
            task.wait(0.15)
            if not isCrateClosed(model) then
                removeCrateESP(model)
            end
        end)
    end

    model.DescendantRemoving:Connect(function(desc)
        if desc:IsA("ProximityPrompt") then
            removeCrateESP(model)
        end
    end)
end

-- ==============================================================================
-- ESCANEO INICIAL Y DETECCIÓN EN VIVO
-- ==============================================================================

local function setupFolderWatcher(folder)
    if not folder then return end
    for _, item in ipairs(folder:GetChildren()) do
        tagCrate(item)
    end
    folder.ChildAdded:Connect(function(child)
        task.wait(0.1)
        tagCrate(child)
    end)
end

-- Escanear Workspace.Map.Crates directamente
local mapFolder = workspace:WaitForChild("Map", 5)
if mapFolder then
    local cratesFolder = mapFolder:WaitForChild("Crates", 5)
    if cratesFolder then
        setupFolderWatcher(cratesFolder)
    end
    mapFolder.ChildAdded:Connect(function(child)
        if child.Name == "Crates" then
            setupFolderWatcher(child)
        end
    end)
end

-- Respaldo general por si aparecen fuera de la carpeta Crates
workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Model") and (desc:GetAttribute("Crate") == true or desc.Name == "Crates") then
        task.wait(0.1)
        tagCrate(desc)
    end
end)
