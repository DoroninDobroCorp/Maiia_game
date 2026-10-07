class_name AudioService
extends Node

## Процедурный звуковой движок: органичные тёплые звуки без внешних зависимостей

var sfx_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var radio_player: AudioStreamPlayer

var samples: Dictionary = {}
var is_muted: bool = false
var master_vol: float = 0.8
var music_vol: float = 0.7
var sfx_vol: float = 0.8

func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "Master"
	add_child(sfx_player)
	
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Master"
	add_child(ambient_player)
	
	radio_player = AudioStreamPlayer.new()
	radio_player.bus = "Master"
	add_child(radio_player)
	
	_generate_all_samples()

func _exit_tree() -> void:
	# Explicitly release procedural streams before the scene tree shuts down.
	# Godot can otherwise keep the looping WAV playback alive until engine exit.
	for child in get_children():
		if child is AudioStreamPlayer:
			if child.playing:
				child.stop()
			child.stream = null
	samples.clear()
	sfx_player = null
	ambient_player = null
	radio_player = null
	# Give the audio thread one mix interval to release stopped WAV playbacks
	# before Godot tears down ObjectDB (CoreAudio uses a ~10 ms buffer here).
	OS.delay_msec(20)

func play_sfx(sound_name: String) -> void:
	if is_muted or not samples.has(sound_name):
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = "Master"
	player.stream = samples[sound_name]
	player.volume_db = linear_to_db(sfx_vol * master_vol)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## Short signature sounds of the four heroes: mood is "greet", "happy" or "think".
## Rendered lazily on first use, so they cost nothing at startup and nothing when muted.
func play_voice(hero: String, mood: String) -> void:
	if is_muted:
		return
	var key := "voice_%s_%s" % [hero, mood]
	if not samples.has(key):
		var made := _create_voice(hero, mood)
		if made == null:
			return
		samples[key] = made
	play_sfx(key)

func play_radio_broadcast() -> void:
	if is_muted or not samples.has("radio_tune"):
		return
	radio_player.stream = samples["radio_tune"]
	radio_player.volume_db = linear_to_db(sfx_vol * master_vol * 0.9)
	radio_player.play()

func stop_radio() -> void:
	if radio_player != null:
		radio_player.stop()

func start_ambient() -> void:
	if not samples.has("wind_ambient"):
		return
	ambient_player.stream = samples["wind_ambient"]
	ambient_player.volume_db = linear_to_db(music_vol * master_vol * 0.4)
	if not is_muted:
		ambient_player.play()

func stop_ambient() -> void:
	if ambient_player != null:
		ambient_player.stop()

func update_volumes(master: float, music: float, sfx: float, muted: bool) -> void:
	master_vol = clampf(master, 0.0, 1.0)
	music_vol = clampf(music, 0.0, 1.0)
	sfx_vol = clampf(sfx, 0.0, 1.0)
	is_muted = muted
	
	if is_muted:
		if ambient_player != null:
			ambient_player.stop()
		if radio_player != null:
			radio_player.stop()
	else:
		if ambient_player != null:
			ambient_player.volume_db = linear_to_db(music_vol * master_vol * 0.4)
			if not ambient_player.playing:
				ambient_player.play()

func _generate_all_samples() -> void:
	samples["click_dial"] = _create_click(0.04, 880.0, 45.0)
	samples["wood_thump"] = _create_thump(0.12, 140.0, 22.0)
	samples["paper_flip"] = _create_paper(0.08)
	var chord_notes: Array[float] = [523.25, 659.25, 783.99, 987.77, 1046.50]
	samples["chime_solve"] = _create_chord(chord_notes, 1.6)
	samples["radio_tune"] = _create_radio_jingle()
	samples["wind_ambient"] = _create_wind_loop(8.0)

