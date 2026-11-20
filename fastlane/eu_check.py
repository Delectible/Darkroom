"""Read-only: is Darkroom, and Darkroom Pro (darkroom_pro), on sale in the
European countries? Asks both stores; changes nothing.

Env: PLAY_JSON (service account file), ASC_KEY / ASC_KEY_ID / ASC_ISSUER.
Trader status (the EU's Digital Services Act) isn't in either API: the
owner checks that in each console.
"""
import json
import os
import time
import urllib.request

EU = {  # EU + EEA + UK + Switzerland: ISO alpha-2 -> alpha-3 (Apple uses alpha-3)
    'AT': 'AUT', 'BE': 'BEL', 'BG': 'BGR', 'HR': 'HRV', 'CY': 'CYP', 'CZ': 'CZE', 'DK': 'DNK',
    'EE': 'EST', 'FI': 'FIN', 'FR': 'FRA', 'DE': 'DEU', 'GR': 'GRC', 'HU': 'HUN', 'IE': 'IRL',
    'IT': 'ITA', 'LV': 'LVA', 'LT': 'LTU', 'LU': 'LUX', 'MT': 'MLT', 'NL': 'NLD', 'PL': 'POL',
    'PT': 'PRT', 'RO': 'ROU', 'SK': 'SVK', 'SI': 'SVN', 'ES': 'ESP', 'SE': 'SWE',
    'IS': 'ISL', 'LI': 'LIE', 'NO': 'NOR', 'GB': 'GBR', 'CH': 'CHE',
}
PKG, BUNDLE, PRODUCT = 'com.dingo.darkroom', 'com.dingo.darkroom', 'darkroom_pro'


def get(url, token):
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def report(store, what, have):
    missing = sorted(c for c in EU if c not in have)
    print(f'{store} {what}: {len(EU) - len(missing)}/{len(EU)} European countries')
    if missing:
        print(f'  missing: {" ".join(missing)}')


def play():
    from google.oauth2 import service_account
    import google.auth.transport.requests
    creds = service_account.Credentials.from_service_account_file(
        os.environ['PLAY_JSON'], scopes=['https://www.googleapis.com/auth/androidpublisher'])
    creds.refresh(google.auth.transport.requests.Request())
    base = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'
    try:
        p = get(f'{base}/inappproducts/{PRODUCT}', creds.token)
        have = set((p.get('prices') or {}).keys())
        print(f'Play Pro: status {p.get("status")}, default {p.get("defaultPrice")}')
        report('Play', 'Pro prices', have)
    except Exception as e:  # newer one-time products live elsewhere
        print(f'Play inappproducts: {e}')
        try:
            p = get(f'{base}/onetimeproducts/{PRODUCT}', creds.token)
            have = set()
            for opt in p.get('purchaseOptions', []):
                for r in opt.get('regionalPricingAndAvailabilityConfigs', []):
                    if r.get('availability', 'AVAILABLE') == 'AVAILABLE':
                        have.add(r.get('regionCode'))
            report('Play', 'Pro available', have)
        except Exception as e2:
            print(f'Play onetimeproducts: {e2}')
    print('Play app: country availability is per track in the Play Console '
          '(Production > Countries / regions); not readable here.')


def apple():
    import jwt
    now = int(time.time())
    token = jwt.encode({'iss': os.environ['ASC_ISSUER'], 'iat': now, 'exp': now + 1100,
                        'aud': 'appstoreconnect-v1'}, os.environ['ASC_KEY'], algorithm='ES256',
                       headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})
    api = 'https://api.appstoreconnect.apple.com'
    app = get(f'{api}/v1/apps?filter[bundleId]={BUNDLE}', token)['data'][0]['id']
    try:
        av = get(f'{api}/v1/apps/{app}/appAvailabilityV2', token)['data']['id']
        rows = get(f'{api}/v2/appAvailabilities/{av}/territoryAvailabilities?limit=200&include=territory', token)
        have3 = {r['relationships']['territory']['data']['id'] for r in rows['data']
                 if r['attributes'].get('available')}
        report('App Store', 'app', {c for c, a3 in EU.items() if a3 in have3})
    except Exception as e:
        print(f'App Store app availability: {e}')
    try:
        iaps = get(f'{api}/v1/apps/{app}/inAppPurchasesV2?filter[productId]={PRODUCT}', token)['data']
        iap = iaps[0]['id']
        print(f'App Store Pro: state {iaps[0]["attributes"].get("state")}')
        av = get(f'{api}/v2/inAppPurchases/{iap}/inAppPurchaseAvailability', token)['data']['id']
        rows = get(f'{api}/v1/inAppPurchaseAvailabilities/{av}/availableTerritories?limit=200', token)
        have3 = {r['id'] for r in rows['data']}
        report('App Store', 'Pro', {c for c, a3 in EU.items() if a3 in have3})
    except Exception as e:
        print(f'App Store Pro availability: {e}')


for f in (play, apple):
    try:
        f()
    except Exception as e:
        print(f'{f.__name__}: {e}')
