-- DT_MANUAL_EDITOR_BEGIN
-- {
--   "manual_id": "do_upd_2026_04_28",
--   "module": "DynamicObjectives",
--   "title": "Update: 03/28 - 04/28",
--   "description": "The Dynamic Quest System Launch. A full quest system overhaul adds procedural objectives, dynamic rewards, and a new mission viewer. — This release focuses entirely on launching the new dynamic quest framework.",
--   "start_page_id": "cat_features",
--   "audiences": [
--     "DynamicObjectives"
--   ],
--   "sort_order": 1,
--   "release_version": "",
--   "popup_version": "",
--   "auto_open_on_update": false,
--   "is_whats_new": true,
--   "manual_type": "whats_new",
--   "show_in_library": false,
--   "support_url": "",
--   "banner_title": "",
--   "banner_text": "",
--   "banner_action_label": "",
--   "source_folder": "WhatsNew",
--   "chapters": [
--     {
--       "id": "release_notes",
--       "title": "Release Notes",
--       "description": "A full quest system overhaul adds procedural objectives, dynamic rewards, and a new mission viewer."
--     }
--   ],
--   "pages": [
--     {
--       "id": "cat_features",
--       "chapter_id": "release_notes",
--       "title": "Features",
--       "keywords": [],
--       "blocks": [
--         {
--           "type": "callout",
--           "tone": "info",
--           "title": "Features Highlights",
--           "text": "A full quest system overhaul adds procedural objectives, dynamic rewards, and a new mission viewer."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_27_dynamicobjectives",
--           "level": 2,
--           "text": "Quest System Overhaul and UI Enhancements"
--         },
--         {
--           "type": "paragraph",
--           "text": "- Quests now track multi-sample drops and area clearances with **improved HUD progress indicators**.\n- **Animated reward summaries** with custom sounds and item textures appear upon completing objectives.\n- Quest generation is blocked for nomadic and bandit factions to ensure better objective stability.\n- Performance is boosted by optimized UI refresh logic and smarter quest storage limits."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Quests now feature smarter tracking, richer rewards, and improved performance for a smoother experience."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_26_dynamicobjectives",
--           "level": 2,
--           "text": "Procedural Quest Rewards and Objectives"
--         },
--         {
--           "type": "paragraph",
--           "text": "* Added a **minimum money reward** setting to the sandbox for procedural quests.\n* Implemented return-to-giver objectives to make quest goals more intuitive.\n* Improved faction display names for better readability during quest interactions."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "New sandbox options and clearer quest goals improve procedural quest variety and tracking."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_25_dynamicobjectives",
--           "level": 2,
--           "text": "Dynamic Quests and Trader Escort Tools"
--         },
--         {
--           "type": "paragraph",
--           "text": "* Traders now automatically generate ambient quests while resting.\n* Added a debug tool to manually trigger trader escort missions.\n* Quest expiration rates are now fully configurable by players."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Traders now generate ambient quests and offer new escort opportunities."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_24_dynamicobjectives",
--           "level": 2,
--           "text": "Dynamic Quest System & Mission Viewer Overhaul"
--         },
--         {
--           "type": "paragraph",
--           "text": "* **New Mission Viewer UI** allows players to track active quests and view dynamic zombie target markers on the map.\n* Quest system now supports time limits, failure conditions, and a fully integrated reward distribution mechanic.\n* Added a quest registry with validation logic and default presets to ensure stable and varied mission generation."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Players can now track dynamic zombie targets and manage complex quests through a new mission interface."
--         }
--       ]
--     },
--     {
--       "id": "cat_misc",
--       "chapter_id": "release_notes",
--       "title": "Misc",
--       "keywords": [],
--       "blocks": [
--         {
--           "type": "callout",
--           "tone": "info",
--           "title": "Misc Highlights",
--           "text": "This release focuses entirely on launching the new dynamic quest framework."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_28_dynamicobjectives",
--           "level": 2,
--           "text": "Escort Quests, UI Overhaul & New Rewards"
--         },
--         {
--           "type": "paragraph",
--           "text": "- **Escort missions now track progress** using baseline distance and update reputation rewards dynamically.\n- New quest failure modal and medical utility helpers added to improve mission flow and support.\n- Quest contact locations resolve dynamically with home-anchoring logic for better world integration.\n- Improved quest item drops on corpses and global state refresh for smoother completion tracking."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Adds dynamic escort missions with progress tracking, new failure states, and improved quest item handling."
--         }
--       ]
--     }
--   ],
--   "raw_lua": null
-- }
-- DT_MANUAL_EDITOR_END
if DynamicTrading and DynamicTrading.RegisterManual then
    DynamicTrading.RegisterManual("do_upd_2026_04_28", {
        title = "Update: 03/28 - 04/28",
        description = "The Dynamic Quest System Launch. A full quest system overhaul adds procedural objectives, dynamic rewards, and a new mission viewer. — This release focuses entirely on launching the new dynamic quest framework.",
        startPageId = "cat_features",
        audiences = { "DynamicObjectives" },
        sortOrder = 1,
        releaseVersion = "",
        popupVersion = "",
        autoOpenOnUpdate = false,
        isWhatsNew = true,
        manualType = "whats_new",
        showInLibrary = false,
        supportUrl = "",
        bannerTitle = "",
        bannerText = "",
        bannerActionLabel = "",
        chapters = {
            {
                id = "release_notes",
                title = "Release Notes",
                description = "A full quest system overhaul adds procedural objectives, dynamic rewards, and a new mission viewer.",
            },
        },
        pages = {
            {
                id = "cat_features",
                chapterId = "release_notes",
                title = "Features",
                keywords = {  },
                blocks = {
                    { type = "callout", tone = "info", title = "Features Highlights", text = "A full quest system overhaul adds procedural objectives, dynamic rewards, and a new mission viewer." },
                    { type = "heading", id = "item_item_2026_04_27_dynamicobjectives", level = 2, text = "Quest System Overhaul and UI Enhancements" },
                    { type = "paragraph", text = "- Quests now track multi-sample drops and area clearances with **improved HUD progress indicators**.\n- **Animated reward summaries** with custom sounds and item textures appear upon completing objectives.\n- Quest generation is blocked for nomadic and bandit factions to ensure better objective stability.\n- Performance is boosted by optimized UI refresh logic and smarter quest storage limits." },
                    { type = "callout", tone = "success", title = "Impact", text = "Quests now feature smarter tracking, richer rewards, and improved performance for a smoother experience." },
                    { type = "heading", id = "item_item_2026_04_26_dynamicobjectives", level = 2, text = "Procedural Quest Rewards and Objectives" },
                    { type = "paragraph", text = "* Added a **minimum money reward** setting to the sandbox for procedural quests.\n* Implemented return-to-giver objectives to make quest goals more intuitive.\n* Improved faction display names for better readability during quest interactions." },
                    { type = "callout", tone = "success", title = "Impact", text = "New sandbox options and clearer quest goals improve procedural quest variety and tracking." },
                    { type = "heading", id = "item_item_2026_04_25_dynamicobjectives", level = 2, text = "Dynamic Quests and Trader Escort Tools" },
                    { type = "paragraph", text = "* Traders now automatically generate ambient quests while resting.\n* Added a debug tool to manually trigger trader escort missions.\n* Quest expiration rates are now fully configurable by players." },
                    { type = "callout", tone = "success", title = "Impact", text = "Traders now generate ambient quests and offer new escort opportunities." },
                    { type = "heading", id = "item_item_2026_04_24_dynamicobjectives", level = 2, text = "Dynamic Quest System & Mission Viewer Overhaul" },
                    { type = "paragraph", text = "* **New Mission Viewer UI** allows players to track active quests and view dynamic zombie target markers on the map.\n* Quest system now supports time limits, failure conditions, and a fully integrated reward distribution mechanic.\n* Added a quest registry with validation logic and default presets to ensure stable and varied mission generation." },
                    { type = "callout", tone = "success", title = "Impact", text = "Players can now track dynamic zombie targets and manage complex quests through a new mission interface." },
                },
            },
            {
                id = "cat_misc",
                chapterId = "release_notes",
                title = "Misc",
                keywords = {  },
                blocks = {
                    { type = "callout", tone = "info", title = "Misc Highlights", text = "This release focuses entirely on launching the new dynamic quest framework." },
                    { type = "heading", id = "item_item_2026_04_28_dynamicobjectives", level = 2, text = "Escort Quests, UI Overhaul & New Rewards" },
                    { type = "paragraph", text = "- **Escort missions now track progress** using baseline distance and update reputation rewards dynamically.\n- New quest failure modal and medical utility helpers added to improve mission flow and support.\n- Quest contact locations resolve dynamically with home-anchoring logic for better world integration.\n- Improved quest item drops on corpses and global state refresh for smoother completion tracking." },
                    { type = "callout", tone = "success", title = "Impact", text = "Adds dynamic escort missions with progress tracking, new failure states, and improved quest item handling." },
                },
            },
        },
    })
end
