-- ==============================================================================
-- EXTRACTOR MAESTRO DE VIDA MÁXIMA (TORRES, AUTOS Y ESTRUCTURAS)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
local myPos = root and root.Position or Vector3.zero

local VISUALS_FOLDER_NAME = "StructureHPViewer"
local VisualFolder = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
if VisualFolder then VisualFolder:ClearAllChildren() else
    VisualFolder = Instance.new("Folder")
    VisualFolder.Name = VISUALS_FOLDER_NAME
    VisualFolder.Parent = workspace
end

local lines = {}
local function log(t) table.insert(lines, t) end

log("==================================================")
log("       TABLA MAESTRA DE VIDA (HP MÁXIMO)          ")
log("==================================================")
log("Hora: " .. os.date("%X"))
log("--------------------------------------------------")

-- 1. RASTREAR BASE DE DATOS EN REPLICATEDSTORAGE (CONFIGURACIONES DE PLANOS)
local MasterHP = {}

local function scanDatabase(parent)
    for _, obj in ipairs(parent:GetDescendants()) do
        local name = obj.Name:lower()
        -- Si encontramos módulos, configuraciones o carpetas con nombres de estructuras
        if obj:IsA("Configuration") or obj:IsA("Folder") or obj:IsA("Model") then
            for k, v in pairs(obj:GetAttributes()) do
                local key = k:lower()
                if (key:find("health") or key:find("hp") or key:find("durability") or key:find("vida")) and type(v) == "number" then
                    MasterHP[obj.Name] = v
                end
            end
            for _, val in ipairs(obj:GetChildren()) do
                if val:IsA("ValueBase") and type(val.Value) == "number" then
                    local vName = val.Name:lower()
                    if vName:find("health") or vName:find("hp") or vName:find("durability") or vName:find("vida") then
                        MasterHP[obj.Name] = val.Value
                    end
                end
            end
        end
    end
end

scanDatabase(ReplicatedStorage)

-- 2. ESCANEO ESPECÍFICO DE OBJETOS EN WORKSPACE (FILTRANDO REPETIDOS)
local uniqueFound = {}
local scannedList = {}

local function inspect(m)
    if not m or not m:IsA("Model") or m == char or Players:GetPlayerFromCharacter(m) then return end
    local mName = m.Name

    local isCar = mName:lower():find("car") or mName:lower():find("truck") or mName:lower():find("vehicle") or m:FindFirstChildWhichIsA("VehicleSeat", true) ~= nil
    local isTower = mName:lower():find("tower") or mName:lower():find("torre") or mName:lower():find("turret")
    local isStruct = m.Parent and m.Parent.Name == "Structures"

    if isCar or isTower or isStruct then
        local cf, size = m:GetBoundingBox()
        local dist = (cf.Position - myPos).Magnitude
        if dist > 140 then return end

        -- Buscar vida en MockHumanoid
        local hpVal = nil
        local mock = m:FindFirstChild("MockHumanoid")
        if mock then
            for k, v in pairs(mock:GetAttributes()) do
                if (k:lower():find("health") or k:lower():find("hp") or k:lower():find("max")) and type(v) == "number" then
                    hpVal = v
                end
            end
            for _, val in ipairs(mock:GetChildren()) do
                if val:IsA("ValueBase") and type(val.Value) == "number" then hpVal = val.Value end
            end
        end

        -- Si no está en MockHumanoid, buscar en el modelo o en la base maestra
        if not hpVal then
            for k, v in pairs(m:GetAttributes()) do
                if (k:lower():find("hp") or k:lower():find("health") or k:lower():find("max")) and type(v) == "number" then hpVal = v end
            end
        end
        if not hpVal and MasterHP[mName] then
            hpVal = MasterHP[mName]
        end

        -- Si es un auto, revisar chasis y asientos
        if isCar and not hpVal then
            local driveSeat = m:FindFirstChildWhichIsA("VehicleSeat", true)
            if driveSeat then
                hpVal = driveSeat:GetAttribute("Health") or driveSeat:GetAttribute("MaxHealth") or m:GetAttribute("Health")
            end
            -- Valor habitual de chasis si el juego usa script de carrocería
            hpVal = hpVal or m:GetAttribute("EngineHealth") or m:GetAttribute("BodyHealth")
        end

        table.insert(scannedList, {
            Name = mName,
            Model = m,
            HP = hpVal,
            IsCar = isCar,
            IsTower = isTower,
            Dist = dist,
            CFrame = cf,
            Size = size
        })
    end
end

for _, m in ipairs(workspace.Structures and workspace.Structures:GetChildren() or {}) do inspect(m) end
for _, m in ipairs(workspace:GetChildren()) do inspect(m) end

-- 3. PROCESAR RESULTADOS Y COLOCAR ETIQUETAS GIGANTES
log("[VALORES EXTRAÍDOS]:")
for _, item in ipairs(scannedList) do
    local displayText = item.HP and string.format("%.0f HP", item.HP) or "Desconocido (En Servidor)"
    log(string.format("• %s [%s] -> %s | Dist: %.1f studs", 
        item.IsCar and "🚗" or (item.IsTower and "🗼" or "🛡️"), item.Name, displayText, item.Dist))

    -- Dibujar en pantalla con Billboard gigante
    local anchor = Instance.new("Part")
    anchor.Name = "HPAnchor_" .. item.Name
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Transparency = 1
    anchor.CFrame = item.CFrame
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Parent = VisualFolder

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 240, 0, 75)
    bb.AlwaysOnTop = true
    bb.Adornee = anchor
    bb.StudsOffset = Vector3.new(0, (item.Size.Y / 2) + 2.5, 0)
    bb.Parent = anchor

    local lblName = Instance.new("TextLabel")
    lblName.Size = UDim2.new(1, 0, 0, 20)
    lblName.BackgroundTransparency = 1
    lblName.TextColor3 = Color3.fromRGB(255, 255, 255)
    lblName.TextStrokeTransparency = 0
    lblName.TextSize = 14
    lblName.Font = Enum.Font.GothamBold
    lblName.Text = (item.IsCar and "🚗 " or "🛡️ ") .. item.Name
    lblName.Parent = bb

    local lblHP = Instance.new("TextLabel")
    lblHP.Size = UDim2.new(1, 0, 0, 50)
    lblHP.Position = UDim2.new(0, 0, 0, 20)
    lblHP.BackgroundTransparency = 1
    lblHP.TextStrokeTransparency = 0
    lblHP.TextSize = 36
    lblHP.Font = Enum.Font.GothamBlack
    lblHP.TextColor3 = item.IsCar and Color3.fromRGB(0, 240, 255) or (item.IsTower and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(50, 255, 120))
    lblHP.Text = displayText
    lblHP.Parent = bb
end

log("==================================================")
local report = table.concat(lines, "\n")
if setclipboard then setclipboard(report) elseif toclipboard then toclipboard(report) end

StarterGui:SetCore("SendNotification", {
    Title = "EXTRACCIÓN MAESTRA LISTA",
    Text = "Datos de vida extraídos y copiados al portapapeles.",
    Duration = 5
})
