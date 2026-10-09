-- ==============================================================================
-- VISUALIZADOR DIRECTO DE PLACEMENT HITBOX (PRE-CONSTRUCCIÓN)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer

local ActiveBoxOutline = nil
local ActiveBillboard = nil
local ActiveLabel = nil

local function cleanupVisuals()
    if ActiveBoxOutline then ActiveBoxOutline:Destroy() ActiveBoxOutline = nil end
    if ActiveBillboard then ActiveBillboard:Destroy() ActiveBillboard = nil end
    ActiveLabel = nil
end

local function attachVisualsToHitbox(hitboxPart, toolName)
    cleanupVisuals()

    -- 1. Forzar visibilidad física de la caja invisible
    hitboxPart.Transparency = 0.65
    hitboxPart.Color = Color3.fromRGB(0, 255, 160)
    hitboxPart.Material = Enum.Material.ForceField

    -- 2. Contorno neón para marcar los bordes exactos
    ActiveBoxOutline = Instance.new("SelectionBox")
    ActiveBoxOutline.Name = "HitboxVisualBorder"
    ActiveBoxOutline.Color3 = Color3.fromRGB(0, 255, 160)
    ActiveBoxOutline.LineThickness = 0.05
    ActiveBoxOutline.Adornee = hitboxPart
    ActiveBoxOutline.Parent = hitboxPart

    -- 3. Etiqueta con medidas exactas en studs
    ActiveBillboard = Instance.new("BillboardGui")
    ActiveBillboard.Name = "HitboxInfoGui"
    ActiveBillboard.Size = UDim2.new(0, 200, 0, 50)
    ActiveBillboard.AlwaysOnTop = true
    ActiveBillboard.Adornee = hitboxPart
    ActiveBillboard.StudsOffset = Vector3.new(0, (hitboxPart.Size.Y / 2) + 1.2, 0)
    ActiveBillboard.Parent = hitboxPart

    ActiveLabel = Instance.new("TextLabel")
    ActiveLabel.Size = UDim2.new(1, 0, 1, 0)
    ActiveLabel.BackgroundTransparency = 1
    ActiveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    ActiveLabel.TextStrokeTransparency = 0
    ActiveLabel.TextSize = 13
    ActiveLabel.Font = Enum.Font.GothamBold
    ActiveLabel.Text = string.format("📐 [%s]\nAncho: %.1f | Alto: %.1f | Fondo: %.1f", 
        toolName, hitboxPart.Size.X, hitboxPart.Size.Y, hitboxPart.Size.Z
    )
    ActiveLabel.Parent = ActiveBillboard
end

-- Monitor en tiempo real para cuando equipes o cambies de plano
RunService.RenderStepped:Connect(function()
    local char = lp.Character
    local tool = char and char:FindFirstChildOfClass("Tool")

    if tool then
        local hitbox = tool:FindFirstChild("PlacementHitbox")
        if hitbox and hitbox:IsA("BasePart") then
            if not ActiveBoxOutline or ActiveBoxOutline.Adornee ~= hitbox then
                attachVisualsToHitbox(hitbox, tool.Name)
            else
                -- Actualizar etiqueta si el juego redimensiona dinámicamente la pieza
                if ActiveLabel then
                    local s = hitbox.Size
                    ActiveLabel.Text = string.format("📐 [%s]\nAncho: %.1f | Alto: %.1f | Fondo: %.1f", tool.Name, s.X, s.Y, s.Z)
                end
            end
            return
        end
    end

    -- Si no hay plano equipado o no tiene hitbox, limpiar
    if ActiveBoxOutline then
        cleanupVisuals()
    end
end)

StarterGui:SetCore("SendNotification", {
    Title = "HITBOX TRACKER ACTIVO",
    Text = "Equipa la valla o cualquier plano para ver su volumen.",
    Duration = 4
})
