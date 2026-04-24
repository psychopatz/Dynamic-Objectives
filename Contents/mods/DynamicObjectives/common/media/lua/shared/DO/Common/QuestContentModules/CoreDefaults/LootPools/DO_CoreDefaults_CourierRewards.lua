DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestLootPool then
    return
end

DO.RegisterQuestLootPool("default_courier_rewards", {
    id = "default_courier_rewards",
    label = "Default Courier Rewards",
    entries = {
        {
            id = "courier_cash_and_food",
            weight = 4,
            rewards = {
                { kind = "money", amount = 280 },
                { kind = "reputation", amount = 3 },
                { kind = "item", itemType = "Base.CannedSoup", count = 2 },
            },
        },
        {
            id = "courier_supply_bundle",
            weight = 3,
            rewards = {
                { kind = "money", amount = 220 },
                { kind = "item", itemType = "Base.Bandage", count = 4 },
                { kind = "item", itemType = "Base.WaterBottleFull", count = 1 },
            },
        },
    },
})
