class_name Cues
## Every cue in the game, from the least to the most exotic.
##
## A cue is a model plus a skin. The model is split into slots (the glTF material names: shaft, grip, blade...)
## and the skin paints each slot: [pattern, colour, second colour, metal, roughness, glow, pattern size, from, to].
## Only the first two are required. Patterns are the CUE_FX numbers in src/game/shaders/cue.gdshader:
##   0 plain  1 wood  2 bands  3 winding stripe  4 scales  5 lava  6 lightning  7 carbon  8 marble  9 crystal
##   10 galaxy  11 holographic  12 runes  13 checker  14 fire  15 inlay points  16 pulsing light  17 fade  18 tiger  19 vortex
##   20 planks (crates)
## A slot a skin does not mention keeps the material the model came with.
## The standard cue (MAIN) has the slots: tip ferrule shaft joint butt inlay wrap sleeve bumper ring.
## The nine special shapes are built by tools/make_cues.py; all play exactly alike.

const MAIN := "res://assets/models/cue_emerald_classic.glb"
const DIR := "res://assets/models/cues/cue_%s.glb"
## The ten shapes designed on 12 Nov 2026 (v1.1.6 test cues, rewards since v1.1.7)
const SHAPES_116 := ["trident", "katana", "staff", "kraken", "clockwork", "seraph", "ionblade", "rose", "arrow", "bamboo"]

const GOLD := [0, "c9963a", "", 1.0, 0.22]
const SILVER := [0, "c8ccd4", "", 1.0, 0.18]
const STEEL := [0, "4a4e58", "", 1.0, 0.28]

## material names of the standard cue model -> slot
const MAIN_SLOTS := {"tip_blue": "tip", "ferrule_ivory": "ferrule", "shaft_maple": "shaft", "joint_brass": "joint", "walnut_gloss": "butt",
	"emerald_inlay": "inlay", "leather_black": "wrap", "emerald_sleeve": "sleeve", "rubber_black": "bumper", "gold_ring": "ring"}

