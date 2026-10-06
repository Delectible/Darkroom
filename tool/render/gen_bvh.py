import re, glob
def process(code, indirect):
    code = code.replace('/* @echo INDIRECT_STRING */', '_indirect' if indirect else '')
    pat = re.compile(r'/\* @if INDIRECT \*/(.*?)(?:/\* @else \*/(.*?))?/\* @endif \*/', re.S)
    # no nesting assumed
    def rep(m): return (m.group(1) if indirect else (m.group(2) or ''))
    out = pat.sub(rep, code)
    assert '@if' not in out and '@endif' not in out
    return out
for f in glob.glob('src/**/*.template.js', recursive=True):
    src = open(f).read()
    open(f.replace('.template.js', '_indirect.generated.js'), 'w').write(process(src, True))
    open(f.replace('.template.js', '.generated.js'), 'w').write(process(src, False))
    print('gen', f)
