extends Node
## 同權守衛(第十一輪):模擬器政策層同 battle UI 只准行同一個公開行動面。
##
## 第十輪嘅教訓:`toggle_lock`(釘骰)喺引擎住咗四輪,UI 從來冇接佢,唯一嘅
## 調用者係模擬器 —— 即係 BALANCE.md 度量緊一隊識做真人做唔到嘅動作嘅隊伍。
## 呢個套件令嗰類外掛冇得再靜靜雞出現:
##
##   1. `BattleCore.PLAYER_ACTIONS` + `PLAYER_QUERIES` 係唯一批准嘅調用面,
##      名單自己要誠實(逐個名真係存在、冇 underscore 私有名)。
##   2. 逐行掃 sim_runner.gd 同 screen_battle.gd:`bc.<method>(` 唔喺名單
##      即紅;`bc.s.… =`(直接寫 state)即紅;讀 state 唔算犯規。
##   3. 負向驗證:摻返一句 `bc.toggle_lock(0, 0)` 式外掛落 fixture,掃描器
##      必須當堂捉到 —— 守衛本身壞咗都要紅。
##
##   godot --headless --path . res://tests/api_parity_test.tscn

var fails := 0
var tests := 0

const SUBJECTS := {
	"sim_runner": "res://scripts/core/sim_runner.gd",
	"screen_battle": "res://scripts/ui/screen_battle.gd",
}


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _ready() -> void:
	var allowed := {}
	for m in BattleCore.PLAYER_ACTIONS + BattleCore.PLAYER_QUERIES:
		allowed[String(m)] = true

	# ---- 名單自己要誠實:冇私有名、每個名真係 BattleCore 一個 func
	var core := FileAccess.get_file_as_string("res://scripts/core/battle_core.gd")
	_check(core.length() > 1000, "battle_core source loaded")
	for m in allowed:
		_check(not String(m).begins_with("_"),
				"whitelist entry %s must be a public name" % m)
		_check(core.contains("func %s(" % m),
				"whitelist entry %s exists as a BattleCore func" % m)
	# 行動同查詢唔准重疊(一個名兩份意思係下一單事故嘅溫床)
	for m in BattleCore.PLAYER_ACTIONS:
		_check(not BattleCore.PLAYER_QUERIES.has(m),
				"%s is in both ACTIONS and QUERIES" % m)

	# ---- 兩個受管對象,逐行掃
	for key in SUBJECTS:
		var src := FileAccess.get_file_as_string(String(SUBJECTS[key]))
		_check(src.length() > 1000, "%s source loaded" % key)
		var bad := _violations(src, allowed)
		_check(bad.is_empty(), "%s stays on the player API: %s" % [key, bad])

	# ---- 負向驗證:守衛要捉得到外掛,唔係就係守衛壞咗
	var cheat_call := "\tbc.toggle_lock(0, 0)\n\tvar fd := bc.die_face(0, 0)\n"
	var flagged := _violations(cheat_call, allowed)
	_check(flagged.size() == 1 and String(flagged[0]).contains("toggle_lock"),
			"a smuggled toggle_lock-style call is caught, got %s" % [flagged])
	var cheat_write := "\tbc.s.heroes[0].block = 99\n"
	_check(_violations(cheat_write, allowed).size() == 1,
			"a direct state WRITE is caught")
	var cheat_compound := "\tbc.s.mana += 3\n"
	_check(_violations(cheat_compound, allowed).size() == 1,
			"a compound state write (+=) is caught")
	var clean := "\tif bc.can_use(0, 0).ok:\n\t\tbc.use_face(0, 0)\n" \
			+ "\tvar hp := bc.s.heroes[0].hp\n" \
			+ "\tif bc.s.mana == 3:\n\t\tpass\n" \
			+ "\t# comment mentioning bc.toggle_lock( stays a comment\n"
	_check(_violations(clean, allowed).is_empty(),
			"whitelisted calls, state READS and comments all pass")

	print("APIPARITY: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("APIPARITY OK")
	get_tree().quit(0 if fails == 0 else 1)


## Every off-whitelist thing `src` does to a BattleCore, as human-readable
## strings. The scanner is one function so the negative fixtures above exercise
## EXACTLY the code that guards the real files.
func _violations(src: String, allowed: Dictionary) -> Array:
	var out := []
	var call_re := RegEx.new()
	call_re.compile("\\bbc\\.([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	var lines := src.split("\n")
	for n in lines.size():
		# strip the comment half; `#` inside string literals would false-strip,
		# but neither subject keeps a `#` in any string it also calls `bc.` on
		var line := String(lines[n]).split("#")[0]
		for m in call_re.search_all(line):
			var name := m.get_string(1)
			if not allowed.has(name):
				out.append("line %d calls bc.%s() (not on the player API)" % [n + 1, name])
		# direct state writes: the line ASSIGNS INTO bc.s (reads are fine)
		var t := line.strip_edges()
		if t.begins_with("bc.s."):
			for op in [" += ", " -= ", " *= ", " /= ", " = "]:
				if t.contains(op):
					out.append("line %d writes battle state directly (%s)" % [n + 1, t])
					break
	return out
