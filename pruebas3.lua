local tilesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Tiles")
local revealedCount = 0

if tilesFolder then
    for _, desc in ipairs(tilesFolder:GetDescendants()) do
        if desc:IsA("BasePart") then
            -- 1. Si es exactamente la caja de colisión del edificio (Tile_120 dentro de Collision en ApartmentBroken)
            local isBuildingBox = (desc.Name == "Tile_120")
                and (desc.Parent and desc.Parent.Name == "Collision")
                and (desc.Parent.Parent and desc.Parent.Parent.Name == "ApartmentBroken")
                and (desc.Size.X >= 50 and desc.Size.Z >= 50)

            if isBuildingBox then
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
            else
                -- 2. Limpiar cualquier contorno o transparencia que se haya puesto en carreteras, basureros o carritos
                local oldOutline = desc:FindFirstChild("CollisionBoxOutline") or desc:FindFirstChild("InvisibleBoxView")
                if oldOutline then
                    oldOutline:Destroy()
                    desc.Transparency = 1
                end
            end
        end
    end
    print(string.format("✅ Listo: Solo %d cajas de edificios ApartmentBroken visibles (basureros y carreteras ocultos).", revealedCount))
else
    warn("⚠️ No se encontró Workspace.Map.Tiles")
end
