"""Prints the Play Store "What's new" text for this build: the app version
and AppInfo.latest (lib/core/app_info.dart), the plain-words note of what
this build changed.

    python3 tool/play/whats_new.py            (stdout, max 500 characters)
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))


def whats_new(src):
    version = re.search(r"static const version = '([^']+)'", src).group(1)
    block = src[src.index('static const latest'):]
    block = block[:block.index(';')]
    parts = re.findall(r"'((?:[^'\\]|\\.)*)'", block)
    line = re.sub(r"\\(.)", r"\1", ''.join(parts)).strip()
    text = f'{version}: {line}'
    return text if len(text) <= 500 else text[:497].rstrip() + '...'


if __name__ == '__main__':
    with open(os.path.join(ROOT, 'lib', 'core', 'app_info.dart'), encoding='utf-8') as f:
        sys.stdout.write(whats_new(f.read()) + '\n')
