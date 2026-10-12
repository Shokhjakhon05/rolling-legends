## Sound effects, synthesised at start-up: the game ships no audio files.
extends Node

const RATE := 22050
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

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
