// hl2ios: posição da arma na mão do Half-Life 2.
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). O HL2 não tem comando para mover a arma (só viewmodel_fov, para o
// FOV, ajustado em hl2ios_jogo.c). Toda arma do jogo passa, a cada imagem, por
// CBaseHLCombatWeapon::AddViewmodelBob(viewmodel, Vector &origem, QAngle &angulos), que balança
// a arma ao andar mexendo na posição e nos ângulos do modelo em primeira pessoa antes de ele ser
// posto no lugar (C_BaseViewModel::CalcViewModelView). O patch 0007 troca essa função traduzida
// (client.so 0x2234c0, conferida byte a byte pelo tools/lift.py) por hl2ios_native_bob_da_arma:
// ela roda a original e depois empurra a origem para a frente, para o lado e para cima, nos eixos
// da câmera. O clarão do tiro e o rastro das balas saem de pontos do próprio modelo: acompanham.
//
// Conferido no client.so do depot 224: as 22 armas do jogo usam essa mesma função (entrada 349
// da tabela virtual); só a arma de teste (cycler) e a de cubemap usam a vazia da classe base.
// P2_NATIVE_HL2IOS_ARMA=0 desliga.
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "hl2ios_arma.h"
#include "modules.h"
#include "rt.h"

static char classe[48];
static uint32_t ultima_arma;

const char *hl2ios_arma_classe(void) {
    return classe;
}

static int legivel(uint32_t a, uint32_t n) {
    return a >= 0x10000 && a < RT_IMPORT_BASE - n && rt_guest_readable(a) && rt_guest_readable(a + n - 1);
}

// Classe da arma pelo ClientClass do jogo: IClientNetworkable fica a +8 no C_BaseEntity
// (IClientUnknown, IClientRenderable, IClientNetworkable, IClientThinkable), GetClientClass é a 3ª
// entrada da tabela dele, e o nome de rede do ClientClass fica a +8 ("CWeaponSMG1").
static void identificar(CPU *c, uint32_t arma) {
    if (arma == ultima_arma) return;
    ultima_arma = arma;
    char antes[sizeof(classe)];
    snprintf(antes, sizeof(antes), "%s", classe);
    classe[0] = 0;
    uint32_t rede = arma + 8;
    if (legivel(rede, 4) && legivel(R32(rede) + 8, 4)) {
        uint32_t cc = rt_invoke(c, R32(R32(rede) + 8), &rede, 1);
        uint32_t nome = legivel(cc, 12) ? R32(cc + 8) : 0;
        if (legivel(nome, 1)) {
            size_t n = 0;
            while (n + 1 < sizeof(classe) && legivel(nome + n, 1)) {
                char ch = (char)R8(nome + n);
                if (!ch) break;
                if (ch < 32 || ch > 126) { n = 0; break; }
                classe[n++] = ch;
            }
            classe[n] = 0;
            if (classe[0] != 'C') classe[0] = 0;
        }
    }
    if (strcmp(antes, classe))
        fprintf(stderr, "[hl2ios] arma na mão: %s\n", classe[0] ? classe : "(classe não identificada)");
}

// QAngle (graus: inclinação, guinada, rolagem) para os eixos da câmera, como AngleVectors.
static void eixos(const float *ang, float frente[3], float direita[3], float cima[3]) {
    const double g = M_PI / 180;
    double sp = sin(ang[0] * g), cp = cos(ang[0] * g), sy = sin(ang[1] * g), cy = cos(ang[1] * g);
    double sr = sin(ang[2] * g), cr = cos(ang[2] * g);
    frente[0] = (float)(cp * cy); frente[1] = (float)(cp * sy); frente[2] = (float)-sp;
    direita[0] = (float)(-sr * sp * cy + cr * sy); direita[1] = (float)(-sr * sp * sy - cr * cy); direita[2] = (float)(-sr * cp);
    cima[0] = (float)(cr * sp * cy + sr * sy); cima[1] = (float)(cr * sp * sy - sr * cy); cima[2] = (float)(cr * cp);
}

int hl2ios_native_bob_da_arma(CPU *c, uint32_t entry);
int hl2ios_native_bob_da_arma(CPU *c, uint32_t entry) {
    static int dentro;
    if (dentro) return 0;   // a chamada feita aqui embaixo: roda a função original
    // [esp]: retorno; [esp+4]: a arma (this); +8: o viewmodel; +12: &origem; +16: &angulos.
    uint32_t args[4] = {R32(c->esp + 4), R32(c->esp + 8), R32(c->esp + 12), R32(c->esp + 16)};
    dentro = 1;
    rt_invoke(c, entry, args, 4);
    dentro = 0;
    identificar(c, args[0]);
    float frente, lado, altura, fov;
    hl2ios_toque_arma(classe, &frente, &lado, &altura, &fov);
    if ((frente || lado || altura) && legivel(args[2], 12) && legivel(args[3], 12)) {
        float origem[3], ang[3], f[3], d[3], u[3];
        memcpy(origem, GPTR(args[2]), sizeof(origem));
        memcpy(ang, GPTR(args[3]), sizeof(ang));
        eixos(ang, f, d, u);
        for (int i = 0; i < 3; ++i) origem[i] += f[i] * frente + d[i] * lado + u[i] * altura;
        if (isfinite(origem[0]) && isfinite(origem[1]) && isfinite(origem[2])) memcpy(GPTR(args[2]), origem, sizeof(origem));
    }
    rt_return(c);
    return 1;
}
#endif
