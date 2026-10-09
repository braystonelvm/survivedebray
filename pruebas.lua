-- ==============================================================================
-- VISUALIZADOR Y ESCÁNER DE LÍMITES INVISIBLES DE ESTRUCTURAS (HITBOX / BOUNDS)
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

-- Carpeta contenedora de las cajas visuales en el Workspace
local VISUALS_FOLDER_NAME = "StructureHitboxVisuals"
local VisualsFolder = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
if not VisualsFolder then
    VisualsFolder = Instance.new("Folder")
    VisualsFolder.Name = VISUALS_FOLDER_NAME
    VisualsFolder.Parent = workspace
end

local Config = {
    ScanRadius = 120,          -- Radio alrededor de ti para analizar (studs)
    ShowOverallBox = true,     -- Muestra la caja total que abarca el modelo
    ShowHiddenParts = true,    -- Muestra piezas 100% invisibles dentro del modelo
    BoxColor = Color3.fromRGB(255, 60, 60),       -- Rojo para el perímetro invisible
    HiddenPartColor = Color3.fromRGB(255, 170, 0) -- Naranja para piezas ocultas
}

local function getRootPos()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    return root and root.Position or Vector3.zero
end

-- Determinar si un modelo es realmente una estructura de base y no un objeto genérico
local function isStructure(model)
    if not model or not model:IsA("Model") then return false end
    if model == lp.Character or Players:GetPlayerFromCharacter(model) then return false end

    local name = model.Name:lower()
    local parentName = model.Parent and model.Parent.Name:lower() or ""

    -- Filtros de exclusión: zombies, drones, autos, armas en el suelo, etc.
    if name:find("drone") or name:find("car") or name:find("zombie") or name:find("dropped") then
        return false
    end
    if parentName == "characters" or parentName == "droppeditems" or parentName == "holsteredweapons" then
        return false
    end

    -- Identificación positiva de estructuras
    if parentName:find("structure") or parentName:find("base") or parentName:find("build") then
        return true
    end

    local structureKeywords = {
        "wall", "pared", "door", "puerta", "gate", "porton", "floor", "piso", "roof", "techo",
        "ramp", "rampa", "foundation", "cimiento", "barricade", "barricada", "turret", "torreta",
        "chest", "cofre", "workbench", "mesa", "generator", "generador", "spikes", "pinchos",
        "fence", "cerca", "ladder", "escalera", "sandbag", "sacos", "light", "foco"
    }

    for _, kw in ipairs(structureKeywords) do
        if name:find(kw) then return true end
    end

    return false
end

-- Limpiar cajas visuales existentes
local function clearVisuals()
    VisualsFolder:ClearAllChildren()
end