const LIST := [
	{"id": "cue_emerald_classic", "name": "Emerald Classic", "rarity": 0, "model": MAIN, "mats": {}},

	# ------------------------------------------------------------ common
	{"id": "cue_walnut", "name": "Walnut Standard", "rarity": 1, "model": MAIN, "mats": {
		"butt": [1, "5a3418", "2e1808", 0.0, 0.3], "sleeve": [1, "5a3418", "2e1808", 0.0, 0.3], "inlay": [0, "d8c9a0", "", 0.0, 0.3], "wrap": [0, "3a2a1c", "", 0.0, 0.8]}},
	{"id": "cue_ebony_ivory", "name": "Ebony & Ivory", "rarity": 1, "model": MAIN, "mats": {
		"butt": [0, "0b0b0d", "", 0.0, 0.16], "sleeve": [0, "0b0b0d", "", 0.0, 0.16], "inlay": [0, "ece4d0", "", 0.0, 0.25], "wrap": [0, "e8e0cc", "", 0.0, 0.7], "ring": SILVER, "joint": SILVER}},
	{"id": "cue_rosewood", "name": "Rosewood Gold", "rarity": 1, "model": MAIN, "mats": {
		"butt": [1, "6b1f16", "3a0c08", 0.0, 0.2], "sleeve": [1, "6b1f16", "3a0c08", 0.0, 0.2], "inlay": GOLD, "wrap": [0, "1a0e0a", "", 0.0, 0.75]}},
	{"id": "cue_midnight", "name": "Midnight Blue", "rarity": 1, "model": MAIN, "mats": {
		"butt": [0, "0c1c48", "", 0.1, 0.16], "sleeve": [0, "0c1c48", "", 0.1, 0.16], "inlay": [0, "8fb4ff", "", 0.2, 0.2], "wrap": [0, "0a0f20", "", 0.0, 0.7], "ring": SILVER, "joint": SILVER}},
	{"id": "cue_sword_a", "name": "Knight's Blade", "rarity": 1, "model": "sword", "mats": {
		"ferrule": SILVER, "blade": [0, "c9ced6", "", 1.0, 0.16], "guard": [0, "c9963a", "", 1.0, 0.25], "grip": [3, "4a2a16", "22120a", 0.0, 0.8, 0.0, 3.0], "gem": [16, "d0142a", "", 0.0, 0.1, 1.4]}},
	{"id": "cue_crystal_a", "name": "Amethyst", "rarity": 1, "model": "crystal", "mats": {
		"crystal": [9, "6a2ab8", "d9a8ff", 0.0, 0.05, 1.0], "shard": [9, "8a3ad8", "f0d0ff", 0.0, 0.04, 1.5], "metal": SILVER}},
	{"id": "cue_rocket_a", "name": "Apollo", "rarity": 1, "model": "rocket", "mats": {
		"shaft": [0, "e9edf2", "", 0.0, 0.25], "grip": [13, "f2f2f2", "16161a", 0.0, 0.3], "nose": [0, "d0142a", "", 0.1, 0.2], "body": [0, "f2f2f2", "", 0.1, 0.2],
		"nozzle": STEEL, "flame": [14, "ff7a1a", "ffe060", 0.0, 0.3, 3.0], "fin": [0, "d0142a", "", 0.1, 0.25], "window": [16, "4cc9f0", "", 0.0, 0.1, 1.4], "metal": STEEL}},
	{"id": "cue_pharaoh_a", "name": "Sceptre of Ra", "rarity": 1, "model": "pharaoh", "mats": {
		"shaft": [0, "1a120c", "", 0.0, 0.25], "gold": [0, "d4a23a", "", 1.0, 0.2], "bands": [2, "d4a23a", "1a3a9a", 0.8, 0.22], "lapis": [0, "1a3a9a", "", 0.2, 0.2], "gem": [16, "d0142a", "", 0.0, 0.1, 1.6]}},
	{"id": "cue_serpent_a", "name": "Emerald Viper", "rarity": 1, "model": "serpent", "mats": {
		"wood": [1, "3a2414", "1c0f08", 0.0, 0.3], "snake": [4, "1a8a4a", "c8e86a", 0.3, 0.3, 0.0, 1.2], "glow": [16, "ffd82a", "", 0.0, 0.2, 2.5], "fang": [0, "f2ecd8", "", 0.0, 0.3], "metal": GOLD}},
	# v1.1.7: the common ones of the ten cues designed on 12 Nov (models from tools/make_cues.py)
	{"id": "cue_arrow", "name": "Fletcher", "rarity": 1, "model": "arrow", "mats": {
		"shaft": [1, "c89a5a", "8a5a2a", 0.0, 0.4], "thread": [0, "8a1a1a", "", 0.0, 0.6], "wood": [1, "b8844a", "6a3e1a", 0.0, 0.4],
		"vane": [2, "f2ece0", "c8321e", 0.0, 0.7, 0.0, 3.0], "nock": [0, "1a1a1e", "", 0.2, 0.3]}},
	{"id": "cue_bamboo", "name": "Jade Bamboo", "rarity": 1, "model": "bamboo", "mats": {
		"ferrule": [0, "e8f0dc", "", 0.0, 0.3], "cane": [17, "1f7a44", "6cbf5a", 0.1, 0.24, 0.0, 1.0, 0.03, 1.46], "node": [0, "1f6a3a", "", 0.2, 0.3],
		"leaf": [9, "1fa86a", "7dffc0", 0.0, 0.2, 0.4]}},

	# ------------------------------------------------------------ uncommon
	{"id": "cue_crimson", "name": "Crimson Lacquer", "rarity": 2, "model": MAIN, "mats": {
		"shaft": [0, "1a1a1e", "", 0.0, 0.25], "butt": [0, "8e0f1c", "", 0.15, 0.1], "sleeve": [0, "8e0f1c", "", 0.15, 0.1], "inlay": GOLD}},
	{"id": "cue_arctic", "name": "Arctic White", "rarity": 2, "model": MAIN, "mats": {
		"shaft": [0, "e9edf2", "", 0.0, 0.25], "butt": [0, "eef2f6", "", 0.0, 0.12], "sleeve": [0, "eef2f6", "", 0.0, 0.12], "inlay": [0, "7fd4ff", "", 0.3, 0.15],
		"wrap": [0, "b9c6d6", "", 0.0, 0.6], "ring": SILVER, "joint": SILVER}},
	{"id": "cue_tiger", "name": "Tiger Maple", "rarity": 2, "model": MAIN, "mats": {
		"butt": [18, "d99a3a", "4a2408", 0.0, 0.2], "sleeve": [18, "d99a3a", "4a2408", 0.0, 0.2], "inlay": [0, "1a0e08", "", 0.0, 0.25], "wrap": [0, "2a180c", "", 0.0, 0.75]}},
	{"id": "cue_sakura", "name": "Sakura", "rarity": 2, "model": MAIN, "mats": {
		"butt": [17, "f7c6d9", "c2386b", 0.0, 0.14, 0.0, 1.0, 0.745, 1.05], "sleeve": [0, "c2386b", "", 0.1, 0.14], "inlay": [0, "ffffff", "", 0.0, 0.2],
		"wrap": [0, "fbe3ec", "", 0.0, 0.6], "ring": [0, "e0a08a", "", 1.0, 0.2], "joint": [0, "e0a08a", "", 1.0, 0.2]}},
	{"id": "cue_sword_b", "name": "Black Knight", "rarity": 2, "model": "sword", "mats": {
		"ferrule": STEEL, "blade": [12, "1a1c22", "ff2a1a", 0.9, 0.2, 2.0], "guard": [0, "2a2c34", "", 1.0, 0.3], "grip": [3, "140a0a", "5a0a0a", 0.0, 0.8, 0.0, 3.0], "gem": [16, "ff2a1a", "", 0.0, 0.1, 2.6]}},
	{"id": "cue_crystal_b", "name": "Aquamarine", "rarity": 2, "model": "crystal", "mats": {
		"crystal": [9, "0f8fa8", "9ff0ff", 0.0, 0.05, 1.0], "shard": [9, "19b8d0", "e0ffff", 0.0, 0.04, 1.5], "metal": GOLD}},
	{"id": "cue_skull_a", "name": "Bonecrusher", "rarity": 2, "model": "skull", "mats": {
		"ferrule": [0, "85795c", "", 0.0, 0.4], "shaft": [0, "141416", "", 0.0, 0.3], "metal": STEEL, "bone": [8, "85795c", "3e3526", 0.0, 0.55, 0.0, 1.6], "skull": [8, "8c8062", "3e3526", 0.0, 0.5, 0.0, 1.3], "glow": [16, "ff2a1a", "", 0.0, 0.3, 3.0]}},
	{"id": "cue_molten_a", "name": "Magma Core", "rarity": 2, "model": "molten", "mats": {
		"ferrule": [0, "2a211c", "", 0.0, 0.5], "rock": [5, "1c1512", "ff5a0a", 0.0, 0.85, 2.2], "glow": [14, "ff5a0a", "ffd040", 0.0, 0.5, 2.6]}},
	{"id": "cue_lightning_a", "name": "Thunderbolt", "rarity": 2, "model": "lightning", "mats": {
		"shaft": [0, "22262e", "", 0.8, 0.3], "metal": GOLD, "core": [0, "14161c", "", 0.8, 0.3], "bolt": [16, "ffc81a", "", 0.0, 0.2, 1.3], "orb": [14, "ffb010", "fff0a0", 0.0, 0.1, 1.2]}},
	# v1.1.7: the uncommon ones of the ten cues designed on 12 Nov (models from tools/make_cues.py)
	{"id": "cue_katana", "name": "Ronin", "rarity": 2, "model": "katana", "mats": {
		"ferrule": [0, "cfd4dc", "", 1.0, 0.14], "blade": [8, "d8dde6", "8a929e", 0.85, 0.16, 0.0, 2.5], "collar": [0, "c9963a", "", 1.0, 0.24],
		"guard": [0, "8a6a3a", "", 1.0, 0.3], "grip": [13, "121214", "7a1420", 0.0, 0.7, 0.0, 3.2]}},
	{"id": "cue_rose", "name": "Thorned Rose", "rarity": 2, "model": "rose", "mats": {
		"shaft": [17, "1a0a0e", "3a0c18", 0.1, 0.2, 0.0, 1.0, 0.1, 0.72], "metal": [0, "c9963a", "", 1.0, 0.22], "stem": [0, "1f4a22", "", 0.0, 0.45], "thorn": [0, "3a2a18", "", 0.0, 0.4],
		"leaf": [0, "2a6a2a", "", 0.0, 0.5], "petal": [17, "a8061e", "ff3a5a", 0.0, 0.35, 0.25, 1.0, 1.39, 1.47]}},

	# ------------------------------------------------------------ rare
	{"id": "cue_carbon", "name": "Carbon Pro", "rarity": 3, "model": MAIN, "mats": {
		"shaft": [7, "30333a", "", 0.35, 0.25], "butt": [7, "2a2c32", "", 0.35, 0.22], "sleeve": [7, "2a2c32", "", 0.35, 0.22], "inlay": [16, "2be7a5", "", 0.3, 0.2, 0.9],
		"wrap": [0, "0c0c0e", "", 0.0, 0.85], "ring": [0, "2be7a5", "", 1.0, 0.2], "joint": STEEL}},
	{"id": "cue_marble", "name": "Marble King", "rarity": 3, "model": MAIN, "mats": {
		"shaft": [0, "efe9dc", "", 0.0, 0.2], "butt": [8, "b9b4aa", "1c1a22", 0.0, 0.1, 0.0, 1.6], "sleeve": [8, "b9b4aa", "1c1a22", 0.0, 0.1, 0.0, 1.6], "inlay": GOLD, "wrap": [0, "1c1c22", "", 0.0, 0.7]}},
	{"id": "cue_sunset", "name": "Sunset Fade", "rarity": 3, "model": MAIN, "mats": {
		"butt": [17, "ffb347", "c2185b", 0.1, 0.12, 0.0, 1.0, 0.745, 1.05], "wrap": [17, "c2185b", "5b1a8e", 0.0, 0.5, 0.0, 1.0, 1.05, 1.3],
		"sleeve": [17, "5b1a8e", "1a1050", 0.1, 0.14, 0.0, 1.0, 1.3, 1.47], "inlay": [0, "fff1c9", "", 0.4, 0.2]}},
	{"id": "cue_royal", "name": "Royal Gold", "rarity": 3, "model": MAIN, "mats": {
		"shaft": [0, "1a1410", "", 0.0, 0.2], "butt": [0, "d4a23a", "", 1.0, 0.2], "inlay": [0, "7a0f1e", "", 0.2, 0.15], "wrap": [0, "3a0a12", "", 0.0, 0.7],
		"sleeve": [12, "d4a23a", "fff0b0", 1.0, 0.22, 0.6], "ring": [0, "fff0c0", "", 1.0, 0.15], "joint": [0, "d4a23a", "", 1.0, 0.2]}},
	{"id": "cue_rocket_b", "name": "Retro Raygun", "rarity": 3, "model": "rocket", "mats": {
		"shaft": SILVER, "grip": [2, "1a8a8a", "c8ccd4", 0.6, 0.25], "nose": SILVER, "body": [0, "1a9a9a", "", 0.6, 0.2], "nozzle": SILVER,
		"flame": [14, "29e6ff", "ffffff", 0.0, 0.3, 3.0], "fin": [0, "ff7a1a", "", 0.3, 0.25], "window": [16, "ffd82a", "", 0.0, 0.1, 2.0], "metal": [0, "ff7a1a", "", 1.0, 0.2]}},
	{"id": "cue_pharaoh_b", "name": "Anubis", "rarity": 3, "model": "pharaoh", "mats": {
		"shaft": [0, "0a0a0c", "", 0.2, 0.15], "gold": [0, "d4a23a", "", 1.0, 0.2], "bands": [2, "0c0c10", "d4a23a", 0.8, 0.2], "lapis": [0, "0c0c10", "", 0.4, 0.15], "gem": [16, "2be7a5", "", 0.0, 0.1, 3.0]}},
	{"id": "cue_serpent_b", "name": "Coral Snake", "rarity": 3, "model": "serpent", "mats": {
		"shaft": [0, "e9dcc0", "", 0.0, 0.3], "wood": [0, "0e0e10", "", 0.0, 0.2], "snake": [2, "d0142a", "f2c81a", 0.2, 0.25, 0.0, 2.2], "glow": [16, "ffffff", "", 0.0, 0.2, 2.0],
		"fang": [0, "ffffff", "", 0.0, 0.3], "metal": [0, "d0142a", "", 0.3, 0.2]}},
	{"id": "cue_skull_b", "name": "Obsidian Skull", "rarity": 3, "model": "skull", "mats": {
		"ferrule": STEEL, "shaft": [0, "0a0a0e", "", 0.2, 0.15], "bone": [0, "121218", "", 0.4, 0.12], "skull": [0, "0e0e14", "", 0.5, 0.08], "glow": [16, "b04bff", "", 0.0, 0.3, 3.0], "metal": [0, "b04bff", "", 1.0, 0.2]}},
	{"id": "cue_molten_b", "name": "Blue Flame", "rarity": 3, "model": "molten", "mats": {
		"ferrule": [0, "1c2028", "", 0.0, 0.5], "rock": [5, "12141c", "2a8cff", 0.0, 0.85, 2.4], "glow": [14, "2a8cff", "c0f0ff", 0.0, 0.5, 2.6]}},
	{"id": "cue_dragon_a", "name": "Emerald Wyrm", "rarity": 3, "model": "dragon", "mats": {
		"shaft": [0, "1a120c", "", 0.0, 0.25], "scales": [4, "0f7a4a", "c8ff9a", 0.6, 0.3], "head": [4, "0f7a4a", "c8ff9a", 0.6, 0.3, 0.0, 1.5], "horn": [0, "e8dcc0", "", 0.0, 0.35], "glow": [16, "ffb020", "", 0.0, 0.2, 3.0]}},
	# v1.1.7: the rare ones of the ten cues designed on 12 Nov (models from tools/make_cues.py)
	{"id": "cue_staff", "name": "Archmage", "rarity": 3, "model": "staff", "mats": {
		"shaft": [1, "4a2e18", "22140a", 0.0, 0.4], "metal": [0, "8a6a3a", "", 1.0, 0.3], "wood": [1, "5a3a1e", "2a180a", 0.0, 0.55],
		"orb": [10, "8a4bff", "29e6ff", 0.0, 0.05, 2.2], "rune": [12, "1a1030", "b98aff", 0.2, 0.2, 2.6]}},
	{"id": "cue_clockwork", "name": "Clockwork", "rarity": 3, "model": "clockwork", "mats": {
		"shaft": [1, "6a4424", "3a200c", 0.0, 0.3], "gear": [0, "d9a640", "", 1.0, 0.24], "dark": [1, "5a3018", "2a1408", 0.0, 0.25], "copper": [0, "c8643a", "", 1.0, 0.22],
		"glass": [16, "ffe2a0", "", 0.0, 0.05, 1.4]}},

	# ------------------------------------------------------------ epic
	{"id": "cue_chrome", "name": "Chrome Phantom", "rarity": 4, "model": MAIN, "mats": {
		"ferrule": [0, "e8ecf2", "", 1.0, 0.15], "shaft": [0, "e4e8f0", "", 1.0, 0.14], "butt": [0, "eef2f8", "", 1.0, 0.08], "inlay": [0, "101216", "", 0.5, 0.2],
		"sleeve": [0, "eef2f8", "", 1.0, 0.08], "wrap": [7, "1a1b1f", "", 0.35, 0.3], "ring": [0, "101216", "", 1.0, 0.2], "joint": SILVER}},
	{"id": "cue_neon", "name": "Neon Pulse", "rarity": 4, "model": MAIN, "mats": {
		"shaft": [0, "0e1016", "", 0.2, 0.2], "butt": [3, "0a0c12", "ff2bd6", 0.2, 0.16, 2.2], "sleeve": [3, "0a0c12", "29e6ff", 0.2, 0.16, 2.2],
		"inlay": [16, "29e6ff", "", 0.0, 0.2, 2.0], "wrap": [0, "0a0a0e", "", 0.0, 0.8], "ring": [16, "ff2bd6", "", 0.0, 0.2, 2.4], "joint": [16, "29e6ff", "", 0.0, 0.2, 2.0]}},
	{"id": "cue_scale", "name": "Dragon Scale", "rarity": 4, "model": MAIN, "mats": {
		"shaft": [0, "1a120c", "", 0.0, 0.25], "butt": [4, "0f7a4a", "ffd87a", 0.7, 0.28, 0.3], "sleeve": [4, "0f7a4a", "ffd87a", 0.7, 0.28, 0.3],
		"inlay": [0, "ffd87a", "", 1.0, 0.2], "wrap": [0, "0a1a12", "", 0.0, 0.8]}},
	{"id": "cue_holo", "name": "Holo Prism", "rarity": 4, "model": MAIN, "mats": {
		"shaft": [11, "e8ecf4", "", 0.9, 0.16, 0.3], "butt": [11, "e8ecf4", "", 0.9, 0.14, 0.4, 1.6], "sleeve": [11, "e8ecf4", "", 0.9, 0.14, 0.4, 1.6],
		"inlay": [0, "ffffff", "", 1.0, 0.1], "wrap": [0, "14141a", "", 0.0, 0.7], "ring": SILVER, "joint": SILVER}},
	{"id": "cue_sword_c", "name": "Excalibur", "rarity": 4, "model": "sword", "mats": {
		"ferrule": [0, "ffd060", "", 1.0, 0.18], "blade": [12, "e8eefc", "7fd4ff", 1.0, 0.1, 2.6], "guard": [0, "ffd060", "", 1.0, 0.18], "grip": [3, "1c3a8a", "ffd060", 0.2, 0.5, 0.0, 3.0], "gem": [16, "7fd4ff", "", 0.0, 0.1, 3.0]}},
	{"id": "cue_crystal_c", "name": "Prismatic", "rarity": 4, "model": "crystal", "mats": {
		"crystal": [11, "ffffff", "", 0.9, 0.1, 0.6, 1.5], "shard": [11, "ffffff", "", 0.9, 0.08, 1.0, 3.0], "metal": [0, "ffffff", "", 1.0, 0.1]}},
	{"id": "cue_rocket_c", "name": "Stealth", "rarity": 4, "model": "rocket", "mats": {
		"shaft": [7, "1a1b1f", "", 0.35, 0.3], "grip": [7, "1a1b1f", "", 0.35, 0.3], "nose": [0, "101114", "", 0.3, 0.4], "body": [0, "14151a", "", 0.3, 0.4], "nozzle": [0, "0a0a0c", "", 1.0, 0.3],
		"flame": [14, "b04bff", "ff4fa3", 0.0, 0.3, 3.2], "fin": [0, "ff5a0a", "", 0.2, 0.3], "window": [16, "ff5a0a", "", 0.0, 0.1, 2.2], "metal": [0, "ff5a0a", "", 1.0, 0.25]}},
	{"id": "cue_serpent_c", "name": "Golden Cobra", "rarity": 4, "model": "serpent", "mats": {
		"shaft": [0, "0c0a08", "", 0.0, 0.2], "wood": [0, "0c0a08", "", 0.2, 0.15], "snake": [4, "d4a23a", "fff0b0", 1.0, 0.22, 0.3, 1.2], "glow": [16, "d0142a", "", 0.0, 0.2, 3.0],
		"fang": [0, "ffffff", "", 0.0, 0.3], "metal": [0, "d0142a", "", 0.3, 0.15]}},
	{"id": "cue_lightning_b", "name": "Plasma Arc", "rarity": 4, "model": "lightning", "mats": {
		"shaft": [6, "120a1e", "c04bff", 0.5, 0.25, 1.8], "metal": SILVER, "core": [0, "0c0814", "", 0.5, 0.3], "bolt": [16, "c04bff", "", 0.0, 0.2, 1.5], "orb": [14, "c04bff", "29e6ff", 0.0, 0.1, 1.4]}},
	{"id": "cue_dragon_b", "name": "Crimson Drake", "rarity": 4, "model": "dragon", "mats": {
		"shaft": [0, "0c0808", "", 0.0, 0.25], "scales": [4, "8e0f14", "ffb020", 0.6, 0.28, 0.4], "head": [4, "8e0f14", "ffb020", 0.6, 0.28, 0.4, 1.5], "horn": [0, "1a1414", "", 0.3, 0.25], "glow": [16, "ffd82a", "", 0.0, 0.2, 3.0]}},
	# v1.1.7: the epic ones of the ten cues designed on 12 Nov (models from tools/make_cues.py)
	{"id": "cue_trident", "name": "Poseidon's Trident", "rarity": 4, "model": "trident", "mats": {
		"ferrule": [0, "e8d8a8", "", 1.0, 0.2], "shaft": [17, "0b3a5a", "1aa6b8", 0.3, 0.18, 0.0, 1.0, 0.1, 0.72], "metal": [0, "d9b45a", "", 1.0, 0.2],
		"grip": [4, "0d6a7a", "7ff0e0", 0.7, 0.24, 0.35, 1.4], "prong": [0, "e6c46a", "", 1.0, 0.14], "gem": [16, "29e6ff", "", 0.0, 0.1, 3.0]}},
	{"id": "cue_kraken", "name": "Kraken", "rarity": 4, "model": "kraken", "mats": {
		"shaft": [17, "0a1c22", "1a5a5a", 0.2, 0.2, 0.0, 1.0, 0.1, 0.72], "metal": [0, "4a6a5a", "", 1.0, 0.3], "flesh": [17, "6a1a4a", "e86a5a", 0.1, 0.3, 0.0, 1.0, 0.8, 1.44],
		"sucker": [16, "ffb8a0", "", 0.0, 0.25, 0.6]}},

	# ------------------------------------------------------------ legendary
	{"id": "cue_lava", "name": "Lava Flow", "rarity": 5, "model": MAIN, "mats": {
		"ferrule": [0, "2a211c", "", 0.0, 0.5], "shaft": [5, "1a1412", "ff5a0a", 0.0, 0.85, 1.8], "butt": [5, "1a1412", "ff5a0a", 0.0, 0.85, 2.2], "sleeve": [5, "1a1412", "ff5a0a", 0.0, 0.85, 2.2],
		"inlay": [16, "ffb020", "", 0.0, 0.3, 2.2], "wrap": [0, "0c0908", "", 0.0, 0.9], "ring": [16, "ff5a0a", "", 0.0, 0.3, 2.0], "joint": [0, "1a1412", "", 0.6, 0.5]}},
	{"id": "cue_galaxy", "name": "Galaxy", "rarity": 5, "model": MAIN, "mats": {
		"shaft": [10, "4c8dff", "b04bff", 0.0, 0.1, 1.3], "butt": [10, "ff4fa3", "4c8dff", 0.0, 0.1, 1.6], "sleeve": [10, "2be7a5", "b04bff", 0.0, 0.1, 1.6],
		"inlay": [16, "ffffff", "", 0.0, 0.2, 1.6], "wrap": [0, "05060c", "", 0.0, 0.6], "ring": SILVER, "joint": SILVER}},
	{"id": "cue_thunder", "name": "Thunder", "rarity": 5, "model": MAIN, "mats": {
		"shaft": [6, "14161e", "9fd0ff", 0.5, 0.25, 2.2], "butt": [6, "0c0e16", "e8f4ff", 0.5, 0.2, 3.0], "sleeve": [6, "0c0e16", "e8f4ff", 0.5, 0.2, 3.0],
		"inlay": [16, "9fd0ff", "", 0.0, 0.2, 2.5], "wrap": [0, "0a0c12", "", 0.0, 0.8], "ring": [16, "e8f4ff", "", 0.0, 0.2, 2.0], "joint": [0, "5a6070", "", 1.0, 0.2]}},
	{"id": "cue_vortex", "name": "Emerald Vortex", "rarity": 5, "model": MAIN, "mats": {
		"shaft": [19, "06140f", "2be7a5", 0.3, 0.14, 1.6], "butt": [19, "04100c", "2be7a5", 0.3, 0.1, 2.6, 1.4], "sleeve": [19, "04100c", "7dffd0", 0.3, 0.1, 2.6, 1.4],
		"inlay": [16, "7dffd0", "", 0.0, 0.2, 2.4], "wrap": [0, "03100b", "", 0.0, 0.7], "ring": [16, "2be7a5", "", 0.0, 0.2, 2.2]}},
	{"id": "cue_phoenix", "name": "Phoenix", "rarity": 5, "model": MAIN, "mats": {
		"shaft": [17, "1a0a06", "c8320a", 0.2, 0.2, 0.0, 1.0, 0.1, 0.72], "butt": [14, "ff3a0a", "ffd040", 0.0, 0.3, 1.1], "sleeve": [14, "ff3a0a", "ffd040", 0.0, 0.3, 1.1],
		"inlay": GOLD, "wrap": [0, "1a0806", "", 0.0, 0.8], "ring": [16, "ffd040", "", 0.0, 0.2, 1.6], "joint": GOLD}},
	{"id": "cue_pharaoh_c", "name": "Cleopatra", "rarity": 5, "model": "pharaoh", "mats": {
		"shaft": [8, "f2efe8", "c9b8a0", 0.0, 0.1], "gold": [0, "e8b090", "", 1.0, 0.16], "bands": [2, "f2efe8", "19c8c0", 0.3, 0.14], "lapis": [16, "19c8c0", "", 0.2, 0.15, 0.8], "gem": [16, "ff4fa3", "", 0.0, 0.1, 3.0]}},
	{"id": "cue_skull_c", "name": "Golden Reaper", "rarity": 5, "model": "skull", "mats": {
		"ferrule": [0, "d4a23a", "", 1.0, 0.25], "shaft": [12, "0c0a08", "ffd060", 0.2, 0.2, 1.6], "bone": [0, "d4a23a", "", 1.0, 0.25], "skull": [0, "e2b24a", "", 1.0, 0.18],
		"glow": [16, "2be7a5", "", 0.0, 0.3, 3.2], "metal": [0, "0c0a08", "", 1.0, 0.3]}},
	{"id": "cue_molten_c", "name": "Toxic Meltdown", "rarity": 5, "model": "molten", "mats": {
		"ferrule": [0, "1c221a", "", 0.0, 0.5], "rock": [5, "101410", "7dff2a", 0.0, 0.85, 2.6], "glow": [14, "7dff2a", "f0ffb0", 0.0, 0.5, 2.8]}},
	{"id": "cue_lightning_c", "name": "Storm Lord", "rarity": 5, "model": "lightning", "mats": {
		"shaft": [6, "0a1220", "9fe0ff", 0.6, 0.2, 2.4], "metal": [0, "e8f4ff", "", 1.0, 0.15], "core": [16, "9fe0ff", "", 0.0, 0.3, 1.2], "bolt": [14, "4cb8ff", "e8f8ff", 0.0, 0.2, 1.6], "orb": [14, "e8f8ff", "4cb8ff", 0.0, 0.1, 1.6]}},
	{"id": "cue_dragon_c", "name": "Frost Dragon", "rarity": 5, "model": "dragon", "mats": {
		"shaft": [9, "9fd8ff", "e8f8ff", 0.0, 0.05, 0.8], "scales": [4, "bfe6ff", "ffffff", 0.7, 0.2, 0.6], "head": [4, "bfe6ff", "ffffff", 0.7, 0.2, 0.6, 1.5],
		"horn": [9, "9fd8ff", "e8f8ff", 0.0, 0.05, 1.2], "glow": [16, "29e6ff", "", 0.0, 0.2, 3.2]}},
	# v1.1.7: the legendary ones of the ten cues designed on 12 Nov (models from tools/make_cues.py)
	{"id": "cue_seraph", "name": "Seraph", "rarity": 5, "model": "seraph", "mats": {
		"ferrule": [0, "f4ecd8", "", 0.0, 0.2], "shaft": [8, "d9d1c2", "b8a582", 0.0, 0.16], "gold": [0, "e6c46a", "", 1.0, 0.16], "ivory": [8, "d9cfbd", "b8a07a", 0.0, 0.16],
		"feather": [17, "e6c46a", "e8e4dc", 0.3, 0.4, 0.5, 1.0, 1.29, 1.39], "plume": [0, "e8e4dc", "", 0.0, 0.5, 0.35], "halo": [16, "ffe6a0", "", 0.0, 0.1, 3.0]}},
	{"id": "cue_ionblade", "name": "Ion Blade", "rarity": 5, "model": "ionblade", "mats": {
		"ferrule": [0, "e8f8ff", "", 0.0, 0.2, 1.0], "core": [16, "ffffff", "", 0.0, 0.1, 3.0], "blade": [16, "29e6ff", "", 0.0, 0.05, 2.2],
		"metal": [0, "b8bec8", "", 1.0, 0.18], "grip": [7, "16181e", "", 0.4, 0.4], "switch": [16, "ff2b4a", "", 0.0, 0.2, 2.4]}},
]


