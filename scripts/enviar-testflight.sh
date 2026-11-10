#!/usr/bin/env bash
# Monta o .xcarchive com o app já montado e envia ao TestFlight com a assinatura gerenciada pela
# Apple (o mesmo caminho do nfios e do hlios: só a chave da API nos segredos, nenhum certificado).
. "$(dirname "$0")/comum.sh"
registrar testflight

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${ASC_KEY_P8:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
	erro "Faltam os segredos do App Store Connect (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APPLE_TEAM_ID)."
	exit 1
fi

BUILD="${BUILD:-1}"
ARQ="$TRAB/$APP_NOME.xcarchive"
K="$TRAB/AuthKey_$ASC_KEY_ID.p8"
trap 'rm -f "$K"' EXIT
printf '%s\n' "$ASC_KEY_P8" > "$K"

cat > "$TRAB/export.plist" <<PLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$APPLE_TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>testFlightInternalTestingOnly</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><false/>
</dict></plist>
PLEOF

montar_archive() {
	rm -rf "$ARQ" "$TRAB/export"
	mkdir -p "$ARQ/Products/Applications"
	cp -R "$APP" "$ARQ/Products/Applications/"
	# o Info.plist que o Xcode põe num archive
	python3 - "$ARQ/Info.plist" "$APP_NOME" "$APP_BUNDLE" "$APP_VERSAO" "$BUILD" "$APPLE_TEAM_ID" <<'PYEOF'
import datetime, plistlib, sys
destino, nome, bundle, versao, build, equipe = sys.argv[1:]
info = {
    'ApplicationProperties': {
        'ApplicationPath': 'Applications/%s.app' % nome,
        'Architectures': ['arm64'],
        'CFBundleIdentifier': bundle,
        'CFBundleShortVersionString': versao,
        'CFBundleVersion': build,
        'Team': equipe,
    },
    'ArchiveVersion': 2,
    'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    'Name': nome,
    'SchemeName': nome,
}
with open(destino, 'wb') as f:
    plistlib.dump(info, f)
PYEOF
}

exportar() { # nome do log
	xcodebuild -exportArchive -archivePath "$ARQ" -exportPath "$TRAB/export" \
		-exportOptionsPlist "$TRAB/export.plist" \
		-allowProvisioningUpdates -authenticationKeyPath "$K" \
		-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
		> "$LOGS/$1.log" 2>&1 || true
	cat "$LOGS/$1.log"
	grep -qE "EXPORT SUCCEEDED|Upload succeeded|Uploaded" "$LOGS/$1.log"
}

montar_archive
DIREITOS="com o direito de mais memória"
if ! exportar export; then
	# Se a recusa foi por causa do direito de memória (capacidade Increased Memory Limit desligada
	# no App ID, por exemplo), tenta de novo sem ele: o app funciona, só com o limite normal.
	if grep -qiE "entitlement|increased-memory-limit|provisioning profile" "$LOGS/export.log"; then
		aviso "o envio com o direito Increased Memory Limit foi recusado: tentando sem ele"
		codesign --force --sign - --timestamp=none "$APP"
		montar_archive
		DIREITOS="SEM o direito de mais memória (confira a capacidade Increased Memory Limit no App ID)"
		exportar export-sem-direitos || { erro "o envio ao TestFlight falhou (veja o log export-sem-direitos)"; exit 1; }
	else
		erro "o envio ao TestFlight falhou (veja o log export)"
		exit 1
	fi
fi

{
	echo "### TestFlight"
	echo "Build $BUILD ($APP_VERSAO) enviada, $DIREITOS. Em uns 10 a 30 minutos aparece no app TestFlight do iPhone."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
