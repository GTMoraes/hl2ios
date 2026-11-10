#!/usr/bin/env bash
# SDL2, FreeType e gl4es para iPhone, com o script do próprio source-recomp (ios/deps/build.sh).
# Nada aqui é da Valve: o resultado fica num cache comum do Actions.
. "$(dirname "$0")/comum.sh"
registrar deps-ios

if [ -f "$DEPS_IOS/device/lib/libgl4es.a" ] && [ -f "$DEPS_IOS/device/lib/libSDL2.a" ] && [ -f "$DEPS_IOS/device/lib/libfreetype.a" ]; then
	echo "dependências de iPhone: do cache"
	ls -la "$DEPS_IOS/device/lib"
	exit 0
fi

rm -rf "$DEPS_IOS"
mkdir -p "$DEPS_IOS"
if ! P2_IOS_DEPS="$DEPS_IOS" bash "$RECOMP/ios/deps/build.sh" device; then
	for l in "$DEPS_IOS"/log-device-*.txt; do
		[ -f "$l" ] || continue
		echo "== $(basename "$l") (fim)"
		tail -40 "$l"
		cp "$l" "$LOGS/deps-$(basename "$l")"
	done
	erro "as dependências de iPhone (SDL2, FreeType, gl4es) não compilaram"
	exit 1
fi

# só o resultado vai para o cache: fontes e pastas de build saem
rm -rf "$DEPS_IOS/src" "$DEPS_IOS"/build-device
for f in libSDL2.a libSDL2main.a libgl4es.a libfreetype.a; do
	[ -f "$DEPS_IOS/device/lib/$f" ] || { erro "faltou $f"; exit 1; }
done
