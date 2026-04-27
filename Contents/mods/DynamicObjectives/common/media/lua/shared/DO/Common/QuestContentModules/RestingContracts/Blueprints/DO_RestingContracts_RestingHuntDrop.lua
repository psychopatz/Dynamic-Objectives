DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestBlueprint then
    return
end

DO.RegisterQuestBlueprint("resting_hunt_drop", {
    id = "resting_hunt_drop",
    name = "Infected Sample Hunt",
    family = "HuntDrop",
    enabled = true,
    weight = 2,
    cooldown = 24,
    difficulty = 1.1,
    timeLimitHours = 20,
    eligibility = {
        traderStates = { "Resting" },
    },
    target = {
        purpose = "Sample Hunt Zone",
        radius = 30,
        r = 0.95,
        g = 0.65,
        b = 0.1,
    },
    encounter = {
        id = "sample_hunt_encounter",
        kind = "hunt_drop",
        baseCount = 7,
        spawnRadius = 18,
        clearRadius = 30,
        spawnMode = "building",
        requireAreaClear = true,
        requirePlayerPresence = true,
    },
    generation = {
        enabled = true,
        rewardProfile = "huntdrop_default",
        offerTtlHours = 6,
        allowProceduralCash = true,
        allowProceduralReputation = true,
    },
    dropItemPool = "default_hunt_drop_items",
    rewardPools = { "default_hunt_rewards" },
    dialogueTree = "default_hunt_dialogue",
    objective = {
        killLabel = "Purge the marked cluster",
        dropLabel = "Recover the sample",
        spawnAfterKills = 4,
        skipAreaClearOnComplete = true,
        completeEncounterObjectivesOnComplete = true,
    },
})
