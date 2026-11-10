#!/usr/bin/env bash
# Monta o app que vai para o TestFlight a partir do HalfLife2.app que o tools/build_ios.py gerou:
# põe dentro dele os módulos preparados (prep) e os binários Linux (linux), o ícone, o Info.plist
# ajustado, o manifesto de privacidade e uma assinatura provisória com os direitos do app.
. "$(dirname "$0")/comum.sh"
registrar montar

BUILD="${BUILD:-1}"
export BUILD APP_BUNDLE APP_VERSAO IOS_MINIMO

[ -f "$APP_ORIGINAL/$APP_EXECUTAVEL" ] || { erro "não achei o app compilado em $APP_ORIGINAL"; exit 1; }
[ -f "$BUILD_HL2/prep/layout.json" ] || { erro "não achei os módulos preparados"; exit 1; }

rm -rf "$TRAB/app"
mkdir -p "$TRAB/app"
cp -R "$APP_ORIGINAL" "$APP"
rm -rf "$APP/_CodeSignature" "$APP/embedded.mobileprovision"
rm -f "$APP"/AppIcon*.png

# 1. prep e linux dentro do app. O source-recomp copia essas duas pastas para Documents pelo
#    cabo, a partir do Mac; aqui elas vêm junto com o app (patch 0002), e no iPhone só falta a
#    pasta game. A pasta prep tem que ser a desta build: os endereços dos módulos saem dela.
rsync -a "$BUILD_HL2/prep/" "$APP/prep/"
rsync -a "$DEPOT/" "$APP/linux/"

# o depot traz um binário de Mac esquecido (ffmpegsumo.so); binário Mach-O solto dentro de um app
# é recusado no envio (ITMS-90171), e o jogo não usa esse arquivo
python3 - "$APP/prep" "$APP/linux" <<'PYEOF'
import os, sys
MAGICOS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce',
           b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
tirados = 0
for pasta in sys.argv[1:]:
    for raiz, _, arquivos in os.walk(pasta):
        for nome in arquivos:
            caminho = os.path.join(raiz, nome)
            if os.path.islink(caminho):
                continue
            with open(caminho, 'rb') as f:
                if f.read(4) in MAGICOS:
                    os.unlink(caminho)
                    tirados += 1
                    print('tirado (binário de Mac): %s' % os.path.relpath(caminho, pasta))
print('binários de Mac tirados: %d' % tirados)
PYEOF
echo "prep: $(du -sh "$APP/prep" | awk '{print $1}'), linux: $(du -sh "$APP/linux" | awk '{print $1}')"

# 2. ícone: o SVG do segredo APP_ICON_SVG vira PNG e entra num catálogo (Assets.car)
ICONE="$TRAB/icone"
rm -rf "$ICONE" "$TRAB/venv"
mkdir -p "$ICONE"
LOGO=""
if [ -n "${APP_ICON_SVG:-}" ] && command -v rsvg-convert >/dev/null 2>&1; then
	printf '%s\n' "$APP_ICON_SVG" > "$ICONE/logo.svg"
	if rsvg-convert -w 880 -h 880 "$ICONE/logo.svg" -o "$ICONE/logo.png" > "$LOGS/icone-rsvg.log" 2>&1; then
		LOGO="$ICONE/logo.png"
	else
		aviso "o segredo APP_ICON_SVG não é um SVG que o rsvg-convert entenda: ícone simples"
	fi
	rm -f "$ICONE/logo.svg"
else
	aviso "sem o segredo APP_ICON_SVG (ou sem o rsvg-convert): ícone simples"
fi
python3 -m venv "$TRAB/venv"
"$TRAB/venv/bin/pip" install -q pillow
if [ -n "$LOGO" ]; then
	"$TRAB/venv/bin/python" "$RAIZ/scripts/icone.py" "$ICONE" "$LOGO"
else
	"$TRAB/venv/bin/python" "$RAIZ/scripts/icone.py" "$ICONE"
fi
rm -f "$ICONE/logo.png"
xcrun actool "$ICONE/Assets.xcassets" --compile "$APP" \
	--platform iphoneos --minimum-deployment-target "$IOS_MINIMO" --target-device iphone \
	--app-icon AppIcon --output-partial-info-plist "$ICONE/parcial.plist" \
	--output-format human-readable-text --notices --warnings --errors

# 3. Info.plist e manifesto de privacidade
python3 "$RAIZ/scripts/info-plist.py" "$APP/Info.plist" "$ICONE/parcial.plist"
cp "$RAIZ/app/PrivacyInfo.xcprivacy" "$APP/"
plutil -lint "$APP/Info.plist"

# 4. assinatura provisória com os direitos do app (o envio ao TestFlight assina de verdade e
#    mantém os direitos que encontra aqui)
codesign --force --sign - --timestamp=none --generate-entitlement-der \
	--entitlements "$RAIZ/app/direitos.plist" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "== app final:"
ls -la "$APP" | awk '{print $5, $9}'
du -sh "$APP"
{
	echo "### App"
	echo "- Tamanho instalado: $(du -sh "$APP" | awk '{print $1}') (sem os dados do jogo, que ficam no iPhone)"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
