#!/usr/bin/env python3
"""Ajusta o Info.plist que o tools/build_ios.py gerou para o envio ao TestFlight.

Mantém o que o source-recomp pôs (nome, executável, chave P2Game, orientação, 120 Hz,
pasta visível no app Arquivos) e acrescenta o que o App Store Connect confere: versão,
número da build, chaves DT* do Xcode usado, ícone do catálogo (do actool), só iPhone,
textos de permissão e a declaração de criptografia.

Uso: info-plist.py <Info.plist do app> <plist parcial do actool>
Ambiente: APP_BUNDLE, APP_VERSAO, BUILD, IOS_MINIMO
"""
import os
import plistlib
import subprocess
import sys


def valores_dt():
    """As chaves DT* que o Xcode põe em todo bundle (o App Store Connect confere o toolchain)."""
    def sai(*args):
        return subprocess.run(args, capture_output=True, text=True).stdout.strip()
    sdk_ver = sai('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    sdk_build = sai('xcrun', '--sdk', 'iphoneos', '--show-sdk-build-version')
    plat_ver = sai('xcrun', '--sdk', 'iphoneos', '--show-sdk-platform-version') or sdk_ver
    xv = sai('xcodebuild', '-version').splitlines()
    xcode_ver = xv[0].split()[-1] if xv else '26.0'
    xcode_build = xv[1].split()[-1] if len(xv) > 1 else ''
    partes = (xcode_ver.split('.') + ['0', '0'])[:3]
    dtxcode = '%02d%d%d' % (int(partes[0]), int(partes[1]), int(partes[2]))
    return {
        'BuildMachineOSBuild': sai('sw_vers', '-buildVersion'),
        'DTCompiler': 'com.apple.compilers.llvm.clang.1_0',
        'DTPlatformBuild': sdk_build,
        'DTPlatformName': 'iphoneos',
        'DTPlatformVersion': plat_ver,
        'DTSDKBuild': sdk_build,
        'DTSDKName': 'iphoneos' + sdk_ver,
        'DTXcode': dtxcode,
        'DTXcodeBuild': xcode_build,
    }


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    caminho, parcial = sys.argv[1:]
    with open(caminho, 'rb') as f:
        info = plistlib.load(f)

    info['CFBundleIdentifier'] = os.environ['APP_BUNDLE']
    info['CFBundleShortVersionString'] = os.environ['APP_VERSAO']
    info['CFBundleVersion'] = os.environ.get('BUILD', '1')
    info['MinimumOSVersion'] = os.environ['IOS_MINIMO']
    info['CFBundleInfoDictionaryVersion'] = '6.0'
    info.update(valores_dt())

    # ícone: sai o esquema antigo de arquivos soltos, entra o do catálogo (Assets.car)
    info.pop('CFBundleIcons', None)
    info.pop('CFBundleIcons~ipad', None)
    if os.path.exists(parcial):
        with open(parcial, 'rb') as f:
            info.update(plistlib.load(f))

    # só iPhone: app de iPad sem as quatro orientações é recusado no envio (ITMS-90474)
    info['UIDeviceFamily'] = [1]
    info['UIRequiredDeviceCapabilities'] = ['arm64']
    info['LSApplicationCategoryType'] = 'public.app-category.action-games'
    # Modo Jogo do iOS: menos atividade em segundo plano
    info['LSSupportsGameMode'] = True
    info['GCSupportsGameMode'] = True
    # só criptografia padrão: o TestFlight não pergunta de exportação a cada build
    info['ITSAppUsesNonExemptEncryption'] = False
    info['UIUserInterfaceStyle'] = 'Dark'
    # textos das permissões que o SDL e o runtime podem pedir (o envio confere os que faltam)
    info.setdefault('NSLocalNetworkUsageDescription', 'Para jogar em rede local.')
    info['NSBluetoothAlwaysUsageDescription'] = 'Para usar controles Bluetooth.'
    info['NSMicrophoneUsageDescription'] = 'O jogo não grava áudio; o texto é exigido pela biblioteca de som.'
    info['NSMotionUsageDescription'] = 'Para mirar girando o iPhone.'

    with open(caminho, 'wb') as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_XML)
    for k in ('CFBundleIdentifier', 'CFBundleDisplayName', 'CFBundleExecutable', 'CFBundleShortVersionString',
              'CFBundleVersion', 'MinimumOSVersion', 'P2Game', 'DTXcode', 'DTXcodeBuild', 'DTSDKName'):
        print('%s = %s' % (k, info.get(k)))
    print('ícones: %s' % ('sim' if 'CFBundleIcons' in info else 'NÃO'))


if __name__ == '__main__':
    main()
