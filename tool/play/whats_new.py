"""Prints the Play Store "What's new" text for this build: the app version
and the newest line of AppInfo.revisions (lib/core/app_info.dart), i.e. the
same words the app shows in Help > About.

    python3 tool/play/whats_new.py            (stdout, max 500 characters)

Convention: each version adds its change as the first string of the newest
revision entry, so that string is what changed last.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))


def whats_new(src):
    version = re.search(r"static const version = '([^']+)'", src).group(1)
    revisions = src[src.index('static const revisions'):]
    m = re.search(r"\(\s*'[^']*',\s*'((?:[^'\\]|\\.)*)'", revisions)
    line = re.sub(r"\\(.)", r"\1", m.group(1)).strip()
    text = f'{version}: {line}'
    return text if len(text) <= 500 else text[:497].rstrip() + '...'


if __name__ == '__main__':
    with open(os.path.join(ROOT, 'lib', 'core', 'app_info.dart'), encoding='utf-8') as f:
        sys.stdout.write(whats_new(f.read()) + '\n')
