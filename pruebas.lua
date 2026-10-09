-- ==============================================================================
-- AUTOPSIA PROFUNDA DE ESTRUCTURAS Y AUTOS (EXTRACTOR TOTAL DE DATOS Y VARIABLES)
-- ==============================================================================

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
local myPos = root and root.Position or Vector3.zero

local lines = {}
local function log(t) table.insert(lines, t) end

log("==================================================")
log("   EXTRACCIÓN FORENSE DE VARIABLES Y ESTRUCTURAS  ")
log("==================================================")
log(string.format("Posición Jugador: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z))
log("Hora: " .. os.date("%X"))
log("--------------------------------------------------")

-- 1. RECOLECTAR MODELOS CERCANOS (RADIO DE 70 STUDS)
local targets = {}
local function checkModel(m)
    if not m or not m:IsA("Model") or m == char or Players:GetPlayerFromCharacter(m) then return end
    if m.Name:lower():find("drone") or m.Name:lower():find("dropped") then return end

    local cf, size = m:GetBoundingBox()
    local dist = (cf.Position - myPos).Magnitude
    if dist <= 70 then
        table.insert(targets, {Model = m, Dist = dist, Size = size, Pos = cf.Position})
    end
end

if workspace:FindFirstChild("Structures") then
    for _, m in ipairs(workspace.Structures:GetChildren()) do checkModel(m) end
end
for _, m in ipairs(workspace:GetChildren()) do
    if m ~= workspace:FindFirstChild("Structures") and m.Name ~= "Characters" then
        checkModel(m)
    end
end

-- Ordenar por cercanía (los más pegados a ti primero)
table.sort(targets, function(a, b) return a.Dist < b.Dist end)

-- Limitar a los 6 más cercanos para no saturar el texto
local maxScan = math.min(#targets, 8)
log(string.format("Total detectados en 70 studs: %d | Analizando a fondo los %d más cercanos:\n", #targets, maxScan))

for i = 1, maxScan do
    local item = targets[i]
    local m = item.Model
    log(string.format("══════════ OBJETO [%d/%d]: %s ══════════", i, maxScan, m.Name))
    log(string.format("• Distancia: %.1f studs | Ubicación: %s", item.Dist, m:GetFullName()))
    log(string.format("• BoundingBox: %.1f x %.1f x %.1f", item.Size.X, item.Size.Y, item.Size.Z))

    -- A. ATRIBUTOS DEL MODELO RAÍZ
    local rootAttrs = {}
    for k, v in pairs(m:GetAttributes()) do
        table.insert(rootAttrs, string.format("%s = %s (%s)", tostring(k), tostring(v), typeof(v)))
    end
    log("• Atributos en Modelo Raíz: " .. (#rootAttrs > 0 and table.concat(rootAttrs, " | ") or "NINGUNO"))

    -- B. ETIQUETAS DE COLLECTION SERVICE (TAGS)
    local tags = CollectionService:GetTags(m)
    log("• Tags de CollectionService: " .. (#tags > 0 and table.concat(tags, ", ") or "NINGUNO"))

    -- C. VALORES INTERNOS (IntValue, NumberValue, StringValue, ObjectValue)
    local valuesFound = {}
    for _, desc in ipairs(m:GetDescendants()) do
        if desc:IsA("ValueBase") then
            table.insert(valuesFound, string.format("%s (%s) = %s", desc.Name, desc.ClassName, tostring(desc.Value)))
        end
    end
    log("• Values internos encontrados: " .. (#valuesFound > 0 and table.concat(valuesFound, " | ") or "NINGUNO"))

    -- D. INTERFACES GRÁFICAS O TEXTOS FLOTANTES (Guis con vida, barras, números)
    local guiTexts = {}
    for _, desc in ipairs(m:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            if desc.Text and desc.Text ~= "" then
                table.insert(guiTexts, string.format("%s: '%s'", desc.Name, desc.Text))
            end
        end
    end
    log("• Textos en Guis internos: " .. (#guiTexts > 0 and table.concat(guiTexts, " | ") or "NINGUNO"))

    -- E. ATRIBUTOS EN PARTES INTERNAS (Muchos juegos ponen la vida en la 'MainPart' o 'Hitbox')
    local partAttrs = {}
    for _, desc in ipairs(m:GetDescendants()) do
        if desc:IsA("BasePart") then
            local pAttrs = desc:GetAttributes()
            for k, v in pairs(pAttrs) do
                table.insert(partAttrs, string.format("[%s].%s = %s", desc.Name, tostring(k), tostring(v)))
            end
        end
    end
    log("• Atributos en BaseParts hijas: " .. (#partAttrs > 0 and table.concat(partAttrs, " | ") or "NINGUNO"))

    -- F. ESTRUCTURA DE CARPETAS / CONFIGURATION
    local configs = {}
    for _, desc in ipairs(m:GetChildren()) do
        if desc:IsA("Configuration") or desc:IsA("Folder") then
            table.insert(configs, string.format("%s (%s con %d hijos)", desc.Name, desc.ClassName, #desc:GetChildren()))
        end
    end
    log("• Carpetas/Configuration raíz: " .. (#configs > 0 and table.concat(configs, ", ") or "NINGUNA"))

    -- G. HUMANOID O SEATS
    local hum = m:FindFirstChildOfClass("Humanoid") or m:FindFirstChildWhichIsA("Humanoid", true)
    if hum then
        log(string.format("• HUMANOID DETECTADO: Health=%.1f | MaxHealth=%.1f", hum.Health, hum.MaxHealth))
    end
    local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
    if seat then
        log(string.format("• ASIENTO DE VEHÍCULO: %s (Ocupante: %s)", seat.Name, tostring(seat.Occupant)))
    end

    log("") -- Salto de línea
end

log("==================================================")
log("             FIN DE LA AUTOPSIA                   ")
log("==================================================")

local fullReport = table.concat(lines, "\n")
if setclipboard then
    setclipboard(fullReport)
elseif toclipboard then
    toclipboard(fullReport)
end

StarterGui:SetCore("SendNotification", {
    Title = "📋 AUTOPSIA COMPLETADA",
    Text = string.format("Datos de %d objetos copiados al portapapeles.", maxScan),
    Duration = 5
})
