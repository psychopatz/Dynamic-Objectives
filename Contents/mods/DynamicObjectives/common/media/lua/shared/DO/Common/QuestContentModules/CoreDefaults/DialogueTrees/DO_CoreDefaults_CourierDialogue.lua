DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestDialogueTree then
    return
end

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
