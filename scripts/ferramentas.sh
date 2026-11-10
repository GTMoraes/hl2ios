#!/usr/bin/env bash
# Confere e instala as ferramentas que o build usa e que o runner pode não trazer.
. "$(dirname "$0")/comum.sh"
registrar ferramentas

precisa() { # comando [fórmula do Homebrew]
	local comando="$1" formula="${2:-$1}"
	if command -v "$comando" >/dev/null 2>&1; then
		echo "$comando: $(command -v "$comando")"
	else
		echo "$comando: instalando ($formula)"
		HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install "$formula" > "$LOGS/brew-$formula.log" 2>&1 \
			|| { tail -20 "$LOGS/brew-$formula.log"; return 1; }
	fi
}

precisa cmake
precisa ninja
precisa zstd
precisa gh
# só o ícone depende dele: se não instalar, o app sai com um ícone simples
precisa rsvg-convert librsvg || aviso "sem o rsvg-convert: o ícone do segredo APP_ICON_SVG não vai ser usado"

python3 --version
clang --version | head -1
echo "objdump: $(command -v objdump)"
echo "núcleos: $NCPU"
echo "memória: $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"
df -h "$RAIZ" | tail -1

# Rust com o alvo de iPhone, para o renderizador Metal (sem ele o app usa OpenGL)
if command -v rustup >/dev/null 2>&1; then
	rustup update stable > "$LOGS/rustup.log" 2>&1 || true
	rustup default stable >> "$LOGS/rustup.log" 2>&1 || true
	rustup target add aarch64-apple-ios >> "$LOGS/rustup.log" 2>&1 || aviso "não consegui instalar o alvo aarch64-apple-ios do Rust"
	rustc --version || true
else
	aviso "runner sem rustup: o app vai sair só com OpenGL"
fi
