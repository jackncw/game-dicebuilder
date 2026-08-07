extends Node
## Autoload "Sfx": procedurally-synthesized sound effects (no asset files).
## All sounds are generated once at startup into AudioStreamWAV objects.

const SAMPLE_RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8
var _next_player := 0


func _ready() -> void:
	_streams["roll"] = _gen_noise_burst(0.12, 0.5)
	_streams["hit"] = _gen_thud(0.15)
	_streams["block"] = _gen_click(0.08)
	_streams["heal"] = _gen_chime([523.25, 659.25, 783.99], 0.10)
	_streams["button"] = _gen_blip(880.0, 0.05)
	_streams["win"] = _gen_chime([523.25, 659.25, 783.99, 1046.5], 0.16)
	_streams["lose"] = _gen_descend(0.5)
	_streams["potion"] = _gen_chime([392.0, 523.25], 0.09)
	_streams["stun"] = _gen_blip(220.0, 0.15)
	_streams["die"] = _gen_knock(0.07)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func play(name: String, volume_scale := 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _streams[name]
	p.volume_db = linear_to_db(clampf(Game.settings.volume * volume_scale, 0.0, 1.0))
	p.play()


# ------------------------------------------------------------ generators

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	return wav


func _gen_noise_burst(dur: float, cutoff: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var prev := 0.0
	for i in n:
		var env := 1.0 - float(i) / n
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, cutoff)
		out[i] = prev * env * 0.5
	return _make_wav(out)


func _gen_thud(dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 30.0)
		var freq := 120.0 - t * 200.0
		out[i] = sin(TAU * freq * t) * env * 0.9
	return _make_wav(out)


func _gen_click(dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 80.0)
		out[i] = sin(TAU * 1400.0 * t) * env * 0.5
	return _make_wav(out)


## A die hitting the table: a woody knock — short noise transient over a fast
## low sine. Played once per die as it lands, so it has to stay small enough
## that eight of them in half a second read as a handful of dice, not a drum.
func _gen_knock(dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 70.0)
		var body := sin(TAU * (260.0 - t * 380.0) * t)
		var tick := rng.randf_range(-1.0, 1.0) * exp(-t * 320.0)
		out[i] = (body * 0.6 + tick * 0.5) * env * 0.7
	return _make_wav(out)


func _gen_blip(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := minf(t * 200.0, 1.0) * (1.0 - float(i) / n)
		out[i] = sin(TAU * freq * t) * env * 0.4
	return _make_wav(out)


func _gen_chime(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * note_dur * freqs.size())
	var out := PackedFloat32Array()
	out.resize(n)
	var per := int(SAMPLE_RATE * note_dur)
	for i in n:
		var note := mini(i / per, freqs.size() - 1)
		var t := float(i % per) / SAMPLE_RATE
		var env := exp(-t * 8.0)
		out[i] = sin(TAU * float(freqs[note]) * t) * env * 0.4
	return _make_wav(out)


func _gen_descend(dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var freq := 440.0 * pow(0.5, t * 2.0)
		var env := 1.0 - float(i) / n
		out[i] = sin(TAU * freq * t) * env * 0.5
	return _make_wav(out)