-- Analizar y dibujar los límites invisibles
local function analyzeAndVisualize()
    clearVisuals()
    local myPos = getRootPos()
    local reportLines = {}
    local function log(t) table.insert(reportLines, t) end

    log("=== REPORTE DE PERÍMETROS Y ESPACIOS INVISIBLES EN ESTRUCTURAS ===")
    log(string.format("Posición Jugador: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z))
    log(string.format("Radio de análisis: %d studs", Config.ScanRadius))
    log("------------------------------------------------------------------")

    local scannedCount = 0

    -- Buscar estructuras en Workspace.Structures o en el Workspace general
    local candidates = {}
    local structFolder = workspace:FindFirstChild("Structures")
    if structFolder then
        for _, obj in ipairs(structFolder:GetChildren()) do
            if isStructure(obj) then table.insert(candidates, obj) end
        end
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if isStructure(obj) and not table.find(candidates, obj) then
            table.insert(candidates, obj)
        end
    end

    for _, model in ipairs(candidates) do
        local cf, size = model:GetBoundingBox()
        local dist = (cf.Position - myPos).Magnitude

        if dist <= Config.ScanRadius then
            scannedCount = scannedCount + 1

            -- 1. DETECTAR PIEZAS INVISIBLES INTERNAS (Hitboxes, Bounds, Colliders)
            local hiddenParts = {}
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA("BasePart") then
                    local pName = p.Name:lower()
                    local isInvisible = p.Transparency >= 0.85
                    local isHitboxName = pName:find("hitbox") or pName:find("bound") or pName:find("box") or pName:find("col") or pName:find("area") or pName:find("zone")

                    if isInvisible or isHitboxName then
                        table.insert(hiddenParts, p)

                        -- Dibujar la pieza oculta exacta en color naranja semi-transparente
                        if Config.ShowHiddenParts then
                            local ghost = Instance.new("Part")
                            ghost.Name = "HiddenPart_" .. p.Name
                            ghost.CFrame = p.CFrame
                            ghost.Size = p.Size
                            ghost.Shape = p.Shape
                            ghost.Anchored = true
                            ghost.CanCollide = false
                            ghost.CanTouch = false
                            ghost.CanQuery = false
                            ghost.CastShadow = false
                            ghost.Material = Enum.Material.Neon
                            ghost.Color = Config.HiddenPartColor
                            ghost.Transparency = 0.55
                            ghost.Parent = VisualsFolder
                        end
                    end
                end
            end

            -- 2. DIBUJAR LA CAJA TOTAL DE RESTRICCIÓN (Bounding Box del Modelo)
            if Config.ShowOverallBox then
                -- Marco de líneas (SelectionBox) para ver los bordes con precisión
                local boxOutline = Instance.new("SelectionBox")
                boxOutline.Name = "Outline_" .. model.Name
                boxOutline.Color3 = Config.BoxColor
                boxOutline.LineThickness = 0.05
                boxOutline.Adornee = VisualsFolder

                -- Pieza física semi-transparente que muestra el volumen que ocupa
                local boxVolume = Instance.new("Part")
                boxVolume.Name = "Box_" .. model.Name
                boxVolume.CFrame = cf
                boxVolume.Size = size
                boxVolume.Anchored = true
                boxVolume.CanCollide = false
                boxVolume.CanTouch = false
                boxVolume.CanQuery = false
                boxVolume.CastShadow = false
                boxVolume.Material = Enum.Material.ForceField
                boxVolume.Color = Config.BoxColor
                boxVolume.Transparency = 0.75
                boxVolume.Parent = VisualsFolder

                boxOutline.Adornee = boxVolume
                boxOutline.Parent = boxVolume

                -- Etiqueta flotante con el nombre y medidas exactas
                local bGui = Instance.new("BillboardGui")
                bGui.Size = UDim2.new(0, 160, 0, 40)
                bGui.AlwaysOnTop = true
                bGui.Adornee = boxVolume
                bGui.StudsOffset = Vector3.new(0, size.Y / 2 + 1.2, 0)
                bGui.Parent = boxVolume

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.TextColor3 = Color3.fromRGB(255, 255, 255)
                label.TextStrokeTransparency = 0
                label.TextSize = 12
                label.Font = Enum.Font.GothamBold
                label.Text = string.format("%s\n%.1f x %.1f x %.1f", model.Name, size.X, size.Y, size.Z)
                label.Parent = bGui
            end

            -- Registro para el informe textual
            log(string.format("• Estructura: [%s] | Distancia: %.1f studs", model.Name, dist))
            log(string.format("   -> Perímetro Total Ocupado: Ancho=%.1f studs | Alto=%.1f studs | Profundidad=%.1f studs", size.X, size.Y, size.Z))
            if #hiddenParts > 0 then
                log(string.format("   -> ¡Tiene %d pieza(s) invisible(s)/hitbox internas!:", #hiddenParts))
                for _, hp in ipairs(hiddenParts) do
                    log(string.format("      * %s (Tamaño: %.1f x %.1f x %.1f | Transparency: %.2f | CanCollide: %s)",
                        hp.Name, hp.Size.X, hp.Size.Y, hp.Size.Z, hp.Transparency, tostring(hp.CanCollide)))
                end
            else
                log("   -> No tiene piezas invisibles individuales (su bloqueo usa el volumen total del modelo).")
            end
        end
    end

    log("------------------------------------------------------------------")
    log(string.format("Total de estructuras analizadas en rango: %d", scannedCount))
    log("=== FIN DEL ANÁLISIS ===")

    local fullReport = table.concat(reportLines, "\n")
    if setclipboard then
        setclipboard(fullReport)
    elseif toclipboard then
        toclipboard(fullReport)
    end

    StarterGui:SetCore("SendNotification", {
        Title = "📐 ANÁLISIS COMPLETADO",
        Text = string.format("%d estructuras visualizadas. Reporte copiado al portapapeles.", scannedCount),
        Duration = 4
    })
end

-- ==============================================================================
-- INTERFAZ RÁPIDA DE CONTROL EN PANTALLA
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "StructureAnalyzerGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 150, 0, 80)
Frame.Position = UDim2.new(0.02, 0, 0.45, 0)
Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 24)
Title.BackgroundTransparency = 1
Title.Text = "HITBOX BUILD ANALYZER"
Title.TextColor3 = Color3.fromRGB(255, 80, 80)
Title.TextSize = 10
Title.Font = Enum.Font.GothamBold
Title.Parent = Frame

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.9, 0, 0, 24)
ScanBtn.Position = UDim2.new(0.05, 0, 0.32, 0)
ScanBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 220)
ScanBtn.Text = "MOSTRAR ESPACIOS"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 11
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = Frame
local BtnCorner1 = Instance.new("UICorner")
BtnCorner1.CornerRadius = UDim.new(0, 4)
BtnCorner1.Parent = ScanBtn

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.9, 0, 0, 22)
ClearBtn.Position = UDim2.new(0.05, 0, 0.66, 0)
ClearBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
ClearBtn.Text = "OCULTAR / LIMPIAR"
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.TextSize = 10
ClearBtn.Font = Enum.Font.Gotham
ClearBtn.Parent = Frame
local BtnCorner2 = Instance.new("UICorner")
BtnCorner2.CornerRadius = UDim.new(0, 4)
BtnCorner2.Parent = ClearBtn

ScanBtn.MouseButton1Click:Connect(function()
    analyzeAndVisualize()
end)

ClearBtn.MouseButton1Click:Connect(function()
    clearVisuals()
    StarterGui:SetCore("SendNotification", {
        Title = "Limpio",
        Text = "Visuales invisibles eliminados.",
        Duration = 2
    })
end)

-- Tecla rápida: Presiona 'B' para actualizar el escaneo de tu base en vivo
UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.B then
        analyzeAndVisualize()
    end
end)

StarterGui:SetCore("SendNotification", {
    Title = "ANALIZADOR LISTO",
    Text = "Presiona 'MOSTRAR ESPACIOS' o la tecla 'B'.",
    Duration = 4
})
