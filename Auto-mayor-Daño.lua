-- ==============================================================================
-- VEHICLE OMNI-RAM & GROUND SMASH (OPTIMIZADO PARA MANEJO ZHUB / 0% LAG)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua"))()

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,
    OmniHitbox = true,           -- Hitbox 360° (frente, laterales y cola)
    HitboxExpansion = 4.0,       -- Studs expandidos alrededor del auto
    SmashForce = 320,            -- Fuerza vertical de aplastamiento contra el suelo
    GhostDamage = true           -- Disparo fantasma de armas en mochila
}

local CurrentCar = nil
local CurrentSeat = nil
local TouchConnections = {}
local HitboxParts = {}
local HitDebounce = {}

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "ZHUB RAM EXTENDER",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 140,
    Size = UDim2.fromOffset(480, 360),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tab = Window:AddTab({ Title = "Parachoques", Icon = "shield" })

local StatusParagraph = Tab:AddParagraph({
    Title = "Estado del Auto",
    Content = "Sube a tu vehículo..."
})

-- FUNCIÓN PARA OBTENER ARMAS DE MOCHILA O MANO
local function getGhostWeaponEvent()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    local function search(folder)
        if not folder then return nil end
        for _, tool in ipairs(folder:GetChildren()) do
            if tool:IsA("Tool") then
                -- Prioridad cuerpo a cuerpo pesado (Sledgehammer/Bat)
                local hitTargets = tool:FindFirstChild("HitTargets")
                if hitTargets and hitTargets:IsA("RemoteEvent") then
                    return hitTargets, "melee", tool
                end
                -- Armas de fuego (AK-47 / AA-12 / Rifle)
                local projHit = tool:FindFirstChild("ProjectileHit")
                if projHit and projHit:IsA("RemoteEvent") then
                    return projHit, "gun", tool
                end
            end
        end
        return nil
    end

    local ev, tType, tool = search(char)
    if ev then return ev, tType, tool end
    return search(bp)
end

-- APLICAR DAÑO LETAL AL ZOMBIE (SIN TOCAR EL AUTO)
local function applyImpactToZombie(model)
    if not Config.Enabled then return end
    if HitDebounce[model] then return end
    HitDebounce[model] = true

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart

    if hum and hum.Health > 0 and root then
        -- 1. APLASTAMIENTO HACIA ABAJO (Afecta solo al zombie, el auto no se entera)
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(0, -Config.SmashForce, 0)
        end)

        -- 2. DAÑO FANTASMA DE TU ARMA
        if Config.GhostDamage then
            local remote, tType, tool = getGhostWeaponEvent()
            if remote then
                pcall(function()
                    if tType == "melee" then
                        remote:FireServer({model})
                    elseif tType == "gun" then
                        remote:FireServer(root, root.Position)
                    end
                end)
            end
        end
    end

    task.delay(0.2, function()
        HitDebounce[model] = nil
    end)
end

-- LIMPIEZA DE CONEXIONES
local function clearHitboxes()
    for _, conn in ipairs(TouchConnections) do
        conn:Disconnect()
    end
    table.clear(TouchConnections)

    for _, p in ipairs(HitboxParts) do
        if p and p.Parent then p:Destroy() end
    end
    table.clear(HitboxParts)
    table.clear(HitDebounce)

    CurrentCar = nil
    CurrentSeat = nil
end

