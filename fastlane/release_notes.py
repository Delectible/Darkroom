"""Lays out the store "What's new" notes in fastlane/whatsnew/<play lang>.txt
for fastlane: Play (supply's changelogs) or the App Store (deliver's
release_notes.txt). One source for both stores; rules in docs/STORES.md.

Usage: python3 -I fastlane/release_notes.py OUT_DIR play
       python3 -I fastlane/release_notes.py OUT_DIR apple EN_CODE
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'whatsnew')

# Play's language code -> App Store Connect's (as fastlane/apple_listing.py)
APPLE = {
    'es-ES': 'es-ES', 'es-419': 'es-MX', 'pt-BR': 'pt-BR', 'fr-FR': 'fr-FR',
    'de-DE': 'de-DE', 'it-IT': 'it', 'ja-JP': 'ja', 'ko-KR': 'ko',
    'zh-CN': 'zh-Hans', 'id': 'id', 'tr-TR': 'tr', 'ru-RU': 'ru', 'hi-IN': 'hi',
    'ar': 'ar-SA', 'vi': 'vi', 'th': 'th', 'pl-PL': 'pl', 'nl-NL': 'nl-NL', 'uk': 'uk',
}


def main():
    out, store = sys.argv[1], sys.argv[2]
    for name in sorted(os.listdir(SRC)):
        lang = name[:-4]
        with open(os.path.join(SRC, name), encoding='utf-8') as f:
            text = f.read().strip()
        if store == 'play':
            if len(text) > 500:
                sys.exit(f'{lang}: over Play\'s 500 characters')
            dst = os.path.join(out, lang, 'changelogs')
            file = 'default.txt'
        else:
            code = sys.argv[3] if lang.startswith('en') else APPLE.get(lang)
            if code is None:
                sys.exit(f'No App Store language for {lang}')
            dst = os.path.join(out, code)
            file = 'release_notes.txt'
        os.makedirs(dst, exist_ok=True)
        with open(os.path.join(dst, file), 'w', encoding='utf-8') as f:
            f.write(text + '\n')
        print(lang, len(text))


main()
