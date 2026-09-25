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
	samples["wind_ambient"] = _create_wind_loop(3.0)

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

func _create_wind_loop(duration: float) -> AudioStreamWAV:
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
	var seed_val: int = 98765
	var last: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(sr)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var white: float = (float(seed_val) / 2147483648.0) * 2.0 - 1.0
		last = last * 0.94 + white * 0.06
		var swell: float = 0.6 + 0.4 * sin(TAU * 0.33 * t)
		var val: float = last * swell * 0.25
		var s16: int = int(clampf(val * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, s16)
	sample.data = data
	return sample
