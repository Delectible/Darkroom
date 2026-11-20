"""Builds the App Store listing folders (fastlane deliver's layout) from the
Play listing in fastlane/metadata/android: one source for both stores.

Usage: python3 -I tool/store/apple_listing.py OUT_DIR [lang ...]
Only the languages given (Play codes); never English (kept by the owner in
App Store Connect). The subtitle is the Play tagline, or apple_subtitle.txt
where that's over Apple's 30 characters.
"""
import os
import sys

# Play's language code -> App Store Connect's
APPLE = {
    'es-ES': 'es-ES', 'es-419': 'es-MX', 'pt-BR': 'pt-BR', 'fr-FR': 'fr-FR',
    'de-DE': 'de-DE', 'it-IT': 'it', 'ja-JP': 'ja', 'ko-KR': 'ko',
    'zh-CN': 'zh-Hans', 'id': 'id', 'tr-TR': 'tr', 'ru-RU': 'ru', 'hi-IN': 'hi',
    'ar': 'ar-SA', 'vi': 'vi', 'th': 'th', 'pl-PL': 'pl', 'nl-NL': 'nl-NL', 'uk': 'uk',
}

SRC = 'fastlane/metadata/android'


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read().strip()


def main():
    out, langs = sys.argv[1], sys.argv[2:] or sorted(APPLE)
    for lang in langs:
        if lang not in APPLE:
            sys.exit(f'No App Store language for {lang}')
        src = os.path.join(SRC, lang)
        sub = os.path.join(src, 'apple_subtitle.txt')
        subtitle = read(sub) if os.path.exists(sub) else read(os.path.join(src, 'short_description.txt'))
        if len(subtitle) > 30:
            sys.exit(f'{lang}: subtitle over 30 characters: {subtitle}')
        dst = os.path.join(out, APPLE[lang])
        os.makedirs(dst, exist_ok=True)
        for name, text in [
            ('name.txt', read(os.path.join(src, 'title.txt'))),
            ('subtitle.txt', subtitle),
            ('description.txt', read(os.path.join(src, 'full_description.txt'))),
        ]:
            with open(os.path.join(dst, name), 'w', encoding='utf-8') as f:
                f.write(text + '\n')
        print(f'{lang} -> {APPLE[lang]}: {subtitle}')


main()
