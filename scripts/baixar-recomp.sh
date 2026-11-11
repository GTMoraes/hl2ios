#!/usr/bin/env bash
# Baixa o source-recomp no commit fixado e aplica as mudanças deste repositório:
# patches/, extras/ (arquivos novos) e raizes/ (alvos de chamada indireta achados no iPhone).
. "$(dirname "$0")/comum.sh"
registrar recomp

baixar_repo "$RECOMP_REPO" "$RECOMP_COMMIT" "$RECOMP"
[ "$(git -C "$RECOMP" rev-parse HEAD)" = "$RECOMP_COMMIT" ] || { erro "o commit baixado não é o fixado em versoes.env"; exit 1; }

for p in "$RAIZ"/patches/*.patch; do
	[ -f "$p" ] || continue
	git -C "$RECOMP" apply --check "$p" || { erro "o patch $(basename "$p") não aplica neste commit do source-recomp"; exit 1; }
	git -C "$RECOMP" apply "$p"
	echo "patch: $(basename "$p")"
done

# arquivos novos do runtime de iPhone (o tools/build_ios.py compila tudo de runtime/ios;
# os .h vão junto porque o touch_controls.m do patch 0003 inclui o hl2ios_toque.h)
for f in "$RAIZ"/extras/*.m "$RAIZ"/extras/*.c "$RAIZ"/extras/*.h; do
	[ -f "$f" ] || continue
	cp "$f" "$RECOMP/runtime/ios/"
	echo "extra: $(basename "$f")"
done

# raízes extras: cada travamento "target not recompiled" vira uma linha em raizes/hl2-extras.json
python3 - "$RECOMP/config/hl2-roots.json" "$RAIZ/raizes/hl2-extras.json" <<'PYEOF'
import json, sys
oficial, extras = sys.argv[1:]
lista = json.load(open(oficial))
try:
    novas = json.load(open(extras))
except FileNotFoundError:
    novas = []
if not isinstance(novas, list) or not all(isinstance(x, str) for x in novas):
    raise SystemExit('erro: raizes/hl2-extras.json tem que ser uma lista de textos')
juntas = list(dict.fromkeys(lista + novas))
acrescentadas = len(juntas) - len(lista)
if acrescentadas:
    with open(oficial, 'w') as f:
        json.dump(juntas, f, indent=1)
        f.write('\n')
print('raízes: %d do source-recomp + %d extras' % (len(lista), acrescentadas))
PYEOF
