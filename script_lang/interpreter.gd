extends RefCounted
## Executes AST with async steps so the player can see each action.

signal log_line(text: String)
signal finished(ok: bool, message: String)

const _MAX_STEPS := 20000
const _MAX_WHILE := 5000
const _MAX_FOR_ITEMS := 10000

var farm: FarmState
var drone: DroneActor
var farm_view: FarmView
var host: Node
## Optional: shared dict with keys hay, wheat, carrot (ints); incremented on harvest.
var harvest_counts: Dictionary = {}

var step_delay: float = 0.11
var cancelled: bool = false

var _steps: int = 0


func stop() -> void:
	cancelled = true


func run_program(ast: Dictionary) -> void:
	cancelled = false
	_steps = 0
	if ast.get("error"):
		finished.emit(false, str(ast.message))
		return
	var scope: Dictionary = _root_scope()
	var r: Array = await _exec_block(ast.body, scope, false)
	if cancelled:
		finished.emit(false, "Stopped.")
		return
	if _is_err_tag(r):
		finished.emit(false, str(r[1]))
		return
	finished.emit(true, "Done.")


func _root_scope() -> Dictionary:
	return {
		"Entities": {"WHEAT": "wheat", "CARROT": "carrot", "HAY": FarmState.HAY_ID},
		"Grounds": {"GRASS": "grass", "SOIL": "soil"},
		# Same idea as TFWR-style direction constants (pass to move())
		"North": "north",
		"South": "south",
		"East": "east",
		"West": "west",
	}


## First element must be a String before comparing — user arrays e.g. [0,1,2] must not use == with "err".
func _stmt_head(v: Variant) -> String:
	if not (v is Array):
		return ""
	var a: Array = v
	if a.is_empty():
		return ""
	var h: Variant = a[0]
	if h is String:
		return h
	return ""


func _is_err_tag(v: Variant) -> bool:
	return _stmt_head(v) == "err"


func _await_step() -> void:
	if cancelled:
		return
	_steps += 1
	if _steps > _MAX_STEPS:
		cancelled = true
		return
	if host != null and is_instance_valid(host):
		await host.get_tree().create_timer(step_delay).timeout
	if farm_view != null:
		farm_view.queue_redraw()


func _exec_block(stmts: Array, scope: Dictionary, in_loop: bool) -> Array:
	for st in stmts:
		if cancelled:
			return ["ok"]
		var r: Array = await _exec_stmt(st, scope, in_loop)
		var rh: String = _stmt_head(r)
		if rh == "break":
			return r
		if rh == "return":
			return r
		if _is_err_tag(r):
			return r
	return ["ok"]


func _exec_stmt(st: Dictionary, scope: Dictionary, in_loop: bool) -> Array:
	var t: String = st.type
	match t:
		"assign":
			var tgt = st.target
			if tgt.parts.size() != 1:
				return ["err", "assignment only supports simple names (line %d)" % st.line]
			var rhs: Variant = await _eval(st.expr, scope)
			if _is_err_tag(rhs):
				return rhs
			scope[str(tgt.parts[0])] = rhs
			return ["ok"]
		"expr":
			var v: Variant = await _eval(st.expr, scope)
			if _is_err_tag(v):
				return v
			return ["ok"]
		"if":
			var cond: Variant = await _eval(st.cond, scope)
			if _is_err_tag(cond):
				return cond
			if _truthy(cond):
				return await _exec_block(st.body, scope, in_loop)
			return ["ok"]
		"while":
			var guard := 0
			while true:
				if cancelled:
					return ["ok"]
				guard += 1
				if guard > _MAX_WHILE:
					return ["err", "while loop exceeded safety limit"]
				var c: Variant = await _eval(st.cond, scope)
				if _is_err_tag(c):
					return c
				if not _truthy(c):
					break
				var wr: Array = await _exec_block(st.body, scope, true)
				var wh: String = _stmt_head(wr)
				if wh == "break":
					break
				if wh == "return":
					return wr
				if _is_err_tag(wr):
					return wr
			return ["ok"]
		"for":
			var seq: Variant = await _eval(st.iter, scope)
			if _is_err_tag(seq):
				return seq
			if not (seq is Array):
				return ["err", "for ... in needs range(...) or another list"]
			var items: Array = seq
			if items.size() > _MAX_FOR_ITEMS:
				return ["err", "for loop iterable too large"]
			for item in items:
				if cancelled:
					return ["ok"]
				scope[st.var] = item
				var fr: Array = await _exec_block(st.body, scope, true)
				var fh: String = _stmt_head(fr)
				if fh == "break":
					break
				if fh == "return":
					return fr
				if _is_err_tag(fr):
					return fr
			return ["ok"]
		"def":
			scope[st.name] = {"userfunc": true, "body": st.body}
			return ["ok"]
		"break":
			if not in_loop:
				return ["err", "break outside loop (line %d)" % st.line]
			return ["break"]
		"return":
			return ["return", st.expr]
	return ["err", "unknown statement"]


