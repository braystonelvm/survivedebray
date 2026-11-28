local tilesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Tiles")
local revealedCount = 0

if tilesFolder then
    for _, desc in ipairs(tilesFolder:GetDescendants()) do
        if desc:IsA("BasePart") and desc.CanCollide and desc.Transparency >= 0.9 then
            -- Hacer visible la caja de colisión invisible (ej. Tile_120)
            desc.Transparency = 0.65
            desc.Color = Color3.fromRGB(0, 235, 255)
            desc.Material = Enum.Material.ForceField

            if not desc:FindFirstChild("CollisionBoxOutline") then
                local box = Instance.new("SelectionBox")
                box.Name = "CollisionBoxOutline"
                box.Adornee = desc
                box.Color3 = Color3.fromRGB(0, 255, 190)
                box.LineThickness = 0.05
                box.Parent = desc
            end
            revealedCount = revealedCount + 1
        end
    end
    print(string.format("✅ Se revelaron %d bloques invisibles en Workspace.Map.Tiles", revealedCount))
else
    warn("⚠️ No se encontró Workspace.Map.Tiles")
end
