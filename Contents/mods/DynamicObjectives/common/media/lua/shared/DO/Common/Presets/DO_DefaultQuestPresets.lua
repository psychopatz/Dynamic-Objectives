DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not (DO.RegisterQuestLootPool and DO.RegisterQuestBlueprint and DO.RegisterQuestDialogueTree) then
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

DO.RegisterQuestLootPool("default_hunt_drop_items", {
    id = "default_hunt_drop_items",
    label = "Default Hunt Drops",
    entries = {
        { id = "infected_sample", weight = 5, itemType = "DTQuest.InfectedSampleQuest", label = "Infected Sample" },
        { id = "proof_of_kill", weight = 3, itemType = "DTQuest.ProofOfKillQuest", label = "Proof of Kill" },
    },
})

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

DO.RegisterQuestDialogueTree("default_courier_dialogue", {
    id = "default_courier_dialogue",
    label = "Default Courier Dialogue",
    choices = {
        accept = "Accept",
        details = "Tell me more",
        rewards = "What's the reward?",
        decline = "Not now",
        back = "Back",
    },
    nodes = {
        offer = {
            text = "I need a runner. Take this package to {target.label} and keep it intact. Interested?",
        },
        details = {
            text = "It is a straight delivery run to {target.label}. Stay alive, keep the cargo on you, and hand it over once you reach the marker.",
        },
        rewards = {
            text = "Finish the run and I will pay out {rewardPreview}.",
        },
        accept = {
            text = "Good. I am marking the route now. Do not lose the package.",
        },
        decline = {
            text = "Then I will find another pair of hands.",
        },
        active = {
            text = "You are already carrying my job. Get to {target.label} and finish the delivery.",
        },
        unavailable = {
            text = "No work from me right now.",
        },
    },
})

DO.RegisterQuestDialogueTree("default_killzone_dialogue", {
    id = "default_killzone_dialogue",
    label = "Default Kill Zone Dialogue",
    choices = {
        accept = "Accept",
        details = "Tell me more",
        rewards = "What's the reward?",
        decline = "Not now",
        back = "Back",
    },
    nodes = {
        offer = {
            text = "There is a bad pocket of infected near {target.label}. Clear it out for me.",
        },
        details = {
            text = "Sweep the marked zone, kill everything in the building, and do not call it done until the place is secure.",
        },
        rewards = {
            text = "You clear the site, I pay {rewardPreview}.",
        },
        accept = {
            text = "Good. Move fast and keep the route clean.",
        },
        decline = {
            text = "Fine. The dead can wait a little longer.",
        },
        active = {
            text = "The marked zone still needs clearing. Finish the sweep around {target.label}.",
        },
        unavailable = {
            text = "I do not have a cleanup contract ready right now.",
        },
    },
})

DO.RegisterQuestDialogueTree("default_hunt_dialogue", {
    id = "default_hunt_dialogue",
    label = "Default Hunt Dialogue",
    choices = {
        accept = "Accept",
        details = "Tell me more",
        rewards = "What's the reward?",
        decline = "Not now",
        back = "Back",
    },
    nodes = {
        offer = {
            text = "I need proof from the infected cluster around {target.label}. Bring back what drops and I will make it worth your time.",
        },
        details = {
            text = "Clear the marked zone, search the corpse drop once it appears, and return with the recovered objective item.",
        },
        rewards = {
            text = "Recover the target and I will pay {rewardPreview}.",
        },
        accept = {
            text = "Then get moving. The sample will not stay useful forever.",
        },
        decline = {
            text = "Then I will hold the contract for someone else.",
        },
        active = {
            text = "You already took the hunt. Clear the marked zone and recover the drop.",
        },
        unavailable = {
            text = "No sample hunt is ready right now.",
        },
    },
})

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
    grantItemPool = "default_courier_items",
    rewardPools = { "default_courier_rewards" },
    dialogueTree = "default_courier_dialogue",
    objective = {
        id = "deliver_package",
        label = "Deliver the package",
        consumeOnComplete = true,
    },
})

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
    rewardPools = { "default_killzone_rewards" },
    dialogueTree = "default_killzone_dialogue",
    objective = {
        id = "kill_zone",
        label = "Eliminate the infestation",
    },
})

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
    dropItemPool = "default_hunt_drop_items",
    rewardPools = { "default_hunt_rewards" },
    dialogueTree = "default_hunt_dialogue",
    objective = {
        killLabel = "Purge the marked cluster",
        dropLabel = "Recover the sample",
        spawnAfterKills = 4,
        completeRemainingObjectives = true,
        completeQuestOnComplete = true,
    },
})

