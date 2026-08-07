"""Balance tuning helper: applies scalar tweaks to the enemy/boss JSON.

Usage:  python tools/tune.py '<json ops>'
  ops = {"enemy_hp": {"1": 1.15}, "enemy_atk": {"1": 1}, "boss_hp": {"B1": 70}}
    enemy_hp  — per-tier ("1".."3") multiplier on every minion's hp
    enemy_atk — per-tier flat delta on every face with an atk value >= 2
    boss_hp   — absolute hp per boss key
    boss_atk  — flat delta on every boss attack face
Values are clamped to >= 1. Run from the project root.
"""
import io, json, sys, collections

ROOT = ""


def load(p):
    return json.load(io.open(p, encoding="utf-8"),
                     object_pairs_hook=collections.OrderedDict)


def save(p, d):
    with io.open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def main(ops):
    enemies = load("data/enemies.json")
    bosses = load("data/bosses.json")

    for tier_s, mult in ops.get("enemy_hp", {}).items():
        ti = int(tier_s) - 1
        for e in enemies.values():
            e["hp"][ti] = max(1, int(round(e["hp"][ti] * mult)))

    for tier_s, delta in ops.get("enemy_atk", {}).items():
        ti = int(tier_s) - 1
        for e in enemies.values():
            for f in e["faces"]:
                if "atk" in f and isinstance(f["atk"], list) and f["atk"][ti] >= 2:
                    f["atk"][ti] = max(1, f["atk"][ti] + delta)

    for key, hp in ops.get("boss_hp", {}).items():
        bosses[key]["hp"] = int(hp)
        if "phase2_hp" in bosses[key] and key in ops.get("boss_phase2_hp", {}):
            bosses[key]["phase2_hp"] = int(ops["boss_phase2_hp"][key])

    for key, delta in ops.get("boss_atk", {}).items():
        for group in ("faces", "phase2_faces"):
            for f in bosses[key].get(group, []):
                if "atk" in f:
                    f["atk"] = max(1, int(f["atk"]) + int(delta))

    save("data/enemies.json", enemies)
    save("data/bosses.json", bosses)
    print("tuned:", json.dumps(ops, ensure_ascii=False))


if __name__ == "__main__":
    main(json.loads(sys.argv[1]))
