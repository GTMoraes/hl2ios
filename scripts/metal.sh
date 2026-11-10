#!/usr/bin/env bash
# libd3d9metal para iPhone (mtld3d): o Direct3D 9 do jogo sobre Metal. Do mesmo jeito que o
# setup.sh do source-recomp faz. Se não compilar, a build continua e o app sai só com OpenGL
# (mais lento e com a imagem mais escura, segundo o próprio projeto).
. "$(dirname "$0")/comum.sh"
registrar metal

if [ -f "$METAL_LIB" ]; then
	echo "libd3d9metal: do cache ($(du -h "$METAL_LIB" | awk '{print $1}'))"
	exit 0
fi

sem_metal() {
	aviso "$1: o app vai sair só com OpenGL"
	{
		echo "### Renderizador"
		echo "Metal **não** entrou nesta build ($1). O app usa OpenGL."
	} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
	exit 0
}

command -v cargo >/dev/null 2>&1 || sem_metal "runner sem Rust"

FONTE="$TRAB/metal/mtld3d"
ALVO="$TRAB/metal/target"
mkdir -p "$TRAB/metal"
baixar_repo "$MTLD3D_REPO" "$MTLD3D_COMMIT" "$FONTE" || sem_metal "não consegui baixar o mtld3d"
[ -d "$FONTE/native" ] || sem_metal "o mtld3d deste commit não tem a pasta native"

# se o projeto fixa uma versão do Rust (rust-toolchain), o alvo de iPhone vai nela
(cd "$FONTE/native" && rustup target add aarch64-apple-ios) >> "$LOGS/rustup.log" 2>&1 || true
(cd "$FONTE/native" && rustc --version) || true

SAIDA="$ALVO/aarch64-apple-ios/production/libd3d9metal.a"
if (cd "$FONTE/native" && CARGO_TARGET_DIR="$ALVO" cargo build --profile production --target aarch64-apple-ios) \
		> "$LOGS/metal-cargo.log" 2>&1 && [ -f "$SAIDA" ]; then
	cp "$SAIDA" "$METAL_LIB"
	echo "libd3d9metal: compilada ($(du -h "$METAL_LIB" | awk '{print $1}'))"
else
	tail -40 "$LOGS/metal-cargo.log" || true
	sem_metal "a libd3d9metal não compilou"
fi

# só a biblioteca vai para o cache
rm -rf "$ALVO" "$FONTE"
