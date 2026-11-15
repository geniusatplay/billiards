class_name Catalog
extends RefCounted
## Content registry. To add a cue, table style or scene, append an entry here — menus, settings
## and the renderer pick it up automatically. (Future: campaign levels / online modes register in MODES.)

## Cue sticks: model is a GLB with the tip at the origin and the butt along local +Z (1.47 m long).
## Every cue (the standard model in its skins, and the nine special shapes): see cues.gd
const CUES := Cues.LIST

## Table styles: cloth, rail wood, skirt and the under-rail light strip.
## A style may also carry: "rarity"; "felt_fx" + "felt2" (a quiet cloth pattern, see felt.gdshader);
## "rail" / "body" / "leg" / "trim" (painted like a cue slot, see cues.gd: the pattern size is the 7th number);
## "legs": classic, block, slab, pedestal, crystal, tech or hover; "led": strength of the light strip.
## Every table has the same height, playing area, cushions and pockets: the styles are looks only.
const TABLES := [
	{"id": "emerald", "name": "Emerald Classic", "rarity": 0, "felt": Color("0f6b4f"), "wood": Color("2a160d"), "skirt": Color("15100c"), "accent": Color("2be7a5")},
	# common
	{"id": "midnight", "name": "Midnight Blue", "rarity": 1, "felt": Color("1b3566"), "wood": Color("1c1c22"), "skirt": Color("0d0d12"), "accent": Color("4cc9f0")},
	{"id": "crimson", "name": "Crimson Club", "rarity": 1, "felt": Color("7a1f2b"), "wood": Color("2b1710"), "skirt": Color("140b08"), "accent": Color("ffc857")},
	{"id": "slate", "name": "Graphite", "rarity": 1, "felt": Color("38424f"), "wood": Color("3a3a40"), "skirt": Color("18181c"), "accent": Color("eaf2ff")},
	{"id": "tournament", "name": "Tournament Blue", "rarity": 1, "felt": Color("17509a"), "accent": Color("ffffff"), "legs": "block",
		"rail": [0, "101114", "", 0.2, 0.25], "body": [0, "0a0a0c", "", 0.2, 0.35], "leg": [0, "101114", "", 0.2, 0.3], "trim": [0, "c8ccd4", "", 1.0, 0.18]},
	# uncommon
	{"id": "violet", "name": "Vortex Violet", "rarity": 2, "felt": Color("4b2a7a"), "wood": Color("161320"), "skirt": Color("0c0a12"), "accent": Color("b388ff")},
	{"id": "walnut", "name": "Walnut Heritage", "rarity": 2, "felt": Color("0b4a2c"), "felt_fx": 5, "accent": Color("ffc857"), "led": 1.2,
		"rail": [1, "6a3e1e", "3a1e0c", 0.0, 0.3, 0.0, 0.25], "body": [1, "4a2a14", "24120a", 0.0, 0.35, 0.0, 0.25], "leg": [1, "5a3418", "2e1808", 0.0, 0.3, 0.0, 0.25]},
	{"id": "arctic", "name": "Arctic", "rarity": 2, "felt": Color("2f6f9a"), "accent": Color("9fe0ff"), "legs": "slab",
		"rail": [0, "e9edf2", "", 0.0, 0.15], "body": [0, "cfd6de", "", 0.0, 0.2], "leg": [0, "e9edf2", "", 0.0, 0.18], "trim": [0, "c8ccd4", "", 1.0, 0.18]},
	{"id": "sakura", "name": "Sakura", "rarity": 2, "felt": Color("a8405f"), "felt_fx": 5, "accent": Color("ff9ac0"),
		"rail": [0, "f4eef0", "", 0.0, 0.15], "body": [0, "e8c6d2", "", 0.0, 0.2], "leg": [0, "f4eef0", "", 0.0, 0.18], "trim": [0, "e0a08a", "", 1.0, 0.2]},
	# rare
	{"id": "carbon", "name": "Carbon", "rarity": 3, "felt": Color("46505c"), "accent": Color("2be7a5"), "legs": "tech", "led": 2.6,
		"rail": [7, "2a2c32", "", 0.35, 0.25, 0.0, 0.12], "body": [7, "1e2026", "", 0.35, 0.3, 0.0, 0.12], "leg": [0, "4a4e58", "", 1.0, 0.28], "trim": [0, "2be7a5", "", 1.0, 0.2]},
	{"id": "marble", "name": "Marble Palace", "rarity": 3, "felt": Color("6a1a2e"), "accent": Color("ffd87a"), "legs": "block", "led": 1.4,
		"rail": [8, "ece8e0", "3a3640", 0.0, 0.08, 0.0, 0.1], "body": [8, "dcd6ca", "3a3640", 0.0, 0.1, 0.0, 0.1], "leg": [8, "ece8e0", "3a3640", 0.0, 0.08, 0.0, 0.1], "trim": [0, "c9963a", "", 1.0, 0.22]},
	{"id": "gold", "name": "Gold Rush", "rarity": 3, "felt": Color("0e4a52"), "accent": Color("ffd060"),
		"rail": [0, "d4a23a", "", 1.0, 0.2], "body": [0, "1a1410", "", 0.2, 0.3], "leg": [0, "d4a23a", "", 1.0, 0.22], "trim": [0, "fff0c0", "", 1.0, 0.15]},
	{"id": "neon", "name": "Neon Arcade", "rarity": 3, "felt": Color("2a1a4a"), "felt_fx": 2, "felt2": Color("ff2bd6"), "accent": Color("ff2bd6"), "legs": "tech", "led": 2.6,
		"rail": [0, "0a0c12", "", 0.3, 0.2], "body": [2, "07080c", "29e6ff", 0.3, 0.3, 0.45, 0.16], "leg": [16, "29e6ff", "", 0.0, 0.3, 0.6], "trim": [16, "29e6ff", "", 0.0, 0.2, 0.9]},
	# epic
	{"id": "ice", "name": "Ice Crystal", "rarity": 4, "felt": Color("2a6686"), "felt_fx": 6, "felt2": Color("cfefff"), "accent": Color("9fe0ff"), "legs": "crystal", "led": 2.6,
		"rail": [9, "9fd8ff", "e8f8ff", 0.0, 0.05, 0.7, 0.1], "body": [9, "6fb8e8", "e8f8ff", 0.0, 0.05, 0.6, 0.1], "leg": [9, "9fd8ff", "e8f8ff", 0.0, 0.05, 0.9, 0.1], "trim": [0, "c8ccd4", "", 1.0, 0.18]},
	{"id": "dragon", "name": "Dragon's Hoard", "rarity": 4, "felt": Color("5a1414"), "accent": Color("ffb020"), "legs": "block", "led": 2.6,
		"rail": [4, "8e0f14", "ffb020", 0.6, 0.28, 0.3, 0.1], "body": [4, "3a0808", "ffb020", 0.6, 0.3, 0.3, 0.1], "leg": [4, "8e0f14", "ffb020", 0.6, 0.28, 0.3, 0.1], "trim": [0, "d4a23a", "", 1.0, 0.2]},
	{"id": "sea", "name": "Deep Sea", "rarity": 4, "felt": Color("0e5a6a"), "felt_fx": 4, "felt2": Color("9ff0ff"), "accent": Color("19c8c0"), "legs": "pedestal", "led": 2.6,
		"rail": [8, "0a3a4a", "19c8c0", 0.2, 0.15, 0.0, 0.12], "body": [4, "0a2a3a", "19c8c0", 0.3, 0.3, 0.2, 0.08], "leg": [4, "0a2a3a", "19c8c0", 0.3, 0.3, 0.2, 0.08], "trim": [0, "e8b090", "", 1.0, 0.2]},
	{"id": "holo", "name": "Holo Chrome", "rarity": 4, "felt": Color("3a3a5a"), "accent": Color("ffffff"), "legs": "slab", "led": 2.6,
		"rail": [11, "e8ecf4", "", 0.9, 0.14, 0.3, 0.15], "body": [0, "9aa2b0", "", 1.0, 0.12], "leg": [11, "e8ecf4", "", 0.9, 0.14, 0.3, 0.15], "trim": [0, "ffffff", "", 1.0, 0.1]},
	# legendary
	{"id": "molten", "name": "Molten Forge", "rarity": 5, "felt": Color("4a2016"), "felt_fx": 3, "felt2": Color("ff5a0a"), "accent": Color("ff5a0a"), "legs": "block", "led": 2.6,
		"rail": [5, "1a1412", "ff5a0a", 0.0, 0.85, 2.0, 0.1], "body": [5, "1a1412", "ff5a0a", 0.0, 0.85, 2.4, 0.1], "leg": [5, "1a1412", "ff5a0a", 0.0, 0.85, 2.4, 0.1], "trim": [0, "1a1412", "", 0.6, 0.5]},
	{"id": "galaxy", "name": "Galaxy", "rarity": 5, "felt": Color("1c1c52"), "felt_fx": 1, "felt2": Color("b04bff"), "accent": Color("b388ff"), "legs": "hover", "led": 2.6,
		"rail": [10, "4c8dff", "b04bff", 0.0, 0.1, 1.4, 0.08], "body": [10, "ff4fa3", "4c8dff", 0.0, 0.1, 1.4, 0.08], "leg": [0, "1a1c2a", "", 0.8, 0.25], "trim": [0, "c8ccd4", "", 1.0, 0.18]},
	{"id": "storm", "name": "Thunderstorm", "rarity": 5, "felt": Color("2a3a52"), "accent": Color("9fe0ff"), "legs": "tech", "led": 2.6,
		"rail": [6, "14161e", "9fd0ff", 0.5, 0.25, 2.4, 0.1], "body": [6, "0c0e16", "e8f4ff", 0.5, 0.2, 3.0, 0.1], "leg": [0, "5a6070", "", 1.0, 0.2], "trim": [16, "9fd0ff", "", 0.0, 0.2, 2.0]},
	{"id": "vortex", "name": "Emerald Vortex", "rarity": 5, "felt": Color("0a5a44"), "felt_fx": 7, "felt2": Color("7dffd0"), "accent": Color("2be7a5"), "legs": "hover", "led": 2.6,
		"rail": [19, "04100c", "2be7a5", 0.3, 0.1, 2.2, 0.07], "body": [19, "04100c", "7dffd0", 0.3, 0.1, 2.6, 0.07], "leg": [0, "0a2a20", "", 0.8, 0.2], "trim": [0, "c9963a", "", 1.0, 0.22]},
]

