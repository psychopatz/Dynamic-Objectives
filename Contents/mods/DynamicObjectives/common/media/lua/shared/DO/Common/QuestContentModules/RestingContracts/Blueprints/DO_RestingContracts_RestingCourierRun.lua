DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestBlueprint then
    return
end

DO.RegisterQuestBlueprint("resting_courier_run", {
    id = "resting_courier_run",
    name = "Courier Run",
    family = "Courier",
    enabled = true,
    weight = 5,
    cooldown = 18,
    difficulty = 1.0,
    timeLimitHours = 24,
    eligibility = {
        traderStates = { "Resting" },
    },
    target = {
        purpose = "Delivery Destination",
        radius = 16,
        r = 0.25,
        g = 0.85,
        b = 1.0,
    },
    generation = {
        enabled = true,
        rewardProfile = "courier_default",
        offerTtlHours = 6,
        allowProceduralCash = true,
        allowProceduralReputation = true,
    },
    grantItemPool = "default_courier_items",
    rewardPools = { "default_courier_rewards" },
    dialogueTree = "default_courier_dialogue",
    objective = {
        id = "deliver_package",
        label = "Deliver the package",
        consumeOnComplete = true,
    },
})
