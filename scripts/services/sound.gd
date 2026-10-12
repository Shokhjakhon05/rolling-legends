## Sound effects, synthesised at start-up: the game ships no audio files.
extends Node

const RATE := 22050
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _tracks := {}                 # world index -> AudioStreamWAV, filled by a worker thread
var _thread: Thread
var _music_world := -1

func _ready() -> void:
	_streams["crystal"] = _tone([[880, 0.05], [1320, 0.09]], 0.5, 9.0)
	_streams["hit"] = _noise(0.16, 0.7, 150.0)
	_streams["fall"] = _sweep(520, 110, 0.5, 0.5)
	_streams["launch"] = _sweep(300, 760, 0.18, 0.4)
	_streams["land"] = _noise(0.07, 0.4, 90.0)
	_streams["checkpoint"] = _tone([[660, 0.08], [880, 0.08], [1100, 0.16]], 0.5, 5.0)
	_streams["win"] = _tone([[523, 0.11], [659, 0.11], [784, 0.11], [1047, 0.3]], 0.55, 3.0)
	_streams["lose"] = _tone([[392, 0.16], [330, 0.16], [262, 0.3]], 0.5, 3.0)
	_streams["click"] = _tone([[740, 0.035]], 0.35, 14.0)
	_streams["boost"] = _sweep(400, 1200, 0.3, 0.4)
	_streams["crumble"] = _noise(0.12, 0.3, 240.0)
	_streams["star"] = _tone([[1047, 0.07], [1568, 0.14]], 0.5, 7.0)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -15.0
	add_child(_music)
	# Composing the three loops takes a moment: do it off the main thread.
	_thread = Thread.new()
	_thread.start(_compose_all)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

func _compose_all() -> void:
	for w in 3:
		var track := _compose(w)
		call_deferred("_track_ready", w, track)

func _track_ready(w: int, track: AudioStreamWAV) -> void:
	_tracks[w] = track
	if w == _music_world:
		set_music(w)

## Starts (or stops, per the setting) the loop of a world.
func set_music(world: int) -> void:
	_music_world = world
	if not Progress.music:
		_music.stop()
		return
	if _tracks.has(world) and _music.stream != _tracks[world]:
		_music.stream = _tracks[world]
		_music.play()
	elif _tracks.has(world) and not _music.playing:
		_music.play()

func refresh_music() -> void:
	set_music(_music_world)

## A calm loop: a soft two-note pad under a plucked pattern. One key and tempo per world.
func _compose(world: int) -> AudioStreamWAV:
	var rate := 16000
	var bpm: float = [96.0, 88.0, 112.0][world]
	var root: float = [220.0, 196.0, 174.61][world]
	var scale: Array = [[0, 4, 7, 9, 12, 16], [0, 3, 5, 7, 10, 12], [0, 3, 7, 10, 12, 15]][world]
	var pattern: Array = [[0, 2, 4, 2, 3, 2, 5, 2, 0, 2, 4, 2, 3, 1, 2, 1], [0, 3, 2, 3, 4, 3, 2, 1, 0, 3, 2, 3, 5, 4, 2, 1], [0, 2, 4, 5, 4, 2, 3, 2, 0, 2, 4, 5, 3, 2, 1, 2]][world]
	var chords: Array = [[0, -5, -3, -7], [0, -2, -4, -7], [0, -4, -2, -5]][world]
	var step := 60.0 / bpm / 2.0
	var steps := 64
	var total := int(steps * step * rate)
	var out := PackedFloat32Array()
	out.resize(total)
	for i in total:
		var t := float(i) / rate
		var k := int(t / step)
		var local := t - k * step
		var chord: int = chords[(k / 16) % 4]
		var base := root * pow(2.0, chord / 12.0)
		var pad := (sin(TAU * base * 0.5 * t) + 0.6 * sin(TAU * base * 0.75 * t)) * (0.5 + 0.2 * sin(TAU * 0.2 * t))
		var note: int = scale[pattern[k % 16]] + chord
		var f := root * 2.0 * pow(2.0, note / 12.0)
		var pluck := (sin(TAU * f * local) + 0.35 * sin(TAU * f * 2.0 * local)) * exp(-7.0 * local) * minf(1.0, local * 400.0)
		out[i] = pad * 0.16 + pluck * 0.3
	# Close the loop without a click.
	var fade := int(rate * 0.03)
	for i in fade:
		out[total - 1 - i] *= float(i) / fade
		out[i] *= float(i) / fade
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = total
	return w

func play(name: String, pitch: float = 1.0) -> void:
	if not Progress.sound or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()

func buzz(ms: int) -> void:
	if Progress.vibration:
		Input.vibrate_handheld(ms)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

## A run of notes [[frequency, seconds], ...] with a soft bell-like decay.
func _tone(notes: Array, volume: float, decay: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for n in notes:
		var count := int(n[1] * RATE)
		for i in count:
			var t := float(i) / RATE
			var env := exp(-decay * t) * minf(1.0, i / 60.0) * minf(1.0, (count - i) / 200.0)
			out.append((sin(TAU * n[0] * t) + 0.3 * sin(TAU * n[0] * 2.0 * t)) * env * volume)
	return _wav(out)

func _sweep(from: float, to: float, seconds: float, volume: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var count := int(seconds * RATE)
	var phase := 0.0
	for i in count:
		var u := float(i) / count
		phase += TAU * lerpf(from, to, u) / RATE
		out.append(sin(phase) * (1.0 - u) * minf(1.0, i / 60.0) * volume)
	return _wav(out)

## A thud: filtered noise that dies away quickly.
func _noise(seconds: float, volume: float, tone: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var count := int(seconds * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var low := 0.0
	for i in count:
		var u := float(i) / count
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.25
		out.append((low + 0.6 * sin(TAU * tone * i / RATE)) * (1.0 - u) * (1.0 - u) * volume)
	return _wav(out)
