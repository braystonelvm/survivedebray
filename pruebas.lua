-- ==============================================================================
-- ESCÁNER MAESTRO: MAPEO DE ENTRADAS (N/S/E/O) Y VARIABLES DE HORDA
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
local baseCenter = root and root.Position or Vector3.zero

local lines = {}
local function log(t) table.insert(lines, t) end

log("==================================================================")
log("   DIAGNÓSTICO MAESTRO: ENTRADAS, CARRETERAS Y DETECCIÓN DE OLEADA ")
log("==================================================================")
log(string.format("Centro de Referencia (Tu posición): Vector3.new(%.1f, %.1f, %.1f)", baseCenter.X, baseCenter.Y, baseCenter.Z))
log("Hora de ejecución: " .. os.date("%X"))
log("------------------------------------------------------------------")

-- 1. MAPEO Y CLASIFICACIÓN DE CARRETERAS Y ENTRADAS (TSECTION Y STRAIGHTROAD)
log("\n[1. CARRETERAS Y ENTRADAS DETECTADAS (RADIO 500 STUDS)]:")
local roadsFound = {}

local function inspectRoad(obj)
    if not obj:IsA("Model") and not obj:IsA("BasePart") then return end
    local name = obj.Name:lower()
    
    if name:find("road") or name:find("tsection") or name:find("section") or name:find("street") or name:find("carretera") or name:find("pista") then
        local cf, size
        if obj:IsA("Model") then
            cf, size = obj:GetBoundingBox()
        else
            cf, size = obj.CFrame, obj.Size
        end

        local pos = cf.Position
        local diff = pos - baseCenter
        local dist = diff.Magnitude

        if dist <= 500 and dist > 8 then -- Ignorar si estás parado exactamente encima
            -- Determinar dirección cardinal respecto a la base
            local direction = "CENTRO"
            if math.abs(diff.Z) > math.abs(diff.X) then
                direction = (diff.Z < 0) and "NORTE (-Z)" or "SUR (+Z)"
            else
                direction = (diff.X > 0) and "ESTE (+X)" or "OESTE (-X)"
            end

            table.insert(roadsFound, {
                Name = obj.Name,
                Direction = direction,
                Dist = dist,
                Position = pos,
                Size = size,
                FullName = obj:GetFullName()
            })
        end
    end
end

for _, item in ipairs(workspace:GetDescendants()) do
    local pName = item.Parent and item.Parent.Name:lower() or ""
    if pName == "tiles" or pName == "map" or pName == "roads" or item.Parent == workspace then
        inspectRoad(item)
    end
end

-- Ordenar carreteras por dirección y distancia
table.sort(roadsFound, function(a, b) return a.Dist < b.Dist end)

if #roadsFound > 0 then
    for i, r in ipairs(roadsFound) do
        if i <= 20 then -- Mostrar las 20 principales
            log(string.format("• [%s] %s | Dist: %.1f studs | Vector3.new(%.1f, %.1f, %.1f)", 
                r.Direction, r.Name, r.Dist, r.Position.X, r.Position.Y, r.Position.Z))
        end
    end
else
    log(">> No se encontraron modelos con nombres de pista comunes en Tiles/Map. Revisa el contenedor de terreno.")
end

-- 2. RADAR DE CONCENTRACIÓN DE ZOMBIES (DETECTA LA DIRECCIÓN REAL DE LA OLEADA)
log("\n------------------------------------------------------------------")
log("[2. RADAR DE OLEADA: CONCENTRACIÓN DE ZOMBIES POR CUADRANTE]:")

local quadrantCount = {
    NORTE = 0, -- Z < 0
    SUR = 0,   -- Z > 0
    ESTE = 0,  -- X > 0
    OESTE = 0  -- X < 0
}

local totalZombies = 0
local charFolder = workspace:FindFirstChild("Characters") or workspace

for _, entity in ipairs(charFolder:GetChildren()) do
    if entity:IsA("Model") and entity ~= char and not Players:GetPlayerFromCharacter(entity) then
        local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
        local hum = entity:FindFirstChildOfClass("Humanoid")
        
        if eRoot and (not hum or hum.Health > 0) then
            local diff = eRoot.Position - baseCenter
            local dist = diff.Magnitude

            -- Filtrar solo zombies en rango activo (hasta 900 studs)
            if dist <= 900 then
                totalZombies = totalZombies + 1
                if math.abs(diff.Z) > math.abs(diff.X) then
                    if diff.Z < 0 then quadrantCount.NORTE = quadrantCount.NORTE + 1
                    else quadrantCount.SUR = quadrantCount.SUR + 1 end
                else
                    if diff.X > 0 then quadrantCount.ESTE = quadrantCount.ESTE + 1
                    else quadrantCount.OESTE = quadrantCount.OESTE + 1 end
                end
            end
        end
    end
