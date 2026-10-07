extends SceneTree

## Each hero has three signature sounds. They are rendered in code, so check that every
## one exists, is audible, does not clip, ends cleanly, and that mute keeps them silent.
const AudioScript = preload("res://scripts/services/audio_service.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
	print("VOICES %d %s" % [checks, label])

func peak_and_tail(sample: AudioStreamWAV) -> Vector2:
	var peak := 0.0
	var tail := 0.0
	var count := sample.data.size() / 2
	for i in range(count):
		var v := absf(float(sample.data.decode_s16(i * 2)) / 32768.0)
		peak = maxf(peak, v)
		if i >= count - 20:
			tail = maxf(tail, v)
	return Vector2(peak, tail)

func run() -> void:
	var audio := AudioScript.new()
	root.add_child(audio)
	await process_frame
	for hero in ["nora", "teo", "clara", "bruno"]:
		for mood in ["greet", "happy", "think"]:
			var label := "%s/%s" % [hero, mood]
			var sample: AudioStreamWAV = audio._create_voice(hero, mood)
			check(sample != null, label + " exists")
			if sample == null:
				continue
			var seconds := float(sample.data.size() / 2) / float(sample.mix_rate)
			check(seconds >= 0.4 and seconds <= 1.6, label + " is short enough (%.2fs)" % seconds)
			var levels := peak_and_tail(sample)
			check(levels.x > 0.12, label + " is audible")
			check(levels.x < 0.97, label + " does not clip")
			check(levels.y < 0.02, label + " ends without a click")
	check(audio._create_voice("nobody", "greet") == null and audio._create_voice("nora", "dance") == null, "unknown hero or mood makes no sound")
	audio.is_muted = true
	audio.play_voice("bruno", "happy")
	check(not audio.samples.has("voice_bruno_happy"), "muted game renders and plays nothing")
	audio.is_muted = false
	audio.play_voice("bruno", "happy")
	check(audio.samples.has("voice_bruno_happy"), "a played cue is cached for next time")
	audio.play_voice("nobody", "greet")
	check(not audio.samples.has("voice_nobody_greet"), "unknown hero is ignored")
	audio.queue_free()
	await process_frame
	print("HERO VOICES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
