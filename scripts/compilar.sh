#!/usr/bin/env bash
# Traduz e compila o Half-Life 2 para iPhone com as ferramentas do source-recomp:
# tools/gameprep.py (prepara os módulos Linux) e tools/build_ios.py (traduz para C, compila e liga).
# É o passo demorado: a primeira vez leva de uma a duas horas neste runner; as seguintes
# reaproveitam o cache.
. "$(dirname "$0")/comum.sh"
registrar compilar

export PYTHONUNBUFFERED=1
# o identificador do app, pela variável que o source-recomp consulta primeiro (tools/ios_bundle_id.py)
export P2_BUNDLE_ID="$APP_BUNDLE"
cd "$RECOMP"

# config/local.json do source-recomp: só o Half-Life 2, sem a cópia do jogo (ela não vem ao runner)
METAL=""
[ -f "$METAL_LIB" ] && METAL="$METAL_LIB"
python3 - "$RECOMP/config/local.json" "$DEPOT" "$APP_BUNDLE" "$METAL" <<'PYEOF'
import json, sys
destino, depot, bundle, metal = sys.argv[1:]
config = {
    'games': {'hl2': {'linux_root': depot, 'steam_appid': 220, 'depot_id': 224, 'ios_bundle_id': bundle}},
}
if metal:
    config['d3d9metal_ios'] = {'device': metal}
with open(destino, 'w') as f:
    json.dump(config, f, indent=1)
    f.write('\n')
print('config/local.json: Metal %s' % ('sim' if metal else 'NÃO (só OpenGL)'))
PYEOF

# 1. módulos preparados (segundos). Do cache quando o depot, os ajustes dele
# (scripts/ajustar-depot.py), o commit e a pasta são os mesmos.
CARIMBO="build/.hl2ios-carimbo"
ESPERADO="$DEPOT_SHA256 ajustes-${DEPOT_AJUSTES:-0} $RECOMP_COMMIT $RECOMP"
if [ -f build/hl2/prep/layout.json ] && [ "$(cat "$CARIMBO" 2>/dev/null || true)" = "$ESPERADO" ]; then
	echo "módulos preparados: do cache"
else
	rm -rf build/hl2/prep "$CARIMBO"
	set +e
	python3 tools/gameprep.py --game hl2 2>&1 | sem_trechos
	ESTADOS=("${PIPESTATUS[@]}")
	set -e
	if [ "${ESTADOS[0]}" != 0 ]; then
		erro "o tools/gameprep.py falhou"
		exit 1
	fi
	# A chave da tradução usa a data dos arquivos preparados, em nanossegundos, e o tar do cache
	# só garante segundos: datas em segundos inteiros para o cache valer na build seguinte.
	python3 - build/hl2/prep <<'PYEOF'
import os, sys
for raiz, _, arquivos in os.walk(sys.argv[1]):
    for nome in arquivos:
        caminho = os.path.join(raiz, nome)
        segundos = int(os.stat(caminho).st_mtime)
        os.utime(caminho, ns=(segundos * 10**9, segundos * 10**9))
PYEOF
	mkdir -p build
	echo "$ESPERADO" > "$CARIMBO"
	echo "módulos preparados: $(find build/hl2/prep -type f | wc -l | tr -d ' ') arquivos, $(du -sh build/hl2/prep | awk '{print $1}')"
fi

# 2. tradução, compilação e ligação
INICIO="$(date +%s)"
set +e
python3 tools/build_ios.py --game hl2 --target device --release \
	--deps "$DEPS_IOS/device" --jobs "$NCPU" 2>&1 | sem_trechos
ESTADOS=("${PIPESTATUS[@]}")
set -e
MINUTOS=$(( ( $(date +%s) - INICIO ) / 60 ))
if [ "${ESTADOS[0]}" != 0 ]; then
	erro "o tools/build_ios.py falhou depois de $MINUTOS min (o que já compilou fica no cache)"
	exit 1
fi

EXE="$APP_ORIGINAL/$APP_EXECUTAVEL"
[ -f "$EXE" ] || { erro "o executável não saiu em $EXE"; exit 1; }

# 3. objetos de traduções antigas saem do cache (ficam só os desta build)
python3 - build/hl2/ios/device/link.rsp build/hl2/ios/device/obj <<'PYEOF'
import os, sys
resposta, pasta = sys.argv[1:]
usados = {os.path.basename(l.strip()) for l in open(resposta) if l.strip()}
apagados = 0
for nome in os.listdir(pasta):
    if nome.endswith('.o') and nome not in usados:
        os.unlink(os.path.join(pasta, nome))
        apagados += 1
print('objetos: %d em uso, %d antigos apagados' % (len(usados), apagados))
PYEOF

# 4. tamanhos. A Apple recusa executável com mais de 500 MB de código (soma das seções __TEXT).
TOTAL_MB=$(( $(stat -f %z "$EXE") / 1048576 ))
TEXTO_MB=$(( $(size "$EXE" | tail -1 | awk '{print $1}') / 1048576 ))
echo "executável: $TOTAL_MB MB no total, $TEXTO_MB MB de código (__TEXT), em $MINUTOS min"
{
	echo "### Compilação"
	echo "- Tempo: $MINUTOS min"
	echo "- Executável: $TOTAL_MB MB no total, **$TEXTO_MB MB de código** (limite da Apple: 500 MB)"
	echo "- Renderizador Metal: $([ -n "$METAL" ] && echo sim || echo "não, só OpenGL")"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ "$TEXTO_MB" -ge 500 ]; then
	aviso "o código tem $TEXTO_MB MB, acima dos 500 MB que o App Store Connect aceita: o envio ao TestFlight deve ser recusado"
fi
