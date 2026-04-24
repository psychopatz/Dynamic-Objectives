DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestContentModule then
    return
end

DO.RegisterQuestContentModule("CoreDefaults", {
    label = "Core Defaults",
    requirePaths = {
        "DO/Common/QuestContentModules/CoreDefaults/LootPools/DO_CoreDefaults_CourierItems",
        "DO/Common/QuestContentModules/CoreDefaults/LootPools/DO_CoreDefaults_HuntDropItems",
        "DO/Common/QuestContentModules/CoreDefaults/LootPools/DO_CoreDefaults_CourierRewards",
        "DO/Common/QuestContentModules/CoreDefaults/LootPools/DO_CoreDefaults_KillZoneRewards",
        "DO/Common/QuestContentModules/CoreDefaults/LootPools/DO_CoreDefaults_HuntRewards",
        "DO/Common/QuestContentModules/CoreDefaults/DialogueTrees/DO_CoreDefaults_CourierDialogue",
        "DO/Common/QuestContentModules/CoreDefaults/DialogueTrees/DO_CoreDefaults_KillZoneDialogue",
        "DO/Common/QuestContentModules/CoreDefaults/DialogueTrees/DO_CoreDefaults_HuntDialogue",
    },
})

DO.RegisterQuestContentModule("RestingContracts", {
    label = "Resting Contracts",
    requirePaths = {
        "DO/Common/QuestContentModules/RestingContracts/Blueprints/DO_RestingContracts_RestingCourierRun",
        "DO/Common/QuestContentModules/RestingContracts/Blueprints/DO_RestingContracts_RestingKillZone",
        "DO/Common/QuestContentModules/RestingContracts/Blueprints/DO_RestingContracts_RestingHuntDrop",
        "DO/Common/QuestContentModules/RestingContracts/Chains/DO_RestingContracts_ProgressionChain",
    },
})
