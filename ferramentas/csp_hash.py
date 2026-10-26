"""Recalcula os hashes do script-src da CSP (meta data-csp) de uma página: um hash por <script> inline, na ordem.
Uso: python3 csp_hash.py arquivo.html [--checa]"""
import re, sys, hashlib, base64
p = sys.argv[1]
h = open(p, encoding='utf-8').read()
m = re.search(r"(<meta http-equiv=\"Content-Security-Policy\" content=\"[^\"]*?script-src )([^;]+)(;)", h)
assert m, 'sem meta CSP'
scripts = re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', h, re.S)
hashes = ["'sha256-" + base64.b64encode(hashlib.sha256(s.encode('utf-8')).digest()).decode() + "'" for s in scripts]
atuais = m.group(2).split()
if '--checa' in sys.argv:
    print('ok' if set(hashes) <= set(atuais) else 'FALTA HASH', len(scripts), 'scripts')
    sys.exit(0 if set(hashes) <= set(atuais) else 1)
novo = h[:m.start(2)] + ' '.join(hashes) + h[m.end(2):]
open(p, 'w', encoding='utf-8').write(novo)
print('hashes:', len(hashes), 'trocados:', sum(1 for x in hashes if x not in atuais))
