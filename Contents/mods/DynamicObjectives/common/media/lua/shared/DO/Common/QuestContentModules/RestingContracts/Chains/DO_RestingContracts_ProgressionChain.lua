DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

if not DO.RegisterQuestChain then
    return
end

DO.RegisterQuestChain("resting_contract_progression", {
    id = "resting_contract_progression",
    label = "Resting Contract Progression",
    defaultAdvanceMode = "offer",
    stages = {
        {
            id = "courier_entry",
            blueprintId = "resting_courier_run",
            nextStageId = "killzone_followup",
            advanceMode = "offer",
        },
        {
            id = "killzone_followup",
            blueprintId = "resting_kill_zone",
            nextStageId = "hunt_cleanup",
            advanceMode = "auto",
        },
        {
            id = "hunt_cleanup",
            blueprintId = "resting_hunt_drop",
        },
    },
})
