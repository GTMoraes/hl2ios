#!/usr/bin/env bash
# Cache do código traduzido, sempre cifrado.
#
# O código traduzido (C gerado e objetos) é o jogo da Valve. Este repositório é público, e um
# workflow de fork consegue ler os caches do Actions, mas não lê segredos. Por isso o cache só
# existe cifrado com o segredo CACHE_SENHA (AES-256). Sem a senha, ou se algo falhar, não há
# cache: a build só demora mais. Nunca sai nada sem cifrar.
#
# Uso: cache.sh abrir | fechar
. "$(dirname "$0")/comum.sh"
registrar cache

ACAO="${1:-}"
PASTA="$TRAB/cache-cifrado"
ARQ="$PASTA/traduzido.tar.zst.enc"
CARIMBO="build/.hl2ios-carimbo"
# o que guardar, relativo ao source-recomp: módulos preparados, C gerado, desmontagem e objetos
ITENS="build/hl2/prep build/hl2/gen build/disasm-cache build/hl2/ios/device/obj $CARIMBO"

if [ -z "${CACHE_SENHA:-}" ]; then
	aviso "sem o segredo CACHE_SENHA: build sem cache (mais demorada)"
	rm -rf "$PASTA"
	exit 0
fi
export CACHE_SENHA

# openssl que entende -pbkdf2 (o do Homebrew ou o do sistema)
OPENSSL=""
for c in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl || true)"; do
	if [ -z "$c" ] || [ ! -x "$c" ]; then
		continue
	fi
	VOLTA="$(echo teste | "$c" enc -aes-256-ctr -pbkdf2 -iter 200000 -salt -pass pass:teste 2>/dev/null \
		| "$c" enc -d -aes-256-ctr -pbkdf2 -iter 200000 -pass pass:teste 2>/dev/null || true)"
	if [ "$VOLTA" = "teste" ]; then
		OPENSSL="$c"
		break
	fi
done
if [ -z "$OPENSSL" ]; then
	aviso "nenhum openssl com -pbkdf2 neste runner: build sem cache"
	rm -rf "$PASTA"
	exit 0
fi

case "$ACAO" in
abrir)
	if [ ! -f "$ARQ" ]; then
		echo "sem cache anterior: build completa"
		exit 0
	fi
	echo "cache: $(du -h "$ARQ" | awk '{print $1}') cifrado"
	mkdir -p "$RECOMP"
	set +e
	"$OPENSSL" enc -d -aes-256-ctr -pbkdf2 -iter 200000 -pass env:CACHE_SENHA -in "$ARQ" | zstd -d -q | tar -xf - -C "$RECOMP"
	ESTADOS=("${PIPESTATUS[@]}")
	set -e
	rm -f "$ARQ"
	if [ "${ESTADOS[0]}" != 0 ] || [ "${ESTADOS[1]}" != 0 ] || [ "${ESTADOS[2]}" != 0 ]; then
		aviso "não consegui abrir o cache (senha trocada ou arquivo incompleto): build completa"
		rm -rf "$RECOMP/build"
		exit 0
	fi
	# os módulos preparados só valem para o mesmo depot, o mesmo commit do source-recomp e a
	# mesma pasta (o layout guarda caminhos absolutos); o scripts/compilar.sh grava o carimbo
	ESPERADO="$DEPOT_SHA256 $RECOMP_COMMIT $RECOMP"
	if [ "$(cat "$RECOMP/$CARIMBO" 2>/dev/null || true)" != "$ESPERADO" ]; then
		echo "cache de outro depot ou de outro commit: refazendo os módulos preparados"
		rm -rf "$RECOMP/build/hl2/prep" "$RECOMP/$CARIMBO"
	fi
	echo "cache aberto: $(du -sh "$RECOMP/build" 2>/dev/null | awk '{print $1}')"
	;;
fechar)
	rm -rf "$PASTA"
	mkdir -p "$PASTA"
	cd "$RECOMP" 2>/dev/null || { echo "nada a guardar"; exit 0; }
	TEM=""
	for i in $ITENS; do
		[ -e "$i" ] && TEM="$TEM $i"
	done
	if [ -z "$TEM" ] || [ ! -d build/hl2/gen ]; then
		echo "nada a guardar"
		rm -rf "$PASTA"
		exit 0
	fi
	set +e
	# shellcheck disable=SC2086
	tar -cf - $TEM | zstd -q -T0 -3 | "$OPENSSL" enc -aes-256-ctr -pbkdf2 -iter 200000 -salt -pass env:CACHE_SENHA -out "$ARQ.tmp"
	ESTADOS=("${PIPESTATUS[@]}")
	set -e
	if [ "${ESTADOS[0]}" != 0 ] || [ "${ESTADOS[1]}" != 0 ] || [ "${ESTADOS[2]}" != 0 ]; then
		aviso "não consegui fechar o cache: a próxima build vai ser completa"
		rm -rf "$PASTA"
		exit 0
	fi
	mv "$ARQ.tmp" "$ARQ"
	echo "cache guardado: $(du -h "$ARQ" | awk '{print $1}') cifrado"
	;;
*)
	echo "uso: cache.sh abrir | fechar"
	exit 2
	;;
esac
