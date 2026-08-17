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
func play(track: String, fade := 0.8) -> void:
	if current == track:
		return
	current = track
	var path := DIR + track + ".ogg"
	if not ResourceLoader.exists(path):
		stop(fade)
		current = track  # remember the ask even if the file is missing
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_live = 1 - _live
	var incoming := _decks[_live]
	var outgoing := _decks[1 - _live]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
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
