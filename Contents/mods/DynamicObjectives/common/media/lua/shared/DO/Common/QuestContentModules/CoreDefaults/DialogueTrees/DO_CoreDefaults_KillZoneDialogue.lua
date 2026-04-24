DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestDialogueTree then
    return
end

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
