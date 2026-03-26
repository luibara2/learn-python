extends RefCounted
## Builds a small AST from tokenizer output.

const TT := {
	"IDENT": "ident",
	"STR": "str",
	"NUM": "num",
	"NEWLINE": "newline",
	"INDENT": "indent",
	"DEDENT": "dedent",
	"OP": "op",
	"LPAREN": "(",
	"RPAREN": ")",
	"COLON": ":",
	"COMMA": ",",
	"DOT": ".",
	"EOF": "eof",
}

var _toks: Array = []
var _i: int = 0


func parse(tokens: Array) -> Variant:
	if tokens.is_empty():
		return _fail("empty program", 1)
	if tokens[0].get("error", false):
		return tokens[0]
	_toks = tokens
	_i = 0
	var body: Array = []
	while not _eof():
		if _match_t(TT.NEWLINE):
			continue
		if _peek_t() == TT.EOF:
			break
		var st = _parse_stmt()
		if st is Dictionary and st.get("error"):
			return st
		body.append(st)
		_match_t(TT.NEWLINE)
	return {"type": "program", "body": body}


func _fail(msg: String, line: int) -> Dictionary:
	return {"error": true, "message": msg, "line": line}


func _peek() -> Dictionary:
	return _toks[_i]


func _peek_t() -> String:
	return _toks[_i].t


func _peek_v() -> Variant:
	return _toks[_i].v


func _line() -> int:
	return _toks[_i].line


func _eof() -> bool:
	return _peek_t() == TT.EOF


func _advance() -> void:
	if not _eof():
		_i += 1


func _match_t(tt: String) -> bool:
	if _peek_t() == tt:
		_advance()
		return true
	return false


func _expect_t(tt: String) -> Variant:
	if _peek_t() != tt:
		return _fail("expected %s, got %s" % [tt, _peek_t()], _line())
	_advance()
	return null


func _parse_stmt() -> Variant:
	if _peek_t() == TT.IDENT:
		var w: String = str(_peek_v())
		if w == "if":
			return _parse_if()
		if w == "while":
			return _parse_while()
		if w == "for":
			return _parse_for()
		if w == "def":
			return _parse_def()
		if w == "break":
			_advance()
			return {"type": "break", "line": _line()}
		if w == "return":
			_advance()
			if _peek_t() == TT.NEWLINE or _peek_t() == TT.EOF:
				return {"type": "return", "expr": null, "line": _line()}
			var ex = _parse_expr()
			if ex is Dictionary and ex.get("error"):
				return ex
			return {"type": "return", "expr": ex, "line": _line()}

	var save := _i
	if _peek_t() == TT.IDENT:
		var stmt_line := _line()
		var nm = _parse_lvalue()
		if nm is Dictionary and nm.get("error"):
			return nm
		if _peek_t() == TT.OP and str(_peek_v()) == "=":
			_advance()
			var rhs = _parse_expr()
			if rhs is Dictionary and rhs.get("error"):
				return rhs
			return {"type": "assign", "target": nm, "expr": rhs, "line": stmt_line}
		_i = save

	var ex_line := _line()
	var ex2 = _parse_expr()
	if ex2 is Dictionary and ex2.get("error"):
		return ex2
	return {"type": "expr", "expr": ex2, "line": ex_line}


func _parse_lvalue() -> Variant:
	if _peek_t() != TT.IDENT:
		return _fail("expected name", _line())
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(_peek_v()))
	_advance()
	while _match_t(TT.DOT):
		if _peek_t() != TT.IDENT:
			return _fail("expected attribute name", _line())
		parts.append(str(_peek_v()))
		_advance()
	return {"parts": parts}


func _parse_if() -> Variant:
	_advance()
	var cond = _parse_expr()
	if cond is Dictionary and cond.get("error"):
		return cond
	var e = _expect_t(TT.COLON)
	if e != null:
		return e
	if not _match_t(TT.NEWLINE):
		return _fail("expected newline after ':'", _line())
	if not _match_t(TT.INDENT):
		return _fail("expected indented block", _line())
	var body = _parse_block()
	if body is Dictionary and body.get("error"):
		return body
	if not _match_t(TT.DEDENT):
		return _fail("expected end of block", _line())
	return {"type": "if", "cond": cond, "body": body}


func _parse_while() -> Variant:
	_advance()
	var cond = _parse_expr()
	if cond is Dictionary and cond.get("error"):
		return cond
	var e2 = _expect_t(TT.COLON)
	if e2 != null:
		return e2
	if not _match_t(TT.NEWLINE):
		return _fail("expected newline after ':'", _line())
	if not _match_t(TT.INDENT):
		return _fail("expected indented block", _line())
	var body = _parse_block()
	if body is Dictionary and body.get("error"):
		return body
	if not _match_t(TT.DEDENT):
		return _fail("expected end of block", _line())
	return {"type": "while", "cond": cond, "body": body}


func _parse_for() -> Variant:
	_advance()
	if _peek_t() != TT.IDENT:
		return _fail("expected loop variable after 'for'", _line())
	var vname: String = str(_peek_v())
	_advance()
	if _peek_t() != TT.IDENT or str(_peek_v()) != "in":
		return _fail("expected 'in' after loop variable", _line())
	_advance()
	var iterexpr = _parse_expr()
	if iterexpr is Dictionary and iterexpr.get("error"):
		return iterexpr
	var ef = _expect_t(TT.COLON)
	if ef != null:
		return ef
	if not _match_t(TT.NEWLINE):
		return _fail("expected newline after ':'", _line())
	if not _match_t(TT.INDENT):
		return _fail("expected indented block", _line())
	var body = _parse_block()
	if body is Dictionary and body.get("error"):
		return body
	if not _match_t(TT.DEDENT):
		return _fail("expected end of block", _line())
	return {"type": "for", "var": vname, "iter": iterexpr, "body": body}


