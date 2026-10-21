-- ==============================================================================
-- RADAR EXCLUSIVO PARA COFRES CERRADOS (ROJO / 0% LAG / SE APAGA AL ABRIRSE)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

-- Función para verificar si el cofre sigue cerrado
local function isChestClosed(model)
    if not model or not model.Parent then return false end

    -- 1. Verificación por atributos comunes del servidor
    if model:GetAttribute("Opened") == true or model:GetAttribute("Open") == true then
        return false
    end

    -- 2. Verificación por ProximityPrompt (un cofre cerrado tiene prompt habilitado para abrir)
    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        return prompt.Enabled
    end

    -- 3. Verificación por valores internos (BoolValue tipo 'Opened' / 'Open')
    local openVal = model:FindFirstChild("Opened", true) or model:FindFirstChild("Open", true)
    if openVal and openVal:IsA("BoolValue") then
        return not openVal.Value
    end

    return true
end

-- Función para limpiar el ESP del cofre
local function removeChestESP(model)
    local hl = model:FindFirstChild("ChestESP_Highlight")
    if hl then hl:Destroy() end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc.Name == "ChestESP_Tag" then
            desc:Destroy()
        end
    end
end

-- Función principal para etiquetar el cofre
local function tagChest(model)
    if not model:IsA("Model") then return end

    -- Filtro de nombre: detecta "chest", "chests" o "crate"
    local nameLower = model.Name:lower()
    if not (nameLower:find("chest") or nameLower:find("crate") or nameLower:find("cofre")) then
        return
    end

    -- Si ya está abierto, no hacer nada o limpiar si tenía ESP
    if not isChestClosed(model) then
        removeChestESP(model)
        return
    end

    if model:FindFirstChild("ChestESP_Highlight") then return end

    -- 1. Resaltado visual en pantalla (Highlight Rojo a través de paredes)
    local hl = Instance.new("Highlight")
    hl.Name = "ChestESP_Highlight"
    hl.FillColor = Color3.fromRGB(255, 30, 30)          -- Rojo llamativo
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.45
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model

    -- 2. Etiqueta flotante
    local anchorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if anchorPart and not anchorPart:FindFirstChild("ChestESP_Tag") then
        local bb = Instance.new("BillboardGui")
        bb.Name = "ChestESP_Tag"
        bb.Size = UDim2.new(0, 110, 0, 26)
        bb.StudsOffset = Vector3.new(0, 3.2, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = anchorPart
        bb.Parent = anchorPart

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "📦 COFRE"
        lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0.2
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
    end

    local pos = anchorPart and anchorPart.Position or Vector3.zero
    print(string.format("📦 [RADAR COFRE]: Detectado cerrado en Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))

    -- 3. Monitorear en tiempo real cuando se abra para apagar el ESP de inmediato
    -- A) Si cambian los atributos
    model.AttributeChanged:Connect(function()
        if not isChestClosed(model) then
            removeChestESP(model)
        end
    end)

    -- B) Si el ProximityPrompt cambia o es eliminado
    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not prompt.Enabled then
                removeChestESP(model)
            end
        end)
        prompt.AncestryChanged:Connect(function(_, parent)
            if not parent then
                removeChestESP(model)
            end
        end)
        prompt.Triggered:Connect(function()
            task.wait(0.2)
            if not isChestClosed(model) then
                removeChestESP(model)
            end
        end)
    end

    -- C) Si un hijo se elimina o cambia (como la tapa o el prompt)
    model.DescendantRemoving:Connect(function(desc)
        if desc:IsA("ProximityPrompt") then
            removeChestESP(model)
        end
    end)
end

-- ==============================================================================
-- ESCANEO Y LISTENERS
-- ==============================================================================

local containers = {
    workspace:FindFirstChild("Structures"),
    workspace:FindFirstChild("DroppedItems"),
    workspace:FindFirstChild("Map"),
    workspace
}

-- Escanear lo que ya esté en el mapa
for _, cont in ipairs(containers) do
    if cont then
        for _, child in ipairs(cont:GetChildren()) do
            tagChest(child)
        end
        -- Detectar cofres nuevos cuando carguen por streaming
        cont.ChildAdded:Connect(function(child)
            task.wait(0.15)
            tagChest(child)
        end)
    end
end
