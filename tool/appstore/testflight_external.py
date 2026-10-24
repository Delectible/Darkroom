"""Hands a TestFlight build to the external testers: waits for Apple to
finish processing it, sets its "What to Test" from AppInfo.latest, adds it
to every external beta group and submits it for beta review (Apple only
reviews when it wants to; later builds of a version often go straight out).

    KEY_ID=.. ISSUER=.. KEY_FILE=AuthKey.p8 python3 tool/appstore/testflight_external.py BUILD_NUMBER

Needs PyJWT and cryptography (pip install pyjwt cryptography).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'play'))
from whats_new import whats_new  # noqa: E402

API = 'https://api.appstoreconnect.apple.com/v1'
BUNDLE = 'com.dingo.darkroom'
LOCALE = os.environ.get('LOCALE', 'en-US')


def token():
    now = int(time.time())
    return jwt.encode(
        {'iss': os.environ['ISSUER'], 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'},
        open(os.environ['KEY_FILE']).read(),
        algorithm='ES256',
        headers={'kid': os.environ['KEY_ID'], 'typ': 'JWT'},
    )


def call(method, path, body=None, ok=(200, 201, 204)):
    req = urllib.request.Request(
        path if path.startswith('http') else API + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={'Authorization': f'Bearer {token()}', 'Content-Type': 'application/json'},
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        if e.code in ok:
            return e.code, {}
        return e.code, (json.loads(raw) if raw else {})


def main(build_number):
    root = os.path.join(os.path.dirname(__file__), '..', '..')
    notes = whats_new(open(os.path.join(root, 'lib', 'core', 'app_info.dart'), encoding='utf-8').read())

    _, apps = call('GET', f'/apps?filter[bundleId]={BUNDLE}')
    app = apps['data'][0]['id']

    # Apple takes a while to process an upload.
    build = None
    for _ in range(90):
        _, b = call('GET', f'/builds?filter[app]={app}&filter[version]={build_number}&limit=1')
        if b.get('data'):
            build = b['data'][0]
            state = build['attributes']['processingState']
            print('build', build_number, state, flush=True)
            if state == 'VALID':
                break
            if state in ('FAILED', 'INVALID'):
                sys.exit(f'build {build_number} {state}')
        time.sleep(40)
    else:
        sys.exit(f'build {build_number} not processed in time')
    bid = build['id']

    # What to Test.
    _, locs = call('GET', f'/builds/{bid}/betaBuildLocalizations')
    mine = [l for l in locs.get('data', []) if l['attributes']['locale'] == LOCALE]
    if mine:
        s, r = call('PATCH', f"/betaBuildLocalizations/{mine[0]['id']}", {
            'data': {'type': 'betaBuildLocalizations', 'id': mine[0]['id'], 'attributes': {'whatsNew': notes}}})
    else:
        s, r = call('POST', '/betaBuildLocalizations', {'data': {
            'type': 'betaBuildLocalizations', 'attributes': {'locale': LOCALE, 'whatsNew': notes},
            'relationships': {'build': {'data': {'type': 'builds', 'id': bid}}}}})
    print('what to test:', s, notes, flush=True)

    # Every external group.
    s, groups = call('GET', f'/betaGroups?filter[app]={app}&limit=50')
    external = [g for g in groups.get('data', []) if not g['attributes'].get('isInternalGroup')]
    if not external:
        sys.exit(f'no external beta groups found ({s}: {json.dumps(groups)[:400]})')
    for g in external:
        s, r = call('POST', f"/betaGroups/{g['id']}/relationships/builds",
                    {'data': [{'type': 'builds', 'id': bid}]})
        print('group', g['attributes']['name'], s, '' if s < 300 else r, flush=True)

    # Beta review (409 when it's already submitted or not needed).
    s, r = call('POST', '/betaAppReviewSubmissions', {'data': {
        'type': 'betaAppReviewSubmissions',
        'relationships': {'build': {'data': {'type': 'builds', 'id': bid}}}}})
    print('beta review:', s, '' if s < 300 else json.dumps(r)[:400], flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
