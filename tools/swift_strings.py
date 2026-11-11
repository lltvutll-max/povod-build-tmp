"""Достаёт из App/*.swift строки интерфейса, которые SwiftUI/Foundation ищут в Localizable.xcstrings.

Локализуемые места: String(localized: "…"), String(localized: "key", defaultValue: "…"),
Text("…"), Button("…"), Label("…"), Stepper("…"), TextField("…"), .navigationTitle("…"),
.alert("…"), .confirmationDialog("…"), .accessibilityLabel/Hint(Text("…")) и тернарники внутри них:
Text(x ? "a" : "b"). Интерполяция \\(…) превращается в спецификатор: Int → %lld, остальное → %@
(тип угадываем по выражению, список исключений — INT_EXPR / STR_EXPR ниже).
"""
import re, glob, os

LOCALIZING_CALLS = {"Text", "Button", "Label", "Stepper", "TextField", "Toggle", "navigationTitle", "alert",
                    "confirmationDialog", "accessibilityLabel", "accessibilityHint", "LocalizedStringKey"}

# выражения в \( ), которые точно String (иначе — эвристика ниже)
STR_EXPR = re.compile(r"(name|title|niche|city|email|statusTitle|windowText|address|message|subject|"
                      r"Fmt\.\w+|MailLang\.\w+|companies\(|uppercased\(\)|joined\(|identifier|\?\? \"|"
                      r"^(e|t|text|line|who|why|via|own|cap|count|st|lang|langName|item\.2)$|\.to \?\?)")
INT_EXPR = re.compile(r"(\.count$|^(n|p|i \+ 1|d|\$0|limit|used|lim|sent|failed|dups|active|page \+ 1)$|"
                      r"\.(issued|left|found|power|sent|total|replied|today|errors|added|noEmail|noPhone|toAdd|updated|noMessage|delayDays|unread|replies)$|"
                      r"leadsUsed|min\(|\.count\b|unseenCount|^status$|^total$|duplicates|"
                      r"^(capMax|dailyCap|num|index \+ 1)$|^CampaignLimits\.)")

# переменные, которые в конкретном файле — строки (одно имя бывает Int в одном месте и String в другом)
FILE_STR = {"Folders.swift": {"n"}}


def spec(expr: str, fname: str = "") -> str:
    e = expr.strip()
    if e in FILE_STR.get(fname, set()):
        return "%@"
    if INT_EXPR.search(e) and not re.search(r"Fmt\.|companies\(|String\(", e):
        return "%lld"
    return "%@"


def parse_literals(src: str):
    """[(start, end, parts)] для обычных "…" литералов; parts — список ('s', текст) / ('i', выражение)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("/*", i):
            j = src.find("*/", i); i = n if j < 0 else j + 2; continue
        if c == "#" and src.startswith('#"', i):  # сырые строки (регэкспы) пропускаем
            j = src.find('"#', i + 2); i = n if j < 0 else j + 2; continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3); i = n if j < 0 else j + 3; continue
        if c == '"':
            parts, j = _read_string(src, i + 1)
            out.append((i, j, parts)); i = j; continue
        i += 1
    return out


def _read_string(src, i):
    parts, buf = [], []
    n = len(src)
    while i < n:
        c = src[i]
        if c == "\\":
            nx = src[i + 1]
            if nx == "(":
                if buf: parts.append(("s", "".join(buf))); buf = []
                depth, j = 1, i + 2
                start = j
                while depth and j < n:
                    if src[j] == '"':
                        _, j = _read_string(src, j + 1); continue
                    if src[j] == "(": depth += 1
                    elif src[j] == ")": depth -= 1
                    j += 1
                parts.append(("i", src[start:j - 1])); i = j; continue
            buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "0": "\0"}.get(nx, nx)); i += 2; continue
        if c == '"':
            if buf: parts.append(("s", "".join(buf)))
            return parts, i + 1
        buf.append(c); i += 1
    return parts, i


def enclosing_call(src, pos):
    """Имя функции/модификатора, в чьих скобках стоит литерал (пропуская безымянные скобки тернарника)."""
    depth = 0
    i = pos - 1
    while i >= 0:
        c = src[i]
        if c == '"':  # перескочить предыдущий литерал целиком — грубо: идём до предыдущей кавычки
            j = src.rfind('"', 0, i)
            i = j - 1 if j >= 0 else -1; continue
        if c == ")": depth += 1
        elif c == "(":
            if depth == 0:
                m = re.search(r"([A-Za-z_]\w*)\s*$", src[:i])
                name = m.group(1) if m else ""
                if name and name not in ("if", "return"):
                    return name, src[i + 1:pos]
            else:
                depth -= 1
        elif c in "{}" and depth == 0:
            return "", ""
        i -= 1
    return "", ""


def _current_arg(inside):
    """Текст текущего аргумента вызова: после последней запятой верхнего уровня."""
    depth, last, i, n = 0, 0, 0, len(inside)
    while i < n:
        c = inside[i]
        if c == '"':
            _, i = _read_string(inside, i + 1); continue
        if c in "([{": depth += 1
        elif c in ")]}": depth -= 1
        elif c == "," and depth == 0: last = i + 1
        i += 1
    return inside[last:]


def key_of(parts, fname=""):
    k = []
    for t, v in parts:
        k.append(v.replace("%", "%%") if t == "s" else spec(v, fname))
    return "".join(k)


def extract(app_dir):
    found = {}  # key -> list of "file:line"
    for f in sorted(glob.glob(os.path.join(app_dir, "*.swift"))):
        if f.endswith("Fixture.swift"):
            continue
        src = open(f, encoding="utf-8").read()
        for (s, e, parts) in parse_literals(src):
            text = "".join(v for t, v in parts if t == "s")
            if not re.search(r"[A-Za-zА-Яа-яЁё]", text):
                continue
            before = src[max(0, s - 40):s]
            line = src.count("\n", 0, s) + 1
            where = f"{os.path.basename(f)}:{line}"
            m = re.search(r'String\(localized:\s*"([^"]+)",\s*defaultValue:\s*$', src[max(0, s - 120):s])
            if m:
                found.setdefault(m.group(1), []).append(where + " default=" + key_of(parts, os.path.basename(f))); continue
            if re.search(r"String\(localized:\s*$", before):
                found.setdefault(key_of(parts, os.path.basename(f)), []).append(where); continue
            name, inside = enclosing_call(src, s)
            if name == "String" and "localized:" in inside:
                continue  # ключ String(localized: "key", defaultValue:) — сам ключ
            if re.search(r"[A-Za-z_]\w*:\s*$", before) and not re.search(r"named:\s*$", before):
                continue  # аргумент с меткой (systemImage:, role: …) — не заголовок
            arg = _current_arg(inside)
            m2 = re.match(r"\s*([A-Za-z_]\w*)\s*:(?!:)", arg)
            if m2 and m2.group(1) != "named":
                continue  # литерал внутри аргумента с меткой (systemImage: x ? "a" : "b")
            if name in LOCALIZING_CALLS:
                # Text(x ? "a" : "b") — только если литерал — сама ветка, а не аргумент вложенного вызова
                found.setdefault(key_of(parts, os.path.basename(f)), []).append(where)
    return found


if __name__ == "__main__":
    import sys, json
    app = sys.argv[1] if len(sys.argv) > 1 else "App"
    res = extract(app)
    print(json.dumps(res, ensure_ascii=False, indent=1))
