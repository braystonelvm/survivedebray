-- ==============================================================================
-- VISUALIZADOR EN VIVO DE LÍMITES PARA PLANOS / HOLOGRAMA (PRE-CONSTRUCCIÓN)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer

local VISUALS_FOLDER_NAME = "LivePlacementBounds"
local VisualsFolder = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
if not VisualsFolder then
    VisualsFolder = Instance.new("Folder")
    VisualsFolder.Name = VISUALS_FOLDER_NAME
    VisualsFolder.Parent = workspace
end

local Config = {
    Enabled = true,
    BoxColor = Color3.fromRGB(0, 255, 170),      -- Verde Neón para el perímetro de colocación
    HitboxColor = Color3.fromRGB(255, 60, 60),   -- Rojo para piezas invisibles internas
    BoxTransparency = 0.75
}

-- Referencias de visualización en vivo
local ActivePreviewModel = nil
local GhostVisualPart = nil
local GhostSelectionBox = nil
local GhostBillboard = nil
local GhostLabel = nil

-- Crear los componentes visuales una sola vez
local function ensureVisualElements()
    if not GhostVisualPart or not GhostVisualPart.Parent then
        GhostVisualPart = Instance.new("Part")
        GhostVisualPart.Name = "LiveBoundsPart"
        GhostVisualPart.Anchored = true
        GhostVisualPart.CanCollide = false
        GhostVisualPart.CanTouch = false
        GhostVisualPart.CanQuery = false
        GhostVisualPart.CastShadow = false
        GhostVisualPart.Material = Enum.Material.ForceField
        GhostVisualPart.Color = Config.BoxColor
        GhostVisualPart.Transparency = Config.BoxTransparency
        GhostVisualPart.Parent = VisualsFolder

        GhostSelectionBox = Instance.new("SelectionBox")
        GhostSelectionBox.Name = "LiveBoundsOutline"
        GhostSelectionBox.Color3 = Config.BoxColor
        GhostSelectionBox.LineThickness = 0.05
        GhostSelectionBox.Adornee = GhostVisualPart
        GhostSelectionBox.Parent = GhostVisualPart

        GhostBillboard = Instance.new("BillboardGui")
        GhostBillboard.Name = "LiveBoundsGui"
        GhostBillboard.Size = UDim2.new(0, 200, 0, 50)
        GhostBillboard.AlwaysOnTop = true
        GhostBillboard.Adornee = GhostVisualPart
        GhostBillboard.Parent = GhostVisualPart

        GhostLabel = Instance.new("TextLabel")
        GhostLabel.Size = UDim2.new(1, 0, 1, 0)
        GhostLabel.BackgroundTransparency = 1
        GhostLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        GhostLabel.TextStrokeTransparency = 0
        GhostLabel.TextSize = 13
        GhostLabel.Font = Enum.Font.GothamBold
        GhostLabel.Parent = GhostBillboard
    end
end

local function hideVisuals()
    if GhostVisualPart then
        GhostVisualPart.CFrame = CFrame.new(0, -5000, 0)
    end
    for _, obj in ipairs(VisualsFolder:GetChildren()) do
        if obj ~= GhostVisualPart then
            obj:Destroy()
        end
    end
end

-- RASTREADOR: Encuentra el modelo holograma que proyecta el plano
local function findPlacementPreview()
    local char = lp.Character
    if not char then return nil end

    -- 1. Buscar modelos con nombres clásicos de vista previa
    local searchTerms = {"preview", "ghost", "placement", "hologram", "blueprint", "temp", "build"}
    for _, folder in ipairs({workspace, workspace:FindFirstChild("Ignore"), workspace:FindFirstChild("CurrentCamera")}) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Model") and child ~= char and not Players:GetPlayerFromCharacter(child) then
                    local name = child.Name:lower()
                    for _, term in ipairs(searchTerms) do
                        if name:find(term) then
                            return child
                        end
                    end
                end
            end
        end
    end

    -- 2. Detección por modelo semi-transparente que no sea zombie/personaje
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child ~= char and not Players:GetPlayerFromCharacter(child) and child.Name ~= "Characters" then
            local primary = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
            if primary and not primary.CanCollide and primary.Transparency > 0.1 then
                if not child.Name:lower():find("drone") and not child.Name:lower():find("car") then
                    return child
                end
            end
        end
    end

    -- 3. Si la herramienta equipada en mano proyecta el modelo adentro
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        local internalModel = tool:FindFirstChildOfClass("Model")
        if internalModel then return internalModel end
    end

    return nil
end

-- BUCLE EN VIVO: Se sincroniza cada fotograma con el movimiento del ratón
RunService.RenderStepped:Connect(function()
    if not Config.Enabled then
        hideVisuals()
        return
    end

    local preview = findPlacementPreview()

    if preview and preview.Parent then
        ensureVisualElements()
        ActivePreviewModel = preview

        local cf, size = preview:GetBoundingBox()

        -- Actualizar posición y tamaño de la caja al milímetro
        GhostVisualPart.Size = size
        GhostVisualPart.CFrame = cf
        GhostBillboard.StudsOffset = Vector3.new(0, (size.Y / 2) + 1.2, 0)

        -- Mostrar medidas exactas
        GhostLabel.Text = string.format("📐 [%s]\nAncho: %.1f | Alto: %.1f | Fondo: %.1f", preview.Name, size.X, size.Y, size.Z)

        -- Resaltar si tiene piezas 100% invisibles en su interior que agranden el espacio
        for _, p in ipairs(preview:GetDescendants()) do
            if p:IsA("BasePart") and p.Transparency >= 0.85 then
                local tag = VisualsFolder:FindFirstChild("Hitbox_" .. p:GetDebugId())
                if not tag then
                    tag = Instance.new("SelectionBox")
                    tag.Name = "Hitbox_" .. p:GetDebugId()
                    tag.Color3 = Config.HitboxColor
                    tag.LineThickness = 0.04
                    tag.Adornee = p
                    tag.Parent = VisualsFolder
                end
            end
        end
    else
        ActivePreviewModel = nil
        hideVisuals()
    end
end)

-- ==============================================================================
-- BOTÓN FLOTANTE DE CONTROL
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LiveBlueprintViewerGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 140, 0, 36)
ToggleBtn.Position = UDim2.new(0.02, 0, 0.55, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 120)
ToggleBtn.Text = "LÍMITES PLANO: ON"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 11
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Active = true
ToggleBtn.Draggable = true
ToggleBtn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 6)
Corner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled
    ToggleBtn.Text = Config.Enabled and "LÍMITES PLANO: ON" or "LÍMITES PLANO: OFF"
    ToggleBtn.BackgroundColor3 = Config.Enabled and Color3.fromRGB(0, 170, 120) or Color3.fromRGB(180, 40, 40)
    if not Config.Enabled then hideVisuals() end
end)

StarterGui:SetCore("SendNotification", {
    Title = "VISOR DE PLANOS LISTO",
    Text = "Equipa el plano para ver los límites antes de colocar.",
    Duration = 4
})