## Ball sets, least exotic first. "rarity" 0 = owned from the start, 1 common ... 5 legendary.
## Sets with "textures" use painted maps; the others are drawn by shaders/ball.gdshader ("style" picks the look).
## "pal" = colours of balls 1-8 (9-15 reuse 1-7 as stripes). Ball size never changes: these are looks only.
const PAL_CLASSIC := ["f4c21b", "1e4cc8", "d3242e", "5a2a8e", "f06a18", "0d7a44", "7c1e22", "111216"]
const PAL_VIVID := ["ffd21f", "2f7bff", "ff2d3f", "a04bff", "ff8a1f", "19d98c", "ff4fa3", "14161c"]
const BALLS := [
	{"id": "balls", "name": "Classic", "rarity": 0, "textures": "balls"},
	{"id": "tournament", "name": "Tournament", "rarity": 1, "style": 0, "pal": ["f5c400", "1f5fe0", "e02b2b", "f06bb0", "f27a1a", "12a150", "9a5b2e", "111216"]},
	{"id": "pastel", "name": "Pastel", "rarity": 1, "style": 0, "pal": ["f2b632", "4d8df0", "f0556a", "9468ee", "f58444", "3fc494", "c9695c", "2b2f3a"], "rough": 0.16},
	{"id": "vintage", "name": "Vintage Ivory", "rarity": 1, "style": 0, "pal": ["d9a441", "2f4f8f", "a63a2e", "5b3a6e", "c8742b", "2e6b4a", "6e2b25", "1a1a1a"], "base": "e9dfc4", "disc": "efe6cf", "ink": "2a1c12", "rough": 0.24, "accent": "a63a2e"},
	{"id": "matte", "name": "Matte Deep", "rarity": 1, "style": 1, "pal": ["b58900", "1d3f8f", "8e1b1b", "3f1f6b", "b4500f", "0b5a34", "5a1414", "0e0e12"], "base": "d9dce2", "accent": "1d3f8f"},
	{"id": "football", "name": "Football Club", "rarity": 1, "style": 24, "pal": PAL_CLASSIC, "base": "f6f6f6", "disc": "ffffff", "accent": "111216"},
	{"id": "pixel", "name": "8-Bit", "rarity": 1, "style": 30, "pal": ["fcd000", "2060f0", "e03030", "9040e0", "f08020", "20c060", "f060a0", "181818"], "base": "f0f0f0", "accent": "20c060"},
	{"id": "tiedye", "name": "Tie-Dye", "rarity": 1, "style": 34, "pal": PAL_VIVID + [], "base": "f6f4f2", "col2": "ff6ad5", "accent": "ff6ad5"},
	{"id": "topo", "name": "Topographic", "rarity": 1, "style": 35, "pal": PAL_CLASSIC, "base": "f2ecdc", "accent": "0d7a44"},
	{"id": "balls_aurora", "name": "Aurora", "rarity": 2, "textures": "balls_aurora"},
	{"id": "marble", "name": "Marble", "rarity": 2, "style": 2, "pal": PAL_CLASSIC, "base": "eeeae2", "col2": "f4f1ea", "rough": 0.07},
	{"id": "wood", "name": "Turned Wood", "rarity": 2, "style": 3, "pal": ["e0a51a", "2a55b8", "c0322c", "6a3a98", "d8701f", "1c7d4b", "7a2a22", "17120e"], "base": "d9b27c", "disc": "f0e2c4", "ink": "2a1a0e", "accent": "7a2a22"},
	{"id": "candy", "name": "Candy Swirl", "rarity": 2, "style": 6, "pal": ["ffcf24", "3a86ff", "ff3355", "b26bff", "ff8c2e", "22d38c", "ff5fa8", "2a2230"], "base": "fff7f2", "accent": "ff3355"},
	{"id": "wild", "name": "Wild Things", "rarity": 2, "style": 25, "pal": ["e8b020", "2460e0", "d42a2a", "8a3ad8", "e87018", "16b06a", "a03a2a", "202228"], "base": "efe6d6", "col2": "1c120a", "accent": "e8b020"},
	{"id": "ink", "name": "Ink Bloom", "rarity": 2, "style": 26, "pal": PAL_VIVID + [], "base": "f4f6fa", "accent": "2f7bff"},
	{"id": "origami", "name": "Origami", "rarity": 2, "style": 29, "pal": ["f5c400", "2f6fd6", "e0303a", "8a4fd0", "f07a20", "20a060", "c0507a", "1c1d22"], "base": "f5f2ea", "accent": "e0303a"},
	{"id": "damascus", "name": "Damascus Steel", "rarity": 2, "style": 33, "pal": PAL_CLASSIC, "base": "c8ccd4", "accent": "1e4cc8"},
	{"id": "midnight", "name": "Midnight Neon", "rarity": 3, "style": 0, "pal": PAL_VIVID, "base": "0d0f16", "disc": "07080c", "ink": "col", "ink_glow": 2.2, "rough": 0.08, "accent": "2be7a5", "cue": "eef1f6"},
	{"id": "carbon", "name": "Carbon Fibre", "rarity": 3, "style": 4, "pal": PAL_VIVID, "base": "1a1b1f", "disc": "f2f3f6", "accent": "2be7a5", "cue": "c9ced8"},
	{"id": "chrome", "name": "Chrome", "rarity": 3, "style": 5, "pal": ["f0c030", "3a78f0", "e83a3a", "9a55e8", "f08a30", "2ac878", "c07048", "30323a"], "base": "d8dce4", "disc": "0c0d10", "ink": "f2f4f8", "accent": "3a78f0"},
	{"id": "planets", "name": "Planets", "rarity": 3, "style": 7, "pal": ["e8b84a", "3b6fd9", "c94b3a", "8a5ad0", "e58a3a", "3fae7c", "b0563a", "2a2d3a"], "base": "e9e4d8", "col2": "fff2d0", "accent": "3b6fd9"},
	{"id": "cathedral", "name": "Cathedral Glass", "rarity": 3, "style": 17, "pal": ["ffc21a", "1f6bff", "ff1f3d", "9b3dff", "ff7a14", "0fd98c", "ff3d9a", "1b1e2a"], "base": "e8eef8", "col2": "ffd76a", "glow": 1.1, "disc": "ffffff", "accent": "1f6bff"},
	{"id": "disco", "name": "Disco Fever", "rarity": 3, "style": 18, "pal": PAL_VIVID + [], "base": "d8dce6", "glow": 1.6, "accent": "ff4fa3"},
	{"id": "circuit", "name": "Circuit Pulse", "rarity": 3, "style": 20, "pal": PAL_VIVID + [], "base": "e8ece4", "col2": "29e6ff", "glow": 1.8, "accent": "2be7a5"},
	{"id": "kintsugi", "name": "Kintsugi", "rarity": 3, "style": 23, "pal": ["d9a62a", "2a58b8", "b8302a", "6a3a98", "d8701f", "2a7a52", "8a3a30", "16161a"], "base": "f2efe6", "col2": "ffb84a", "accent": "2a58b8"},
	{"id": "neon_grid", "name": "Neon Grid", "rarity": 4, "style": 8, "pal": PAL_VIVID + [], "base": "d8e4ff", "disc": "05060a", "ink": "col", "ink_glow": 2.4, "glow": 1.3, "accent": "2be7a5"},
	{"id": "gemstone", "name": "Gemstones", "rarity": 4, "style": 10, "pal": ["ffc21a", "1f6bff", "ff1f3d", "9b3dff", "ff7a14", "0fd98c", "ff3d9a", "1b1e2a"], "base": "eef3ff", "glow": 1.0, "disc": "ffffff", "accent": "0fd98c"},
	{"id": "scales", "name": "Dragon Scale", "rarity": 4, "style": 11, "pal": ["e8b020", "2460e0", "d42a2a", "8a3ad8", "e87018", "16b06a", "a03a2a", "202228"], "base": "c9ced8", "col2": "ffe9a8", "disc": "0d0e12", "ink": "ffe9a8", "accent": "d42a2a"},
	{"id": "galaxy", "name": "Galaxy", "rarity": 4, "style": 9, "pal": PAL_VIVID + [], "base": "cfe0ff", "col2": "ffffff", "disc": "04050a", "ink": "ffffff", "ink_glow": 1.6, "glow": 1.8, "accent": "b388ff"},
	{"id": "opal", "name": "Black Opal", "rarity": 4, "style": 21, "pal": PAL_CLASSIC, "base": "eef0f4", "glow": 1.0, "accent": "4cc9f0"},
	{"id": "abyss", "name": "Abyss Glow", "rarity": 4, "style": 27, "pal": ["ffe14a", "3fb6ff", "ff3d6e", "c06bff", "ff9a3d", "2be7a5", "ff6ad5", "8a96b0"], "base": "dfe8f2", "col2": "7dfff0", "glow": 1.8, "accent": "7dfff0"},
	{"id": "hologram", "name": "Hologram", "rarity": 4, "style": 28, "pal": PAL_VIVID + [], "base": "cfe8ff", "glow": 1.5, "accent": "29e6ff"},
	{"id": "rain", "name": "Digital Rain", "rarity": 4, "style": 32, "pal": PAL_VIVID + [], "base": "e8f0ea", "glow": 1.8, "accent": "19d98c"},
	{"id": "molten", "name": "Molten", "rarity": 5, "style": 12, "pal": ["ffd21f", "3f8cff", "ff3b2f", "c04bff", "ff8a1f", "2be7a5", "ff4fa3", "ff6a00"], "base": "ffe2b0", "col2": "fff2c0", "disc": "0a0808", "ink": "ffd9a0", "ink_glow": 1.8, "glow": 1.7, "accent": "ff6a00"},
	{"id": "gold_enamel", "name": "Gold & Enamel", "rarity": 5, "style": 13, "pal": ["e6a800", "1546c8", "c81e2e", "6a2ab8", "e06a12", "0c8a58", "8a1e2a", "0c0d12"], "base": "f4efe2", "col2": "ffb84a", "disc": "fff6e0", "ink": "3a2408", "accent": "0c8a58"},
	{"id": "storm", "name": "Thunderstorm", "rarity": 5, "style": 14, "pal": PAL_VIVID + [], "base": "dfe8ff", "disc": "05060b", "ink": "eaf2ff", "ink_glow": 1.5, "glow": 2.2, "accent": "4cc9f0"},
	{"id": "vortex", "name": "Emerald Vortex", "rarity": 5, "style": 15, "pal": ["ffd84a", "4c8dff", "ff5c7a", "b388ff", "ff9a4d", "2be7a5", "ff7ac8", "9aa4b8"], "base": "d8fff0", "col2": "0f6b4f", "disc": "030806", "ink": "eafff6", "ink_glow": 1.6, "glow": 2.6, "accent": "2be7a5"},
	{"id": "watchers", "name": "Watchers", "rarity": 5, "style": 16, "pal": PAL_VIVID + [], "base": "f4f1ea", "col2": "ffe9a8", "glow": 1.0, "accent": "2be7a5"},
	{"id": "lavalamp", "name": "Lava Lamp", "rarity": 5, "style": 19, "pal": ["ffcf24", "3a86ff", "ff3355", "b26bff", "ff8c2e", "22d38c", "ff5fa8", "2a1a30"], "base": "f2efe8", "col2": "fff2c0", "glow": 1.5, "accent": "ff8c2e"},
	{"id": "snowglobe", "name": "Snow Globe", "rarity": 5, "style": 22, "pal": PAL_VIVID + [], "base": "f2f6ff", "glow": 0.9, "accent": "4cc9f0"},
	{"id": "fireworks", "name": "Fireworks", "rarity": 5, "style": 31, "pal": PAL_VIVID + [], "base": "e6eaf4", "col2": "ffffff", "glow": 2.2, "accent": "ff4fa3"},
]