-- CREAR HITBOX 360° TRANSPARENTE ALREDEDOR DEL AUTO
local function setupOmniHitbox(car, seat)
    clearHitboxes()
    CurrentCar = car
    CurrentSeat = seat

    -- Crear una caja de impacto que envuelve todo el auto
    local hitbox = Instance.new("Part")
    hitbox.Name = "OmniRamHitbox"
    hitbox.Size = (car:GetExtentsSize()) + Vector3.new(Config.HitboxExpansion, 1.5, Config.HitboxExpansion)
    hitbox.CFrame = seat.CFrame
    hitbox.Transparency = 1 -- Invisible
    hitbox.CanCollide = false
    hitbox.CanTouch = true
    hitbox.Massless = true
    hitbox.Parent = car

    -- Unir rígidamente al asiento para que siga cualquier rotación o derrape del ZHUB
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = seat
    weld.Part1 = hitbox
    weld.Parent = hitbox

    table.insert(HitboxParts, hitbox)

    -- Detectar contacto en cualquier ángulo (frente, lados, reversa)
    local conn = hitbox.Touched:Connect(function(hit)
        if not hit or not hit.Parent then return end
        local model = hit:FindFirstAncestorOfClass("Model")
        if model and model ~= lp.Character and not Players:GetPlayerFromCharacter(model) then
            applyImpactToZombie(model)
        end
    end)
    table.insert(TouchConnections, conn)

    -- También activar los bumpers nativos si existen
    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then
            local n = p.Name:lower()
            if n:find("bump") or n:find("plow") or n == "bumper" then
                p.CanTouch = true
                p.CanCollide = false
                local bConn = p.Touched:Connect(function(hit)
                    if not hit or not hit.Parent then return end
                    local model = hit:FindFirstAncestorOfClass("Model")
                    if model and model ~= lp.Character and not Players:GetPlayerFromCharacter(model) then
                        applyImpactToZombie(model)
                    end
                end)
                table.insert(TouchConnections, bConn)
            end
        end
    end

    StatusParagraph:SetDesc(string.format("✅ Conectado a [%s]\nHitbox 360° activa (+%.1f studs). Cero aceleración forzada.", car.Name, Config.HitboxExpansion))
end

-- CONTROLES DEL MENÚ
Tab:AddToggle("MasterToggle", {
    Title = "Parachoques Letal Activo",
    Default = true,
    Callback = function(v)
        Config.Enabled = v
        if v and CurrentCar and CurrentSeat then
            setupOmniHitbox(CurrentCar, CurrentSeat)
        end
    end
})

Tab:AddSlider("SizeSlider", {
    Title = "Alcance de la Hitbox (Studs)",
    Description = "Distancia extra para golpear antes de tocar tu carrocería",
    Default = 4.0,
    Min = 2.0,
    Max = 8.0,
    Rounding = 1,
    Callback = function(v)
        Config.HitboxExpansion = v
        if CurrentCar and CurrentSeat then
            setupOmniHitbox(CurrentCar, CurrentSeat)
        end
    end
})

Tab:AddToggle("GhostToggle", {
    Title = "Activar Daño Fantasma de Armas",
    Description = "Aplica el daño de tus armas al golpear con el auto",
    Default = true,
    Callback = function(v) Config.GhostDamage = v end
})

Tab:AddSlider("SmashSlider", {
    Title = "Fuerza de Aplastamiento al Zombie",
    Default = 320,
    Min = 150,
    Max = 500,
    Rounding = 0,
    Callback = function(v) Config.SmashForce = v end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OmniRamFloatBtn"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = lp:WaitForChild("PlayerGui")

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isOpen = not isOpen
    Window.Root.Visible = isOpen
end)

-- DETECCIÓN DEL ASIENTO (CADA 1.5s)
task.spawn(function()
    while true do
        task.wait(1.5)
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local seat = hum and hum.SeatPart

        if seat and seat:IsA("VehicleSeat") then
            local car = seat:FindFirstAncestorOfClass("Model")
            if car and car ~= CurrentCar then
                setupOmniHitbox(car, seat)
            end
        else
            if CurrentCar then
                clearHitboxes()
                StatusParagraph:SetDesc("Esperando a que subas a un vehículo...")
            end
        end
    end
end)

Fluent:Notify({
    Title = "PARACHOQUES 360° LISTO",
    Content = "Sin empujes bruscos. Adaptado para manejo ZHUB.",
    Duration = 3.5
})

Window:SelectTab(1)
