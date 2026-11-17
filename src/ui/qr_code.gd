class_name QrCode
extends RefCounted
## v1.1.15: QR codes made on the phone (the share popup's "QR code": a friend scans it with their phone's camera).
## Byte mode, error correction M (about 15% of the code can be dirty or covered), versions 1 to 10 (up to 213
## characters, far more than the game's link). A port of the reference algorithm (ISO/IEC 18004; after Project
## Nayuki's qrcodegen, MIT licence).

# error correction level M: codewords per block and number of blocks, versions 1..10 (index 0 unused)
const ECC_PER_BLOCK := [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const BLOCKS := [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const FORMAT_M := 0        # the two format bits of level M

var version := 1
var size := 21
var modules: Array = []     # [y][x] true = dark
var _func: Array = []       # [y][x] true = part of a fixed pattern


## The code for `text` (UTF-8), or null when it is too long.
static func make(text: String) -> QrCode:
	var data := text.to_utf8_buffer()
	for v in range(1, 11):
		var cap_bits := _data_codewords(v) * 8
		var need := 4 + (8 if v < 10 else 16) + data.size() * 8
		if need <= cap_bits:
			var q := QrCode.new()
			q._build(v, data)
			return q
	return null


static func _raw_modules(v: int) -> int:
	var r := (16 * v + 128) * v + 64
	if v >= 2:
		var na := v / 7 + 2
		r -= (25 * na - 10) * na - 55
		if v >= 7:
			r -= 36
	return r


static func _data_codewords(v: int) -> int:
	return _raw_modules(v) / 8 - ECC_PER_BLOCK[v] * BLOCKS[v]


func _build(v: int, data: PackedByteArray) -> void:
	version = v
	size = v * 4 + 17
	modules = []
	_func = []
	for y in size:
		var row := []
		var frow := []
		row.resize(size)
		frow.resize(size)
		row.fill(false)
		frow.fill(false)
		modules.append(row)
		_func.append(frow)
	# the bits: mode (byte), length, the bytes, end, padding
	var bits: Array[int] = []
	_put(bits, 4, 4)
	_put(bits, data.size(), 8 if v < 10 else 16)
	for b in data:
		_put(bits, b, 8)
	var cap := _data_codewords(v) * 8
	_put(bits, 0, mini(4, cap - bits.size()))
	_put(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < cap:
		_put(bits, pad, 8)
		pad ^= 0xEC ^ 0x11
	var words := PackedByteArray()
	words.resize(bits.size() / 8)
	for i in bits.size():
		words[i >> 3] |= bits[i] << (7 - (i & 7))
	_draw_fixed()
	_draw_codewords(_with_ecc(words))
	# the mask that leaves the fewest confusing patterns
	var best := 0
	var best_pen := 1 << 30
	for m in 8:
		_apply_mask(m)
		_draw_format(m)
		var pen := _penalty()
		if pen < best_pen:
			best_pen = pen
			best = m
		_apply_mask(m)       # (undo: masking twice is no mask)
	_apply_mask(best)
	_draw_format(best)


static func _put(bits: Array[int], val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)


func _set_fn(x: int, y: int, dark: bool) -> void:
	modules[y][x] = dark
	_func[y][x] = true


func _draw_fixed() -> void:
	for i in size:
		_set_fn(6, i, i % 2 == 0)
		_set_fn(i, 6, i % 2 == 0)
	for c in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c.x + dx
				var y: int = c.y + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var d := maxi(absi(dx), absi(dy))
					_set_fn(x, y, d != 2 and d != 4)
	var pos := _align_positions()
	var na := pos.size()
	for i in na:
		for j in na:
			if (i == 0 and j == 0) or (i == 0 and j == na - 1) or (i == na - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_fn(pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format(0)
	if version >= 7:
		var rem := version
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var b := (version << 12) | rem
		for i in 18:
			var bit := ((b >> i) & 1) != 0
			var a := size - 11 + i % 3
			var c2 := i / 3
			_set_fn(a, c2, bit)
			_set_fn(c2, a, bit)


func _align_positions() -> Array[int]:
	var out: Array[int] = []
	if version == 1:
		return out
	var na := version / 7 + 2
	var step := (version * 4 + na * 2 + 1) / (na * 2 - 2) * 2
	out.append(6)
	var p := size - 7
	while out.size() < na:
		out.insert(1, p)
		p -= step
	return out


func _draw_format(mask: int) -> void:
	var data := (FORMAT_M << 3) | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var b := ((data << 10) | rem) ^ 0x5412
	var bit := func(i: int) -> bool: return ((b >> i) & 1) != 0
	for i in 6:
		_set_fn(8, i, bit.call(i))
	_set_fn(8, 7, bit.call(6))
	_set_fn(8, 8, bit.call(7))
	_set_fn(7, 8, bit.call(8))
	for i in range(9, 15):
		_set_fn(14 - i, 8, bit.call(i))
	for i in 8:
		_set_fn(size - 1 - i, 8, bit.call(i))
	for i in range(8, 15):
		_set_fn(8, size - 15 + i, bit.call(i))
	_set_fn(8, size - 8, true)


func _with_ecc(data: PackedByteArray) -> PackedByteArray:
	var nb: int = BLOCKS[version]
	var ecc_len: int = ECC_PER_BLOCK[version]
	var raw := _raw_modules(version) / 8
	var n_short := nb - raw % nb
	var short_len := raw / nb
	var div := _rs_divisor(ecc_len)
	var blocks: Array = []
	var k := 0
	for i in nb:
		var n := short_len - ecc_len + (0 if i < n_short else 1)
		var dat := data.slice(k, k + n)
		k += n
		var ecc := _rs_remainder(dat, div)
		if i < n_short:
			dat.append(0)
		dat.append_array(ecc)
		blocks.append(dat)
	var out := PackedByteArray()
	for i in (blocks[0] as PackedByteArray).size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= n_short:
				out.append((blocks[j] as PackedByteArray)[i])
	return out


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _rs_divisor(degree: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(degree)
	r[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			r[j] = _gf_mul(r[j], root)
			if j + 1 < degree:
				r[j] ^= r[j + 1]
		root = _gf_mul(root, 0x02)
	return r


static func _rs_remainder(data: PackedByteArray, div: PackedByteArray) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(div.size())
	for b in data:
		var f := b ^ r[0]
		r.remove_at(0)
		r.append(0)
		for i in div.size():
			r[i] ^= _gf_mul(div[i], f)
	return r


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var up := ((right + 1) & 2) == 0
				var y := size - 1 - vert if up else vert
				if not _func[y][x] and i < data.size() * 8:
					modules[y][x] = ((data[i >> 3] >> (7 - (i & 7))) & 1) != 0
					i += 1
		right -= 2


func _apply_mask(m: int) -> void:
	for y in size:
		for x in size:
			if _func[y][x]:
				continue
			var inv := false
			match m:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				modules[y][x] = not modules[y][x]


## The standard's penalty score: long runs, 2×2 blocks, finder-like patterns, and too much dark or light.
func _penalty() -> int:
	var p := 0
	var dark := 0
	for pass_no in 2:
		for a in size:
			var run := 0
			var last := false
			var line := []
			for b in size:
				var v: bool = modules[a][b] if pass_no == 0 else modules[b][a]
				line.append(v)
				if pass_no == 0 and v:
					dark += 1
				if b > 0 and v == last:
					run += 1
				else:
					if run >= 5:
						p += 3 + run - 5
					run = 1
				last = v
			if run >= 5:
				p += 3 + run - 5
			# 1:1:3:1:1 with four light modules on a side
			for b in range(0, size - 6):
				if line[b] and not line[b + 1] and line[b + 2] and line[b + 3] and line[b + 4] and not line[b + 5] and line[b + 6]:
					var before: bool = b >= 4 and not (line[b - 1] or line[b - 2] or line[b - 3] or line[b - 4])
					var after: bool = b + 10 < size and not (line[b + 7] or line[b + 8] or line[b + 9] or line[b + 10])
					if before or after:
						p += 40
	for y in size - 1:
		for x in size - 1:
			var c: bool = modules[y][x]
			if c == modules[y][x + 1] and c == modules[y + 1][x] and c == modules[y + 1][x + 1]:
				p += 3
	var total := size * size
	var k := int(ceil(absf(dark * 20.0 - total * 10.0) / total)) - 1
	p += maxi(k, 0) * 10
	return p


## The code as a picture: `scale` pixels a module, a light border four modules wide (as scanners need).
func image(scale := 8, dark := Color("0b1220"), light := Color.WHITE) -> Image:
	var border := 4
	var n := (size + border * 2) * scale
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(light)
	for y in size:
		for x in size:
			if modules[y][x]:
				img.fill_rect(Rect2i((x + border) * scale, (y + border) * scale, scale, scale), dark)
	return img


func texture(scale := 8) -> ImageTexture:
	return ImageTexture.create_from_image(image(scale))