func _parse_def() -> Variant:
	_advance()
	if _peek_t() != TT.IDENT:
		return _fail("expected function name", _line())
	var fname: String = str(_peek_v())
	_advance()
	var e3 = _expect_t(TT.LPAREN)
	if e3 != null:
		return e3
	var e4 = _expect_t(TT.RPAREN)
	if e4 != null:
		return e4
	var e5 = _expect_t(TT.COLON)
	if e5 != null:
		return e5
	if not _match_t(TT.NEWLINE):
		return _fail("expected newline after ':'", _line())
	if not _match_t(TT.INDENT):
		return _fail("expected indented block", _line())
	var body = _parse_block()
	if body is Dictionary and body.get("error"):
		return body
	if not _match_t(TT.DEDENT):
		return _fail("expected end of block", _line())
	return {"type": "def", "name": fname, "body": body}


func _parse_block() -> Variant:
	var stmts: Array = []
	while not _eof() and _peek_t() != TT.DEDENT:
		if _match_t(TT.NEWLINE):
			continue
		var st = _parse_stmt()
		if st is Dictionary and st.get("error"):
			return st
		stmts.append(st)
		_match_t(TT.NEWLINE)
	return stmts


func _parse_expr() -> Variant:
	return _parse_or()


func _parse_or() -> Variant:
	var left = _parse_and()
	if left is Dictionary and left.get("error"):
		return left
	while _peek_t() == TT.OP and str(_peek_v()) == "or":
		_advance()
		var right = _parse_and()
		if right is Dictionary and right.get("error"):
			return right
		left = {"kind": "bin", "op": "or", "left": left, "right": right}
	return left


func _parse_and() -> Variant:
	var left = _parse_not()
	if left is Dictionary and left.get("error"):
		return left
	while _peek_t() == TT.OP and str(_peek_v()) == "and":
		_advance()
		var right = _parse_not()
		if right is Dictionary and right.get("error"):
			return right
		left = {"kind": "bin", "op": "and", "left": left, "right": right}
	return left


func _parse_not() -> Variant:
	if _peek_t() == TT.OP and str(_peek_v()) == "not":
		_advance()
		var inner = _parse_not()
		if inner is Dictionary and inner.get("error"):
			return inner
		return {"kind": "un", "op": "not", "expr": inner}
	return _parse_cmp()


func _parse_cmp() -> Variant:
	var left = _parse_add()
	if left is Dictionary and left.get("error"):
		return left
	while _peek_t() == TT.OP:
		var op := str(_peek_v())
		if op == "==" or op == "!=" or op == "<" or op == ">" or op == "<=" or op == ">=":
			_advance()
			var right = _parse_add()
			if right is Dictionary and right.get("error"):
				return right
			left = {"kind": "bin", "op": op, "left": left, "right": right}
		else:
			break
	return left


func _parse_add() -> Variant:
	var left = _parse_mul()
	if left is Dictionary and left.get("error"):
		return left
	while _peek_t() == TT.OP:
		var op := str(_peek_v())
		if op == "+" or op == "-":
			_advance()
			var right = _parse_mul()
			if right is Dictionary and right.get("error"):
				return right
			left = {"kind": "bin", "op": op, "left": left, "right": right}
		else:
			break
	return left


func _parse_mul() -> Variant:
	var left = _parse_unary()
	if left is Dictionary and left.get("error"):
		return left
	while _peek_t() == TT.OP:
		var op := str(_peek_v())
		if op == "*" or op == "/":
			_advance()
			var right = _parse_unary()
			if right is Dictionary and right.get("error"):
				return right
			left = {"kind": "bin", "op": op, "left": left, "right": right}
		else:
			break
	return left


func _parse_unary() -> Variant:
	if _peek_t() == TT.OP and str(_peek_v()) == "-":
		_advance()
		var inner = _parse_unary()
		if inner is Dictionary and inner.get("error"):
			return inner
		return {"kind": "un", "op": "-", "expr": inner}
	return _parse_postfix()


func _parse_postfix() -> Variant:
	var node = _parse_primary()
	if node is Dictionary and node.get("error"):
		return node
	while true:
		if _match_t(TT.DOT):
			if _peek_t() != TT.IDENT:
				return _fail("expected name after '.'", _line())
			var field: String = str(_peek_v())
			_advance()
			node = {"kind": "attr", "base": node, "field": field}
			continue
		if _peek_t() == TT.LPAREN:
			_advance()
			var args: Array = []
			if _peek_t() != TT.RPAREN:
				while true:
					var arg = _parse_expr()
					if arg is Dictionary and arg.get("error"):
						return arg
					args.append(arg)
					if _match_t(TT.COMMA):
						continue
					break
			var er = _expect_t(TT.RPAREN)
			if er != null:
				return er
			node = {"kind": "call", "func": node, "args": args}
			continue
		break
	return node


func _parse_primary() -> Variant:
	if _peek_t() == TT.NUM:
		var v = _peek_v()
		_advance()
		return {"kind": "lit", "value": v}
	if _peek_t() == TT.STR:
		var s = _peek_v()
		_advance()
		return {"kind": "lit", "value": s}
	if _peek_t() == TT.IDENT:
		var id = str(_peek_v())
		_advance()
		if id == "True":
			return {"kind": "lit", "value": true}
		if id == "False":
			return {"kind": "lit", "value": false}
		return {"kind": "name", "name": id}
	if _match_t(TT.LPAREN):
		var inner = _parse_expr()
		if inner is Dictionary and inner.get("error"):
			return inner
		var er2 = _expect_t(TT.RPAREN)
		if er2 != null:
			return er2
		return inner
	return _fail("expected value", _line())
