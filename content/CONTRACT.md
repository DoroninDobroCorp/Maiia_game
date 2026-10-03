# SUR adventure content contract

`AdventureContent.quests()`, `get_quest(id)`, and `lexicon()` return deep-independent definitions. Built-in quests are FG01, FG11, FG08, schema 2, revision 2. Parent integration must select the next free revision if a profile already owns a different revision 2. No content file writes a save or publishes itself.

All dependency content is embedded in `quest.adventure`: `stages`, `interactions`, `dialogues`, `work_recipes`, `grant_definitions`, and (FG01) `lexicon`, `envelopes`, `channels`, `final_check`. No runtime lookup of mutable shared text is required by a frozen quest instance.

Stages have `stage_id`, `title`, `summary`, `criteria`, `prerequisite_stage_ids`, `completion_policy`, `budget_share`, `grant_ids`, `atlas_unlock_ids`, `work_recipe_id`, `interaction_ids`, `next_hint`. IDs and budgets exactly follow the mission spec. Water river/fall depend on plan independently. Real visits and all functional game stages require joint review.

Every interaction has `interaction_id`, `type`, `title`, `prompt`, `hints` (three strings), `success_text`, and `config`:

| Type | Config |
| --- | --- |
| match_cards | `cards:[{id,text}]`, `targets:[{id,text}]`, `accepted_pairs:{card_id:target_id}`, `pair_feedback:{card_id:text}` |
| order_fragments | `fragments:[{id,text}]`, `accepted_orders:[[id,...]]` |
| assemble_selection | `items:[{id,text}]`, `required_ids`, `min_selected`, `max_selected`, `ordered:false`; empty required IDs = free bounded choice |
| scripted_dialogue | `start_node_id`, `nodes:[{node_id,speaker,text,choices:[{id,text,next_node_id,correct,feedback}]}]`; terminal nodes have `terminal:true`, no choices |
| inspect_reveal | `details:[{id,title,text}]`, `required_detail_ids` |
| real_world_step | `criteria`, `materials`, `fields:[{id,label,required}]`, optional `starter_project_id`; UI submission does not imply approval |
| compare_observations | `source_stage_ids`, `categories:[{id,text}]`, `min_observations:2`, `fields` |
| exhibit_composition | `choices:[{id,text}]`, `min_selected`, `max_selected`, `fields`, optional `source_stage_ids` |

Each Spanish envelope has `envelope_id`, `number`, `channel_id`, `title`, `story`, five `lexeme_ids`, `review_lexeme_ids`, `interaction_ids`, `world_reaction`, `real_world_variants`. A target lexeme occurs in exactly one introduction envelope; recurrence references its same ID. Cards include base form, translation, accepted variants, example and translation, topics, initial status. Inflections never add a new lexeme. Accent marks remain significant. Words used as grammatical scaffolding are translated in scene prompts and do not enter the count.

Each lexeme also carries `channel_id`. `es_callsign` and `es_20_cover` have `config.lexeme_credit:false`: cosmetic selection does not assert language use. Mixed check config includes the ordered `lexeme_ids` corresponding to `cards`; attempts record actual `pairs` and `assisted_ids`, and the core derives the unassisted count. Final evidence must refer to that recorded attempt.

Builtin schema2 goal order and editorial priority are FG01=1, FG11=2, FG08=3. The original schema1 definitions are untouched. `choice_effects` maps named choices to declared presentation grants; `choice_instructions` describes how to transfer game theme/layout into the separate working project. Water comparison includes question-specific `question_hints`.

Launch data never enters quest JSON. A separately persisted, local `LaunchService` registry stores checksums and managed copies. Works link by `launch_entry_id` only. Launching the supplied demonstration grants no stage completion or authorship.

`LaunchService.new(root_directory="user://launch_registry")` exposes `prepare_starter_project(destination="")`, `working_project_path()`, `register_project(directory, version_label, actor_id="parent_local", profile_id="player_01")`, `register_app(directory, version_label, actor_id="parent_local", profile_id="player_01")`, `list_entries(profile_id)`, `inspect_entry(id, profile_id)`, `launch(id, profile_id)`, and `process_status(pid, profile_id)`. Return values use `{ok,reason,message}` plus operation-specific fields. Registration is a local adult UI convention, not authentication.

The default working copy is `user://launch_registry/working/station_light`. Versions are copied to `user://launch_registry/versions/<id>/project` or `Game.app`, alongside `source.zip`. The work's `source_archive_file` is an internal relative name. `source_archive_kind` distinguishes `project_source` from `application_bundle`; registering an exported binary does not manufacture its source code. Register the working source project as well to retain source material. The separate `registry.json` is excluded from portable backup, requiring registration after transfer.

Preparing the shipped starter reads `assets/learning_starter/manifest.json` and a fixed version ZIP through Godot's virtual filesystem, including PCK builds. It verifies the archive SHA-256, an exact seven-file allowlist and individual source hashes, then writes a new working directory without overwriting existing work. This extractor accepts only the builtin starter versions; user archives remain opaque. After repackaging learner source, run `python3 content/tools/sync_learning_starter.py` to promote the verified ZIPs outside the nested Godot project. Export includes `*.json,*.zip` and can exclude `learning_projects/*`.

The tested project adapter uses `OS.create_process` on the checksum-verified Godot executable with arguments built in code (direct child PID, avoiding macOS LaunchServices exit-status ambiguity). It requires an editor-capable Godot executable; changing that executable invalidates its previous registration. The tested macOS app adapter reads `CFBundleExecutable` from a Godot-style XML Info.plist and starts that verified executable inside the copied bundle with `OS.create_process`, with no shell or content-supplied arguments. Binary plists and non-macOS exported application bundles are not supported by this adapter. [Godot OS API reference](https://docs.godotengine.org/en/stable/classes/class_os.html).

To regenerate the committed JSON resources, run `python3 content/tools/build_first_chapter.py`. The generator is deterministic and never touches saves; the full dependency trees are written directly into each quest JSON. Tests: `godot --headless --path . --script tests/test_adventure_content.gd` checks definitions and actual launcher behavior; `tests/test_adventure_journeys.gd` runs all three complete service journeys and the imported AR02 package using isolated storage. Independent learner verification is described in `learning_projects/station_light/README.md`.
