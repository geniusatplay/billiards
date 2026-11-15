class_name XP
## Experience points and levels.
##
## Randy's rules: XP for every ball you pot; +10% for each further potting shot in the same turn (a streak);
## +10% for each extra ball that falls in the same shot (a combo); the 8-ball is worth +120%; winning adds
## 30% of everything earned in that game. Online matches pay in full, matches against the CPU pay half,
## Local Turn Based and Practice pay nothing.
## Levels (v1.1.7, Randy: "keep the total xp to reach max level (people will get levels more often)"): 130 levels,
## one for each reward, 26 of each rarity. The first costs 78 XP (three plain balls), each next one a little more,
## and the top level costs exactly what it did when there were 100 levels: 30,874 XP in all, about a hundred won
## games (three two-in-a-row streaks a game, no combos). Before v1.1.7: 100 levels, 100 + 4.217 x level each.

const PER_BALL := 25.0
const STREAK_STEP := 0.10
const COMBO_STEP := 0.10
const EIGHT := 55.0            # 25 + 120%
const WIN_BONUS := 0.30
const MAX_LEVEL := 130
const LEVEL_BASE := 78.0
const LEVEL_STEP := 2.4727
const PER_RARITY := 26          # levels (and rewards) of each rarity
## The XP chest (Randy, 11 Nov): half of what the current level costs, every 6 hours; watching an advert
## (the player's choice) makes that wait 2 hours instead (Randy, 12 Nov: it "saves 4 hours", and the button says
## "Open 4 Hours Faster With Ad"). The wait starts again when the chest is opened.
const CHEST_WAIT := 6 * 3600
const CHEST_WAIT_AD := 2 * 3600
## Packages unlock by themselves this long after they are earned (by rarity, 1 common ... 5 legendary);
## watching an advert (the player's choice) opens one at once.
const PACKAGE_WAIT := [0, 30 * 60, 3600, 2 * 3600, 4 * 3600, 8 * 3600]
const MODE_FACTOR := {"online": 1.0, "cpu": 0.5, "local": 0.0, "practice": 0.0}
const RARITY_NAMES := ["Starter", "Common", "Uncommon", "Rare", "Epic", "Legendary"]


## What the XP chest holds at `level`: half of that level's cost (50 XP at level 9, 76 at 30).
static func chest_xp(level: int) -> int:
	return int(round(need(mini(level, MAX_LEVEL - 1)) * 0.5))


## "5:12:09", or "12:09" under an hour.
static func clock(seconds: int) -> String:
	var t := maxi(seconds, 0)
	if t >= 3600:
		return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
	return "%d:%02d" % [t / 60, t % 60]


## XP needed to go from `level` to the next one.
static func need(level: int) -> int:
	return int(round(LEVEL_BASE + LEVEL_STEP * float(level)))


## Total XP at which `level` is reached.
static func total_for(level: int) -> int:
	var t := 0
	for l in mini(level, MAX_LEVEL):
		t += need(l)
	return t


static func level_of(xp: int) -> int:
	var l := 0
	var left := xp
	while l < MAX_LEVEL and left >= need(l):
		left -= need(l)
		l += 1
	return l


## How far into the current level `xp` is: [XP into the level, XP the level needs].
static func into_level(xp: int) -> Array:
	var l := level_of(xp)
	if l >= MAX_LEVEL:
		return [1, 1]
	return [xp - total_for(l), need(l)]


## Levels 1-26 give common packages, 27-52 uncommon, 53-78 rare, 79-104 epic, 105-130 legendary.
static func rarity_of_level(level: int) -> int:
	return clampi(int(ceil(float(level) / float(PER_RARITY))), 1, 5)


## The level a save's XP stood at before v1.1.7 (100 levels of 100 + 4.217 x level XP), for moving old saves over.
static func old_level_of(xp: int) -> int:
	var l := 0
	var left := xp
	while l < 100 and left >= int(round(100.0 + 4.217 * float(l))):
		left -= int(round(100.0 + 4.217 * float(l)))
		l += 1
	return l


## Counts one player's XP through a match.
class Tracker extends RefCounted:
	var streak := 0          # potting shots in a row in the current turn
	var balls := 0           # balls potted
	var ball_xp := 0.0
	var streak_xp := 0.0
	var combo_xp := 0.0
	var eight_xp := 0.0
	var won := false
	var best_streak := 0

	## After each of the player's shots. `potted`: own balls that went down without a foul.
	func shot(potted: int, sank_eight := false) -> void:
		if potted <= 0 and not sank_eight:
			streak = 0
			return
		streak += 1
		best_streak = maxi(best_streak, streak)
		if potted > 0:
			var base := XP.PER_BALL * float(potted)
			var s_mult := 1.0 + XP.STREAK_STEP * float(streak - 1)
			var c_mult := 1.0 + XP.COMBO_STEP * float(potted - 1)
			balls += potted
			ball_xp += base
			streak_xp += base * (s_mult - 1.0)
			combo_xp += base * s_mult * (c_mult - 1.0)
		if sank_eight:
			eight_xp += XP.EIGHT

	## The turn passed to the other player.
	func turn_over() -> void:
		streak = 0

	func earned() -> float:
		return ball_xp + streak_xp + combo_xp + eight_xp

	## The lines of the score screen and the final sum for a mode ("online", "cpu", "local", "practice").
	func summary(mode: String) -> Dictionary:
		var f := float(XP.MODE_FACTOR.get(mode, 0.0))
		var win_xp := earned() * XP.WIN_BONUS if won else 0.0
		var total := int(round((earned() + win_xp) * f))
		return {"balls": balls, "ball_xp": int(round(ball_xp * f)), "streak_xp": int(round(streak_xp * f)), "combo_xp": int(round(combo_xp * f)),
			"eight_xp": int(round(eight_xp * f)), "win_xp": int(round(win_xp * f)), "factor": f, "total": total, "best_streak": best_streak, "mode": mode}
