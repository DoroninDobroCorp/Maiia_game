extends SceneTree

## Child-facing mission copy must stay aligned with the authored quests it explains.
## Pure data checks: no AppRoot, no save, no media.
const Content = preload("res://scripts/services/adventure_content.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
	print("GUIDE %d %s" % [checks, label])

func run() -> void:
	var stage_ids: Dictionary = {}
	for qid in Guide.IDS:
		var quest := Content.get_quest(qid)
		check(not quest.is_empty(), "%s exists in the shipped content" % qid)
		var mission := Guide.mission(qid)
		for key in ["speaker", "role", "object", "hook", "goal", "rhythm", "payoff", "needs", "remains", "done_title", "done_text"]:
			check(not str(mission.get(key, "")).strip_edges().is_empty(), "%s has plain-language %s" % [qid, key])
		check(str(mission.get("hook", "")).length() < 520, "%s hook stays short enough to read before starting" % qid)
		var authored_ids: Dictionary = {}
		for stage in quest.adventure.stages:
			var sid := str(stage.stage_id)
			authored_ids[sid] = stage
			stage_ids[sid] = qid
			var step := Guide.step(sid)
			check(not step.is_empty(), "%s step %s is explained" % [qid, sid])
			for key in ["title", "task", "say", "done"]:
				check(not str(step.get(key, "")).strip_edges().is_empty(), "%s has %s" % [sid, key])
			check(not step.get("where", []).is_empty() and not Guide.where_text(step).is_empty(), "%s says where the step happens" % sid)
			var override: Array = Guide.CRITERIA.get(sid, [])
			check(override.size() == stage.get("criteria", []).size(), "%s child-facing checklist matches the authored checklist one to one" % sid)
		var position := Guide.position(quest.adventure.stages, str(quest.adventure.stages[2].stage_id))
		check(position == Vector2i(3, quest.adventure.stages.size()), "%s reports step 3 of its path" % qid)
		for inter_id in Guide.INTERACTIONS:
			if not quest.adventure.interactions.has(inter_id):
				continue
			var inter: Dictionary = quest.adventure.interactions[inter_id]
			var data: Dictionary = Guide.INTERACTIONS[inter_id]
			check(not Guide.prompt(inter_id, "").is_empty() or data.has("fields") or data.has("how"), "%s override is not empty" % inter_id)
			var authored_fields: Dictionary = {}
			for field in inter.config.get("fields", []):
				authored_fields[str(field.id)] = true
			for field_id in data.get("fields", {}):
				check(authored_fields.has(field_id), "%s relabels only fields that exist (%s)" % [inter_id, field_id])
			if data.has("criteria"):
				check(data.criteria.size() == inter.config.get("criteria", []).size(), "%s checklist override keeps the authored number of checks" % inter_id)
			if inter.type == "real_world_step" and quest_has_how(qid):
				check(data.has("how") or qid == "FG01", "%s real-world step tells the child what to do" % inter_id)
	for inter_id in Guide.INTERACTIONS:
		var found := false
		for qid in Guide.IDS:
			found = found or Content.get_quest(qid).adventure.interactions.has(inter_id)
		check(found, "%s override points at a real interaction" % inter_id)
	for sid in Guide.STEPS:
		check(stage_ids.has(sid), "%s step text points at a real stage" % sid)
	var authored := ["a", "b", "c"]
	check(Guide.criteria("game_move", "", authored) == authored, "mismatched wording never replaces authored checks")
	check(Guide.prompt("unknown_interaction", "authored text") == "authored text", "unknown interactions keep authored prompts")
	check(Guide.field_label("unknown_interaction", "x", "authored") == "authored", "unknown fields keep authored labels")
	check(Guide.mission("FG99").is_empty() and not Guide.is_current("FG99"), "family-made adventures are not touched")
	print("MISSION GUIDE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func quest_has_how(qid: String) -> bool:
	return qid != "FG01"
