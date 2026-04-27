DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestBlueprint then
    return
end

DO.RegisterQuestBlueprint("resting_kill_zone", {
    id = "resting_kill_zone",
    name = "Kill Zone Sweep",
    family = "KillZone",
    enabled = true,
    weight = 3,
    cooldown = 24,
    difficulty = 1.0,
    timeLimitHours = 18,
    eligibility = {
        traderStates = { "Resting" },
    },
    target = {
        purpose = "Marked Kill Zone",
        radius = 28,
        r = 1.0,
        g = 0.3,
        b = 0.2,
    },
    encounter = {
        id = "kill_zone_encounter",
        kind = "kill_zone",
        baseCount = 8,
        spawnRadius = 18,
        clearRadius = 28,
        spawnMode = "building",
        requireAreaClear = true,
        requirePlayerPresence = true,
    },
    generation = {
        enabled = true,
        rewardProfile = "killzone_default",
        offerTtlHours = 6,
        allowProceduralCash = true,
        allowProceduralReputation = true,
    },
    rewardPools = { "default_killzone_rewards" },
    dialogueTree = "default_killzone_dialogue",
    objective = {
        id = "kill_zone",
        label = "Secure the building",
    },
})
