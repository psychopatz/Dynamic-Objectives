DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestLootPool then
    return
end

DO.RegisterQuestLootPool("default_hunt_rewards", {
    id = "default_hunt_rewards",
    label = "Default Hunt Rewards",
    entries = {
        {
            id = "hunt_scavenger_bundle",
            weight = 4,
            rewards = {
                { kind = "money", amount = 240 },
                { kind = "reputation", amount = 5 },
                { kind = "item", itemType = "Base.Bandage", count = 2 },
            },
        },
        {
            id = "hunt_recruit_bundle",
            weight = 1,
            rewards = {
                { kind = "money", amount = 200 },
                {
                    kind = "recruit",
                    count = 1,
                    template = {
                        profession = "Scavenger",
                        jobType = "Scavenger",
                        name = "Recovered Scout",
                    },
                },
            },
        },
    },
})
