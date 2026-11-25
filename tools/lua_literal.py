"""Reads Lua files that only set tables to plain values, such as the spawn
database's db/*.lua (`pfDB["units"]["data"] = { ... }`), without running
them: a downloaded file is data, so nothing in it is ever executed.

    from lua_literal import load_assignments
    pfDB = load_assignments(["db/units.lua", "db/enUS/units.lua"])
    pfDB["units"]["data"][12696]["coords"][1]   # { 1: 73.8, 2: 61.5, ... }

Tables come back as `Table`, a dict that answers None for a missing key, as
a Lua table does. A list part is keyed 1, 2, 3 ..., as in Lua. Only
strings, numbers, true, false, nil and tables are read; anything else (a
call, an operator, a variable) stops the read with an error.
"""

import re

TOKEN = re.compile(r"""
    \s+ | --\[\[.*?\]\] | --[^\n]*
  | (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<sym>[{}\[\]=,;])
""", re.VERBOSE | re.DOTALL)

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a",
           "b": "\b", "f": "\f", "v": "\v"}


class Table(dict):
    """A Lua table: a missing key reads as None."""

    def __missing__(self, key):
        return None


def _string(text):
    body, out, i = text[1:-1], [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1] if i + 1 < len(body) else ""
        if nxt.isdigit():
            digits = re.match(r"\d{1,3}", body[i + 1:]).group(0)
            out.append(chr(int(digits)))
            i += 1 + len(digits)
        else:
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
    return "".join(out)


def _number(text):
    if text.lower().lstrip("-").startswith("0x"):
        return int(text, 16)
    value = float(text)
    return int(value) if value.is_integer() and not re.search(r"[.eE]", text) else value


def tokens(text):
    pos, end = 0, len(text)
    while pos < end:
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"cannot read at character {pos}: {text[pos:pos + 40]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)


class _Reader:
    def __init__(self, text):
        self.items = list(tokens(text))
        self.i = 0

    def peek(self, ahead=0):
        j = self.i + ahead
        return self.items[j] if j < len(self.items) else (None, None)

    def take(self, want=None):
        tok = self.peek()
        if want is not None and tok[1] != want:
            raise ValueError(f"expected {want!r}, found {tok[1]!r}")
        self.i += 1
        return tok

    def value(self):
        kind, text = self.take()
        if kind == "str":
            return _string(text)
        if kind == "num":
            return _number(text)
        if kind == "name" and text in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[text]
        if text == "{":
            return self.table()
        raise ValueError(f"not a plain value: {text!r}")

    def table(self):
        out, n = Table(), 0
        while self.peek()[1] != "}":
            kind, text = self.peek()
            if text == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                value = self.value()
            elif kind == "name" and self.peek(1)[1] == "=":
                self.take()
                self.take("=")
                key, value = text, self.value()
            else:
                n += 1
                key, value = n, self.value()
            if value is not None:
                out[key] = value
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return out


def load_assignments(paths, into=None):
    """Read each file's `name["a"]["b"] = { ... }` lines into one table
    (`into`, or a new one), keyed by the bracketed names after the first."""
    root = into if into is not None else Table()
    for path in paths:
        with open(path, encoding="utf-8") as f:
            reader = _Reader(f.read())
        while reader.peek()[0] is not None:
            kind, _ = reader.take()
            if kind != "name":
                raise ValueError(f"{path}: expected a name to set")
            keys = []
            while reader.peek()[1] == "[":
                reader.take("[")
                keys.append(reader.value())
                reader.take("]")
            reader.take("=")
            value = reader.value()
            if not keys:
                raise ValueError(f"{path}: only table fields are set")
            node = root
            for key in keys[:-1]:
                if node[key] is None:
                    node[key] = Table()
                node = node[key]
            node[keys[-1]] = value
    return root


def load_returned_table(path):
    """The table a file hands back from a long string that holds
    `return { ... }`, as a quest database keeps its rows
    (`QuestieDB.questData = [[return { ... }]]`)."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    start = text.find("[[return")
    if start < 0:
        raise ValueError(f"{path}: no [[return {{ ... }}]] in it")
    body = text[start + len("[[return"):text.rfind("]]")]
    reader = _Reader(body)
    reader.take("{")
    return reader.table()
