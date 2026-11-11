#!/usr/bin/env python3
"""Добавить / обновить строки в App/Localizable.xcstrings (или App/InfoPlist.xcstrings с --infoplist).

    python3 tools/xcstrings-add.py new-strings.json
    python3 tools/xcstrings-add.py --infoplist plist-strings.json

new-strings.json:
{
  "удалить %lld писем?": {                       ← ключ = русский текст из кода (\\(n) → %lld, строка → %@)
    "ru": {"one": "удалить %lld письмо?", "few": "удалить %lld письма?", "many": "удалить %lld писем?", "other": "удалить %lld письма?"},
    "en": {"one": "delete %lld email?", "other": "delete %lld emails?"},
    "de": "…", "fr": "…", "es": "…", "pt": "…", "it": "…", "pl": {"one": "…", "few": "…", "many": "…", "other": "…"}
  },
  "сохранено": {"ru": "сохранено", "en": "saved", ...}
}
Значение — строка (обычный перевод) или объект форм множественного числа (plural).
Если "ru" не указан, берётся сам ключ. После — обязательно python3 tools/check-xcstrings.py.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def loc(v):
    if isinstance(v, dict):
        return {"variations": {"plural": {form: unit(text) for form, text in v.items()}}}
    return unit(v)


def write_catalog(path, data):
    text = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    with open(path, "w", encoding="utf-8") as f:
        f.write(text + "\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__); sys.exit(2)
    name = "InfoPlist.xcstrings" if "--infoplist" in sys.argv else "Localizable.xcstrings"
    path = os.path.join(ROOT, "App", name)
    data = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {"sourceLanguage": "ru", "strings": {}, "version": "1.0"}
    new = json.load(open(args[0], encoding="utf-8"))
    for key, langs in new.items():
        entry = data["strings"].setdefault(key, {})
        locs = entry.setdefault("localizations", {})
        if "ru" not in langs:
            langs = dict(langs, ru=key)
        for lang, v in langs.items():
            if lang.startswith("_"):
                continue
            if v in ("", None):
                continue
            locs[lang] = loc(v)
    write_catalog(path, data)
    print(f"{name}: {len(new)} ключей добавлено/обновлено, всего {len(data['strings'])}")


if __name__ == "__main__":
    main()
