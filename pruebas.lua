-- ==============================================================================
-- ESCÁNER PASIVO DE HERRAMIENTAS Y PREVISUALIZACIÓN DE PLANOS
-- ==============================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local lp = Players.LocalPlayer

local lines = {}
local function log(t) table.insert(lines, t) end

log("=== DIAGNÓSTICO DE ELEMENTOS DE CONSTRUCCIÓN ===")
log("Hora: " .. os.date("%X"))

local char = lp.Character
local tool = char and char:FindFirstChildOfClass("Tool")

if tool then
    log(string.format("• Herramienta equipada: %s (Clase: %s)", tool.Name, tool.ClassName))
    for _, desc in ipairs(tool:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("ValueBase") or desc:IsA("Configuration") then
            log(string.format("   -> Contenido interno: %s (%s)", desc.Name, desc.ClassName))
        end
    end
else
    log("• No hay ninguna herramienta equipada en mano actualmente.")
end

-- Rastrear piezas temporales creadas en la cámara o espacio de trabajo
log("\n[BUSCANDO MODELOS TEMPORALES O CLONES RECIENTES]:")
local foundPreview = false

local function checkContainer(parent, parentName)
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("Model") and child ~= char and not Players:GetPlayerFromCharacter(child) then
            local primary = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
            if primary and (primary.Transparency > 0.1 or not primary.CanCollide) then
                foundPreview = true
                log(string.format("• Objeto sospechoso en %s: %s (Partes: %d, Transparencia base: %.2f)",
                    parentName, child.Name, #child:GetChildren(), primary.Transparency))
            end
        end
    end
end

if workspace.CurrentCamera then
    checkContainer(workspace.CurrentCamera, "CurrentCamera")
end
checkContainer(workspace, "Workspace")

if not foundPreview then
    log(">> No se encontraron modelos temporales transparentes en Workspace ni Camera.")
end

log("=== FIN DEL REPORTE ===")

local result = table.concat(lines, "\n")
if setclipboard then
    setclipboard(result)
elseif toclipboard then
    toclipboard(result)
end

StarterGui:SetCore("SendNotification", {
    Title = "📋 REPORTE COPIADO",
    Text = "Diagnóstico copiado al portapapeles.",
    Duration = 4
})
