extends RefCounted
## Produces a flat token list with indent/dedent like Python.

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


func tokenize(source: String) -> Array:
	var raw_lines: PackedStringArray = source.split("\n")
	var indent_stack: Array[int] = [0]
	var out: Array = []
	var line_no := 1

	for raw in raw_lines:
		var line: String = raw
		var expanded := ""
		for ch in line:
			if ch == "\t":
				expanded += "    "
			else:
				expanded += ch
		line = expanded

		var content_start := 0
		while content_start < line.length() and line[content_start] == " ":
			content_start += 1

		var is_blank := true
		for i in range(content_start, line.length()):
			if line[i] != " " and line[i] != "\r":
				is_blank = false
				break
		if is_blank:
			line_no += 1
			continue

		var indent := content_start
		var body := line.substr(content_start).strip_edges()

		if body.begins_with("#"):
			line_no += 1
			continue

		while indent < indent_stack.back():
			indent_stack.pop_back()
			out.append(_tok(TT.DEDENT, "", line_no))

		if indent > indent_stack.back():
			indent_stack.append(indent)
			out.append(_tok(TT.INDENT, "", line_no))
		elif indent != indent_stack.back():
			return [_err("indentation does not match any outer level", line_no)]

		var scanned: Variant = _scan_line(body, line_no)
		if scanned is Dictionary:
			return [scanned]
		out.append_array(scanned as Array)
		out.append(_tok(TT.NEWLINE, "", line_no))
		line_no += 1

	while indent_stack.size() > 1:
		indent_stack.pop_back()
		out.append(_tok(TT.DEDENT, "", line_no))

	out.append(_tok(TT.EOF, "", line_no))
	return out


func _err(msg: String, line: int) -> Dictionary:
	return {"error": true, "message": msg, "line": line}


func _tok(type: String, value: Variant, line: int) -> Dictionary:
	return {"t": type, "v": value, "line": line}


func _scan_line(body: String, line_no: int) -> Variant:
	var out: Array = []
	var i := 0
	var n := body.length()
	while i < n:
		var c := body[i]
		if c == " ":
			i += 1
			continue

		if c == "#":
			break

		if c == "(":
			out.append(_tok(TT.LPAREN, "", line_no))
			i += 1
			continue
		if c == ")":
			out.append(_tok(TT.RPAREN, "", line_no))
			i += 1
			continue
		if c == ":":
			out.append(_tok(TT.COLON, "", line_no))
			i += 1
			continue
		if c == ",":
			out.append(_tok(TT.COMMA, "", line_no))
			i += 1
			continue
		if c == ".":
			out.append(_tok(TT.DOT, "", line_no))
			i += 1
			continue

		if c == '"' or c == "'":
			var q := c
			i += 1
			var s := ""
			while i < n and body[i] != q:
				if body[i] == "\\" and i + 1 < n:
					i += 1
					match body[i]:
						"n":
							s += "\n"
						"t":
							s += "\t"
						_:
							s += body[i]
				else:
					s += body[i]
				i += 1
			if i >= n:
				return _err("unterminated string", line_no)
			i += 1
			out.append(_tok(TT.STR, s, line_no))
			continue

		if c.is_valid_int():
			var j := i
			while j < n and body[j].is_valid_int():
				j += 1
			out.append(_tok(TT.NUM, int(body.substr(i, j - i)), line_no))
			i = j
			continue

		if c.is_valid_identifier():
			var j := i
			while j < n:
				var ch := body[j]
				if ch.is_valid_identifier() or ch.is_valid_int():
					j += 1
				else:
					break
			var word := body.substr(i, j - i)
			i = j
			if word == "and" or word == "or" or word == "not":
				out.append(_tok(TT.OP, word, line_no))
			elif word == "True" or word == "False":
				out.append(_tok(TT.IDENT, word, line_no))
			else:
				out.append(_tok(TT.IDENT, word, line_no))
			continue

		if i + 1 < n:
			var two := body.substr(i, 2)
			if two == "==" or two == "!=" or two == "<=" or two == ">=":
				out.append(_tok(TT.OP, two, line_no))
				i += 2
				continue
		if c == "=" or c == "<" or c == ">":
			out.append(_tok(TT.OP, c, line_no))
			i += 1
			continue

		return _err("unexpected character: %s" % c, line_no)

	return out