static var _shaders := {}    # pattern number -> its own copy of the cue shader
static var _mats := {}       # skin spec -> material


static func model_path(e: Dictionary) -> String:
	var m := str(e.get("model", MAIN))
	return m if m.begins_with("res://") else DIR % m


## The material for one slot of a skin.
static func material(spec: Array) -> ShaderMaterial:
	var key := str(spec)
	if _mats.has(key):
		return _mats[key]
	var fx := int(spec[0])
	if not _shaders.has(fx):
		var base_sh: Shader = preload("res://src/game/shaders/cue.gdshader")
		if fx == 0:
			_shaders[fx] = base_sh
		else:
			var sh := Shader.new()
			sh.code = base_sh.code.replace("#define CUE_FX 0", "#define CUE_FX %d" % fx)
			_shaders[fx] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[fx]
	m.set_shader_parameter("col", Color(str(spec[1])))
	var c2 := str(spec[2]) if spec.size() > 2 else ""
	m.set_shader_parameter("col2", Color(c2) if c2 != "" else Color.BLACK)
	m.set_shader_parameter("metal", float(spec[3]) if spec.size() > 3 else 0.0)
	m.set_shader_parameter("rough", float(spec[4]) if spec.size() > 4 else 0.3)
	m.set_shader_parameter("glow", float(spec[5]) if spec.size() > 5 else 0.0)
	m.set_shader_parameter("scale", float(spec[6]) if spec.size() > 6 else 1.0)
	m.set_shader_parameter("za", float(spec[7]) if spec.size() > 7 else 0.75)
	m.set_shader_parameter("zb", float(spec[8]) if spec.size() > 8 else 1.05)
	_mats[key] = m
	return m


## Paints a freshly instanced cue model with a skin.
static func paint(model: Node, e: Dictionary) -> void:
	var mats: Dictionary = e.get("mats", {})
	if mats.is_empty():
		return
	for n in model.find_children("*", "MeshInstance3D", true, false) + ([model] if model is MeshInstance3D else []):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var slot := str(mat.resource_name) if mat else ""
			slot = str(MAIN_SLOTS.get(slot, slot))
			if mats.has(slot):
				mi.set_surface_override_material(s, material(mats[slot]))
