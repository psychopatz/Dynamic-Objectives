DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestLootPool then
    return
end

DO.RegisterQuestLootPool("default_killzone_rewards", {
    id = "default_killzone_rewards",
    label = "Default Kill Zone Rewards",
    entries = {
        {
            id = "killzone_combat_bundle",
            weight = 4,
            rewards = {
                { kind = "money", amount = 180 },
                { kind = "item", itemType = "Base.Bandage", count = 2 },
            },
        },
        {
            id = "killzone_rep_bundle",
            weight = 2,
            rewards = {
                { kind = "money", amount = 140 },
                { kind = "reputation", amount = 4 },
                { kind = "item", itemType = "Base.Pills", count = 1 },
            },
        },
    },
})
