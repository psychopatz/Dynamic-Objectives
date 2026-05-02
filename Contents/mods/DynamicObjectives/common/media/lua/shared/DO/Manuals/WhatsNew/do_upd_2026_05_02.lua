-- DT_MANUAL_EDITOR_BEGIN
-- {
--   "manual_id": "do_upd_2026_05_02",
--   "module": "DynamicObjectives",
--   "title": "Update: 03/29 - 05/02",
--   "description": "The Dynamic Quest System Launch. Added a full quest system with procedural rewards, faction displays, escort tools, and a mission viewer. — No miscellaneous changes were listed outside the core feature rollout.",
--   "start_page_id": "cat_features",
--   "audiences": [
--     "DynamicObjectives"
--   ],
--   "sort_order": 2,
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
--       "description": "Added a full quest system with procedural rewards, faction displays, escort tools, and a mission viewer."
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
--           "text": "Added a full quest system with procedural rewards, faction displays, escort tools, and a mission viewer."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_27_dynamicobjectives",
--           "level": 2,
--           "text": "Quest System Overhaul and UI Enhancements"
--         },
--         {
--           "type": "paragraph",
--           "text": "* Quest generation is now restricted for nomadic, independent, and bandit factions.\n* **Animated reward summaries** with item textures and custom sounds now appear on completion.\n* Objective logic supports multi-sample drops, area clearing, and improved HUD tracking.\n* Quest storage limits are enforced and DT NPCs are excluded from kill tracking."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Quests now feature dynamic rewards, smarter objectives, and a polished completion interface."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_26_dynamicobjectives",
--           "level": 2,
--           "text": "Procedural Quest Rewards & Faction Display Updates"
--         },
--         {
--           "type": "paragraph",
--           "text": "- Added a sandbox option to set **minimum money rewards** for procedural quests.\n- Quests now correctly return items to the giver upon completion.\n- Faction display names are now resolved more accurately in quest logs."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Adds money reward options and fixes faction names in procedural quests."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_25_dynamicobjectives",
--           "level": 2,
--           "text": "Dynamic Trader Quests and Escort Tools"
--         },
--         {
--           "type": "paragraph",
--           "text": "- Traders now **automatically generate ambient quests** when entering resting states to keep gameplay fresh.\n- Added a debug tool for testing trader escort missions alongside new quest caching systems.\n- Implemented an objective hook system to support custom interactions and dynamic quest lifecycle events."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Traders now generate unique ambient quests while resting, adding new dynamic gameplay loops."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_24_dynamicobjectives",
--           "level": 2,
--           "text": "Dynamic Quest System and Mission Viewer"
--         },
--         {
--           "type": "paragraph",
--           "text": "- New **mission viewer UI** lets you track active quests and dynamic zombie targets in real time.\n- Implemented quest registry, validation, and default presets to support complex mission logic.\n- Quests now feature reward systems, time limits, and automatic failure handling mechanics."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Adds a full quest framework with mission tracking, rewards, and dynamic objectives."
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
--           "text": "No miscellaneous changes were listed outside the core feature rollout."
--         },
--         {
--           "type": "heading",
--           "id": "item_item_2026_04_28_dynamicobjectives",
--           "level": 2,
--           "text": "Dynamic Objectives Progress & Quest Overhaul"
--         },
--         {
--           "type": "paragraph",
--           "text": "* **Escort missions now track progress** using baseline distance and update reputation rewards dynamically.\n* Added a new quest failure modal and improved UI logic with centralized event queue systems.\n* Quest contacts now resolve to home-anchored locations and corpses drop quest items upon death.\n* Integrated DynamicTrading icons for better texture validation within the completion modal."
--         },
--         {
--           "type": "callout",
--           "tone": "success",
--           "title": "Impact",
--           "text": "Enhances mission tracking with new progress visuals, failure states, and item drop mechanics."
--         }
--       ]
--     }
--   ],
--   "raw_lua": null
-- }
-- DT_MANUAL_EDITOR_END
if DynamicTrading and DynamicTrading.RegisterManual then
    DynamicTrading.RegisterManual("do_upd_2026_05_02", {
        title = "Update: 03/29 - 05/02",
        description = "The Dynamic Quest System Launch. Added a full quest system with procedural rewards, faction displays, escort tools, and a mission viewer. — No miscellaneous changes were listed outside the core feature rollout.",
        startPageId = "cat_features",
        audiences = { "DynamicObjectives" },
        sortOrder = 2,
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
                description = "Added a full quest system with procedural rewards, faction displays, escort tools, and a mission viewer.",
            },
        },
        pages = {
            {
                id = "cat_features",
                chapterId = "release_notes",
                title = "Features",
                keywords = {  },
                blocks = {
                    { type = "callout", tone = "info", title = "Features Highlights", text = "Added a full quest system with procedural rewards, faction displays, escort tools, and a mission viewer." },
                    { type = "heading", id = "item_item_2026_04_27_dynamicobjectives", level = 2, text = "Quest System Overhaul and UI Enhancements" },
                    { type = "paragraph", text = "* Quest generation is now restricted for nomadic, independent, and bandit factions.\n* **Animated reward summaries** with item textures and custom sounds now appear on completion.\n* Objective logic supports multi-sample drops, area clearing, and improved HUD tracking.\n* Quest storage limits are enforced and DT NPCs are excluded from kill tracking." },
                    { type = "callout", tone = "success", title = "Impact", text = "Quests now feature dynamic rewards, smarter objectives, and a polished completion interface." },
                    { type = "heading", id = "item_item_2026_04_26_dynamicobjectives", level = 2, text = "Procedural Quest Rewards & Faction Display Updates" },
                    { type = "paragraph", text = "- Added a sandbox option to set **minimum money rewards** for procedural quests.\n- Quests now correctly return items to the giver upon completion.\n- Faction display names are now resolved more accurately in quest logs." },
                    { type = "callout", tone = "success", title = "Impact", text = "Adds money reward options and fixes faction names in procedural quests." },
                    { type = "heading", id = "item_item_2026_04_25_dynamicobjectives", level = 2, text = "Dynamic Trader Quests and Escort Tools" },
                    { type = "paragraph", text = "- Traders now **automatically generate ambient quests** when entering resting states to keep gameplay fresh.\n- Added a debug tool for testing trader escort missions alongside new quest caching systems.\n- Implemented an objective hook system to support custom interactions and dynamic quest lifecycle events." },
                    { type = "callout", tone = "success", title = "Impact", text = "Traders now generate unique ambient quests while resting, adding new dynamic gameplay loops." },
                    { type = "heading", id = "item_item_2026_04_24_dynamicobjectives", level = 2, text = "Dynamic Quest System and Mission Viewer" },
                    { type = "paragraph", text = "- New **mission viewer UI** lets you track active quests and dynamic zombie targets in real time.\n- Implemented quest registry, validation, and default presets to support complex mission logic.\n- Quests now feature reward systems, time limits, and automatic failure handling mechanics." },
                    { type = "callout", tone = "success", title = "Impact", text = "Adds a full quest framework with mission tracking, rewards, and dynamic objectives." },
                },
            },
            {
                id = "cat_misc",
                chapterId = "release_notes",
                title = "Misc",
                keywords = {  },
                blocks = {
                    { type = "callout", tone = "info", title = "Misc Highlights", text = "No miscellaneous changes were listed outside the core feature rollout." },
                    { type = "heading", id = "item_item_2026_04_28_dynamicobjectives", level = 2, text = "Dynamic Objectives Progress & Quest Overhaul" },
                    { type = "paragraph", text = "* **Escort missions now track progress** using baseline distance and update reputation rewards dynamically.\n* Added a new quest failure modal and improved UI logic with centralized event queue systems.\n* Quest contacts now resolve to home-anchored locations and corpses drop quest items upon death.\n* Integrated DynamicTrading icons for better texture validation within the completion modal." },
                    { type = "callout", tone = "success", title = "Impact", text = "Enhances mission tracking with new progress visuals, failure states, and item drop mechanics." },
                },
            },
        },
    })
end
