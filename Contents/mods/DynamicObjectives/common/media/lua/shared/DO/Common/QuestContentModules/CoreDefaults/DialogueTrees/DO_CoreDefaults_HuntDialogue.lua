DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestDialogueTree then
    return
end

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
