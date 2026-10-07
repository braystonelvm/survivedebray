-- ==============================================================================
-- ESCÁNER RÁPIDO DE ZOMBIES (COPIA AUTOMÁTICA AL PORTAPAPELES)
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer
local char = lp.Character
local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
local myPos = root and root.Position or Vector3.zero

local lines = {}
local function log(t) table.insert(lines, t) end

log("=== DIAGNÓSTICO EN VIVO DE ZOMBIES EN CLIENTE ===")
log(string.format("Posición Jugador: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z))
log("Hora: " .. os.date("%X"))
log("--------------------------------------------------")

local total = 0
local withHL = 0
local under750 = 0
local under1200 = 0
local checked = {}

local function inspectZombie(m)
    if not m:IsA("Model") or m == char or Players:GetPlayerFromCharacter(m) then return end
    if checked[m] then return end

    local eRoot = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not eRoot then return end

    checked[m] = true
    total = total + 1

    local dist = (eRoot.Position - myPos).Magnitude
    if dist <= 750 then under750 = under750 + 1 end
    if dist <= 1200 then under1200 = under1200 + 1 end

    -- Búsqueda de Highlight (directo o descendiente)
    local hl = m:FindFirstChildOfClass("Highlight") or m:FindFirstChildWhichIsA("Highlight", true)
    local hasHL = hl ~= nil
    if hasHL then withHL = withHL + 1 end

    -- Extraer atributos
    local attrs = {}
    for k, v in pairs(m:GetAttributes()) do
        table.insert(attrs, string.format("%s=%s", tostring(k), tostring(v)))
    end
    local attrText = #attrs > 0 and table.concat(attrs, ", ") or "sin_atributos"

    local hp = hum and string.format("%.0f HP", hum.Health) or "no_humanoid"

    log(string.format("• [%s] | Dist: %.1f studs | HL: %s | %s | Ubicacion: %s | Attrs: [%s]",
        m.Name, dist, tostring(hasHL), hp, m.Parent.Name, attrText
    ))
end

-- 1. Revisar carpeta Characters si existe
local folder = workspace:FindFirstChild("Characters")
if folder then
    for _, child in ipairs(folder:GetChildren()) do
        inspectZombie(child)
    end
end

-- 2. Revisar directamente en Workspace
for _, child in ipairs(workspace:GetChildren()) do
    inspectZombie(child)
end

log("--------------------------------------------------")
log(string.format("TOTAL DETECTADOS EN RAM: %d", total))
log(string.format("A menos de 750 studs: %d", under750))
log(string.format("A menos de 1200 studs: %d", under1200))
log(string.format("Con Highlight (brillo): %d", withHL))
log("=== FIN DEL REPORTE ===")

local finalReport = table.concat(lines, "\n")

-- Copiado al portapapeles
if setclipboard then
    setclipboard(finalReport)
elseif toclipboard then
    toclipboard(finalReport)
end

-- Notificación en pantalla de Roblox
pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "📋 REPORTE COPIADO",
        Text = string.format("Detectados: %d zombies. Ya está en tu portapapeles.", total),
        Duration = 5
    })
end)
