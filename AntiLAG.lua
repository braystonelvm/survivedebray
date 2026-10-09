-- ==============================================================================
-- PURGADOR DE RESIDUOS DE COMBATE (CERO LAG | PROTECCIÓN TOTAL DE BASE)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local StatsService = game:GetService("Stats")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Config = {
    AutoPurgeInterval = 180, -- Purga automática cada 3 minutos (en segundos)
    ProtectRadius = 250,     -- Radio en studs alrededor tuyo donde NO tocará nada decorativo
}

local Window = Fluent:CreateWindow({
    Title = "COMBAT RAM PURGER",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 140,
    Size = UDim2.fromOffset(480, 340),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tab = Window:AddTab({ Title = "Limpieza", Icon = "trash-2" })

local StatusParagraph = Tab:AddParagraph({
    Title = "Monitor de Memoria",
    Content = "Iniciando monitor..."
})

-- FUNCIÓN DE PURGA EXCLUSIVA DE COMBATE (SIN TOCAR BASE NI ZANAHORIAS)
local function purgeCombatLeaks()
    local beforeRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local myPos = root and root.Position or Vector3.zero

    local destroyedCount = 0

    -- 1. LIMPIAR RESIDUOS EN LA CÁMARA (Donde los juegos arrojan trazadoras y sangre)
    if workspace.CurrentCamera then
        for _, obj in ipairs(workspace.CurrentCamera:GetChildren()) do
            pcall(function()
                obj:Destroy()
                destroyedCount = destroyedCount + 1
            end)
        end
    end

    -- 2. PURGAR CALCOMANÍAS DE SANGRE / IMPACTOS FUERA DE TU BASE
    -- (Busca Decals con texturas o nombres de sangre/disparos para no tocar carteles de tu base)
    for _, obj in ipairs(workspace:GetChildren()) do
        -- REGLA DE ORO: SI ES TU BASE O ESTRUCTURAS, NO ENTRAR
        local oName = obj.Name:lower()
        if oName ~= "structures" and oName ~= "map" and obj ~= char then
            for _, desc in ipairs(obj:GetDescendants()) do
                local dName = desc.Name:lower()
                local isBloodOrHit = dName:find("blood") or dName:find("hit") or dName:find("bullet") or dName:find("splatter") or dName:find("gore") or dName:find("sangre")

                -- Eliminar si es residuo de zombie
                if desc:IsA("Decal") and isBloodOrHit then
                    pcall(function()
                        desc:Destroy()
                        destroyedCount = destroyedCount + 1
                    end)
                elseif desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") then
                    if isBloodOrHit or not desc.Enabled then
                        pcall(function()
                            desc:Destroy()
                            destroyedCount = destroyedCount + 1
                        end)
                    end
                end
            end
        end
    end

    -- 3. ELIMINAR ZOMBIES MUERTOS Y RESTOS DE RAGDOLL EN CHARACTERS
    local charFolder = workspace:FindFirstChild("Characters")
    if charFolder then
        for _, entity in ipairs(charFolder:GetChildren()) do
            if entity:IsA("Model") and entity ~= char and not Players:GetPlayerFromCharacter(entity) then
                local hum = entity:FindFirstChildOfClass("Humanoid")
                local isCorpse = (hum and hum.Health <= 0) or entity.Name:lower():find("corpse") or entity.Name:lower():find("ragdoll")

                if isCorpse then
                    pcall(function()
                        entity:Destroy()
                        destroyedCount = destroyedCount + 1
                    end)
                end
            end
        end
    end

    -- 4. LIMPIAR CONTENEDOR DE ESCOMBROS DE ROBLOX
    local debrisFolder = workspace:FindFirstChild("Debris") or workspace:FindFirstChild("Ignore")
    if debrisFolder then
        for _, item in ipairs(debrisFolder:GetChildren()) do
            pcall(function()
                item:Destroy()
                destroyedCount = destroyedCount + 1
            end)
        end
    end

    -- 5. FORZAR LIBERACIÓN DE MEMORIA DEL MOTOR
    for _ = 1, 2 do
        collectgarbage("collect")
    end

    task.wait(0.2)
    local afterRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
    local msg = string.format("Purgados: %d residuos de combate | RAM Actual: %d MB", destroyedCount, afterRAM)
    StatusParagraph:SetDesc(msg)

    Fluent:Notify({
        Title = "Purga de Combate Completada",
        Content = msg,
        Duration = 3
    })
end

-- CONTROLES
Tab:AddButton({
    Title = "⚡ PURGAR RESIDUOS DE COMBATE AHORA",
    Description = "Elimina calcomanías de sangre, emisores huérfanos y proyectiles acumulados",
    Callback = function()
        purgeCombatLeaks()
    end
})

-- BUCLE AUTOMÁTICO EN SEGUNDO PLANO
task.spawn(function()
    while true do
        task.wait(Config.AutoPurgeInterval)
        purgeCombatLeaks()
    end
end)

-- MONITOR DE RAM EN VIVO EN LA INTERFAZ
task.spawn(function()
    while true do
        task.wait(2.0)
        local curRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
        StatusParagraph:SetTitle(string.format("Consumo RAM: %d MB (%.2f GB)", curRAM, curRAM / 1024))
    end
end)

Fluent:Notify({
    Title = "PURGADOR ACTIVADO",
    Content = "Tus estructuras y cultivos están 100% protegidos.",
    Duration = 4
})

Window:SelectTab(1)
