class_name FillIn
extends RefCounted
## v1.1.15 (Randy: "I want the timer to look for a match to be 1 minute, if it doesn't find a game, they verse a
## cpu, please find a list of 100+ screen names so it feels more natural, dont label the ai opponents ... as cpu").
## When Play Online finds nobody within a minute, the match goes ahead against the game's own AI under a screen
## name, with a level near the player's, its own cue, and its table or balls (as an online opponent brings).
## The match plays and pays like an online match (full XP) and is not counted in the CPU records.

const NAMES := [
	"Marco88", "lily_p", "KevOnCue", "Tomasz_W", "AnaSofia", "Rina", "DeltaJay", "mike.r", "Sven K", "Priya_S",
	"BigBreakBen", "noah.t", "Lucia R", "ChalkDust", "Yusuf", "hannah_b", "Mateo10", "Kenji", "olivia.m", "Rafa_C",
	"SideSpin", "Amara", "jonas.k", "Leila", "GreenFelt", "dmitri", "Chloe P", "Ivan_88", "bankshot_bo", "Emre",
	"sofie_v", "Diego R", "Mia K", "CornerPocket", "Arjun", "tess", "Lukas_M", "Zara", "Nico_B", "eightball_eli",
	"Ines", "Owen T", "Hiro", "Fatima_A", "PeteTheCue", "marta.s", "Liam_O", "Aylin", "Bruno", "Sakura",
	"Theo", "kat_plays", "Andre", "Elif", "Max_R", "Noor", "Carlos", "Jade W", "Felix", "Anya",
	"Sami", "RackEmRoy", "Grace", "Tariq", "Elena V", "Jules", "Kofi", "Vera", "Oscar", "Mei",
	"Daniel K", "Yara", "Hugo", "Nadia", "Leo_P", "Isla", "Mateus", "Aiko", "Ravi", "Sara_L",
	"Viktor", "Lena", "Omar", "Clara", "Jasper", "Thandi", "Matteo", "Rosa", "Kai", "Ingrid",
	"Dev", "Lotte", "Ahmed", "Bianca", "Finn", "Mira", "Joao", "Hana", "Stefan", "Lucy",
	"Arman", "Paula", "Ryo", "Eva", "Kwame", "Signe", "Pablo", "Wren", "Tobias", "Anika",
	"cue_ball_cal", "Ruby", "Dario", "Esra", "Gus", "Linnea", "Malik", "Petra", "Sol", "TopSpinTia",
]


## A screen name (now and then with a number, as people pick), never the player's own.
static func pick_name(rng: RandomNumberGenerator, own: String) -> String:
	for _i in 8:
		var n: String = NAMES[rng.randi_range(0, NAMES.size() - 1)]
		if not (" " in n or "_" in n or "." in n or n[n.length() - 1].is_valid_int()) and rng.randf() < 0.25:
			n += str(rng.randi_range(7, 99))
		if n.to_lower() != own.to_lower():
			return n
	return "Rina"


## How strong the stand-in plays, from the player's level: mostly a fair game.
static func ai_level_for(level: int, rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if level < 3:
		return 0 if r < 0.7 else 1
	if level < 10:
		return 0 if r < 0.25 else (1 if r < 0.85 else 2)
	return 1 if r < 0.5 else 2


## Everything the match needs to show the opponent: name, level, cue, table, balls, and who breaks.
static func make(own_name: String, own_level: int, seed_no := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_no >= 0:
		rng.seed = seed_no
	else:
		rng.randomize()
	var cues: Array = Catalog.ids(Catalog.CUES)
	var tables: Array = Catalog.ids(Catalog.TABLES)
	var balls: Array = Catalog.ids(Catalog.BALLS)
	return {
		"name": pick_name(rng, own_name),
		"level": maxi(0, own_level + rng.randi_range(-3, 3)),
		"ai_level": ai_level_for(own_level, rng),
		"cue": cues[rng.randi_range(0, cues.size() - 1)],
		"table": tables[rng.randi_range(0, tables.size() - 1)],
		"balls": balls[rng.randi_range(0, balls.size() - 1)],
		"they_break": rng.randf() < 0.5,
	}
