#!/usr/bin/env python3
"""Собирает Support/Localization/{en,ru,uk}.lproj/Localizable.strings из scripts/l10n/strings.tsv
и проверяет, что все строки интерфейса в коде есть в таблице.

Запуск из корня проекта:  python3 scripts/l10n/generate.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TABLE = ROOT / "scripts/l10n/strings.tsv"
OUT = ROOT / "Support/Localization"


def escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


rows = []
for n, line in enumerate(TABLE.read_text(encoding="utf-8").splitlines(), 1):
    if not line.strip() or line.startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        sys.exit(f"strings.tsv:{n}: ожидалось 3 колонки, получено {len(parts)}")
    rows.append(parts)

keys = [r[0] for r in rows]
dupes = {k for k in keys if keys.count(k) > 1}
if dupes:
    sys.exit(f"Дубликаты ключей: {sorted(dupes)}")

for lang, col in (("en", 0), ("ru", 1), ("uk", 2)):
    d = OUT / f"{lang}.lproj"
    d.mkdir(parents=True, exist_ok=True)
    body = "/* Сгенерировано scripts/l10n/generate.py из strings.tsv — не редактировать вручную. */\n\n"
    body += "".join(f'"{escape(r[0])}" = "{escape(r[col])}";\n' for r in rows)
    (d / "Localizable.strings").write_text(body, encoding="utf-8")

# Проверка: кириллица в строковых литералах исходников приложения (кроме комментариев и логов)
# — признак непереведённой строки интерфейса. Исключение — строка с меткой `// l10n-ignore`.
problems = []
for path in sorted((ROOT / "Sources").rglob("*.swift")):
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if "l10n-ignore" in line:  # намеренно не переводимая строка
            continue
        code = line.split("//", 1)[0]
        if "NSLog(" in code:
            continue
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', code):
            if re.search(r"[А-Яа-яЁёІіЇїЄєҐґ]", lit):
                problems.append(f"{path.relative_to(ROOT)}:{n}: {lit}")

print(f"Строк в таблице: {len(rows)}; файлы: {', '.join(p.name for p in sorted(OUT.iterdir()))}")
if problems:
    print("Кириллица в литералах (непереведённые строки?):")
    print("\n".join("  " + p for p in problems))
    sys.exit(1)
print("Непереведённых строк в коде не найдено.")
