extends Node
## Autoload "Music": BGM with crossfade and duck. Two decks on the Music bus;
## play() fades between them, so a chapter change or a boss entrance is never
## a hard cut. Tracks live in assets/audio/bgm/ (see tools/music_build.py).

const DIR := "res://assets/audio/bgm/"
const SILENT_DB := -44.0

var current := ""      # track name the game asked for last
var _decks: Array[AudioStreamPlayer] = []
var _live := 0         # index of the deck that should be audible
var _fades: Array = [null, null]
var _duck_tween: Tween = null
var _duck_db := 0.0


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_decks.append(p)


## Crossfade to a track. Same-name calls are free, so every screen can state
## the music it wants without tracking who played what before it.
##
## On the web the five loop tracks are NOT in the pck (they are what kept the
## first load under 18MB): they live beside the page as bgm/*.ogg and are
## fetched on first request. Until the bytes arrive this fades the old track
## out and remembers the ask; the fetch callback starts the music if the ask
## still stands. A run that outraces its soundtrack simply starts quiet.
var _cache := {}      # track name → AudioStream, res:// or fetched
var _fetching := {}   # track name → true while an HTTPRequest is in flight


func play(track: String, fade := 0.8) -> void:
	if current == track:
		return
	current = track
	var stream := _get_stream(track)
	if stream == null:
		for i in 2:
			if _decks[i].playing:
				_fade_deck(i, _decks[i], SILENT_DB, fade)
		return
	_start(stream, fade)


func _get_stream(track: String) -> AudioStream:
	if _cache.has(track):
		return _cache[track]
	var path := DIR + track + ".ogg"
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_cache[track] = stream
		return stream
	if OS.has_feature("web"):
		_fetch(track)
	return null


func _fetch(track: String) -> void:
	if _fetching.get(track, false):
		return
	_fetching[track] = true
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int,
			_headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		_fetching.erase(track)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
			return
		var stream := AudioStreamOggVorbis.load_from_buffer(body)
		if stream == null:
			return
		stream.loop = true
		_cache[track] = stream
		if current == track:
			_start(stream, 1.2))
	if req.request("bgm/%s.ogg" % track) != OK:
		req.queue_free()
		_fetching.erase(track)


func _start(stream: AudioStream, fade: float) -> void:
	_live = 1 - _live
	var incoming := _decks[_live]
	var outgoing := _decks[1 - _live]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_publish_state()
	_fade_deck(_live, incoming, _duck_db, fade)
	if outgoing.playing:
		var tw := _fade_deck(1 - _live, outgoing, SILENT_DB, fade)
		tw.finished.connect(func() -> void:
			if _live != _decks.find(outgoing):
				outgoing.stop())


func stop(fade := 0.8) -> void:
	current = ""
	for i in 2:
		var d := _decks[i]
		if d.playing:
			var tw := _fade_deck(i, d, SILENT_DB, fade)
			tw.finished.connect(func() -> void:
				if current == "":
					d.stop())


## Dip the music under a stinger, then breathe back up.
func duck(db := -10.0, hold := 1.6, recover := 1.2) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_db = db
	var live_deck := _decks[_live]
	_duck_tween = create_tween()
	_duck_tween.tween_property(live_deck, "volume_db", db, 0.15)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_property(live_deck, "volume_db", 0.0, recover)
	_duck_tween.tween_callback(func() -> void: _duck_db = 0.0)


func _fade_deck(i: int, deck: AudioStreamPlayer, to_db: float, dur: float) -> Tween:
	if _fades[i] is Tween and (_fades[i] as Tween).is_valid():
		(_fades[i] as Tween).kill()
	var tw := create_tween()
	tw.tween_property(deck, "volume_db", to_db, dur)
	_fades[i] = tw
	return tw


## Web-only probe: the Playwright verification cannot hear, so the current
## track name is posted to `window.__dgMusic` where a test can assert that
## the boss entrance really did switch the score.
func _publish_state() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__dgMusic = %s" % JSON.stringify(current), true)


## The standing track policy: which music a screen wants. Battle is the one
## caller that decides for itself (boss intro switches mid-screen).
static func track_for(screen: String, chapter: int) -> String:
	match screen:
		"menu", "charselect", "settings", "codex", "metaprogress":
			return "title"
		"map", "shop", "rest", "treasure", "event", "reward", "battle":
			return "ch%d" % clampi(chapter, 1, 3)
		"victory":
			return ""   # victory screen ducks + plays the win stinger itself
		"gameover":
			return ""
	return ""
