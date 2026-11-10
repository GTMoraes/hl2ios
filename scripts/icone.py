#!/usr/bin/env python3
"""Monta o catálogo de ícones (Assets.xcassets/AppIcon) a partir do logo já convertido em PNG.

O logo não fica no repositório (que é público): vem do segredo APP_ICON_SVG, e o
scripts/montar-app.sh converte o SVG em PNG com o rsvg-convert. A Apple pede 1024x1024 sem
canal alfa, então o logo vai centralizado sobre um fundo preto, ocupando 86% do lado (a
máscara de cantos arredondados do iOS não corta nada). Sem o PNG, sai um ícone simples, só
para a build não parar.

Uso: icone.py <pasta de saída> [logo.png]
"""
import json
import os
import sys

from PIL import Image, ImageDraw

LADO = 1024
LOGO = 880


def imagem_simples():
    img = Image.new('RGB', (LADO, LADO), (14, 14, 16))
    d = ImageDraw.Draw(img)
    d.ellipse((132, 132, LADO - 132, LADO - 132), outline=(255, 138, 31), width=72)
    return img


def imagem_do_logo(caminho):
    try:
        logo = Image.open(caminho).convert('RGBA')
    except Exception as e:  # arquivo com conteúdo errado: avisa e segue com o simples
        print('aviso: o logo não é uma imagem válida (%s)' % e)
        return None
    print('logo: %dx%d' % logo.size)
    logo.thumbnail((LOGO, LOGO), Image.LANCZOS)
    fundo = Image.new('RGBA', (LADO, LADO), (0, 0, 0, 255))
    fundo.alpha_composite(logo, ((LADO - logo.size[0]) // 2, (LADO - logo.size[1]) // 2))
    return fundo.convert('RGB')  # sem canal alfa (ITMS-90717)


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    saida = sys.argv[1]
    pasta = os.path.join(saida, 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(pasta, exist_ok=True)

    img = None
    if len(sys.argv) == 3 and os.path.isfile(sys.argv[2]):
        img = imagem_do_logo(sys.argv[2])
    if img is None:
        print('aviso: sem o logo, usando um ícone simples')
        img = imagem_simples()
    img.save(os.path.join(pasta, 'icone-1024.png'), 'PNG')

    with open(os.path.join(saida, 'Assets.xcassets', 'Contents.json'), 'w') as f:
        json.dump({'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    with open(os.path.join(pasta, 'Contents.json'), 'w') as f:
        json.dump({
            'images': [{'filename': 'icone-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
            'info': {'author': 'xcode', 'version': 1},
        }, f, indent=2)
    print('ok: %s' % pasta)


if __name__ == '__main__':
    main()
