-- CAPTURADOR NATIVO SIN HOOK (FUNCIONA EN CUALQUIER EJECUTOR)
local lp = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local logs = {}

local function logTable( prefix, tbl )
    for k, v in pairs(tbl) do
        table.insert(logs, string.format("%s [%s] = %s (%s)", prefix, tostring(k), tostring(v), typeof(v)))
    end
end

-- 1. Inspeccionar el módulo Projectile de ReplicatedStorage
pcall(function()
    local projMod = ReplicatedStorage:FindFirstChild("Projectile", true)
    if projMod and projMod:IsA("ModuleScript") then
        local req = require(projMod)
        if type(req) == "table" then
            table.insert(logs, "=== FUNCIONES EN MODULE PROJECTILE ===")
            logTable("Projectile", req)
        end
    end
end)

-- 2. Escuchar BindableEvents nativos de las armas (ShotFired / ShotHit)
for _, cont in ipairs({lp.Character, lp:FindFirstChild("Backpack")}) do
    if cont then
        for _, tool in ipairs(cont:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("ToolType") == "Gun" then
                for _, evName in ipairs({"ShotFired", "ShotHit"}) do
                    local bev = tool:FindFirstChild(evName)
                    if bev and bev:IsA("BindableEvent") then
                        bev.Event:Connect(function(...)
                            local args = {...}
                            local str = "🎯 " .. tool.Name .. "." .. evName .. " -> "
                            for i, a in ipairs(args) do
                                str = str .. string.format("Arg[%d]=%s (%s) | ", i, tostring(a), typeof(a))
                            end
                            table.insert(logs, str)
                            print(str)
                        end)
                    end
                end
            end
        end
    end
end

-- Copiar después de disparar 1 bala
task.delay(6, function()
    local txt = table.concat(logs, "\n")
    if setclipboard then setclipboard(txt) end
    print("✅ Reporte sin-hook copiado al portapapeles.")
end)
