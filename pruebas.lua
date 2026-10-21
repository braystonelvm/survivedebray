-- ==============================================================================
-- RADAR FORZADO PARA COFRES (SOBREESCRIBE HIGHLIGHT DEL JUEGO / ROJO 360°)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function getCratePrompt(model)
    return model:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function isCrateClosed(model)
    if not model or not model.Parent then return false end
    
    local prompt = getCratePrompt(model)
    if prompt and prompt.Enabled then
        return true
    end

    -- Si no hay prompt activo o fue borrado, el cofre ya está abierto
    return false
end

local function clearCustomESP(model)
    local tag = model:FindFirstChild("CustomCrateTag", true)
    if tag then tag:Destroy() end

    -- Restaurar o eliminar los highlights creados
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Highlight") and desc.Name == "CrateESP_RedOverride" then
            desc:Destroy()
        end
    end
end

local function applyStrongRedESP(model)
    if not model:IsA("Model") then return end

    -- Verificar que sea un cofre válido (por carpeta o por atributos del reporte)
    local isCrate = (model.Parent and model.Parent.Name == "Crates")
        or model:GetAttribute("Crate") == true
        or model:FindFirstChild("CrateServer") ~= nil

    if not isCrate then return end

    -- Si ya está abierto, limpiar y salir
    if not isCrateClosed(model) then
        clearCustomESP(model)
        return
    end

    -- 1. SECUESTRAR O SOBREESCRIBIR EL HIGHLIGHT EXISTENTE
    -- Buscamos si el juego ya le puso un Highlight
    local existingHl = model:FindFirstChildWhichIsA("Highlight", true)
    if existingHl then
        existingHl.Name = "CrateESP_RedOverride"
        existingHl.FillColor = Color3.fromRGB(255, 0, 0)
        existingHl.OutlineColor = Color3.fromRGB(255, 255, 255)
        existingHl.FillTransparency = 0.3
        existingHl.OutlineTransparency = 0
        existingHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        existingHl.Enabled = true
    else
        -- Si no tenía ninguno creado todavía, lo creamos directamente
        local newHl = Instance.new("Highlight")
        newHl.Name = "CrateESP_RedOverride"
        newHl.FillColor = Color3.fromRGB(255, 0, 0)
        newHl.OutlineColor = Color3.fromRGB(255, 255, 255)
        newHl.FillTransparency = 0.3
        newHl.OutlineTransparency = 0
        newHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        newHl.Adornee = model
        newHl.Parent = model
    end

    -- 2. ETIQUETA FLOTANTE CON DISTANCIA (SE VE DESDE LEJOS A TRAVÉS DE TODO)
    local anchorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if anchorPart and not anchorPart:FindFirstChild("CustomCrateTag") then
        local bb = Instance.new("BillboardGui")
        bb.Name = "CustomCrateTag"
        bb.Size = UDim2.new(0, 120, 0, 30)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = anchorPart
        bb.Parent = anchorPart

        local lbl = Instance.new("TextLabel")
        lbl.Name = "DistanceLabel"
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "📦 COFRE"
        lbl.TextColor3 = Color3.fromRGB(255, 40, 40)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
    end

    -- 3. ESCUCHA DE EVENTOS PARA APAGARLO CUANDO SE ABRA
    local prompt = getCratePrompt(model)
    if prompt then
        prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not prompt.Enabled then
                clearCustomESP(model)
                local hl = model:FindFirstChildWhichIsA("Highlight", true)
                if hl then hl.Enabled = false end
            end
        end)
        prompt.Triggered:Connect(function()
            task.wait(0.1)
            if not isCrateClosed(model) then
                clearCustomESP(model)
                local hl = model:FindFirstChildWhichIsA("Highlight", true)
                if hl then hl.Enabled = false end
            end
        end)
    end

    model.DescendantRemoving:Connect(function(desc)
        if desc:IsA("ProximityPrompt") then
            clearCustomESP(model)
            local hl = model:FindFirstChildWhichIsA("Highlight", true)
            if hl then hl.Enabled = false end
        end
    end)
end

-- ==============================================================================
-- BUCLE EN TIEMPO REAL (ACTUALIZA DISTANCIAS Y CAPTURA COFRES A CUALQUIER DISTANCIA)
-- ==============================================================================

task.spawn(function()
    while true do
        task.wait(0.5)
        local char = lp.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local myPos = root and root.Position or Vector3.zero

        local cratesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                if crate:IsA("Model") then
                    if isCrateClosed(crate) then
                        applyStrongRedESP(crate)

                        -- Actualizar distancia numérica en studs
                        local part = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
                        local tag = crate:FindFirstChild("CustomCrateTag", true)
                        local lbl = tag and tag:FindFirstChild("DistanceLabel")
                        if part and lbl then
                            local dist = math.floor((part.Position - myPos).Magnitude)
                            lbl.Text = string.format("📦 COFRE [%dm]", dist)
                        end
                    else
                        clearCustomESP(crate)
                        local hl = crate:FindFirstChildWhichIsA("Highlight", true)
                        if hl then hl.Enabled = false end
                    end
                end
            end
        end
    end
end)
