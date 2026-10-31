#!/usr/bin/env python3
"""Rebuilds Scachs/Localizable.xcstrings from tools/translations.json.
Run after a build: lists any key the compiler extracted that has no translation yet."""
import glob, json, pathlib, plistlib
root = pathlib.Path(__file__).parent.parent
T = json.load(open(root / 'tools/translations.json'))
keys = set()
for f in glob.glob(str(root / 'build/dd/**/*.stringsdata'), recursive=True):
    b = open(f, 'rb').read()
    try: d = json.loads(b)
    except Exception:
        try: d = plistlib.loads(b)
        except Exception: continue
    for table, entries in d.get('tables', {}).items():
        if table in ('Localizable', ''):
            keys |= {e['key'] for e in entries if e.get('key')}
missing = sorted(keys - set(T))
strings = {}
for k in sorted(set(T) | keys):
    loc = {}
    for lang in ('es', 'en'):
        if k in T and T[k].get(lang):
            loc[lang] = {'stringUnit': {'state': 'translated', 'value': T[k][lang]}}
    strings[k] = {'extractionState': 'manual', 'localizations': loc} if loc else {'extractionState': 'manual'}
out = {'sourceLanguage': 'ca', 'strings': strings, 'version': '1.0'}
(root / 'Scachs/Localizable.xcstrings').write_text(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True))
print(len(strings), 'strings;', len(missing), 'without translation')
for m in missing: print('  ', repr(m))
