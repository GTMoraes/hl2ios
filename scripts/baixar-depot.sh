#!/usr/bin/env bash
# Baixa os binários Linux do Half-Life 2 (depot 224) do repositório privado e confere o SHA-256.
# Este repositório é público: os binários da Valve nunca entram nele, só passam pelo runner.
. "$(dirname "$0")/comum.sh"
registrar depot

if [ -z "${DEPOT_TOKEN:-}" ]; then
	erro "Falta o segredo DEPOT_TOKEN (token de leitura do repositório $DEPOT_REPO)."
	exit 1
fi

rm -rf "$TRAB/depot-baixado" "$TRAB/depot-aberto" "$DEPOT"
mkdir -p "$TRAB/depot-baixado" "$TRAB/depot-aberto"

if ! GH_TOKEN="$DEPOT_TOKEN" gh release download "$DEPOT_TAG" --repo "$DEPOT_REPO" \
		--pattern "$DEPOT_ARQUIVO" --dir "$TRAB/depot-baixado" > "$LOGS/depot-gh.log" 2>&1; then
	cat "$LOGS/depot-gh.log"
	erro "Não consegui baixar $DEPOT_ARQUIVO da Release $DEPOT_TAG de $DEPOT_REPO. Token vencido ou sem acesso a esse repositório?"
	exit 1
fi

ZIP="$TRAB/depot-baixado/$DEPOT_ARQUIVO"
TEM="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [ "$TEM" != "$DEPOT_SHA256" ]; then
	erro "SHA-256 do depot diferente do fixado em versoes.env (veio $TEM)."
	exit 1
fi
echo "depot: $(du -h "$ZIP" | awk '{print $1}'), SHA-256 confere"

unzip -q "$ZIP" -d "$TRAB/depot-aberto"
rm -f "$ZIP"

# o zip pode trazer a pasta depot_224 por fora ou não: vale a pasta onde está o hl2_linux
ACHADO="$(find "$TRAB/depot-aberto" -maxdepth 3 -type f -name hl2_linux -print -quit)"
if [ -z "$ACHADO" ]; then
	erro "O zip do depot não tem o arquivo hl2_linux."
	exit 1
fi
mv "$(dirname "$ACHADO")" "$DEPOT"
rm -rf "$TRAB/depot-aberto" "$TRAB/depot-baixado"

for f in hl2_linux bin/engine.so bin/shaderapivk.so hl2_complete/bin/client.so hl2_complete/bin/server.so; do
	[ -f "$DEPOT/$f" ] || { erro "falta $f no depot"; exit 1; }
done
echo "depot aberto: $(find "$DEPOT" -type f | wc -l | tr -d ' ') arquivos, $(du -sh "$DEPOT" | awk '{print $1}')"
