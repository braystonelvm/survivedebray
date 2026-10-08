-- ==============================================================================
-- RADIOGRAFÍA / ESCÁNER TÉCNICO DE GASOLINERA (DENTRO O FUERA DEL AUTO)
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
local hum = char:FindFirstChildOfClass("Humanoid")

local lines = {}
local function log(t) table.insert(lines, t) end

log("==================================================")
log("   RADIOGRAFÍA DE SURTIDOR / PROXIMITY PROMPT    ")
log("==================================================")
log("Hora local: " .. os.date("%X"))

-- 1. ESTADO DEL JUGADOR Y VEHÍCULO
local seat = hum and hum.SeatPart
local carModel = seat and (seat:FindFirstAncestorOfClass("Model") or seat.Parent)
local currentPos = (seat and seat.Position) or (root and root.Position) or Vector3.zero

log(string.format("Posición Jugador/Asiento: Vector3.new(%.1f, %.1f, %.1f)", currentPos.X, currentPos.Y, currentPos.Z))
log(string.format("¿Está sentado?: %s", tostring(hum and hum.Sit or false)))
if seat then
    log(string.format("Asiento actual: %s (Clase: %s)", seat.Name, seat.ClassName))
    log(string.format("Vehículo detectado: %s", carModel and carModel.Name or "Desconocido"))
else
    log("Estado: A pie (Fuera de cualquier auto)")
end
log("--------------------------------------------------")

-- 2. ESCANEO DE PROXIMITY PROMPTS EN UN RADIO DE 60 STUDS
log("[PROXIMITY PROMPTS EN RADIO DE 60 STUDS]:")
local promptsFound = 0

for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("ProximityPrompt") then
        local pPart = obj.Parent
        local pPos = nil

        if pPart:IsA("BasePart") then
            pPos = pPart.Position
        elseif pPart:IsA("Attachment") then
            pPos = pPart.WorldPosition
        end

        if pPos then
            local dist = (pPos - currentPos).Magnitude
            if dist <= 60 then
                promptsFound = promptsFound + 1
                log(string.format("\n--- PROMPT #%d ---", promptsFound))
                log(string.format("Objeto Padre: %s (Clase: %s | Ruta: %s)", pPart.Name, pPart.ClassName, pPart:GetFullName()))
                log(string.format("Distancia al jugador: %.2f studs", dist))
                log(string.format("Texto: ActionText='%s' | ObjectText='%s'", obj.ActionText, obj.ObjectText))
                log(string.format("Enabled: %s", tostring(obj.Enabled)))
                log(string.format("MaxActivationDistance: %.1f studs", obj.MaxActivationDistance))
                log(string.format("HoldDuration: %.2f s", obj.HoldDuration))
                log(string.format("RequiresLineOfSight: %s", tostring(obj.RequiresLineOfSight)))
                log(string.format("ClickablePrompt: %s", tostring(obj.ClickablePrompt)))
                log(string.format("ExceedsMaxDistance: %s", tostring(dist > obj.MaxActivationDistance)))

                -- Verificación de atributos del padre
                local attrs = {}
                for k, v in pairs(pPart:GetAttributes()) do
                    table.insert(attrs, string.format("%s=%s", tostring(k), tostring(v)))
                end
                log(string.format("Atributos del Padre: [%s]", #attrs > 0 and table.concat(attrs, ", ") or "ninguno"))
            end
        end
    end
end

if promptsFound == 0 then
    log(">> No se encontró ningún ProximityPrompt a menos de 60 studs.")
end

log("\n--------------------------------------------------")
-- 3. ESCANEO DE ESTRUCTURAS DE GASOLINA / TOUCH / CLICKDETECTOR
log("[OBJETOS RELACIONADOS CON GASOLINA/PUMP EN 60 STUDS]:")
local gasPartsFound = 0

for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("BasePart") then
        local name = obj.Name:lower()
        if name:find("gas") or name:find("pump") or name:find("surtidor") or name:find("fuel") or name:find("combustible") then
            local dist = (obj.Position - currentPos).Magnitude
            if dist <= 60 then
                gasPartsFound = gasPartsFound + 1
                local cd = obj:FindFirstChildOfClass("ClickDetector")
                local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
                local touch = obj:FindFirstChildOfClass("TouchTransmitter") ~= nil

                log(string.format("• [%s] | Dist: %.1f studs | ProximityPrompt: %s | ClickDetector: %s | CanTouch: %s", 
                    obj.Name, dist, tostring(prompt ~= nil), tostring(cd ~= nil), tostring(obj.CanCollide)
                ))
            end
        end
    end
end

if gasPartsFound == 0 then
    log(">> No se encontraron piezas nombradas con gas/pump en 60 studs.")
end

log("==================================================")
log("             FIN DE LA RADIOGRAFÍA               ")
log("==================================================")

local reportText = table.concat(lines, "\n")

-- Copiado directo al portapapeles
if setclipboard then
    setclipboard(reportText)
elseif toclipboard then
    toclipboard(reportText)
end

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "🔍 RADIOGRAFÍA LISTA",
        Text = string.format("Prompts: %d | Guardado en el portapapeles.", promptsFound),
        Duration = 5
    })
end)