func _range_values(args: Array) -> Variant:
	if args.is_empty() or args.size() > 3:
		return ["err", "range() expects 1 to 3 integers"]
	var start := 0
	var stop := 0
	var step := 1
	if args.size() == 1:
		stop = int(args[0])
	elif args.size() == 2:
		start = int(args[0])
		stop = int(args[1])
	else:
		start = int(args[0])
		stop = int(args[1])
		step = int(args[2])
	if step == 0:
		return ["err", "range() step must not be zero"]
	var out: Array = []
	var i: int = start
	if step > 0:
		while i < stop:
			if out.size() >= _MAX_FOR_ITEMS:
				return ["err", "range() result too large"]
			out.append(i)
			i += step
	else:
		while i > stop:
			if out.size() >= _MAX_FOR_ITEMS:
				return ["err", "range() result too large"]
			out.append(i)
			i += step
	return out


func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0
	if v is String:
		return v != ""
	return v != null


func _eval(node: Variant, scope: Dictionary) -> Variant:
	if not (node is Dictionary):
		return ["err", "internal eval error"]
	var k: String = str(node.get("kind", ""))
	if k == "":
		return ["err", "invalid expression"]
	match k:
		"lit":
			return node.value
		"name":
			return _resolve_name(node.name, scope)
		"attr":
			var b: Variant = await _eval(node.base, scope)
			if _is_err_tag(b):
				return b
			if b is Dictionary:
				if b.has(node.field):
					return b[node.field]
				return ["err", "unknown key '%s'" % node.field]
			return ["err", "cannot access attribute on this value"]
		"call":
			return await _eval_call(node, scope)
		"bin":
			return await _eval_bin(node, scope)
		"un":
			return await _eval_un(node, scope)
	return ["err", "invalid expression"]


func _resolve_name(n: String, scope: Dictionary) -> Variant:
	if scope.has(n):
		return scope[n]
	if n == "True":
		return true
	if n == "False":
		return false
	return ["err", "unknown name '%s'" % n]


func _eval_bin(node: Dictionary, scope: Dictionary) -> Variant:
	var op: String = node.op
	if op == "and":
		var L: Variant = await _eval(node.left, scope)
		if _is_err_tag(L):
			return L
		if not _truthy(L):
			return false
		var R: Variant = await _eval(node.right, scope)
		if _is_err_tag(R):
			return R
		return _truthy(R)
	if op == "or":
		var L2: Variant = await _eval(node.left, scope)
		if _is_err_tag(L2):
			return L2
		if _truthy(L2):
			return true
		var R2: Variant = await _eval(node.right, scope)
		if _is_err_tag(R2):
			return R2
		return _truthy(R2)

	var L3: Variant = await _eval(node.left, scope)
	if _is_err_tag(L3):
		return L3
	var R3: Variant = await _eval(node.right, scope)
	if _is_err_tag(R3):
		return R3
	match op:
		"==":
			return _eq_values(L3, R3)
		"!=":
			return not _eq_values(L3, R3)
		"<", ">", "<=", ">=":
			return _compare_ordered(L3, R3, op)
		"+":
			return L3 + R3
		"-":
			return L3 - R3
		"*":
			return L3 * R3
		"/":
			if R3 == 0:
				return ["err", "division by zero"]
			return L3 / R3
	return ["err", "bad operator"]


## Python-like == : different types (e.g. int vs str) → false, never a GDScript type error.
func _eq_values(a: Variant, b: Variant) -> bool:
	if a is int and b is float:
		return float(a) == b
	if a is float and b is int:
		return a == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


