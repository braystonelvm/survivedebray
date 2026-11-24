local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

local function getFullPath(inst)
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local lines = {}
local function log(str)
    table.insert(lines, str)
end

log("=== ESCÁNER DE TIEMPOS Y RELOJES ===")
log("Lighting.ClockTime inicial: " .. tostring(Lighting.ClockTime))

-- 1. Capturar textos con números o ':' en PlayerGui (Muestra 1)
local pg = lp:WaitForChild("PlayerGui")
local guiSnapshots = {}

for _, gui in ipairs(pg:GetChildren()) do
    if gui:IsA("ScreenGui") and gui.Enabled then
        for _, desc in ipairs(gui:GetDescendants()) do
            if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Visible then
                local txt = desc.Text:gsub("%s+", " ")
                if txt:match("%d") and #txt <= 35 then
                    guiSnapshots[desc] = {
                        Text1 = txt,
                        Path = getFullPath(desc),
                        Pos = string.format("X:%.0f, Y:%.0f", desc.AbsolutePosition.X, desc.AbsolutePosition.Y)
                    }
                end
            end
        end
    end
end

-- Esperar 2.5 segundos para detectar cuáles cambian y cuáles están detenidos
task.wait(2.5)

log("Lighting.ClockTime tras 2.5s: " .. tostring(Lighting.ClockTime))
log("\n--- TEXTOS EN PLAYERGUI (CON NÚMEROS) ---")

for inst, data in pairs(guiSnapshots) do
    if inst and inst.Parent then
        local txt2 = inst.Text:gsub("%s+", " ")
        local estado = (txt2 ~= data.Text1) and "[CAMBIANDO]" or "[QUIETO]"
        log(string.format("%s '%s' -> '%s' | Pos(%s) | %s", estado, data.Text1, txt2, data.Pos, data.Path))
    end
end

-- 2. Revisar Atributos y Values en Workspace, ReplicatedStorage y Lighting
log("\n--- ATRIBUTOS Y VALUES DE TIEMPO/OLEADA ---")
local keywords = {"time", "clock", "timer", "wave", "round", "day", "night", "sec", "min", "countdown", "elapsed", "hora", "tiempo"}

local function matchesKeyword(name)
    local low = name:lower()
    for _, kw in ipairs(keywords) do
        if low:find(kw, 1, true) then return true end
    end
    return false
end

for _, service in ipairs({workspace, ReplicatedStorage, Lighting}) do
    for attrName, attrVal in pairs(service:GetAttributes()) do
        if matchesKeyword(attrName) then
            log(string.format("[Attr] %s.%s = %s", service.Name, attrName, tostring(attrVal)))
        end
    end
    for _, desc in ipairs(service:GetDescendants()) do
        if (desc:IsA("NumberValue") or desc:IsA("IntValue") or desc:IsA("StringValue") or desc:IsA("BoolValue")) and matchesKeyword(desc.Name) then
            log(string.format("[%s] %s = %s", desc.ClassName, getFullPath(desc), tostring(desc.Value)))
        end
    end
end

local finalOutput = table.concat(lines, "\n")
print(finalOutput)

if setclipboard then
    setclipboard(finalOutput)
    warn("✅ Reporte copiado al portapapeles (" .. #lines .. " líneas). Pégalo aquí.")
elseif toclipboard then
    toclipboard(finalOutput)
    warn("✅ Reporte copiado al portapapeles (" .. #lines .. " líneas). Pégalo aquí.")
else
    warn("⚠️ Tu ejecutor no soporta setclipboard; copia el texto desde la consola F9.")
end
