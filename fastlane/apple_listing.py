"""Builds the App Store listing folders (fastlane deliver's layout) from the
Play listing in fastlane/metadata/android: one source for both stores.

Usage: python3 -I fastlane/apple_listing.py OUT_DIR [lang ...]
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


def english_support_url():
    """The support URL on the owner's English listing (App Store Connect),
    copied to every language (Apple requires one each). Needs ASC_KEY,
    ASC_KEY_ID, ASC_ISSUER and PyJWT; None without them."""
    try:
        import json, time, urllib.request
        import jwt
        now = int(time.time())
        token = jwt.encode({'iss': os.environ['ASC_ISSUER'], 'iat': now, 'exp': now + 1100,
                            'aud': 'appstoreconnect-v1'}, os.environ['ASC_KEY'], algorithm='ES256',
                           headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})

        def get(url):
            req = urllib.request.Request('https://api.appstoreconnect.apple.com' + url,
                                         headers={'Authorization': f'Bearer {token}'})
            with urllib.request.urlopen(req) as r:
                return json.load(r)

        app = get('/v1/apps?filter[bundleId]=com.dingo.darkroom')['data'][0]['id']
        for v in get(f'/v1/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=5')['data']:
            for loc in get(f'/v1/appStoreVersions/{v["id"]}/appStoreVersionLocalizations?limit=50')['data']:
                a = loc['attributes']
                if a['locale'].startswith('en') and a.get('supportUrl'):
                    return a['supportUrl']
    except Exception as e:
        print(f'(no support URL from App Store Connect: {e})', file=sys.stderr)
    return None


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read().strip()


def main():
    out, langs = sys.argv[1], sys.argv[2:] or sorted(APPLE)
    support = english_support_url()
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
            ('keywords.txt', read(os.path.join(src, 'apple_keywords.txt'))),
        ] + ([('support_url.txt', support)] if support else []):
            with open(os.path.join(dst, name), 'w', encoding='utf-8') as f:
                f.write(text + '\n')
        print(f'{lang} -> {APPLE[lang]}: {subtitle}')


main()
