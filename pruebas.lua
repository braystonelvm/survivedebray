-- ==============================================================================
-- ESCÁNER PROFUNDO DE GASOLINERA Y REMOTES (A PIE)
-- ==============================================================================

local lp = game.Players.LocalPlayer
local char = lp.Character
local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
local pos = root and root.Position or Vector3.new(-182.2, 3.2, -258.9)

local info = {}
local function add(t) table.insert(info, t) end

add("=== INSPECCIÓN DE GASOLINERA EN EL MAPA ===")
add(string.format("Posición de escaneo: Vector3.new(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))

-- 1. Buscar modelos de la gasolinera en Workspace
add("\n[MODELOS Y PIEZAS EN 25 STUDS]:")
for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("BasePart") and not obj:IsDescendantOf(char) and not (obj.Parent and obj.Parent.Name:find("Car")) then
        local dist = (obj.Position - pos).Magnitude
        if dist <= 25 then
            local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
            local cd = obj:FindFirstChildOfClass("ClickDetector")
            add(string.format("• Objeto: %s | Dist: %.1f studs | Prompt: %s | ClickDetector: %s | Ruta: %s",
                obj.Name, dist, tostring(prompt ~= nil), tostring(cd ~= nil), obj:GetFullName()))
            if prompt then
                add(string.format("   -> Prompt Activo: %s | Texto: '%s %s'", tostring(prompt.Enabled), prompt.ObjectText, prompt.ActionText))
            end
        end
    end
end

-- 2. Buscar Remotes relacionados con combustible
add("\n[REMOTES DE COMBUSTIBLE EN REPLICATEDSTORAGE]:")
local rep = game:GetService("ReplicatedStorage")
for _, r in ipairs(rep:GetDescendants()) do
    if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
        local rName = r.Name:lower()
        if rName:find("gas") or rName:find("fuel") or rName:find("vehicle") or rName:find("car") or rName:find("pump") then
            add(string.format("• Remote: %s (%s) | Ruta: %s", r.Name, r.ClassName, r:GetFullName()))
        end
    end
end

local res = table.concat(info, "\n")
if setclipboard then setclipboard(res) elseif toclipboard then toclipboard(res) end

game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "🔍 ESCANEO DE GASOLINERA LISTO",
    Text = "Copiado al portapapeles. Pégalo aquí.",
    Duration = 5
})