func _create_click(duration: float, freq: float, decay: float) -> AudioStreamWAV:
	var sr: int = 22050
	var total: int = int(float(sr) * duration)
	var sample: AudioStreamWAV = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = sr
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	for i in range(total):
		var t: float = float(i) / float(sr)
		var val: float = sin(TAU * freq * t) * exp(-decay * t)
		var s16: int = int(clampf(val * 0.7 * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)
	sample.data = data
	return sample

func _create_thump(duration: float, base_freq: float, decay: float) -> AudioStreamWAV:
	var sr: int = 22050
	var total: int = int(float(sr) * duration)
	var sample: AudioStreamWAV = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = sr
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	for i in range(total):
		var t: float = float(i) / float(sr)
		var freq: float = base_freq * (1.0 - t * 2.0)
		var val: float = sin(TAU * maxf(freq, 40.0) * t) * exp(-decay * t)
		var s16: int = int(clampf(val * 0.8 * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)
	sample.data = data
	return sample

func _create_paper(duration: float) -> AudioStreamWAV:
	var sr: int = 22050
	var total: int = int(float(sr) * duration)
	var sample: AudioStreamWAV = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = sr
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	var seed_val: int = 12345
	for i in range(total):
		var t: float = float(i) / float(sr)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var noise: float = (float(seed_val) / 2147483648.0) * 2.0 - 1.0
		var env: float = sin(PI * (t / duration)) * exp(-12.0 * t)
		var s16: int = int(clampf(noise * env * 0.5 * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)
	sample.data = data
	return sample

func _create_chord(notes: Array[float], duration: float) -> AudioStreamWAV:
	var sr: int = 22050
	var total: int = int(float(sr) * duration)
	var sample: AudioStreamWAV = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = sr
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	for i in range(total):
		var t: float = float(i) / float(sr)
		var sum: float = 0.0
		for n_idx in range(notes.size()):
			var note_time: float = maxf(0.0, t - float(n_idx) * 0.07)
			var note_f: float = notes[n_idx]
			var env: float = exp(-3.2 * note_time) if note_time > 0.0 else 0.0
			sum += (sin(TAU * note_f * note_time) + 0.25 * sin(TAU * note_f * 2.0 * note_time)) * env
		var val: float = (sum / float(notes.size())) * 0.9
		var s16: int = int(clampf(val * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)
	sample.data = data
	return sample

func _create_radio_jingle() -> AudioStreamWAV:
	var sr: int = 22050
	var duration: float = 2.2
	var total: int = int(float(sr) * duration)
	var sample: AudioStreamWAV = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = sr
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	var melody_times: Array[float] = [0.0, 0.3, 0.6, 1.0]
	var melody_freqs: Array[float] = [440.0, 554.37, 659.25, 880.0]
	var melody_durs: Array[float] = [0.25, 0.25, 0.3, 0.7]
	var seed_val: int = 54321
	for i in range(total):
		var t: float = float(i) / float(sr)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var static_noise: float = ((float(seed_val) / 2147483648.0) * 2.0 - 1.0) * 0.06 * exp(-1.5 * t)
		var tone: float = 0.0
		for idx in range(melody_times.size()):
			var start: float = melody_times[idx]
			var dur: float = melody_durs[idx]
			var freq: float = melody_freqs[idx]
			if t >= start and t <= (start + dur):
				var nt: float = t - start
				var env: float = sin(PI * (nt / dur))
				tone += sin(TAU * freq * nt) * env * 0.4
		var val: float = tone + static_noise
		var s16: int = int(clampf(val * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)
	sample.data = data
	return sample

func _create_wind_loop(duration: float = 8.0) -> AudioStreamWAV:
	# Горный сосновый лес Патагонии (Эль-Больсон):
	# 1. Мягкий шелест сосен и крон в верхушках деревьев (без басового гула и без ритмичных волн прибоя);
	# 2. Нежные, далёкие щебетания лесных птиц (славка / чиж), сразу создающие ощущение живого леса.
	var sr: int = 22050
	var total: int = int(float(sr) * duration)
	var sample: AudioStreamWAV = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = sr
	sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sample.loop_begin = 0
	sample.loop_end = total
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)

	var seed_val: int = 42135
	var bp_state1: float = 0.0
	var bp_state2: float = 0.0

	# Параметры далёких птичьих трелей (время появления, базовая частота, модуляция, длительность)
	var bird_calls := [
		{"t0": 1.40, "f0": 3100.0, "f1": 3700.0, "dur": 0.09, "amp": 0.18},
		{"t0": 1.56, "f0": 3600.0, "f1": 4200.0, "dur": 0.11, "amp": 0.15},
		{"t0": 4.80, "f0": 2900.0, "f1": 3400.0, "dur": 0.10, "amp": 0.16},
		{"t0": 6.90, "f0": 3300.0, "f1": 3900.0, "dur": 0.08, "amp": 0.14}
	]

	for i in range(total):
		var t: float = float(i) / float(sr)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var white: float = (float(seed_val) / 2147483648.0) * 2.0 - 1.0

		# Полосовой фильтр для хвои и листьев (~2000-4500 Гц): лёгкий шелест, без басового гула
		bp_state1 = bp_state1 * 0.78 + white * 0.22
		bp_state2 = bp_state2 * 0.82 + (white - bp_state1) * 0.18
		var leaves_shimmer: float = bp_state2 * 0.22

		# Далёкие лесные птицы
		var birds_total: float = 0.0
		for b in bird_calls:
			var bt: float = t - float(b["t0"])
			var bdur: float = float(b["dur"])
			if bt >= 0.0 and bt <= bdur:
				var prog: float = bt / bdur
				var bfreq: float = lerpf(float(b["f0"]), float(b["f1"]), prog)
				var benv: float = sin(prog * PI)
				birds_total += (sin(TAU * bfreq * bt) + 0.2 * sin(TAU * bfreq * 2.0 * bt)) * benv * float(b["amp"])

		# Плавная, спокойная лесная атмосфера (без морских накатов волн)
		var val: float = leaves_shimmer + birds_total
		var s16: int = int(clampf(val * 0.45 * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)

	# Сглаживание начала и конца (микро-кроссфейд на 20 мс) для идеального бесшовного цикла без щелчков
	var fade_samples: int = int(sr * 0.02)
	for i in range(fade_samples):
		var alpha: float = float(i) / float(fade_samples)
		var s_start: int = data.decode_s16(i * 2)
		var s_end: int = data.decode_s16((total - fade_samples + i) * 2)
		var blended: int = int(lerpf(float(s_end), float(s_start), alpha))
		data.encode_s16(i * 2, blended)

	sample.data = data
	return sample


# --------------------------------------------------------------------------- hero voices
const VOICE_RATE := 22050

## Renders `duration` seconds by calling voice.call(t, noise) per sample; noise is -1..1.
func _render(duration: float, seed_value: int, voice: Callable) -> AudioStreamWAV:
	var total: int = int(float(VOICE_RATE) * duration)
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = VOICE_RATE
	var data := PackedByteArray()
	data.resize(total * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(total):
		var t := float(i) / float(VOICE_RATE)
		var val: float = voice.call(t, rng.randf_range(-1.0, 1.0))
		# Gentle fade on the last 15 ms avoids a click at the end of the sample.
		val *= clampf((duration - t) / 0.015, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(val * 0.6, -1.0, 1.0) * 32767.0))
	sample.data = data
	return sample

## A decaying sine that starts at `start`; the building block of chimes and dings.
func _ping(t: float, start: float, freq: float, decay: float, amp: float = 1.0) -> float:
	var nt := t - start
	if nt < 0.0:
		return 0.0
	return sin(TAU * freq * nt) * exp(-decay * nt) * minf(nt / 0.004, 1.0) * amp

## A short burst of noise: shutter clicks, gear teeth, stopwatch ticks.
func _burst(t: float, start: float, noise: float, decay: float, amp: float = 1.0) -> float:
	var nt := t - start
	if nt < 0.0:
		return 0.0
	return noise * exp(-decay * nt) * amp

## Rich "brass" tone: first six harmonics with a soft attack and release.
func _brass(t: float, start: float, length: float, freq: float, amp: float = 1.0) -> float:
	var nt := t - start
	if nt < 0.0 or nt > length:
		return 0.0
	var env := minf(nt / 0.03, 1.0) * clampf((length - nt) / 0.08, 0.0, 1.0)
	var sum := 0.0
	for h in range(1, 7):
		sum += sin(TAU * freq * float(h) * nt) / float(h)
	return sum * env * amp * 0.45

func _create_voice(hero: String, mood: String) -> AudioStreamWAV:
	match hero + ":" + mood:
		# Nora: a voice that surfaces from radio static.
		"nora:greet":
			return _render(1.2, 11, func(t: float, n: float) -> float:
				var crackle := n * 0.22 * exp(-2.2 * t) * (1.0 if absf(n) > 0.35 else 0.25)
				var sweep := sin(TAU * (500.0 + 900.0 * sin(PI * minf(t / 0.5, 1.0))) * t) * 0.16 * (1.0 if t < 0.5 else 0.0) * clampf((0.5 - t) / 0.12, 0.0, 1.0)
				return crackle + sweep + _ping(t, 0.55, 392.0, 4.5, 0.4) + _ping(t, 0.78, 587.33, 4.0, 0.34))
		"nora:happy":
			return _render(1.3, 12, func(t: float, n: float) -> float:
				var warm := _ping(t, 0.0, 440.0, 4.0, 0.34) + _ping(t, 0.17, 554.37, 4.0, 0.34) + _ping(t, 0.34, 659.25, 3.4, 0.38) + _ping(t, 0.34, 329.63, 3.0, 0.2)
				return warm + n * 0.04 * exp(-3.0 * t))
		"nora:think":
			return _render(1.0, 13, func(t: float, n: float) -> float:
				var gate := 1.0 if absf(n) > 0.55 else 0.15
				var wobble := sin(TAU * (330.0 - 120.0 * t + 14.0 * sin(TAU * 6.0 * t)) * t) * 0.22 * exp(-2.5 * t)
				return n * 0.2 * gate * exp(-1.3 * t) + wobble)
		# Teo: springs, clanks and sparks.
		"teo:greet":
			return _render(0.9, 21, func(t: float, n: float) -> float:
				var f := 260.0 * (1.0 + 0.55 * sin(TAU * 13.0 * t) * exp(-4.0 * t)) * (1.0 - 0.3 * t)
				var boing := (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-4.5 * t) * 0.5
				var clank := (_ping(t, 0.38, 830.0, 16.0) + _ping(t, 0.38, 1370.0, 20.0, 0.7) + _ping(t, 0.38, 2210.0, 26.0, 0.5)) * 0.35
				return boing + clank + _burst(t, 0.38, n, 90.0, 0.25))
		"teo:happy":
			return _render(1.2, 22, func(t: float, n: float) -> float:
				var run := 0.0
				var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
				for k in range(notes.size()):
					run += (_ping(t, 0.07 * float(k), notes[k], 7.0) + 0.3 * _ping(t, 0.07 * float(k), notes[k] * 3.0, 9.0)) * 0.4
				var gears := 0.0
				for k in range(5):
					gears += _burst(t, 0.5 + 0.06 * float(k), n, 140.0, 0.35)
				return run + gears + _ping(t, 0.82, 2093.0, 5.0, 0.3) + _ping(t, 0.88, 2637.0, 6.0, 0.2))
		"teo:think":
			return _render(1.0, 23, func(t: float, n: float) -> float:
				var ticks := 0.0
				for k in range(5):
					var s := 0.1 * float(k)
					ticks += _burst(t, s, n, 220.0, 0.4) + _ping(t, s, 1800.0, 160.0, 0.3)
				var hmm := 0.0
				if t > 0.55:
					var nt := t - 0.55
					hmm = sin(TAU * (230.0 - 70.0 * nt + 8.0 * sin(TAU * 7.0 * nt)) * nt) * exp(-3.0 * nt) * 0.4
				return ticks + hmm)
		# Clara: a camera shutter, a soft focus motor and bright chimes.
		"clara:greet":
			return _render(0.45, 31, func(t: float, n: float) -> float:
				return _burst(t, 0.0, n, 260.0, 0.6) + _ping(t, 0.0, 150.0, 70.0, 0.7) + _burst(t, 0.09, n, 300.0, 0.4) + _ping(t, 0.09, 120.0, 80.0, 0.5))
		"clara:happy":
			return _render(1.0, 32, func(t: float, n: float) -> float:
				return _burst(t, 0.0, n, 260.0, 0.5) + _ping(t, 0.0, 150.0, 70.0, 0.6) + _ping(t, 0.18, 987.77, 5.0, 0.42) + _ping(t, 0.3, 1318.5, 4.5, 0.4) + _ping(t, 0.3, 659.25, 4.0, 0.2))
		"clara:think":
			return _render(0.75, 33, func(t: float, n: float) -> float:
				var whirr := 0.0
				if t < 0.36:
					var f := 900.0 + 600.0 * sin(PI * t / 0.36)
					whirr = (1.0 if sin(TAU * f * t) > 0.0 else -1.0) * 0.1 * sin(PI * t / 0.36)
				return whirr + _burst(t, 0.46, n, 260.0, 0.5) + _ping(t, 0.46, 150.0, 70.0, 0.6))
		# Bruno: whistles, stopwatch ticks and a brass fanfare.
		"bruno:greet":
			return _render(0.95, 41, func(t: float, n: float) -> float:
				var blast_a := 0.0
				if t < 0.36:
					blast_a = sin(TAU * (2600.0 + 380.0 * sin(TAU * 18.0 * t)) * t) * 0.34 * minf(t / 0.02, 1.0) * clampf((0.36 - t) / 0.05, 0.0, 1.0)
				var blast_b := 0.0
				if t > 0.46 and t < 0.78:
					var nt := t - 0.46
					blast_b = sin(TAU * (2950.0 + 320.0 * sin(TAU * 20.0 * nt)) * nt) * 0.34 * minf(nt / 0.02, 1.0) * clampf((0.32 - nt) / 0.05, 0.0, 1.0)
				return blast_a + blast_b + n * 0.03 * (1.0 if (blast_a != 0.0 or blast_b != 0.0) else 0.0))
		"bruno:happy":
			return _render(1.5, 42, func(t: float, n: float) -> float:
				var fanfare := _brass(t, 0.0, 0.2, 261.63) + _brass(t, 0.16, 0.2, 329.63) + _brass(t, 0.32, 0.2, 392.0) + _brass(t, 0.5, 0.75, 523.25) + _brass(t, 0.5, 0.75, 392.0, 0.6)
				var cheer := 0.0
				if t > 0.8:
					cheer = n * 0.1 * sin(PI * clampf((t - 0.8) / 0.7, 0.0, 1.0))
				return fanfare * 0.7 + cheer)
		"bruno:think":
			return _render(0.95, 43, func(t: float, n: float) -> float:
				var ticks := 0.0
				for k in range(6):
					var s := 0.12 * float(k)
					ticks += _ping(t, s, 1200.0 if k % 2 == 0 else 900.0, 120.0, 0.5) + _burst(t, s, n, 300.0, 0.18)
				var blip := 0.0
				if t > 0.8 and t < 0.93:
					blip = sin(TAU * 2800.0 * t) * 0.28
				return ticks + blip)
	return null
