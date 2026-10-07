-- ==============================================================================
-- RADAR EXCLUSIVO PARA TRUCK (0% LAG / FILTRO ESTRICTO)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function tagTruck(model)
    if not model:IsA("Model") then return end

    -- Filtro estricto: solo el modelo exacto "Truck"
    if model.Name:lower() ~= "truck" then return end
    if model:FindFirstChild("TruckESP_Highlight") then return end

    -- 1. Resaltado visual en pantalla (Highlight a través de paredes)
    local hl = Instance.new("Highlight")
    hl.Name = "TruckESP_Highlight"
    hl.FillColor = Color3.fromRGB(255, 160, 0)      -- Naranja llamativo
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model

    -- 2. Etiqueta flotante con distancia
    local anchorPart = model:FindFirstChild("DriveSeat") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if anchorPart and not anchorPart:FindFirstChild("TruckESP_Tag") then
        local bb = Instance.new("BillboardGui")
        bb.Name = "TruckESP_Tag"
        bb.Size = UDim2.new(0, 100, 0, 26)
        bb.StudsOffset = Vector3.new(0, 4.5, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = anchorPart
        bb.Parent = anchorPart

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "🚚 TRUCK"
        lbl.TextColor3 = Color3.fromRGB(255, 180, 0)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0.2
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
    end

    local pos = anchorPart and anchorPart.Position or Vector3.zero
    print(string.format("🚚 [RADAR TRUCK]: Detectado en Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))
end

-- Escaneo de lo que ya esté cargado en Structures
local container = workspace:FindFirstChild("Structures") or workspace
for _, child in ipairs(container:GetChildren()) do
    tagTruck(child)
end

-- Listener en tiempo real cuando el servidor descargue un nuevo objeto al acercarte
container.ChildAdded:Connect(function(child)
    task.wait(0.2)
    tagTruck(child)
end)
