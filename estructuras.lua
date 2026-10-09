-- ==============================================================================
-- VISUALIZADOR Y RADIOGRAFÍA DE HITBOXES / ESPACIO DE ESTRUCTURAS (CON BOTÓN ON/OFF)
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer

-- Carpeta temporal para las cajas visuales
local VisualFolder = workspace:FindFirstChild("StructureHitboxVisuals")
if not VisualFolder then
    VisualFolder = Instance.new("Folder")
    VisualFolder.Name = "StructureHitboxVisuals"
    VisualFolder.Parent = workspace
end

local IsActive = false

-- Función para dibujar el espacio invisible
local function drawVisualBounds(cf, size, name, hasHiddenParts)
    local box = Instance.new("Part")
    box.Name = "VisualBounds_" .. name
    box.Size = size
    box.CFrame = cf
    box.Anchored = true
    box.CanCollide = false
    box.CanTouch = false
    box.CanQuery = false
    box.Material = Enum.Material.ForceField -- Visual holográfico limpio
    box.Color = hasHiddenParts and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(255, 140, 0)
    box.Transparency = 0.65
    box.Parent = VisualFolder

    -- Borde exterior para ver los límites con precisión milimétrica
    local sel = Instance.new("SelectionBox")
    sel.Adornee = box
    sel.Color3 = hasHiddenParts and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 200, 0)
    sel.LineThickness = 0.05
    sel.SurfaceTransparency = 0.9
    sel.Parent = box

    -- Etiqueta con el nombre y medidas
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 140, 0, 35)
    bb.AlwaysOnTop = true
    bb.Adornee = box
    bb.StudsOffset = Vector3.new(0, (size.Y / 2) + 1.2, 0)
    bb.Parent = box

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeTransparency = 0.2
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = string.format("%s\n[%.1f x %.1f x %.1f]", name, size.X, size.Y, size.Z)
    lbl.Parent = bb
end

-- Función para limpiar todas las cajas dibujadas
local function clearVisuals()
    if VisualFolder then
        VisualFolder:ClearAllChildren()
    end
end

-- Función principal de escaneo y dibujo
local function scanAndDraw()
    clearVisuals()

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local myPos = root and root.Position or Vector3.zero

    local lines = {}
    local function log(t) table.insert(lines, t) end

    log("==================================================")
    log("  ANÁLISIS DE ESPACIO Y HITBOXES DE ESTRUCTURAS   ")
    log("==================================================")
    log(string.format("Posición del Jugador: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z))
    log("Radio de análisis: 120 studs a la redonda")
    log("--------------------------------------------------")

    local count = 0
    local structuresFolder = workspace:FindFirstChild("Structures") or workspace

    -- Escanear exclusivamente modelos dentro de Structures
    local candidates = structuresFolder:GetChildren()
    for _, model in ipairs(candidates) do
        -- Filtrar solo modelos que sean estructuras (ignorar autos, jugadores y NPCs)
        if model:IsA("Model") and model ~= char and not Players:GetPlayerFromCharacter(model) then
            local mName = model.Name:lower()
            local isCar = mName:find("car") or mName:find("truck") or mName:find("vehicle") or model:FindFirstChildWhichIsA("VehicleSeat", true)
            
            if not isCar then
                local cf, size = model:GetBoundingBox()
                local dist = (cf.Position - myPos).Magnitude

                -- Solo estructuras dentro de 120 studs de tu base
                if dist <= 120 then
                    count = count + 1
                    log(string.format("\n[%d] ESTRUCTURA: %s | Distancia: %.1f studs", count, model.Name, dist))
                    log(string.format("   • Medidas Totales (BoundingBox): X=%.2f | Y=%.2f | Z=%.2f", size.X, size.Y, size.Z))
                    log(string.format("   • Centro: Vector3.new(%.1f, %.1f, %.1f)", cf.Position.X, cf.Position.Y, cf.Position.Z))

                    -- Revisar si tiene piezas invisibles infladas en su interior
                    local invisibleParts = {}
                    for _, part in ipairs(model:GetDescendants()) do
                        if part:IsA("BasePart") then
                            if part.Transparency >= 0.8 or not part.CastShadow then
                                table.insert(invisibleParts, string.format("%s (Tamaño: %.1fx%.1fx%.1f | Colisión: %s)", 
                                    part.Name, part.Size.X, part.Size.Y, part.Size.Z, tostring(part.CanCollide)))
                            end
                        end
                    end

                    if #invisibleParts > 0 then
                        log("   ⚠️ PIEZAS INVISIBLES DETECTADAS:")
                        for _, pInfo in ipairs(invisibleParts) do
                            log("      -> " .. pInfo)
                        end
                    else
                        log("   • No contiene piezas invisibles individuales (usa colisión del modelo).")
                    end

                    -- Dibujar la caja tridimensional en pantalla
                    drawVisualBounds(cf, size, model.Name, #invisibleParts > 0)
                end
            end
        end
    end

    log("--------------------------------------------------")
    log(string.format("TOTAL DE ESTRUCTURAS ANALIZADAS: %d", count))
    log("==================================================")

    local reportText = table.concat(lines, "\n")
    if setclipboard then setclipboard(reportText) elseif toclipboard then toclipboard(reportText) end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "📐 HITBOXES VISIBLES",
            Text = string.format("%d estructuras proyectadas en neón. Reporte copiado.", count),
            Duration = 4
        })
    end)
end

-- ==============================================================================
-- BOTÓN FLOTANTE (ON / OFF)
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HitboxToggleGUI"
ScreenGui.ResetOnSpawn = false
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 130, 0, 36)
ToggleBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
ToggleBtn.Text = "HITBOXES: OFF"
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
    IsActive = not IsActive

    if IsActive then
        ToggleBtn.Text = "HITBOXES: ON"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
        scanAndDraw()
    else
        ToggleBtn.Text = "HITBOXES: OFF"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        clearVisuals()
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "📐 HITBOXES APAGADAS",
                Text = "Visuales limpiados de pantalla.",
                Duration = 2
            })
        end)
    end
end)

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "BOTÓN LISTO",
        Text = "Usa el botón en pantalla para encender o apagar.",
        Duration = 3
    })
end)