## Studio scenes (non-AR backdrop): sky gradient, lamp colour, floor tint.
const SCENES := [
	{"id": "lounge", "name": "Emerald Lounge", "rarity": 0, "sky_top": Color("14233a"), "sky_horizon": Color("2a3f60"), "lamp": Color("fff1d6"), "floor": Color(1, 1, 1)},
	{"id": "neon", "name": "Neon Night", "rarity": 1, "sky_top": Color("120a24"), "sky_horizon": Color("3a1450"), "lamp": Color("ffe0f4"), "floor": Color(0.7, 0.75, 1.0)},
	{"id": "sunset", "name": "Sunset Deck", "rarity": 2, "sky_top": Color("2a3a66"), "sky_horizon": Color("c77a4a"), "lamp": Color("ffe2b8"), "floor": Color(1.1, 0.95, 0.85)},
	# The ten showpiece scenes, from the least to the most exotic.
	#   sky / floor_style: which surroundings and floor the scene shaders draw (backdrop.gdshaderinc, studio_floor.gdshader)
	#   ground: the colour the floor fades into far away; open: the room is a platform and the scene carries on underneath
	#   fx: drifting particles; sun: direction towards the scene's sun or moon; amb: how much the sky lights the table
	#   "ready": false on an entry keeps it out of Settings (for scenes still under review)
	{"id": "desert", "name": "Desert Dusk", "rarity": 1, "sky": 6, "floor_style": 6, "ground": Color(0.42, 0.18, 0.12), "fx": "sand", "shadow": 0.6,
		"lamp": Color(1.0, 0.9, 0.78), "lamp_e": 3.0, "sun": Vector3(0.94, 0.085, -0.33), "sun_col": Color(1.0, 0.72, 0.5), "sun_e": 1.0, "amb": 1.3,
		"sky_top": Color(0.16, 0.1, 0.36), "sky_horizon": Color(0.9, 0.42, 0.2)},
	{"id": "grove", "name": "Firefly Grove", "rarity": 1, "sky": 7, "floor_style": 7, "ground": Color(0.012, 0.045, 0.04), "fx": "fireflies", "shadow": 0.75,
		"lamp": Color(0.95, 1.0, 0.86), "lamp_e": 3.4, "sun": Vector3(0.92, 0.3, 0.25), "sun_col": Color(0.75, 0.95, 0.9), "sun_e": 1.0, "amb": 0.9,
		"sky_top": Color(0.02, 0.09, 0.15), "sky_horizon": Color(0.09, 0.3, 0.27)},
	{"id": "aurora", "name": "Aurora Lake", "rarity": 2, "sky": 2, "floor_style": 2, "ground": Color(0.02, 0.04, 0.07), "fx": "snow", "shadow": 0.7,
		"lamp": Color(0.92, 0.97, 1.0), "lamp_e": 3.4, "sun": Vector3(-0.4, 0.6, 0.3), "sun_col": Color(0.5, 0.9, 0.8), "sun_e": 0.6, "amb": 0.9,
		"sky_top": Color(0.008, 0.02, 0.06), "sky_horizon": Color(0.05, 0.2, 0.2)},
	{"id": "reef", "name": "Coral Deep", "rarity": 2, "sky": 4, "floor_style": 4, "ground": Color(0.03, 0.25, 0.32), "fx": "bubbles", "shadow": 0.7,
		"lamp": Color(0.95, 1.0, 0.98), "lamp_e": 3.3, "sun": Vector3(0.1, 1.0, 0.1), "sun_col": Color(0.6, 0.9, 0.85), "sun_e": 0.6, "amb": 0.45,
		"sky_top": Color(0.06, 0.5, 0.62), "sky_horizon": Color(0.01, 0.17, 0.27)},
	{"id": "skyline", "name": "Neon Skyline", "rarity": 3, "sky": 3, "floor_style": 3, "open": true, "fx": "",
		"lamp": Color(1.0, 0.9, 0.95), "lamp_e": 3.4, "sun": Vector3(0.9, 0.3, -0.35), "sun_col": Color(0.85, 0.65, 1.0), "sun_e": 1.0, "amb": 1.1, "shadow": 0.7,
		"sky_top": Color(0.015, 0.01, 0.05), "sky_horizon": Color(0.42, 0.1, 0.34)},
	{"id": "temple", "name": "Sky Temple", "rarity": 3, "sky": 9, "floor_style": 9, "open": true, "fx": "motes",
		"shadow": 0.6,
		"lamp": Color(1.0, 0.96, 0.9), "lamp_e": 1.9, "sun": Vector3(0.85, 0.15, -0.5), "sun_col": Color(1.0, 0.82, 0.6), "sun_e": 0.9, "amb": 0.6,
		"sky_top": Color(0.32, 0.4, 0.6), "sky_horizon": Color(1.0, 0.76, 0.52)},
	{"id": "cavern", "name": "Crystal Cavern", "rarity": 4, "sky": 8, "floor_style": 8, "ground": Color(0.02, 0.03, 0.06), "fx": "sparkles",
		"lamp": Color(0.85, 0.95, 1.0), "lamp_e": 3.4, "sun": Vector3(0.0, 1.0, 0.0), "sun_col": Color(0.5, 0.7, 1.0), "sun_e": 0.5, "amb": 0.5,
		"sky_top": Color(0.03, 0.05, 0.1), "sky_horizon": Color(0.05, 0.12, 0.2)},
	{"id": "forge", "name": "Magma Forge", "rarity": 4, "sky": 5, "floor_style": 5, "ground": Color(0.035, 0.018, 0.016), "fx": "embers",
		"lamp": Color(1.0, 0.86, 0.7), "lamp_e": 3.3, "sun": Vector3(0.95, 0.4, 0.31), "sun_col": Color(1.0, 0.4, 0.15), "sun_e": 0.9, "amb": 0.6,
		"sky_top": Color(0.03, 0.012, 0.012), "sky_horizon": Color(0.5, 0.12, 0.03)},
	{"id": "synth", "name": "Synth Horizon", "rarity": 5, "sky": 10, "floor_style": 10, "ground": Color(0.3, 0.03, 0.25), "fx": "",
		"lamp": Color(1.0, 0.86, 1.0), "lamp_e": 3.2, "sun": Vector3(1.0, 0.19, 0.0), "sun_col": Color(1.0, 0.4, 0.7), "sun_e": 0.8, "amb": 0.6,
		"sky_top": Color(0.02, 0.0, 0.07), "sky_horizon": Color(0.6, 0.08, 0.45)},
	{"id": "orbit", "name": "Orbit Station", "rarity": 5, "sky": 1, "floor_style": 1, "open": true, "fx": "stardust",
		"lamp": Color(0.85, 0.93, 1.0), "lamp_e": 3.4, "sun": Vector3(0.62, 0.2, -0.75), "sun_col": Color(1.0, 0.95, 0.85), "sun_e": 1.3, "amb": 0.4,
		"sky_top": Color(0.01, 0.015, 0.04), "sky_horizon": Color(0.03, 0.05, 0.12)},
]

## Game modes shown in the menu. Campaign / online multiplayer can be added here later.
const MODES := ["vs_ai", "pass_play", "practice"]




## The list for a kind of gear: "cue", "table", "balls" or "scene".
static func kind_list(kind: String) -> Array:
	match kind:
		"cue": return CUES
		"table": return TABLES
		"balls": return BALLS
	return SCENES


## 0 = everyone has it, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary.
static func rarity(e: Dictionary) -> int:
	return int(e.get("rarity", 0))


static func find(list: Array, id: String) -> Dictionary:
	for e in list:
		if e["id"] == id:
			return e
	return list[0]


static func ids(list: Array) -> Array:
	var out := []
	for e in list:
		out.append(e["id"])
	return out


static func names(list: Array) -> Array:
	var out := []
	for e in list:
		out.append(e["name"])
	return out


static func cue(id: String) -> Dictionary:
	return find(CUES, id)


static func table(id: String) -> Dictionary:
	return find(TABLES, id)


static func ball_set(id: String) -> Dictionary:
	return find(BALLS, id)


static func scene(id: String) -> Dictionary:
	return find(SCENES, id)
