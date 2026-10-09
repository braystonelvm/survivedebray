-- ==============================================================================
-- EXTRACTOR DIRECTO DE ESTADÍSTICAS Y HP DESDE MODULESCRIPTS
-- ==============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local lp = game.Players.LocalPlayer

local lines = {}
local function log(t) table.insert(lines, t) end

log("==================================================")
log("  EXTRACCIÓN DE HP MÁXIMO DESDE MÓDULOS DEL JUEGO ")
log("==================================================")
log("Hora: " .. os.date("%X"))
log("--------------------------------------------------")

local HP_Database = {}

-- Función recursiva para desarmar tablas en busca de vida
local function inspectTable(tbl, sourceName)
    if type(tbl) ~= "table" then return end

    for key, val in pairs(tbl) do
        local strKey = tostring(key)

        -- Caso A: La clave es una estructura (ej: tbl["Fence"] = {Health = 500})
        if type(val) == "table" then
            local hp = val.Health or val.MaxHealth or val.HP or val.Durability or val.MaxDurability or val.MaxHp or val.Vida
            local def = val.Defense or val.Armor or val.Resistance
            if hp and type(hp) == "number" then
                if not HP_Database[strKey] or HP_Database[strKey].HP < hp then
                    HP_Database[strKey] = {HP = hp, Defense = def, Source = sourceName}
                end
            end
            -- Seguir buscando dentro por si está anidado
            inspectTable(val, sourceName)

        -- Caso B: La clave directa es la vida (ej: tbl["Tower_Health"] = 5000)
        elseif type(val) == "number" then
            local lowerK = strKey:lower()
            if lowerK:find("health") or lowerK:find("hp") or lowerK:find("durability") or lowerK:find("vida") then
                HP_Database[strKey] = {HP = val, Defense = nil, Source = sourceName}
            end
        end
    end
end

-- 1. REVISAR TODOS LOS MODULESCRIPTS EN REPLICATEDSTORAGE Y PLAYERSCRIPTS
local searchLocations = {
    ReplicatedStorage,
    lp:WaitForChild("PlayerScripts")
}

local modulesChecked = 0
for _, loc in ipairs(searchLocations) do
    for _, obj in ipairs(loc:GetDescendants()) do
        if obj:IsA("ModuleScript") then
            modulesChecked = modulesChecked + 1
            local success, result = pcall(function()
                return require(obj)
            end)

            if success and type(result) == "table" then
                inspectTable(result, obj.Name)
            end
        end
    end
end

log(string.format("Módulos analizados en memoria: %d", modulesChecked))
log("--------------------------------------------------")

-- 2. FILTRAR Y ORDENAR ESTRUCTURAS, TORRES Y AUTOS
local sortedList = {}
for name, data in pairs(HP_Database) do
    table.insert(sortedList, {Name = name, HP = data.HP, Defense = data.Defense, Source = data.Source})
end

table.sort(sortedList, function(a, b)
    return a.HP > b.HP
end)

log("[RANKING DE VIDA MÁXIMA ENCONTRADA]:")
if #sortedList > 0 then
    for rank, item in ipairs(sortedList) do
        local defText = item.Defense and string.format(" | Defensa/Armadura: %s", tostring(item.Defense)) or ""
        log(string.format("#%d [%s] -> %s HP%s (Módulo: %s)", 
            rank, item.Name, string.format("%.0f", item.HP), defText, item.Source))
    end
else
    log(">> Las tablas de datos no están expuestas como módulos públicos del cliente.")
end

-- 3. REVISAR VALORES NUMÉRICOS EN HERRAMIENTAS DE LA MOCHILA (PLANOS EQUIPADOS)
log("\n--------------------------------------------------")
log("[REVISIÓN DE PLANOS EN MOCHILA / INVENTARIO]:")
local backpack = lp:FindFirstChild("Backpack")
local char = lp.Character

local function checkTools(container)
    if not container then return end
    for _, t in ipairs(container:GetChildren()) do
        if t:IsA("Tool") then
            local stats = {}
            for k, v in pairs(t:GetAttributes()) do
                table.insert(stats, string.format("%s = %s", tostring(k), tostring(v)))
            end
            for _, val in ipairs(t:GetDescendants()) do
                if val:IsA("ValueBase") then
                    table.insert(stats, string.format("%s = %s", val.Name, tostring(val.Value)))
                end
            end
            log(string.format("• Plano [%s]: %s", t.Name, #stats > 0 and table.concat(stats, " | ") or "Sin variables numéricas"))
        end
    end
end

checkTools(backpack)
checkTools(char)

log("==================================================")
log("              FIN DE LA EXTRACCIÓN                ")
log("==================================================")

local fullReport = table.concat(lines, "\n")
if setclipboard then
    setclipboard(fullReport)
elseif toclipboard then
    toclipboard(fullReport)
end

StarterGui:SetCore("SendNotification", {
    Title = "📊 MÓDULOS EXTRAÍDOS",
    Text = string.format("%d estadísticas de HP copiadas al portapapeles.", #sortedList),
    Duration = 5
})
