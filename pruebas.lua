-- ==============================================================================
-- ESCÁNER FORENSE POR CONSOLA (SIN GUI - 100% COMPATIBLE CON DELTA)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

print("\n==================================================================")
print("       INICIANDO ESCÁNER DE PROFUNDIDADES Y ROCAS (300 STUDS)      ")
print("==================================================================")

local rocksFound = 0
local deepZones = 0
local baseCenter = Vector3.new(0, 0, 0)
local lowestPartY = 0

for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("BasePart") then
        local pos = desc.Position
        local dist = (pos - baseCenter).Magnitude

        if dist <= 300 then
            local nameLower = desc.Name:lower()

            -- 1. Detectar y colorear rocas de verde brillante
            if nameLower:find("rock") or nameLower:find("stone") or nameLower:find("boulder") or nameLower:find("piedra") or nameLower:find("roca") or nameLower:find("cliff") then
                rocksFound = rocksFound + 1
                pcall(function()
                    desc.Color = Color3.fromRGB(0, 255, 120)
                    desc.Material = Enum.Material.Neon
                end)
                if rocksFound <= 15 then
                    print(string.format("🪨 Roca: '%s' | Pos: (%.1f, %.1f, %.1f) | Profundidad Y: %.1f", desc.Name, pos.X, pos.Y, pos.Z, pos.Y))
                end
            end

            -- 2. Detectar partes más profundas bajo tierra
            if pos.Y < lowestPartY then
                lowestPartY = pos.Y
            end

            if pos.Y <= -2.0 then
                deepZones = deepZones + 1
            end
        end
    end
end

print(string.format("\n[RESULTADO DEL ESCANEO]:"))
print(string.format(" • Total de rocas iluminadas de verde: %d", rocksFound))
print(string.format(" • Total de zonas bajo tierra (Y < -2): %d", deepZones))
print(string.format(" • Punto más profundo registrado en el mapa: Y = %.1f", lowestPartY))
print("==================================================================\n")

-- ==============================================================================
-- COMANDO DE PRUEBA DE TELETRANSPORTE SUBTERRÁNEO
-- ==============================================================================
-- Esto te baja a Y = -15 de golpe para verificar si el mapa te deja ahí abajo
local function testUndergroundTeleport()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        warn("¡Personaje no encontrado!")
        return
    end

    -- Desactivar colisiones para el test
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end

    local testY = -15.0
    root.CFrame = CFrame.new(root.Position.X, testY, root.Position.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    print(string.format("⚡ [TEST DE TELEPORT]: Te he bajado a la coordenada Y = %.1f. Revisa si el servidor te mantiene abajo o te hace rollback.", testY))
end

-- Ejecutar el test de teletransporte automáticamente al terminar el escaneo
task.spawn(testUndergroundTeleport)-- ==============================================================================
-- ESCÁNER FORENSE POR CONSOLA (SIN GUI - 100% COMPATIBLE CON DELTA)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

print("\n==================================================================")
print("       INICIANDO ESCÁNER DE PROFUNDIDADES Y ROCAS (300 STUDS)      ")
print("==================================================================")

local rocksFound = 0
local deepZones = 0
local baseCenter = Vector3.new(0, 0, 0)
local lowestPartY = 0

for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("BasePart") then
        local pos = desc.Position
        local dist = (pos - baseCenter).Magnitude

        if dist <= 300 then
            local nameLower = desc.Name:lower()

            -- 1. Detectar y colorear rocas de verde brillante
            if nameLower:find("rock") or nameLower:find("stone") or nameLower:find("boulder") or nameLower:find("piedra") or nameLower:find("roca") or nameLower:find("cliff") then
                rocksFound = rocksFound + 1
                pcall(function()
                    desc.Color = Color3.fromRGB(0, 255, 120)
                    desc.Material = Enum.Material.Neon
                end)
                if rocksFound <= 15 then
                    print(string.format("🪨 Roca: '%s' | Pos: (%.1f, %.1f, %.1f) | Profundidad Y: %.1f", desc.Name, pos.X, pos.Y, pos.Z, pos.Y))
                end
            end

            -- 2. Detectar partes más profundas bajo tierra
            if pos.Y < lowestPartY then
                lowestPartY = pos.Y
            end

            if pos.Y <= -2.0 then
                deepZones = deepZones + 1
            end
        end
    end
end

print(string.format("\n[RESULTADO DEL ESCANEO]:"))
print(string.format(" • Total de rocas iluminadas de verde: %d", rocksFound))
print(string.format(" • Total de zonas bajo tierra (Y < -2): %d", deepZones))
print(string.format(" • Punto más profundo registrado en el mapa: Y = %.1f", lowestPartY))
print("==================================================================\n")

-- ==============================================================================
-- COMANDO DE PRUEBA DE TELETRANSPORTE SUBTERRÁNEO
-- ==============================================================================
-- Esto te baja a Y = -15 de golpe para verificar si el mapa te deja ahí abajo
local function testUndergroundTeleport()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        warn("¡Personaje no encontrado!")
        return
    end

    -- Desactivar colisiones para el test
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end

    local testY = -15.0
    root.CFrame = CFrame.new(root.Position.X, testY, root.Position.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    print(string.format("⚡ [TEST DE TELEPORT]: Te he bajado a la coordenada Y = %.1f. Revisa si el servidor te mantiene abajo o te hace rollback.", testY))
end

-- Ejecutar el test de teletransporte automáticamente al terminar el escaneo
task.spawn(testUndergroundTeleport)
