#!/usr/bin/env python3
"""Проверка переводов Повода: App/Localizable.xcstrings и App/InfoPlist.xcstrings.

    python3 tools/check-xcstrings.py            # из корня репозитория
    python3 tools/check-xcstrings.py --missing  # + шаблон JSON для недостающих ключей (для tools/xcstrings-add.py)

Ошибка (код выхода 1), если:
  - файл не JSON или sourceLanguage не ru;
  - у ключа нет перевода на любой из 8 языков (ru en de fr es pt it pl) или он пустой / не translated;
  - спецификаторы (%@, %lld, %d, %%) в переводе не совпадают с ключом по количеству и порядку;
  - у plural не хватает форм (ru/pl: one few many other; остальные: one other);
  - строка интерфейса есть в коде App/*.swift, а в каталоге её нет (ищет tools/swift_strings.py);
  - ключа из InfoPlist.xcstrings нет в Resources/Info.plist.
Предупреждение — ключ есть в каталоге, но в коде не найден (устаревший).
"""
import json, os, re, sys, plistlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import swift_strings  # noqa: E402

LANGS = ["ru", "en", "de", "fr", "es", "pt", "it", "pl"]
PLURAL_FORMS = {"ru": {"one", "few", "many", "other"}, "pl": {"one", "few", "many", "other"}}
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f|%)")

errors, warnings = [], []


def specs(s):
    return [m.group(0) for m in SPEC.finditer(s)]


def unit_values(loc):
    """Все тексты локализации: [(форма, текст, state)]."""
    out = []
    if "stringUnit" in loc:
        u = loc["stringUnit"]
        out.append(("", u.get("value", ""), u.get("state", "")))
    for kind, forms in loc.get("variations", {}).items():
        for form, v in forms.items():
            u = v.get("stringUnit", {})
            out.append((f"{kind}.{form}", u.get("value", ""), u.get("state", "")))
    return out


def check_catalog(path, code_keys=None, plist_keys=None):
    name = os.path.basename(path)
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        errors.append(f"{name}: не JSON — {e}")
        return {}
    if data.get("sourceLanguage") != "ru":
        errors.append(f"{name}: sourceLanguage = {data.get('sourceLanguage')!r}, нужно 'ru'")
    strings = data.get("strings", {})
    for key, entry in strings.items():
        locs = entry.get("localizations", {})
        ru_vals = unit_values(locs.get("ru", {}))
        # эталон спецификаторов: сам ключ, а для технических ключей (logo.povod, CFBundle…) — русский текст
        ref = specs(key) if (SPEC.search(key) or not ru_vals) else specs(ru_vals[0][1])
        for lang in LANGS:
            if lang not in locs:
                errors.append(f"{name}: [{lang}] нет перевода: {key!r}")
                continue
            vals = unit_values(locs[lang])
            if not vals:
                errors.append(f"{name}: [{lang}] пусто: {key!r}")
                continue
            plural = locs[lang].get("variations", {}).get("plural")
            if plural is not None:
                need = PLURAL_FORMS.get(lang, {"one", "other"})
                have = set(plural)
                if not need <= have:
                    errors.append(f"{name}: [{lang}] plural без форм {sorted(need - have)}: {key!r}")
            for form, text, state in vals:
                if not text.strip():
                    errors.append(f"{name}: [{lang}{'.' + form if form else ''}] пустой текст: {key!r}")
                if state not in ("translated", ""):
                    errors.append(f"{name}: [{lang}] state={state}: {key!r}")
                got = specs(text)
                # в plural-форме «one» число можно не писать («один отзыв») — тогда спецификатор может отсутствовать
                if got != ref and not (form.endswith(".one") and got == [s for s in ref if s != "%lld"]):
                    errors.append(f"{name}: [{lang}{'.' + form if form else ''}] спецификаторы {got} ≠ {ref}: {key!r} → {text!r}")
    if code_keys is not None:
        for k, where in code_keys.items():
            if k not in strings:
                errors.append(f"{name}: нет ключа из кода {k!r} ({where[0]})")
        for k in strings:
            if k not in code_keys:
                warnings.append(f"{name}: в коде не найден (устарел?) {k!r}")
    if plist_keys is not None:
        for k in strings:
            if k not in plist_keys:
                errors.append(f"{name}: ключа {k!r} нет в Resources/Info.plist")
    return strings


def main():
    os.chdir(ROOT)
    code = swift_strings.extract(os.path.join(ROOT, "App"))
    loc = check_catalog(os.path.join(ROOT, "App", "Localizable.xcstrings"), code_keys=code)
    with open(os.path.join(ROOT, "Resources", "Info.plist"), "rb") as f:
        plist = plistlib.load(f)
    check_catalog(os.path.join(ROOT, "App", "InfoPlist.xcstrings"), plist_keys=set(plist))
    if sorted(plist.get("CFBundleLocalizations", [])) != sorted(LANGS):
        errors.append(f"Info.plist: CFBundleLocalizations = {plist.get('CFBundleLocalizations')} — нужно 8 языков {LANGS}")
    for w in warnings:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"ключей в Localizable: {len(loc)}, строк в коде: {len(code)}, языков: {len(LANGS)}, ошибок: {len(errors)}, предупреждений: {len(warnings)}")
    if "--missing" in sys.argv:
        miss = {k: {"ru": k, "en": "", "de": "", "fr": "", "es": "", "pt": "", "it": "", "pl": ""} for k in code if k not in loc}
        print(json.dumps(miss, ensure_ascii=False, indent=1))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