func _compare_ordered(a: Variant, b: Variant, op: String) -> Variant:
	var na: bool = a is int or a is float
	var nb: bool = b is int or b is float
	if na and nb:
		var fa: float = float(a)
		var fb: float = float(b)
		match op:
			"<":
				return fa < fb
			">":
				return fa > fb
			"<=":
				return fa <= fb
			">=":
				return fa >= fb
	if typeof(a) != typeof(b):
		return ["err", "cannot compare these types (use matching types or numbers)"]
	match op:
		"<":
			return a < b
		">":
			return a > b
		"<=":
			return a <= b
		">=":
			return a >= b
	return ["err", "bad comparison"]


func _eval_un(node: Dictionary, scope: Dictionary) -> Variant:
	var e: Variant = await _eval(node.expr, scope)
	if _is_err_tag(e):
		return e
	match node.op:
		"not":
			return not _truthy(e)
		"-":
			return -e
	return ["err", "bad unary op"]


func _eval_call(node: Dictionary, scope: Dictionary) -> Variant:
	var fn = node.func
	var args: Array = []
	for a in node.args:
		var v: Variant = await _eval(a, scope)
		if _is_err_tag(v):
			return v
		args.append(v)

	if fn.get("kind") == "name":
		var nm: String = fn.name
		match nm:
			"move":
				if args.size() != 1:
					return ["err", "move() needs one string"]
				drone.move_dir(str(args[0]))
				if farm_view:
					farm_view.set_drone_cell(drone.grid_pos)
				await _await_step()
				if cancelled:
					return null
				return null
			"harvest":
				if args.size() != 0:
					return ["err", "harvest() takes no arguments"]
				var got: String = farm.harvest_at(drone.grid_pos)
				if got != "":
					_record_harvest(got)
				if farm_view:
					farm_view.queue_redraw()
				await _await_step()
				if cancelled:
					return null
				return got
			"plant":
				if args.size() != 1:
					return ["err", "plant() needs one entity"]
				var ok: bool = farm.plant_at(drone.grid_pos, str(args[0]))
				if farm_view:
					farm_view.queue_redraw()
				await _await_step()
				if cancelled:
					return null
				return ok
			"till":
				if args.size() != 0:
					return ["err", "till() takes no arguments"]
				farm.till_at(drone.grid_pos)
				if farm_view:
					farm_view.queue_redraw()
				await _await_step()
				if cancelled:
					return null
				return null
			"reset":
				if args.size() != 0:
					return ["err", "reset() takes no arguments"]
				farm.reset_to_default()
				drone.snap_to_start()
				if farm_view:
					farm_view.set_drone_cell(drone.grid_pos)
					farm_view.queue_redraw()
				return null
			"can_harvest":
				if args.size() != 0:
					return ["err", "can_harvest() takes no arguments"]
				return farm.can_harvest_at(drone.grid_pos)
			"get_ground":
				if args.size() != 0:
					return ["err", "get_ground() takes no arguments"]
				return farm.get_ground_at(drone.grid_pos)
			"log":
				if args.size() != 1:
					return ["err", "log() needs one value"]
				log_line.emit(str(args[0]))
				return null
			"get_world_size":
				if args.size() != 0:
					return ["err", "get_world_size() takes no arguments"]
				if farm == null:
					return ["err", "no farm"]
				return farm.width
			"range":
				return _range_values(args)
			_:
				pass

		if scope.has(nm):
			var u = scope[nm]
			if u is Dictionary and u.get("userfunc"):
				var inner: Dictionary = scope.duplicate()
				var r: Array = await _exec_block(u.body, inner, false)
				if _stmt_head(r) == "return":
					if r.size() > 1 and r[1] != null:
						return await _eval(r[1], inner)
					return null
				if _is_err_tag(r):
					return r
				return null
			return ["err", "'%s' is not callable" % nm]

	return ["err", "only simple calls like move('north') are supported here"]


func _record_harvest(item: String) -> void:
	if item == "":
		return
	if harvest_counts.is_empty():
		return
	if harvest_counts.has(item):
		harvest_counts[item] = int(harvest_counts[item]) + 1
