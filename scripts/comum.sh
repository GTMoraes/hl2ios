#!/usr/bin/env bash
# comum.sh: caminhos e funções usados pelos outros scripts (carregado com ".")
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRAB="${TRAB:-$RAIZ/trabalho}"
LOGS="$RAIZ/logs"
mkdir -p "$TRAB" "$LOGS"

# versões fixadas: no Actions já vêm no ambiente; fora dele, lê o arquivo
if [ -z "${RECOMP_COMMIT:-}" ]; then
	set -a
	# shellcheck disable=SC1090
	. <(grep -E '^[A-Z0-9_]+=' "$RAIZ/versoes.env")
	set +a
fi

RECOMP="$TRAB/source-recomp"          # o source-recomp no commit fixado, com as nossas mudanças
DEPOT="$TRAB/depot_224"               # binários Linux do jogo (do repositório privado)
DEPS_IOS="$TRAB/deps-ios"             # SDL2, FreeType e gl4es para iPhone
METAL_LIB="$TRAB/metal/libd3d9metal.a"
BUILD_HL2="$RECOMP/build/hl2"
APP_ORIGINAL="$BUILD_HL2/ios/device/$APP_NOME.app"   # o que o tools/build_ios.py monta
APP="$TRAB/app/$APP_NOME.app"                         # o que vai para o TestFlight
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

# manda toda a saída do script também para logs/<nome>.log
registrar() {
	exec > >(tee -a "$LOGS/$1.log") 2>&1
}

# O repositório é público e os logs também. Um erro do compilador mostra trechos do
# código traduzido (que é o jogo da Valve): este filtro tira as linhas de trecho de
# código ("  123 | ...") e as de marcação ("      | ^~~").
sem_trechos() {
	# linha a linha, para o andamento aparecer na hora: -u no sed GNU, -l no do macOS
	if sed --version >/dev/null 2>&1; then
		sed -u -E -e '/^[[:space:]]*[0-9]+[[:space:]]*\|/d' -e '/^[[:space:]]*\|/d'
	else
		sed -l -E -e '/^[[:space:]]*[0-9]+[[:space:]]*\|/d' -e '/^[[:space:]]*\|/d'
	fi
}

aviso() { echo "::warning::$*"; }
erro() { echo "::error::$*"; }

# baixa um repositório num commit exato
baixar_repo() { # url commit destino
	local url="$1" commit="$2" destino="$3"
	rm -rf "$destino"
	git init -q "$destino"
	git -C "$destino" remote add origin "$url"
	git -C "$destino" fetch -q --depth 1 origin "$commit"
	git -C "$destino" -c advice.detachedHead=false checkout -q FETCH_HEAD
	echo "$url @ $(git -C "$destino" rev-parse --short HEAD)"
}
