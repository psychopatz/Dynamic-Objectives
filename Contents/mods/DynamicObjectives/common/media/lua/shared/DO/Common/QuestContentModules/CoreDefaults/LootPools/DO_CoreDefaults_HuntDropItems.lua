DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestLootPool then
    return
end

DO.RegisterQuestLootPool("default_hunt_drop_items", {
    id = "default_hunt_drop_items",
    label = "Default Hunt Drops",
    entries = {
        { id = "infected_sample", weight = 5, itemType = "DTQuest.InfectedSampleQuest", label = "Infected Sample" },
        { id = "proof_of_kill", weight = 3, itemType = "DTQuest.ProofOfKillQuest", label = "Proof of Kill" },
    },
})
