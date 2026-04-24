DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestLootPool then
    return
end

DO.RegisterQuestLootPool("default_courier_items", {
    id = "default_courier_items",
    label = "Default Courier Items",
    entries = {
        { id = "medical_package", weight = 5, itemType = "DTQuest.PackageMedicalQuest", label = "Medical Supplies", difficulty = 1.0 },
        { id = "small_package", weight = 4, itemType = "DTQuest.PackageSmallQuest", label = "Small Package", difficulty = 0.9 },
        { id = "gift_package", weight = 3, itemType = "DTQuest.PackageGiftQuest", label = "Gift Parcel", difficulty = 0.8 },
        { id = "fragile_package", weight = 2, itemType = "DTQuest.PackageFragileQuest", label = "Fragile Cargo", difficulty = 1.1 },
    },
})
