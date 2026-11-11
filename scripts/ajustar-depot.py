#!/usr/bin/env python3
# Ajustes de bytes nos binários do depot, feitos logo depois de baixar (scripts/baixar-depot.sh)
# e antes da tradução: o código traduzido e o app saem do binário já ajustado.
#
# Cada ajuste confere os bytes originais no lugar exato antes de trocar. Se o depot não for o
# fixado em versoes.env, nada confere e o build para. Ao mudar esta lista, suba DEPOT_AJUSTES em
# versoes.env: o cache dos módulos preparados (scripts/compilar.sh) vale só para o mesmo valor.
import sys

AJUSTES = [
    # CWeaponShotgun::SecondaryAttack (tiro duplo da escopeta): FireBulletsInfo_t.m_iShots = 12,
    # "mov dword [ebp-0x68], 12". Vai a 24, o dobro, como o tiro normal (sk_plr_num_shotgun_pellets,
    # dobrada pelo app em extras/hl2ios_jogo.c).
    ('hl2_complete/bin/server.so', 0x801a59, 'c7 45 98 0c 00 00 00', 'c7 45 98 18 00 00 00',
     'escopeta: tiro duplo com 24 bagos'),
]


def main(depot):
    for arquivo, deslocamento, original, novo, descricao in AJUSTES:
        caminho = '%s/%s' % (depot, arquivo)
        original, novo = bytes.fromhex(original), bytes.fromhex(novo)
        with open(caminho, 'r+b') as f:
            f.seek(deslocamento)
            tem = f.read(len(original))
            if tem == novo:
                print('ajuste: %s (já estava)' % descricao)
                continue
            if tem != original:
                print('::error::ajuste "%s": bytes diferentes em %s %#x (veio %s)'
                      % (descricao, arquivo, deslocamento, tem.hex(' ')))
                return 1
            f.seek(deslocamento)
            f.write(novo)
        print('ajuste: %s' % descricao)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