end

log(string.format("Total zombies vivos en radar: %d", totalZombies))
log(string.format("• Sector NORTE: %d zombies (%.1f%%)", quadrantCount.NORTE, totalZombies > 0 and (quadrantCount.NORTE/totalZombies*100) or 0))
log(string.format("• Sector SUR:   %d zombies (%.1f%%)", quadrantCount.SUR, totalZombies > 0 and (quadrantCount.SUR/totalZombies*100) or 0))
log(string.format("• Sector ESTE:  %d zombies (%.1f%%)", quadrantCount.ESTE, totalZombies > 0 and (quadrantCount.ESTE/totalZombies*100) or 0))
log(string.format("• Sector OESTE: %d zombies (%.1f%%)", quadrantCount.OESTE, totalZombies > 0 and (quadrantCount.OESTE/totalZombies*100) or 0))

local activeSector = "DISPERSOS / EN PAUSA"
local maxZ = 0
for sec, cnt in pairs(quadrantCount) do
    if cnt > maxZ and cnt >= 15 then
        maxZ = cnt
        activeSector = sec
    end
end
log(string.format(">>> SECTOR PRINCIPAL ATACANDO AHORA: %s <<<", activeSector))

-- 3. FILTRADO PROFUNDO DE INTERFAZ (EXCLUYENDO DIÁLOGOS DE RADIO / SOBREVIVIENTES)
log("\n------------------------------------------------------------------")
log("[3. RASTREO DE TEXTOS Y BANNERS DE SISTEMA EN PLAYERGUI]:")

local validTexts = {}
local pGui = lp:FindFirstChild("PlayerGui")
if pGui then
    for _, desc in ipairs(pGui:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" then
            local t = desc.Text
            local tLower = t:lower()

            -- Descartar diálogos de radio, chat y textos genéricos
            local isRadioChat = tLower:find("bzzt") or tLower:find("survivor") or tLower:find("hello") or tLower:find("radio") or tLower:find("chatter")
            local isButton = desc.Parent:IsA("TextButton") or desc.Parent:IsA("ImageButton")

            if not isRadioChat and not isButton and #t >= 2 then
                table.insert(validTexts, string.format("• [%s] Ruta: %s\n   Texto: '%s'", desc.Name, desc:GetFullName(), t))
            end
        end
    end
end

if #validTexts > 0 then
    for i = 1, math.min(#validTexts, 15) do
        log(validTexts[i])
    end
else
    log(">> No hay textos activos relevantes en PlayerGui en este instante.")
end

-- 4. ATRIBUTOS Y VALORES GLOBALES EN REPLICATEDSTORAGE / WORKSPACE
log("\n------------------------------------------------------------------")
log("[4. VALORES Y ATRIBUTOS DE OLEADA EN REPLICATEDSTORAGE Y WORKSPACE]:")

local function checkGlobals(container, name)
    for k, v in pairs(container:GetAttributes()) do
        local key = k:lower()
        if key:find("wave") or key:find("horde") or key:find("blood") or key:find("night") or key:find("day") or key:find("side") or key:find("dir") then
            log(string.format("• Atributo en %s: %s = %s", name, k, tostring(v)))
        end
    end
    for _, val in ipairs(container:GetChildren()) do
        if val:IsA("ValueBase") then
            local vName = val.Name:lower()
            if vName:find("wave") or vName:find("horde") or vName:find("blood") or vName:find("night") or vName:find("day") or vName:find("side") or vName:find("dir") then
                log(string.format("• Objeto Value en %s: %s (%s) = %s", name, val.Name, val.ClassName, tostring(val.Value)))
            end
        end
    end
end

checkGlobals(ReplicatedStorage, "ReplicatedStorage")
checkGlobals(workspace, "Workspace")

log("==================================================================")
log("                    FIN DEL DIAGNÓSTICO                           ")
log("==================================================================")

local fullReport = table.concat(lines, "\n")
if setclipboard then
    setclipboard(fullReport)
elseif toclipboard then
    toclipboard(fullReport)
end

StarterGui:SetCore("SendNotification", {
    Title = "MAPEO COMPLETADO",
    Text = string.format("Entradas y radar de %d zombies copiados al portapapeles.", totalZombies),
    Duration = 5
})
