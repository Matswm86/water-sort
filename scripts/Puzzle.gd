class_name Puzzle
extends RefCounted

## Pure puzzle rules: level generation, pour legality and a solver.
## A tube is an Array of color ids, bottom first. Every tube holds CAP units.

const CAP := 4
const MAX_COLORS := 12


static func colors_for(level: int) -> int:
	if level <= 1:
		return 2
	if level == 2:
		return 3
	return mini(MAX_COLORS, 4 + (level - 3) / 3)


static func empties_for(level: int) -> int:
	return 1 if level <= 2 else 2


## Deterministic per level: the same level number always gives the same puzzle.
static func generate(level: int) -> Array:
	var colors := colors_for(level)
	var empties := empties_for(level)
	var rng := RandomNumberGenerator.new()
	for attempt in range(200):
		rng.seed = level * 7919 + attempt * 104729 + 12345
		var pool: Array = []
		for c in range(colors):
			for k in range(CAP):
				pool.append(c)
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		var tubes: Array = []
		for c in range(colors):
			tubes.append(pool.slice(c * CAP, (c + 1) * CAP))
		for e in range(empties):
			tubes.append([])
		if _has_complete_tube(tubes):
			continue
		if solve(tubes) != null:
			return tubes
	push_error("Puzzle.generate: no solvable layout for level %d" % level)
	return []


static func _has_complete_tube(tubes: Array) -> bool:
	for t in tubes:
		if is_complete(t):
			return true
	return false


static func is_complete(tube: Array) -> bool:
	if tube.size() != CAP:
		return false
	for c in tube:
		if c != tube[0]:
			return false
	return true


static func is_solved(tubes: Array) -> bool:
	for t in tubes:
		if not t.is_empty() and not is_complete(t):
			return false
	return true


static func top_run(tube: Array) -> int:
	if tube.is_empty():
		return 0
	var n := 1
	var top: int = tube.back()
	for i in range(tube.size() - 2, -1, -1):
		if tube[i] != top:
			break
		n += 1
	return n


static func can_pour(tubes: Array, from: int, to: int) -> bool:
	if from == to:
		return false
	var src: Array = tubes[from]
	var dst: Array = tubes[to]
	if src.is_empty() or dst.size() >= CAP:
		return false
	return dst.is_empty() or dst.back() == src.back()


## Units that move when pouring from -> to (0 when the pour is illegal).
static func pour_amount(tubes: Array, from: int, to: int) -> int:
	if not can_pour(tubes, from, to):
		return 0
	return mini(top_run(tubes[from]), CAP - tubes[to].size())


## Returns the list of [from, to] moves that solves the puzzle, or null.
static func solve(tubes: Array, limit: int = 40000) -> Variant:
	var work: Array = tubes.duplicate(true)
	var seen := {}
	var path: Array = []
	if _dfs(work, seen, path, limit):
		return path
	return null


static func _key(tubes: Array) -> String:
	var parts: PackedStringArray = []
	for t in tubes:
		parts.append(",".join(PackedStringArray(t.map(func(c): return str(c)))))
	parts.sort()
	return "|".join(parts)


static func _dfs(tubes: Array, seen: Dictionary, path: Array, limit: int) -> bool:
	if is_solved(tubes):
		return true
	if seen.size() > limit:
		return false
	var key := _key(tubes)
	if seen.has(key):
		return false
	seen[key] = true
	# Pass 0 pours onto matching colors, pass 1 into the first empty tube only.
	for pass_no in range(2):
		for i in range(tubes.size()):
			var src: Array = tubes[i]
			if src.is_empty() or is_complete(src):
				continue
			var first_empty_seen := false
			for j in range(tubes.size()):
				if not can_pour(tubes, i, j):
					continue
				var dst_empty: bool = tubes[j].is_empty()
				if dst_empty != (pass_no == 1):
					continue
				if dst_empty:
					if first_empty_seen or top_run(src) == src.size():
						continue
					first_empty_seen = true
				var n := pour_amount(tubes, i, j)
				for k in range(n):
					tubes[j].append(tubes[i].pop_back())
				path.append([i, j])
				if _dfs(tubes, seen, path, limit):
					return true
				path.pop_back()
				for k in range(n):
					tubes[i].append(tubes[j].pop_back())
	return false
