// hl2ios: editor dos controles de toque do Half-Life 2.
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). O source-recomp desenha os botões a partir de uma tabela fixa
// (touch_layout.c); este arquivo guarda, por botão, o que o jogador mudou nela (posição,
// tamanho, oculto, alternar, mirar ao arrastar), mais a opacidade e o tamanho dos sticks, e o
// touch_controls.m aplica isso ao montar a disposição (patches/0003).
//
// O editor abre pelo botão de engrenagem, por cima do menu de pausa, numa janela própria acima
// da do jogo: arrastar move um botão, a pinça muda o tamanho, e o painel tem o resto. Nada é
// gravado antes de Concluir; Cancelar, Restaurar tudo e Apagar perguntam antes.
//
// Novo botão cria um botão a mais (até 24), a partir de um modelo (guardar a arma, arma 1 a 6,
// última arma) ou de um comando do console digitado, com ícone e cor escolhidos. O que ele faz
// roda em hl2ios_jogo.c.
//
// Arma ajusta a posição (frente, lado, altura) e o FOV da arma na mão, por arma, com o jogo
// rodando atrás para ver o resultado ao vivo (hl2ios_arma.c e hl2ios_jogo.c aplicam).
//
// A janela não vira a principal (o SDL continua com o foco), e o laço de eventos do SDL não
// deixa o UIKit desenhar sozinho: como o touch_controls.m, o editor termina cada mudança com
// [CATransaction flush], e um observador do laço faz o mesmo a cada passagem.
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "game_ios.h"
#include "hl2ios_arma.h"
#include "hl2ios_jogo.h"
#include "hl2ios_toque.h"

// Arquivo fora do source-recomp: avisos de API antiga ou de parâmetro sem uso não podem parar
// o build (o runtime compila com -Wall -Wextra -Werror).
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunused-parameter"

// ---- o que cada botão é e o que dá para mudar nele ----

enum { PODE_ALTERNAR = 1, PODE_MIRAR = 2, SEMPRE_VISIVEL = 4 };
typedef struct {
    rt_touch_action acao;
    const char *chave;   // nome no hl2-toque.json (não muda entre versões)
    const char *nome;    // no editor
    unsigned pode;
} Info;
static const Info kInfo[] = {
    {RT_TOUCH_FIRE, "tiro", "Tiro", PODE_ALTERNAR | PODE_MIRAR},
    {RT_TOUCH_ALT_FIRE, "tiro-secundario", "Tiro secundário", PODE_ALTERNAR | PODE_MIRAR},
    {RT_TOUCH_RELOAD, "recarregar", "Recarregar", PODE_MIRAR},
    {RT_TOUCH_JUMP, "pulo", "Pulo", PODE_MIRAR},
    {RT_TOUCH_LONG_JUMP, "pulo-agachado", "Pulo agachado", PODE_MIRAR},
    {RT_TOUCH_CROUCH, "agachar", "Agachar", PODE_ALTERNAR | PODE_MIRAR},
    {RT_TOUCH_USE, "usar", "Usar", PODE_MIRAR},
    {RT_TOUCH_SPRINT, "correr", "Correr", PODE_ALTERNAR | PODE_MIRAR},
    {RT_TOUCH_FLASHLIGHT, "lanterna", "Lanterna", PODE_MIRAR},
    {RT_TOUCH_WEAPON_PREV, "arma-anterior", "Arma anterior", 0},
    {RT_TOUCH_WEAPON_NEXT, "arma-seguinte", "Arma seguinte", 0},
    {RT_TOUCH_QUICKSAVE, "salvar", "Salvar (segure: carregar)", 0},
    {RT_TOUCH_PAUSE, "pausa", "Pausa", 0},
    {RT_TOUCH_LOOK_MODE, "modo-camera", "Stick ou trackpad", 0},
    {RT_TOUCH_EDIT, "editor", "Editor", SEMPRE_VISIVEL},
};
enum { N_INFO = (int)(sizeof(kInfo) / sizeof(*kInfo)) };

static const Info *info_de(rt_touch_action acao) {
    for (int i = 0; i < N_INFO; ++i)
        if (kInfo[i].acao == acao) return &kInfo[i];
    return NULL;
}

// ---- botões criados: modelos, cores e ícones ----

enum { TIPO_COMANDO, TIPO_GUARDAR, TIPO_ARMA };
typedef struct {
    const char *chave, *nome;
    const char *comando;   // TIPO_ARMA: o comando do jogo
    const char *icone;     // ícone ao escolher o modelo
    int tipo;
} Modelo;
static const Modelo kModelos[] = {
    {"guardar", "Guardar arma", NULL, "hand.raised.fill", TIPO_GUARDAR},
    {"arma1", "Arma 1", "slot1", "1.circle", TIPO_ARMA},
    {"arma2", "Arma 2", "slot2", "2.circle", TIPO_ARMA},
    {"arma3", "Arma 3", "slot3", "3.circle", TIPO_ARMA},
    {"arma4", "Arma 4", "slot4", "4.circle", TIPO_ARMA},
    {"arma5", "Arma 5", "slot5", "5.circle", TIPO_ARMA},
    {"arma6", "Arma 6", "slot6", "6.circle", TIPO_ARMA},
    {"ultima-arma", "Última arma", "lastinv", "arrow.left.arrow.right", TIPO_ARMA},
    {"comando", "Comando", NULL, "terminal.fill", TIPO_COMANDO},
};
enum { N_MODELOS = (int)(sizeof(kModelos) / sizeof(*kModelos)), MODELO_COMANDO = N_MODELOS - 1 };

// As quatro primeiras são as do touch_controls.m (palette_init).
static const struct { const char *chave; float r, g, b, a; } kCores[] = {
    {"escuro", 0, 0, 0, .35f},       {"azul", .16f, .55f, 1, .6f},   {"laranja", 1, .55f, .05f, .6f},
    {"vermelho", .75f, .12f, .08f, .45f}, {"verde", .14f, .62f, .24f, .55f}, {"roxo", .55f, .25f, .85f, .55f},
    {"amarelo", .95f, .8f, .1f, .55f}, {"branco", 1, 1, 1, .35f},
};
enum { N_CORES = (int)(sizeof(kCores) / sizeof(*kCores)) };

static const char *const kIcones[] = {
    "hand.raised.fill", "1.circle", "2.circle", "3.circle", "4.circle", "5.circle", "6.circle",
    "arrow.left.arrow.right", "terminal.fill", "scope", "target", "flame.fill", "bolt.fill", "burst.fill",
    "shield.fill", "cross.case.fill", "heart.fill", "star.fill", "eye.fill", "binoculars.fill",
    "magnifyingglass", "lightbulb.fill", "flag.fill", "bell.fill", "figure.walk", "figure.run",
    "arrow.up", "arrow.down", "arrow.clockwise", "car.fill", "hammer.fill", "wrench.fill",
    "speaker.wave.2.fill", "camera.fill", "map.fill", "gamecontroller.fill", "plus", "minus",
    "xmark", "questionmark", "circle.fill", "square.fill", "triangle.fill",
};
enum { N_ICONES = (int)(sizeof(kIcones) / sizeof(*kIcones)) };

enum { MAX_PERS = RT_TOUCH_CUSTOM_LAST - RT_TOUCH_CUSTOM + 1, COMANDO = 256, ICONE = 48 };
typedef struct {
    int modelo, cor;        // índices em kModelos e kCores
    char comando[COMANDO];  // TIPO_COMANDO: a linha do console
    char icone[ICONE];      // nome SF Symbols
    double fx, fy;          // centro, em fração da zona segura
    float tamanho;          // diâmetro em pontos
    int alternar, mirar;    // 0 ou 1 (alternar só vale para comando)
} Pers;

static const float kTamanhoPers = 54;

// ---- ajuste da arma na mão ----

enum { MAX_ARMAS = 32, CLASSE = 48 };
typedef struct {
    char classe[CLASSE];          // nome de rede da arma ("CWeaponSMG1")
    float frente, lado, altura;   // unidades do jogo, nos eixos da câmera
    float fov;                    // FOV da arma (0: o do jogo)
} ArmaAj;
static const float kDeslocMax = 12, kFovMin = 40, kFovMax = 110, kFovJogo = 54;

// Nomes das armas no editor (as que não estão aqui aparecem pelo nome de rede).
static const struct { const char *classe, *nome; } kNomesArmas[] = {
    {"CWeaponCrowbar", "Pé de cabra"},    {"CWeaponPhysCannon", "Arma de gravidade"},
    {"CWeaponPistol", "Pistola"},         {"CWeapon357", "Revólver .357"},
    {"CWeaponSMG1", "SMG"},               {"CWeaponAR2", "Rifle de pulso (AR2)"},
    {"CWeaponShotgun", "Escopeta"},       {"CWeaponCrossbow", "Besta"},
    {"CWeaponFrag", "Granada"},           {"CWeaponRPG", "Lança-foguetes (RPG)"},
    {"CWeaponBugBait", "Feromônio"},      {"CWeaponAnnabelle", "Annabelle"},
    {"CWeaponStunStick", "Cassetete"},    {"CWeaponStunStickPlayer", "Cassetete"},
    {"CWeaponAlyxGun", "Arma da Alyx"},   {"CWeaponHopwire", "Hopwire"},
    {"CWeapon_SLAM", "SLAM"},
};

// ---- ajustes ----

static const float kTamanhoMin = 28, kTamanhoMax = 140;
static const float kOpacidadeMin = .15f, kSticksMin = .6f, kSticksMax = 1.6f;

typedef struct {
    int posicao;          // 1: fx e fy valem
    double fx, fy;        // centro, em fração da zona segura
    float tamanho;        // diâmetro em pontos (0: o da tabela)
    int oculto;           // 1: não aparece no jogo
    int alternar, mirar;  // -1: o da tabela; 0 ou 1
} Ajuste;
typedef struct {
    Ajuste botao[RT_TOUCH_ACTION_COUNT];
    float opacidade, sticks;
    Pers pers[MAX_PERS];   // botões criados, na ordem em que foram criados
    int nPers;
    ArmaAj armas[MAX_ARMAS];   // ajuste por arma
    int nArmas;
    ArmaAj geral;              // armas sem ajuste próprio (Copiar para todas)
} Ajustes;

static void ajuste_padrao(Ajuste *j) {
    memset(j, 0, sizeof(*j));
    j->alternar = j->mirar = -1;
}
static void ajustes_padrao(Ajustes *a) {
    memset(a, 0, sizeof(*a));
    for (int i = 0; i < RT_TOUCH_ACTION_COUNT; ++i) ajuste_padrao(&a->botao[i]);
    a->opacidade = 1;
    a->sticks = 1;
}
static int ajustes_iguais(const Ajustes *a, const Ajustes *b) {
    if (a->opacidade != b->opacidade || a->sticks != b->sticks) return 0;
    for (int i = 0; i < RT_TOUCH_ACTION_COUNT; ++i) {
        const Ajuste *x = &a->botao[i], *y = &b->botao[i];
        if (x->posicao != y->posicao || x->tamanho != y->tamanho || x->oculto != y->oculto ||
            x->alternar != y->alternar || x->mirar != y->mirar) return 0;
        if (x->posicao && (x->fx != y->fx || x->fy != y->fy)) return 0;
    }
    if (a->nPers != b->nPers) return 0;
    for (int i = 0; i < a->nPers; ++i) {
        const Pers *x = &a->pers[i], *y = &b->pers[i];
        if (x->modelo != y->modelo || x->cor != y->cor || strcmp(x->comando, y->comando) || strcmp(x->icone, y->icone) ||
            x->fx != y->fx || x->fy != y->fy || x->tamanho != y->tamanho || x->alternar != y->alternar ||
            x->mirar != y->mirar) return 0;
    }
    if (a->nArmas != b->nArmas) return 0;
    for (int i = 0; i <= a->nArmas; ++i) {
        const ArmaAj *x = i < a->nArmas ? &a->armas[i] : &a->geral, *y = i < b->nArmas ? &b->armas[i] : &b->geral;
        if (strcmp(x->classe, y->classe) || x->frente != y->frente || x->lado != y->lado || x->altura != y->altura ||
            x->fov != y->fov) return 0;
    }
    return 1;
}

// Ajuste desta arma: o dela, ou o geral.
static const ArmaAj *arma_de(const Ajustes *a, const char *classe) {
    if (classe && classe[0])
        for (int i = 0; i < a->nArmas; ++i)
            if (!strcmp(a->armas[i].classe, classe)) return &a->armas[i];
    return &a->geral;
}
// O dela, criado a partir do geral se ainda não existe (NULL sem arma ou sem espaço).
static ArmaAj *arma_propria(Ajustes *a, const char *classe) {
    if (!classe || !classe[0]) return NULL;
    for (int i = 0; i < a->nArmas; ++i)
        if (!strcmp(a->armas[i].classe, classe)) return &a->armas[i];
    if (a->nArmas == MAX_ARMAS) return NULL;
    ArmaAj *j = &a->armas[a->nArmas++];
    *j = a->geral;
    snprintf(j->classe, sizeof(j->classe), "%s", classe);
    return j;
}

static double limitar(double v, double lo, double hi) {
    return hi < lo ? (lo + hi) / 2 : fmin(hi, fmax(lo, v));
}

// Posição, tamanho e opções finais do botão. Devolve 0 se ele está oculto e `ocultar` vale
// (no editor, os ocultos continuam à vista).
static int aplicar(const Ajustes *a, rt_touch_action acao, int ocultar, double x, double y, double w, double h,
                   double *cx, double *cy, float *tamanho, unsigned *flags) {
    if ((int)acao < 0 || (int)acao >= RT_TOUCH_ACTION_COUNT) return 1;
    const Ajuste *j = &a->botao[acao];
    const Info *info = info_de(acao);
    unsigned pode = info ? info->pode : 0;
    if (ocultar && j->oculto && !(pode & SEMPRE_VISIVEL)) return 0;
    if (j->tamanho > 0) *tamanho = j->tamanho;
    if (j->posicao) {
        *cx = x + w * j->fx;
        *cy = y + h * j->fy;
    }
    if (j->posicao || j->tamanho > 0) {   // nada fica fora da zona segura
        double r = *tamanho / 2.0;
        *cx = limitar(*cx, x + r, x + w - r);
        *cy = limitar(*cy, y + r, y + h - r);
    }
    if ((pode & PODE_ALTERNAR) && j->alternar >= 0)
        *flags = j->alternar ? (*flags | (unsigned)RT_TOUCH_TOGGLE) : (*flags & ~(unsigned)RT_TOUCH_TOGGLE);
    if ((pode & PODE_MIRAR) && j->mirar >= 0)
        *flags = j->mirar ? (*flags | (unsigned)RT_TOUCH_AIM) : (*flags & ~(unsigned)RT_TOUCH_AIM);
    return 1;
}

// O mesmo para um botão criado.
static void aplicar_pers(const Pers *p, double x, double y, double w, double h, double *cx, double *cy,
                         float *tamanho, unsigned *flags) {
    *tamanho = p->tamanho > 0 ? p->tamanho : kTamanhoPers;
    double r = *tamanho / 2.0;
    *cx = limitar(x + w * p->fx, x + r, x + w - r);
    *cy = limitar(y + h * p->fy, y + r, y + h - r);
    *flags = 0;
    if (p->alternar && kModelos[p->modelo].tipo == TIPO_COMANDO) *flags |= RT_TOUCH_TOGGLE;
    if (p->mirar) *flags |= RT_TOUCH_AIM;
}

static void pers_novo(Pers *p, int modelo) {
    memset(p, 0, sizeof(*p));
    p->modelo = modelo;
    snprintf(p->icone, sizeof(p->icone), "%s", kModelos[modelo].icone);
    p->fx = .5;
    p->fy = .3;
    p->tamanho = kTamanhoPers;
}

// ---- arquivo (Documents/hl2-toque.json) ----

static Ajustes salvos;
static int carregados;

static NSString *documento(NSString *nome) {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:nome];
}
static double numero(id v, double padrao, double min, double max) {
    if (![v isKindOfClass:NSNumber.class]) return padrao;
    double d = [(NSNumber *)v doubleValue];
    return isfinite(d) ? fmin(max, fmax(min, d)) : padrao;
}
static int sim_nao(id v, int padrao) {
    return [v isKindOfClass:NSNumber.class] ? ([(NSNumber *)v boolValue] ? 1 : 0) : padrao;
}

static void arma_ler(id v, ArmaAj *j) {
    if (![v isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = v;
    j->frente = (float)numero(d[@"frente"], 0, -kDeslocMax, kDeslocMax);
    j->lado = (float)numero(d[@"lado"], 0, -kDeslocMax, kDeslocMax);
    j->altura = (float)numero(d[@"altura"], 0, -kDeslocMax, kDeslocMax);
    j->fov = [d[@"fov"] isKindOfClass:NSNumber.class] ? (float)numero(d[@"fov"], 0, kFovMin, kFovMax) : 0;
}

static void carregar(void) {
    if (carregados) return;
    carregados = 1;
    ajustes_padrao(&salvos);
    NSData *dados = [NSData dataWithContentsOfFile:documento(@"hl2-toque.json")];
    if (!dados) {
        fprintf(stderr, "[hl2ios] toque: sem hl2-toque.json, disposição padrão\n");
        return;
    }
    id lido = [NSJSONSerialization JSONObjectWithData:dados options:0 error:NULL];
    if (![lido isKindOfClass:NSDictionary.class]) {
        fprintf(stderr, "[hl2ios] toque: hl2-toque.json ilegível, disposição padrão\n");
        return;
    }
    NSDictionary *raiz = lido;
    salvos.opacidade = (float)numero(raiz[@"opacidade"], 1, kOpacidadeMin, 1);
    salvos.sticks = (float)numero(raiz[@"sticks"], 1, kSticksMin, kSticksMax);
    NSDictionary *botoes = raiz[@"botoes"];
    int lidos = 0;
    if ([botoes isKindOfClass:NSDictionary.class]) {
        for (int i = 0; i < N_INFO; ++i) {
            NSDictionary *b = botoes[@(kInfo[i].chave)];
            if (![b isKindOfClass:NSDictionary.class]) continue;
            Ajuste *j = &salvos.botao[kInfo[i].acao];
            if ([b[@"x"] isKindOfClass:NSNumber.class] && [b[@"y"] isKindOfClass:NSNumber.class]) {
                j->posicao = 1;
                j->fx = numero(b[@"x"], .5, 0, 1);
                j->fy = numero(b[@"y"], .5, 0, 1);
            }
            if ([b[@"tamanho"] isKindOfClass:NSNumber.class])
                j->tamanho = (float)numero(b[@"tamanho"], 0, kTamanhoMin, kTamanhoMax);
            j->oculto = (kInfo[i].pode & SEMPRE_VISIVEL) ? 0 : sim_nao(b[@"oculto"], 0);
            j->alternar = sim_nao(b[@"alternar"], -1);
            j->mirar = sim_nao(b[@"mirar"], -1);
            ++lidos;
        }
    }
    NSArray *criados = raiz[@"personalizados"];
    if ([criados isKindOfClass:NSArray.class]) {
        for (id item in criados) {
            if (salvos.nPers == MAX_PERS || ![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *d = item;
            int modelo = -1, cor = 0;
            for (int m = 0; m < N_MODELOS; ++m)
                if ([d[@"modelo"] isEqual:@(kModelos[m].chave)]) modelo = m;
            if (modelo < 0) continue;   // modelo de uma versão mais nova: deixado de fora
            for (int k = 0; k < N_CORES; ++k)
                if ([d[@"cor"] isEqual:@(kCores[k].chave)]) cor = k;
            Pers *p = &salvos.pers[salvos.nPers++];
            pers_novo(p, modelo);
            p->cor = cor;
            if ([d[@"comando"] isKindOfClass:NSString.class])
                snprintf(p->comando, sizeof(p->comando), "%s", [(NSString *)d[@"comando"] UTF8String]);
            if ([d[@"icone"] isKindOfClass:NSString.class] && [(NSString *)d[@"icone"] length])
                snprintf(p->icone, sizeof(p->icone), "%s", [(NSString *)d[@"icone"] UTF8String]);
            p->fx = numero(d[@"x"], .5, 0, 1);
            p->fy = numero(d[@"y"], .3, 0, 1);
            p->tamanho = (float)numero(d[@"tamanho"], kTamanhoPers, kTamanhoMin, kTamanhoMax);
            p->alternar = sim_nao(d[@"alternar"], 0);
            p->mirar = sim_nao(d[@"mirar"], 0);
        }
    }
    salvos.geral.classe[0] = 0;
    arma_ler(raiz[@"arma-geral"], &salvos.geral);
    NSDictionary *armas = raiz[@"armas"];
    if ([armas isKindOfClass:NSDictionary.class]) {
        for (NSString *nome in [armas.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if (salvos.nArmas == MAX_ARMAS || ![nome isKindOfClass:NSString.class] || !nome.length ||
                [nome lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= CLASSE) continue;
            ArmaAj *j = &salvos.armas[salvos.nArmas++];
            memset(j, 0, sizeof(*j));
            snprintf(j->classe, sizeof(j->classe), "%s", nome.UTF8String);
            arma_ler(armas[nome], j);
        }
    }
    fprintf(stderr, "[hl2ios] toque: hl2-toque.json com %d botões ajustados, %d criados e %d armas ajustadas, opacidade "
            "%.2f, sticks %.2f\n", lidos, salvos.nPers, salvos.nArmas, salvos.opacidade, salvos.sticks);
}

// Texto em UTF-8 para NSString; "" se não for UTF-8 válido (nunca nil num dicionário).
static NSString *texto(const char *c) {
    NSString *t = c ? [NSString stringWithUTF8String:c] : nil;
    return t ?: @"";
}

static double arredondar(double v, double passo) {
    return round(v / passo) * passo;
}

static NSDictionary *arma_dic(const ArmaAj *j) {
    NSMutableDictionary *d = [@{
        @"frente": @(arredondar(j->frente, .1)),
        @"lado": @(arredondar(j->lado, .1)),
        @"altura": @(arredondar(j->altura, .1)),
    } mutableCopy];
    if (j->fov > 0) d[@"fov"] = @(arredondar(j->fov, .1));
    return d;
}

// Grava os ajustes; a versão anterior do arquivo fica em hl2-toque-anterior.json.
static BOOL gravar(const Ajustes *a) {
    NSMutableDictionary *botoes = [NSMutableDictionary dictionary];
    for (int i = 0; i < N_INFO; ++i) {
        const Ajuste *j = &a->botao[kInfo[i].acao];
        NSMutableDictionary *b = [NSMutableDictionary dictionary];
        if (j->posicao) {
            b[@"x"] = @(arredondar(j->fx, .0001));
            b[@"y"] = @(arredondar(j->fy, .0001));
        }
        if (j->tamanho > 0) b[@"tamanho"] = @(arredondar(j->tamanho, .1));
        if (j->oculto) b[@"oculto"] = @YES;
        if (j->alternar >= 0) b[@"alternar"] = j->alternar ? @YES : @NO;
        if (j->mirar >= 0) b[@"mirar"] = j->mirar ? @YES : @NO;
        if (b.count) botoes[@(kInfo[i].chave)] = b;
    }
    NSMutableArray *criados = [NSMutableArray array];
    for (int i = 0; i < a->nPers; ++i) {
        const Pers *p = &a->pers[i];
        NSMutableDictionary *d = [@{
            @"modelo": @(kModelos[p->modelo].chave),
            @"icone": texto(p->icone),
            @"cor": @(kCores[p->cor].chave),
            @"x": @(arredondar(p->fx, .0001)),
            @"y": @(arredondar(p->fy, .0001)),
            @"tamanho": @(arredondar(p->tamanho, .1)),
        } mutableCopy];
        if (kModelos[p->modelo].tipo == TIPO_COMANDO) d[@"comando"] = texto(p->comando);
        if (p->alternar) d[@"alternar"] = @YES;
        if (p->mirar) d[@"mirar"] = @YES;
        [criados addObject:d];
    }
    NSMutableDictionary *armas = [NSMutableDictionary dictionary];
    for (int i = 0; i < a->nArmas; ++i) armas[texto(a->armas[i].classe)] = arma_dic(&a->armas[i]);
    NSDictionary *raiz = @{
        @"versao": @3,
        @"armas": armas,
        @"arma-geral": arma_dic(&a->geral),
        @"opacidade": @(arredondar(a->opacidade, .01)),
        @"sticks": @(arredondar(a->sticks, .01)),
        @"botoes": botoes,
        @"personalizados": criados,
    };
    NSData *dados = [NSJSONSerialization dataWithJSONObject:raiz
                                                    options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                      error:NULL];
    NSString *arquivo = documento(@"hl2-toque.json"), *anterior = documento(@"hl2-toque-anterior.json");
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:arquivo]) {
        [fm removeItemAtPath:anterior error:NULL];
        [fm copyItemAtPath:arquivo toPath:anterior error:NULL];
    }
    BOOL ok = dados && [dados writeToFile:arquivo atomically:YES];
    fprintf(stderr, "[hl2ios] toque: %s hl2-toque.json (%lu botões ajustados, %d criados)\n",
            ok ? "gravado" : "NÃO consegui gravar", (unsigned long)botoes.count, a->nPers);
    return ok;
}

// ---- o que o touch_controls.m chama ----

int hl2ios_toque_ajustar(rt_touch_action acao, double x, double y, double w, double h,
                         double *cx, double *cy, float *tamanho, unsigned *flags) {
    carregar();
    return aplicar(&salvos, acao, 1, x, y, w, h, cx, cy, tamanho, flags);
}

float hl2ios_toque_opacidade(void) {
    carregar();
    return salvos.opacidade;
}

float hl2ios_toque_escala_sticks(void) {
    carregar();
    return salvos.sticks;
}

// O que está em edição enquanto o editor está aberto (o jogo mostra ao vivo), o gravado fora dele.
static const Ajustes *ativos;

void hl2ios_toque_arma(const char *classe, float *frente, float *lado, float *altura, float *fov) {
    carregar();
    const ArmaAj *j = arma_de(ativos ? ativos : &salvos, classe);
    *frente = j->frente;
    *lado = j->lado;
    *altura = j->altura;
    *fov = j->fov;
}

int hl2ios_toque_personalizados(void) {
    carregar();
    return salvos.nPers;
}

int hl2ios_toque_personalizado(int i, double x, double y, double w, double h, double *cx, double *cy,
                               float *tamanho, unsigned *flags, const char **simbolo, float rgba[4], int *guardar) {
    carregar();
    if (i < 0 || i >= salvos.nPers) return -1;
    const Pers *p = &salvos.pers[i];
    aplicar_pers(p, x, y, w, h, cx, cy, tamanho, flags);
    *simbolo = p->icone[0] ? p->icone : kModelos[p->modelo].icone;
    rgba[0] = kCores[p->cor].r;
    rgba[1] = kCores[p->cor].g;
    rgba[2] = kCores[p->cor].b;
    rgba[3] = kCores[p->cor].a;
    *guardar = kModelos[p->modelo].tipo == TIPO_GUARDAR;
    return RT_TOUCH_CUSTOM + i;
}

// Para soltar um comando: "-x" para cada parte que começa com "+x" ("+jump; +duck" vira
// "-jump;-duck"). Devolve 0 se não há nada a soltar.
static int soltura(const char *linha, char *saida, size_t tamanho) {
    size_t n = 0;
    saida[0] = 0;
    for (const char *p = linha; *p;) {
        while (*p == ' ' || *p == ';') ++p;
        if (*p == '+') {
            const char *fim = p + 1;
            while (*fim && *fim != ' ' && *fim != ';') ++fim;
            if (fim > p + 1 && n + (size_t)(fim - p) + 2 < tamanho) {
                n += (size_t)snprintf(saida + n, tamanho - n, "%s-%.*s", n ? ";" : "", (int)(fim - p - 1), p + 1);
            }
        }
        while (*p && *p != ';') ++p;
    }
    return n > 0;
}

void hl2ios_toque_executar(int i, int apertou) {
    carregar();
    if (i < 0 || i >= salvos.nPers) return;
    const Pers *p = &salvos.pers[i];
    const Modelo *m = &kModelos[p->modelo];
    if (m->tipo == TIPO_GUARDAR) {
        if (apertou) hl2ios_jogo_guardar();
    } else if (m->tipo == TIPO_ARMA) {
        if (apertou) {
            hl2ios_jogo_selecao();
            hl2ios_jogo_comando(m->comando);
        }
    } else if (apertou) {
        hl2ios_jogo_comando(p->comando);
    } else {
        char solta[COMANDO];
        if (soltura(p->comando, solta, sizeof(solta))) hl2ios_jogo_comando(solta);
    }
}

// ---- editor ----

static void editor_fechar(int salvou);
static UIWindow *janela;
static void (^ao_pausar)(int pausar);   // touch_controls.m: fecha (0) ou abre (1) o menu de pausa

// O campo do comando só recebe o teclado na janela principal: o editor a pega enquanto o campo
// está em uso e a devolve (à do SDL) quando ele termina ou o editor fecha.
static UIWindow *chave_anterior;
static void pegar_chave(void) {
    if (!janela || janela.isKeyWindow) return;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (w.isKeyWindow) chave_anterior = w;
    [janela makeKeyWindow];
}
static void devolver_chave(void) {
    UIWindow *w = chave_anterior;
    chave_anterior = nil;
    if (w) [w makeKeyWindow];
}

static UIColor *laranja(void) {
    return [UIColor colorWithRed:.98 green:.55 blue:.05 alpha:1];
}
// As mesmas cores do touch_controls.m (palette_init).
static UIColor *cor_de(rt_touch_color c) {
    switch (c) {
    case RT_TOUCH_RED: return [UIColor colorWithRed:.75 green:.12 blue:.08 alpha:.45];
    case RT_TOUCH_ORANGE: return [UIColor colorWithRed:1 green:.55 blue:.05 alpha:.6];
    case RT_TOUCH_BLUE: return [UIColor colorWithRed:.16 green:.55 blue:1 alpha:.6];
    default: return [UIColor colorWithWhite:0 alpha:.35];
    }
}

static UIColor *cor_pers(int cor) {
    return [UIColor colorWithRed:kCores[cor].r green:kCores[cor].g blue:kCores[cor].b alpha:kCores[cor].a];
}
static NSString *nome_pers(const Pers *p) {
    if (kModelos[p->modelo].tipo != TIPO_COMANDO || !p->comando[0]) return @(kModelos[p->modelo].nome);
    NSString *t = texto(p->comando);
    if (t.length <= 22) return t;
    return [[t substringWithRange:[t rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 21)]] stringByAppendingString:@"…"];
}

// Um botão no editor: o círculo com o ícone, e o nome embaixo.
@interface HL2EdBotao : UIView
@property (nonatomic) rt_touch_action acao;
@property (nonatomic) int indice;   // posição na tabela de touch_layout.c
@property (nonatomic) int pers;     // botão criado: índice em Ajustes.pers (-1: da tabela)
@property (nonatomic) float tamanho;
@property (nonatomic, copy) NSString *simbolo;
@property (nonatomic, strong) UIImageView *icone;
@property (nonatomic, strong) UILabel *rotulo;
- (instancetype)initWithAcao:(rt_touch_action)acao simbolo:(NSString *)simbolo cor:(UIColor *)cor;
- (void)mostrarEm:(CGPoint)centro tamanho:(float)tamanho;
- (void)trocarSimbolo:(NSString *)simbolo;
@end

@implementation HL2EdBotao
- (instancetype)initWithAcao:(rt_touch_action)acao simbolo:(NSString *)simbolo cor:(UIColor *)cor {
    if ((self = [super initWithFrame:CGRectZero])) {
        _acao = acao;
        _pers = -1;
        _simbolo = [simbolo copy];
        self.backgroundColor = cor;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:.45].CGColor;
        self.userInteractionEnabled = NO;   // os toques vão para a tela do editor, que decide
        _icone = [[UIImageView alloc] init];
        _icone.tintColor = [UIColor colorWithWhite:1 alpha:.9];
        _icone.contentMode = UIViewContentModeCenter;
        [self addSubview:_icone];
        _rotulo = [[UILabel alloc] init];
        _rotulo.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _rotulo.textColor = UIColor.whiteColor;
        _rotulo.textAlignment = NSTextAlignmentCenter;
        _rotulo.shadowColor = UIColor.blackColor;
        _rotulo.shadowOffset = CGSizeMake(0, 1);
        const Info *info = info_de(acao);
        _rotulo.text = info ? @(info->nome) : @"";
        [self addSubview:_rotulo];
    }
    return self;
}
- (void)mostrarEm:(CGPoint)centro tamanho:(float)tamanho {
    if (tamanho != _tamanho || !_icone.image) {
        _tamanho = tamanho;
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:tamanho * .38
                                                                                             weight:UIImageSymbolWeightBold];
        _icone.image = _simbolo ? [UIImage systemImageNamed:_simbolo withConfiguration:config] : nil;
    }
    self.bounds = CGRectMake(0, 0, tamanho, tamanho);
    self.center = centro;
    self.layer.cornerRadius = tamanho / 2;
    _icone.frame = self.bounds;
    _rotulo.frame = CGRectMake(-50, tamanho + 1, tamanho + 100, 13);
}
- (void)trocarSimbolo:(NSString *)simbolo {
    _simbolo = [simbolo copy];
    _icone.image = nil;   // refeito no próximo mostrarEm
}
@end

typedef void (^HL2EdAcao)(void);

// A tela do editor: os botões, a divisa dos sticks, o painel, a folha do botão criado e a
// confirmação.
@interface HL2EdTela : UIView <UITextFieldDelegate>
@end

@implementation HL2EdTela {
    Ajustes trabalho;               // o que está sendo editado (vira `salvos` em Concluir)
    const rt_touch_button *tabela;  // touch_layout.c
    int nTabela;
    NSMutableArray<HL2EdBotao *> *botoes;
    int selecionado;                // índice em `botoes` (-1: nenhum)
    UITouch *arrasto;
    CGPoint deslocamento;           // do dedo ao centro do botão arrastado
    float tamanhoBase;              // tamanho no começo da pinça
    BOOL painelEmbaixo;
    CAShapeLayer *divisa, *anelSticks[2];
    UILabel *divisaTexto;
    UIView *painel;
    UILabel *nome, *dica, *rTamanho, *rAlternar, *rMirar, *rOpacidade, *rSticks;
    UISlider *sTamanho, *sOpacidade, *sSticks;
    UISwitch *swAlternar, *swMirar;
    UIButton *bOcultar, *bPadraoDeste, *bRestaurar, *bMoverPainel, *bCancelar, *bConcluir;
    int nFixos;                     // botões da tabela no começo de `botoes`; depois, os criados
    UIButton *bNovo, *bEditar, *bApagar;
    UIView *folha, *folhaCaixa;     // folha do botão criado: modelo, comando, cor e ícone
    UILabel *folhaTitulo, *campoDica, *rCor;
    UIScrollView *folhaModelos, *folhaIcones;
    NSMutableArray<UIButton *> *bModelos, *bIcones, *bCores;
    UITextField *campo;
    UIButton *bPronto;
    BOOL modoArma;                  // ajuste da arma: só a barra, com o jogo rodando atrás
    UIButton *bArma;
    UIView *barra;
    UILabel *armaNome, *rFrente, *rLado, *rAltura, *rFov;
    UISlider *sFrente, *sLado, *sAltura, *sFov;
    UIButton *bPadraoArma, *bCopiarTodas, *bVoltar;
    NSTimer *relogio;               // acompanha a arma na mão
    NSString *classeVista;
    UIView *confirma, *caixa;
    UILabel *confirmaTexto;
    UIButton *confirmaSim, *confirmaNao;
    HL2EdAcao confirmaAcao;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        carregar();
        trabalho = salvos;
        ativos = &trabalho;   // o jogo mostra a arma com o que está em edição
        selecionado = -1;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:.4];
        self.multipleTouchEnabled = YES;

        // Divisa do meio: à esquerda o dedo vira o stick de andar, à direita o da câmera.
        divisa = [CAShapeLayer layer];
        divisa.strokeColor = [UIColor colorWithWhite:1 alpha:.3].CGColor;
        divisa.lineWidth = 1;
        divisa.lineDashPattern = @[@6, @6];
        [self.layer addSublayer:divisa];
        for (int i = 0; i < 2; ++i) {
            anelSticks[i] = [CAShapeLayer layer];
            anelSticks[i].strokeColor = [UIColor colorWithWhite:1 alpha:.3].CGColor;
            anelSticks[i].fillColor = UIColor.clearColor.CGColor;
            anelSticks[i].lineWidth = 2;
            [self.layer addSublayer:anelSticks[i]];
        }
        divisaTexto = [self rotulo:@"andar  |  câmera" tamanho:11 peso:UIFontWeightMedium em:self];
        divisaTexto.textAlignment = NSTextAlignmentCenter;
        divisaTexto.textColor = [UIColor colorWithWhite:1 alpha:.5];

        tabela = rt_touch_layout(rt_ios_current_game()->layout, &nTabela);
        botoes = [NSMutableArray array];
        for (int i = 0; i < nTabela; ++i) {
            const rt_touch_button *t = &tabela[i];
            if (t->flags & (RT_TOUCH_PORTAL | RT_TOUCH_DATASET)) continue;
            HL2EdBotao *b = [[HL2EdBotao alloc] initWithAcao:t->action
                                                     simbolo:t->symbol ? @(t->symbol) : nil
                                                         cor:cor_de(t->color)];
            b.indice = i;
            [botoes addObject:b];
            [self addSubview:b];
        }
        nFixos = (int)botoes.count;
        [self recriarPersonalizados];
        [self montarPainel];
        [self montarFolha];
        [self montarBarra];
        [self montarConfirmacao];
        UIPinchGestureRecognizer *pinca = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinca:)];
        [self addGestureRecognizer:pinca];
        [self atualizarPainel];
    }
    return self;
}

// ---- peças do painel ----
- (UILabel *)rotulo:(NSString *)texto tamanho:(CGFloat)tamanho peso:(UIFontWeight)peso em:(UIView *)pai {
    UILabel *l = [[UILabel alloc] init];
    l.text = texto;
    l.font = [UIFont systemFontOfSize:tamanho weight:peso];
    l.textColor = UIColor.whiteColor;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = .7;
    [pai addSubview:l];
    return l;
}
- (UIButton *)botao:(NSString *)titulo acao:(SEL)acao destaque:(BOOL)destaque em:(UIView *)pai {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:titulo forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:.55] forState:UIControlStateHighlighted];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:.3] forState:UIControlStateDisabled];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = .7;
    b.backgroundColor = destaque ? laranja() : [UIColor colorWithWhite:1 alpha:.16];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:acao forControlEvents:UIControlEventTouchUpInside];
    [pai addSubview:b];
    return b;
}
- (UISlider *)deslizador:(float)min max:(float)max acao:(SEL)acao {
    UISlider *s = [[UISlider alloc] init];
    s.minimumValue = min;
    s.maximumValue = max;
    s.minimumTrackTintColor = laranja();
    [s addTarget:self action:acao forControlEvents:UIControlEventValueChanged];
    [painel addSubview:s];
    return s;
}
- (UISwitch *)chave:(SEL)acao {
    UISwitch *s = [[UISwitch alloc] init];
    s.onTintColor = laranja();
    s.transform = CGAffineTransformMakeScale(.75, .75);
    [s addTarget:self action:acao forControlEvents:UIControlEventValueChanged];
    [painel addSubview:s];
    return s;
}
- (void)montarPainel {
    painel = [[UIView alloc] init];
    painel.backgroundColor = [UIColor colorWithWhite:.05 alpha:.85];
    painel.layer.cornerRadius = 12;
    [self addSubview:painel];
    // linha 1, com um botão escolhido
    nome = [self rotulo:@"" tamanho:15 peso:UIFontWeightBold em:painel];
    nome.textColor = laranja();
    rTamanho = [self rotulo:@"Tamanho" tamanho:13 peso:UIFontWeightRegular em:painel];
    sTamanho = [self deslizador:kTamanhoMin max:kTamanhoMax acao:@selector(mudouTamanho:)];
    bOcultar = [self botao:@"Ocultar" acao:@selector(tocouOcultar) destaque:NO em:painel];
    rAlternar = [self rotulo:@"Alternar" tamanho:13 peso:UIFontWeightRegular em:painel];
    swAlternar = [self chave:@selector(mudouAlternar:)];
    rMirar = [self rotulo:@"Mira ao arrastar" tamanho:13 peso:UIFontWeightRegular em:painel];
    swMirar = [self chave:@selector(mudouMirar:)];
    bEditar = [self botao:@"Editar" acao:@selector(tocouEditar) destaque:NO em:painel];
    bApagar = [self botao:@"Apagar" acao:@selector(tocouApagar) destaque:NO em:painel];
    bApagar.backgroundColor = [UIColor colorWithRed:.6 green:.12 blue:.08 alpha:1];
    // linha 1, sem botão escolhido
    dica = [self rotulo:@"Toque num botão para ajustá-lo. Arraste para mover, pince para o tamanho."
                tamanho:12 peso:UIFontWeightRegular em:painel];
    dica.numberOfLines = 2;
    rOpacidade = [self rotulo:@"Opacidade" tamanho:13 peso:UIFontWeightRegular em:painel];
    sOpacidade = [self deslizador:kOpacidadeMin max:1 acao:@selector(mudouOpacidade:)];
    rSticks = [self rotulo:@"Sticks" tamanho:13 peso:UIFontWeightRegular em:painel];
    sSticks = [self deslizador:kSticksMin max:kSticksMax acao:@selector(mudouSticks:)];
    // linha 2
    bNovo = [self botao:@"Novo botão" acao:@selector(tocouNovo) destaque:NO em:painel];
    bArma = [self botao:@"Arma" acao:@selector(tocouArma) destaque:NO em:painel];
    bPadraoDeste = [self botao:@"Padrão deste" acao:@selector(tocouPadraoDeste) destaque:NO em:painel];
    bRestaurar = [self botao:@"Restaurar tudo" acao:@selector(tocouRestaurar) destaque:NO em:painel];
    bMoverPainel = [self botao:@"Painel embaixo" acao:@selector(tocouMoverPainel) destaque:NO em:painel];
    bCancelar = [self botao:@"Cancelar" acao:@selector(tocouCancelar) destaque:NO em:painel];
    bConcluir = [self botao:@"Concluir" acao:@selector(tocouConcluir) destaque:YES em:painel];
}
- (void)montarConfirmacao {
    confirma = [[UIView alloc] init];
    confirma.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    confirma.hidden = YES;
    [self addSubview:confirma];
    caixa = [[UIView alloc] init];
    caixa.backgroundColor = [UIColor colorWithWhite:.12 alpha:1];
    caixa.layer.cornerRadius = 14;
    [confirma addSubview:caixa];
    confirmaTexto = [self rotulo:@"" tamanho:15 peso:UIFontWeightRegular em:caixa];
    confirmaTexto.numberOfLines = 0;
    confirmaTexto.textAlignment = NSTextAlignmentCenter;
    confirmaNao = [self botao:@"Não" acao:@selector(tocouNao) destaque:NO em:caixa];
    confirmaSim = [self botao:@"Sim" acao:@selector(tocouSim) destaque:YES em:caixa];
    confirmaSim.backgroundColor = [UIColor colorWithRed:.75 green:.15 blue:.1 alpha:1];
}

// Botões criados: vistas refeitas a partir de trabalho.pers (depois de criar, apagar ou
// restaurar).
- (void)recriarPersonalizados {
    while ((int)botoes.count > nFixos) {
        [botoes.lastObject removeFromSuperview];
        [botoes removeLastObject];
    }
    for (int i = 0; i < trabalho.nPers; ++i) {
        const Pers *p = &trabalho.pers[i];
        HL2EdBotao *b = [[HL2EdBotao alloc] initWithAcao:(rt_touch_action)(RT_TOUCH_CUSTOM + i)
                                                 simbolo:texto(p->icone)
                                                     cor:cor_pers(p->cor)];
        b.pers = i;
        [botoes addObject:b];
        if (painel) [self insertSubview:b belowSubview:painel];
        else [self addSubview:b];
    }
    if (selecionado >= (int)botoes.count) selecionado = -1;
}

// ---- folha do botão criado ----
- (UIButton *)escolha:(NSString *)titulo imagem:(UIImage *)imagem acao:(SEL)acao tag:(NSInteger)tag em:(UIView *)pai {
    UIButton *b = [self botao:titulo ?: @"" acao:acao destaque:NO em:pai];
    b.tag = tag;
    if (imagem) {
        [b setImage:imagem forState:UIControlStateNormal];
        b.tintColor = UIColor.whiteColor;
    }
    b.layer.borderColor = laranja().CGColor;
    return b;
}
- (void)montarFolha {
    folha = [[UIView alloc] init];
    folha.backgroundColor = [UIColor colorWithWhite:0 alpha:.45];
    folha.hidden = YES;
    [self addSubview:folha];
    folhaCaixa = [[UIView alloc] init];
    folhaCaixa.backgroundColor = [UIColor colorWithWhite:.1 alpha:.97];
    folhaCaixa.layer.cornerRadius = 14;
    [folha addSubview:folhaCaixa];
    folhaTitulo = [self rotulo:@"Botão criado" tamanho:15 peso:UIFontWeightBold em:folhaCaixa];
    folhaTitulo.textColor = laranja();
    folhaModelos = [[UIScrollView alloc] init];
    folhaModelos.showsHorizontalScrollIndicator = NO;
    [folhaCaixa addSubview:folhaModelos];
    bModelos = [NSMutableArray array];
    for (int m = 0; m < N_MODELOS; ++m)
        [bModelos addObject:[self escolha:@(kModelos[m].nome) imagem:nil acao:@selector(tocouModelo:) tag:m em:folhaModelos]];
    campo = [[UITextField alloc] init];
    campo.delegate = self;
    campo.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    campo.textColor = UIColor.whiteColor;
    campo.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
    campo.layer.cornerRadius = 8;
    campo.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    campo.leftViewMode = UITextFieldViewModeAlways;
    campo.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"comando do console, ex.: +zoom"
            attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:.35]}];
    campo.autocorrectionType = UITextAutocorrectionTypeNo;
    campo.autocapitalizationType = UITextAutocapitalizationTypeNone;
    campo.spellCheckingType = UITextSpellCheckingTypeNo;
    campo.smartQuotesType = UITextSmartQuotesTypeNo;
    campo.smartDashesType = UITextSmartDashesTypeNo;
    campo.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    campo.keyboardType = UIKeyboardTypeASCIICapable;
    campo.keyboardAppearance = UIKeyboardAppearanceDark;
    campo.returnKeyType = UIReturnKeyDone;
    campo.clearButtonMode = UITextFieldViewModeWhileEditing;
    [campo addTarget:self action:@selector(mudouCampo) forControlEvents:UIControlEventEditingChanged];
    [folhaCaixa addSubview:campo];
    bPronto = [self botao:@"Pronto" acao:@selector(tocouPronto) destaque:YES em:folhaCaixa];
    campoDica = [self rotulo:@"" tamanho:11 peso:UIFontWeightRegular em:folhaCaixa];
    campoDica.textColor = [UIColor colorWithWhite:1 alpha:.6];
    rCor = [self rotulo:@"Cor" tamanho:13 peso:UIFontWeightRegular em:folhaCaixa];
    bCores = [NSMutableArray array];
    for (int k = 0; k < N_CORES; ++k) {
        UIButton *b = [self escolha:nil imagem:nil acao:@selector(tocouCor:) tag:k em:folhaCaixa];
        b.backgroundColor = [cor_pers(k) colorWithAlphaComponent:MAX(.5, kCores[k].a + .25)];
        b.layer.borderColor = UIColor.whiteColor.CGColor;
        [bCores addObject:b];
    }
    folhaIcones = [[UIScrollView alloc] init];
    folhaIcones.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [folhaCaixa addSubview:folhaIcones];
    bIcones = [NSMutableArray array];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                         weight:UIImageSymbolWeightBold];
    for (int i = 0; i < N_ICONES; ++i) {
        UIImage *imagem = [UIImage systemImageNamed:@(kIcones[i]) withConfiguration:config];
        [bIcones addObject:[self escolha:imagem ? nil : @"?" imagem:imagem acao:@selector(tocouIcone:) tag:i em:folhaIcones]];
    }
}
- (void)disporFolha:(CGRect)a {
    folha.frame = self.bounds;
    // Presa no alto: com o teclado aberto, o modelo e o campo continuam à vista.
    CGFloat w = MIN(a.size.width - 12, 660), h = MIN(a.size.height - 12, 330), m = 12;
    folhaCaixa.frame = CGRectMake(CGRectGetMidX(a) - w / 2, CGRectGetMinY(a) + 6, w, h);
    folhaTitulo.frame = CGRectMake(m, 8, w - 2 * m, 20);
    folhaModelos.frame = CGRectMake(m, 34, w - 2 * m, 34);
    CGFloat x = 0;
    for (UIButton *b in bModelos) {
        CGFloat bw = MAX(64, [b.titleLabel.text sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font}].width + 22);
        b.frame = CGRectMake(x, 0, bw, 34);
        x += bw + 8;
    }
    folhaModelos.contentSize = CGSizeMake(x - 8, 34);
    campo.frame = CGRectMake(m, 76, w - 2 * m - 96, 34);
    bPronto.frame = CGRectMake(w - m - 88, 76, 88, 34);
    campoDica.frame = CGRectMake(m, 112, w - 2 * m, 16);
    rCor.frame = CGRectMake(m, 134, 36, 30);
    x = m + 40;
    for (UIButton *b in bCores) {
        b.frame = CGRectMake(x, 134, 30, 30);
        b.layer.cornerRadius = 15;
        x += 38;
    }
    CGFloat topo = 172;
    folhaIcones.frame = CGRectMake(m, topo, w - 2 * m, MAX(46, h - topo - m));
    int colunas = MAX(1, (int)((w - 2 * m + 6) / 46));
    for (NSUInteger i = 0; i < bIcones.count; ++i)
        bIcones[i].frame = CGRectMake((CGFloat)(i % (NSUInteger)colunas) * 46, (CGFloat)(i / (NSUInteger)colunas) * 46, 40, 40);
    folhaIcones.contentSize = CGSizeMake(w - 2 * m, ((CGFloat)((bIcones.count + (NSUInteger)colunas - 1) / (NSUInteger)colunas)) * 46 - 6);
}
- (Pers *)persEscolhido {
    HL2EdBotao *b = [self escolhido];
    return b && b.pers >= 0 && b.pers < trabalho.nPers ? &trabalho.pers[b.pers] : NULL;
}
- (void)atualizarFolha {
    Pers *p = [self persEscolhido];
    if (!p) return;
    int comando = kModelos[p->modelo].tipo == TIPO_COMANDO;
    for (UIButton *b in bModelos) b.layer.borderWidth = b.tag == p->modelo ? 2 : 0;
    for (UIButton *b in bCores) b.layer.borderWidth = b.tag == p->cor ? 3 : 0;
    for (UIButton *b in bIcones) b.layer.borderWidth = !strcmp(kIcones[b.tag], p->icone) ? 2 : 0;
    campo.enabled = comando;
    campo.alpha = comando ? 1 : .5;
    if (comando) {
        if (!campo.isEditing) campo.text = texto(p->comando);
        campoDica.text = @"Vários comandos: separe com ;. Os com + (ex.: +attack) ficam apertados enquanto você segura.";
    } else {
        if (campo.isEditing) [campo resignFirstResponder];
        const Modelo *m = &kModelos[p->modelo];
        campo.text = m->tipo == TIPO_GUARDAR ? @"impulse 200" : @(m->comando);
        campoDica.text = m->tipo == TIPO_GUARDAR
            ? @"Guarda e saca a arma. Guardada, o tiro fica travado; tocar no tiro saca a arma."
            : @"Troca de arma. Com a arma guardada, também a saca.";
    }
}
- (void)abrirFolha {
    if (![self persEscolhido]) return;
    arrasto = nil;
    folha.hidden = NO;
    [self atualizarFolha];
    [self redesenhar];
}
- (void)aparenciaDoEscolhido {
    HL2EdBotao *b = [self escolhido];
    Pers *p = [self persEscolhido];
    if (!b || !p) return;
    b.backgroundColor = cor_pers(p->cor);
    [b trocarSimbolo:texto(p->icone)];
}
- (void)tocouModelo:(UIButton *)botao {
    Pers *p = [self persEscolhido];
    if (!p || botao.tag < 0 || botao.tag >= N_MODELOS) return;
    // O ícone acompanha o modelo enquanto for o do modelo anterior.
    if (!strcmp(p->icone, kModelos[p->modelo].icone))
        snprintf(p->icone, sizeof(p->icone), "%s", kModelos[botao.tag].icone);
    p->modelo = (int)botao.tag;
    [self aparenciaDoEscolhido];
    [self atualizarFolha];
    [self atualizarPainel];
    [self redesenhar];
    if (p->modelo == MODELO_COMANDO && !p->comando[0]) {
        pegar_chave();
        [campo becomeFirstResponder];
    }
}
- (void)tocouCor:(UIButton *)botao {
    Pers *p = [self persEscolhido];
    if (!p || botao.tag < 0 || botao.tag >= N_CORES) return;
    p->cor = (int)botao.tag;
    [self aparenciaDoEscolhido];
    [self atualizarFolha];
    [self redesenhar];
}
- (void)tocouIcone:(UIButton *)botao {
    Pers *p = [self persEscolhido];
    if (!p || botao.tag < 0 || botao.tag >= N_ICONES) return;
    snprintf(p->icone, sizeof(p->icone), "%s", kIcones[botao.tag]);
    [self aparenciaDoEscolhido];
    [self atualizarFolha];
    [self redesenhar];
}
- (void)mudouCampo {
    Pers *p = [self persEscolhido];
    if (!p || kModelos[p->modelo].tipo != TIPO_COMANDO) return;
    NSString *t = campo.text ?: @"";
    // Cabe em COMANDO bytes, sem cortar um caractere ao meio.
    while ([t lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= COMANDO)
        t = [t substringWithRange:[t rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, t.length - 1)]];
    if (![t isEqualToString:campo.text]) campo.text = t;
    snprintf(p->comando, sizeof(p->comando), "%s", t.UTF8String);
    [self atualizarPainel];
    [self redesenhar];
}
- (BOOL)textFieldShouldBeginEditing:(UITextField *)campoTocado {
    (void)campoTocado;
    pegar_chave();
    return YES;
}
- (void)textFieldDidEndEditing:(UITextField *)campoTocado {
    (void)campoTocado;
    [self mudouCampo];
    devolver_chave();
    [self redesenhar];
}
- (BOOL)textFieldShouldReturn:(UITextField *)campoTocado {
    [campoTocado resignFirstResponder];
    return NO;
}
- (void)tocouPronto {
    [campo resignFirstResponder];
    devolver_chave();
    folha.hidden = YES;
    [self atualizarPainel];
    [self redesenhar];
}

// ---- ajuste da arma ----
- (UILabel *)rotuloBarra:(NSString *)t {
    return [self rotulo:t tamanho:13 peso:UIFontWeightRegular em:barra];
}
- (UISlider *)deslizadorBarra:(float)min max:(float)max {
    UISlider *s = [[UISlider alloc] init];
    s.minimumValue = min;
    s.maximumValue = max;
    s.minimumTrackTintColor = laranja();
    [s addTarget:self action:@selector(mudouArma:) forControlEvents:UIControlEventValueChanged];
    [barra addSubview:s];
    return s;
}
- (void)montarBarra {
    barra = [[UIView alloc] init];
    barra.backgroundColor = [UIColor colorWithWhite:.05 alpha:.8];
    barra.layer.cornerRadius = 12;
    barra.hidden = YES;
    [self addSubview:barra];
    armaNome = [self rotulo:@"" tamanho:15 peso:UIFontWeightBold em:barra];
    armaNome.textColor = laranja();
    rFrente = [self rotuloBarra:@""];
    sFrente = [self deslizadorBarra:-kDeslocMax max:kDeslocMax];
    rLado = [self rotuloBarra:@""];
    sLado = [self deslizadorBarra:-kDeslocMax max:kDeslocMax];
    rAltura = [self rotuloBarra:@""];
    sAltura = [self deslizadorBarra:-kDeslocMax max:kDeslocMax];
    rFov = [self rotuloBarra:@""];
    sFov = [self deslizadorBarra:kFovMin max:kFovMax];
    bPadraoArma = [self botao:@"Padrão desta arma" acao:@selector(tocouPadraoArma) destaque:NO em:barra];
    bCopiarTodas = [self botao:@"Copiar para todas" acao:@selector(tocouCopiarTodas) destaque:NO em:barra];
    bVoltar = [self botao:@"Voltar ao editor" acao:@selector(tocouVoltarEditor) destaque:YES em:barra];
}
- (void)disporBarra:(CGRect)a {
    const CGFloat margem = 12, linha = 34;
    NSArray<UIView *> *v1 = @[armaNome, rFrente, sFrente, rLado, sLado, rAltura, sAltura];
    const CGFloat w1[] = {150, 88, 104, 76, 104, 84, 104};
    CGFloat fim1 = enfileirar(v1, w1, margem, margem, linha);
    NSArray<UIView *> *v2 = @[rFov, sFov, bPadraoArma, bCopiarTodas, bVoltar];
    const CGFloat w2[] = {116, 150, 150, 142, 140};
    CGFloat fim2 = enfileirar(v2, w2, margem, margem + linha + 10, linha);
    CGFloat largura = MAX(fim1, fim2) - 8 + margem, altura = margem + linha + 10 + linha + margem;
    CGFloat escala = MIN(1, (a.size.width - 12) / largura);
    barra.transform = CGAffineTransformIdentity;
    barra.bounds = CGRectMake(0, 0, largura, altura);
    // No alto: a arma fica embaixo, à direita.
    barra.center = CGPointMake(CGRectGetMidX(a), CGRectGetMinY(a) + 6 + altura * escala / 2);
    barra.transform = CGAffineTransformMakeScale(escala, escala);
}
static NSString *nome_da_arma(NSString *classe) {
    if (!classe.length) return @"Sem arma na mão";
    for (size_t i = 0; i < sizeof(kNomesArmas) / sizeof(*kNomesArmas); ++i)
        if ([classe isEqualToString:@(kNomesArmas[i].classe)]) return @(kNomesArmas[i].nome);
    return classe;
}
static NSString *numero_texto(NSString *nome, float v) {
    return [NSString stringWithFormat:@"%@ %@%.1f", nome, v > 0 ? @"+" : @"", (double)v];
}
// Rótulos e controles com o ajuste da arma na mão; `controles` também move os controles
// (não durante um arrasto, que já os move).
- (void)atualizarBarra:(BOOL)controles {
    const char *classe = hl2ios_arma_classe();
    const ArmaAj *j = arma_de(&trabalho, classe);
    BOOL tem = classe[0] != 0;
    armaNome.text = nome_da_arma(texto(classe));
    for (UIControl *c in @[sFrente, sLado, sAltura, sFov, bPadraoArma, bCopiarTodas]) {
        c.enabled = tem;
        c.alpha = tem ? 1 : .4;
    }
    rFrente.text = numero_texto(@"Frente", j->frente);
    rLado.text = numero_texto(@"Lado", j->lado);
    rAltura.text = numero_texto(@"Altura", j->altura);
    rFov.text = j->fov > 0 ? [NSString stringWithFormat:@"FOV da arma %.0f", (double)j->fov]
                           : [NSString stringWithFormat:@"FOV da arma %.0f (jogo)", (double)kFovJogo];
    if (controles) {
        sFrente.value = j->frente;
        sLado.value = j->lado;
        sAltura.value = j->altura;
        sFov.value = j->fov > 0 ? j->fov : kFovJogo;
    }
}
- (void)acompanharArma {
    NSString *classe = texto(hl2ios_arma_classe());
    if ([classe isEqualToString:classeVista ?: @""]) return;
    classeVista = classe;
    [self atualizarBarra:YES];
    [self redesenhar];
}
- (void)tocouArma {
    modoArma = YES;
    classeVista = nil;
    selecionado = -1;
    arrasto = nil;
    if (ao_pausar) ao_pausar(0);
    __weak HL2EdTela *fraca = self;
    relogio = [NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(NSTimer *t) {
        (void)t;
        [fraca acompanharArma];
    }];
    [self acompanharArma];
    [self atualizarPainel];
    [self redesenhar];
}
- (void)dealloc {
    [relogio invalidate];
}
- (void)tocouVoltarEditor {
    modoArma = NO;
    [relogio invalidate];
    relogio = nil;
    if (ao_pausar) ao_pausar(1);
    [self redesenhar];
}
- (void)mudouArma:(UISlider *)s {
    ArmaAj *j = arma_propria(&trabalho, hl2ios_arma_classe());
    if (!j) return;
    float v = (float)(s == sFov ? round(s.value) : round(s.value * 2) / 2);   // passos de 1 e de 0,5
    if (s == sFrente) j->frente = v;
    else if (s == sLado) j->lado = v;
    else if (s == sAltura) j->altura = v;
    else j->fov = v;
    [self atualizarBarra:NO];
    [self redesenhar];
}
- (void)tocouPadraoArma {
    ArmaAj *j = arma_propria(&trabalho, hl2ios_arma_classe());
    if (!j) return;
    j->frente = j->lado = j->altura = j->fov = 0;
    [self atualizarBarra:YES];
    [self redesenhar];
}
- (void)copiarParaTodas {
    const ArmaAj *j = arma_de(&trabalho, hl2ios_arma_classe());
    ArmaAj modelo = *j;
    for (int i = 0; i < trabalho.nArmas; ++i) {
        trabalho.armas[i].frente = modelo.frente;
        trabalho.armas[i].lado = modelo.lado;
        trabalho.armas[i].altura = modelo.altura;
        trabalho.armas[i].fov = modelo.fov;
    }
    modelo.classe[0] = 0;
    trabalho.geral = modelo;
    [self atualizarBarra:YES];
    [self redesenhar];
}
- (void)tocouCopiarTodas {
    __weak HL2EdTela *fraca = self;
    [self perguntar:[NSString stringWithFormat:@"Tem certeza? A posição e o FOV de \u201c%@\u201d vão para todas as "
                                               @"outras armas, inclusive as já ajustadas. Só é gravado quando você "
                                               @"tocar em Concluir.", armaNome.text]
                sim:@"Copiar"
               acao:^{ [fraca copiarParaTodas]; }];
}

// ---- disposição ----
- (CGRect)area {
    return UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
}
- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self setNeedsLayout];
}
- (void)redesenhar {
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [CATransaction flush];
}
- (HL2EdBotao *)escolhido {
    return selecionado >= 0 && selecionado < (int)botoes.count ? botoes[(NSUInteger)selecionado] : nil;
}
// Centro e tamanho do botão com os ajustes em edição (ocultos também).
- (CGPoint)centroDe:(HL2EdBotao *)b tamanho:(float *)tamanho {
    CGRect a = [self area];
    if (b.pers >= 0) {
        double cx, cy;
        unsigned flags;
        aplicar_pers(&trabalho.pers[b.pers], a.origin.x, a.origin.y, a.size.width, a.size.height, &cx, &cy, tamanho, &flags);
        return CGPointMake(cx, cy);
    }
    const rt_touch_button *t = &tabela[b.indice];
    double cx, cy;
    rt_touch_place(t, a.origin.x, a.origin.y, a.size.width, a.size.height, &cx, &cy);
    float tam = t->size;
    unsigned flags = t->flags;
    aplicar(&trabalho, t->action, 0, a.origin.x, a.origin.y, a.size.width, a.size.height, &cx, &cy, &tam, &flags);
    *tamanho = tam;
    return CGPointMake(cx, cy);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect a = [self area];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat meio = CGRectGetMidX(self.bounds);   // o touch_controls.m divide pelo meio da vista
    CGMutablePathRef linha = CGPathCreateMutable();
    CGPathMoveToPoint(linha, NULL, meio, 0);
    CGPathAddLineToPoint(linha, NULL, meio, self.bounds.size.height);
    divisa.path = linha;
    CGPathRelease(linha);
    // Sticks em repouso, como o restingStick: e o stickRadius do touch_controls.m.
    CGFloat raio = MIN(66, a.size.height * .15) * trabalho.sticks;
    double xs[2] = {.16, rt_touch_look_rest(rt_ios_current_game()->layout)};
    for (int i = 0; i < 2; ++i) {
        CGPathRef anel = CGPathCreateWithEllipseInRect(CGRectMake(-raio, -raio, 2 * raio, 2 * raio), NULL);
        anelSticks[i].path = anel;
        CGPathRelease(anel);
        anelSticks[i].position = CGPointMake(CGRectGetMinX(a) + a.size.width * xs[i], CGRectGetMinY(a) + a.size.height * .72);
        anelSticks[i].opacity = trabalho.opacidade;
    }
    [CATransaction commit];
    divisaTexto.frame = CGRectMake(meio - 80, CGRectGetMaxY(a) - 18, 160, 16);

    HL2EdBotao *escolhido = [self escolhido];
    for (HL2EdBotao *b in botoes) {
        float tam;
        CGPoint centro = [self centroDe:b tamanho:&tam];
        [b mostrarEm:centro tamanho:tam];
        BOOL oculto = b.pers < 0 && trabalho.botao[b.acao].oculto != 0;
        b.alpha = oculto ? .25 : MAX(.3, trabalho.opacidade);
        const Info *info = b.pers < 0 ? info_de(b.acao) : NULL;
        NSString *rotulo = b.pers >= 0 ? nome_pers(&trabalho.pers[b.pers]) : info ? @(info->nome) : @"";
        b.rotulo.text = oculto ? [rotulo stringByAppendingString:@" (oculto)"] : rotulo;
        b.layer.borderColor = (b == escolhido ? laranja() : [UIColor colorWithWhite:1 alpha:.45]).CGColor;
        b.layer.borderWidth = b == escolhido ? 3 : 2;
    }
    // Ajuste da arma: some tudo menos a barra, e o fundo fica claro para ver a arma.
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:modoArma ? 0 : .4];
    for (HL2EdBotao *b in botoes) b.hidden = modoArma;
    painel.hidden = divisaTexto.hidden = modoArma;
    divisa.hidden = anelSticks[0].hidden = anelSticks[1].hidden = modoArma;
    barra.hidden = !modoArma;
    [self bringSubviewToFront:painel];
    [self bringSubviewToFront:folha];
    [self bringSubviewToFront:barra];
    [self bringSubviewToFront:confirma];
    [self disporPainel:a];
    [self disporFolha:a];
    [self disporBarra:a];
    [self disporConfirmacao];
}
// Coloca as vistas lado a lado a partir de x, numa linha de altura h; devolve o x final.
static CGFloat enfileirar(NSArray<UIView *> *vistas, const CGFloat *larguras, CGFloat x, CGFloat y, CGFloat h) {
    for (NSUInteger i = 0; i < vistas.count; ++i) {
        UIView *v = vistas[i];
        if (v.hidden) continue;
        if ([v isKindOfClass:UISwitch.class]) v.center = CGPointMake(x + larguras[i] / 2, y + h / 2);
        else v.frame = CGRectMake(x, y, larguras[i], h);
        x += larguras[i] + 8;
    }
    return x;
}
- (void)disporPainel:(CGRect)a {
    const CGFloat margem = 12, linha = 34;
    CGFloat fim1;
    if ([self escolhido]) {
        NSArray<UIView *> *v = @[nome, rTamanho, sTamanho, bOcultar, bEditar, bApagar, rAlternar, swAlternar, rMirar, swMirar];
        const CGFloat w[] = {150, 58, 120, 80, 72, 76, 58, 40, 108, 40};
        fim1 = enfileirar(v, w, margem, margem, linha);
    } else {
        NSArray<UIView *> *v = @[dica, rOpacidade, sOpacidade, rSticks, sSticks];
        const CGFloat w[] = {250, 70, 120, 46, 120};
        fim1 = enfileirar(v, w, margem, margem, linha);
    }
    NSArray<UIView *> *v2 = @[bNovo, bArma, bPadraoDeste, bRestaurar, bMoverPainel, bCancelar, bConcluir];
    const CGFloat w2[] = {104, 70, 108, 120, 128, 92, 100};
    CGFloat fim2 = enfileirar(v2, w2, margem, margem + linha + 10, linha);
    CGFloat largura = MAX(fim1, fim2) - 8 + margem, altura = margem + linha + 10 + linha + margem;
    // Cabe na zona segura: se não couber, o painel inteiro encolhe.
    CGFloat escala = MIN(1, (a.size.width - 12) / largura);
    painel.transform = CGAffineTransformIdentity;
    painel.bounds = CGRectMake(0, 0, largura, altura);
    CGFloat meia = altura * escala / 2;
    painel.center = CGPointMake(CGRectGetMidX(a), painelEmbaixo ? CGRectGetMaxY(a) - 6 - meia : CGRectGetMinY(a) + 6 + meia);
    painel.transform = CGAffineTransformMakeScale(escala, escala);
}
- (void)disporConfirmacao {
    confirma.frame = self.bounds;
    CGFloat w = MIN(460, self.bounds.size.width - 40), h = 170;
    caixa.frame = CGRectMake((self.bounds.size.width - w) / 2, (self.bounds.size.height - h) / 2, w, h);
    confirmaTexto.frame = CGRectMake(18, 14, w - 36, h - 14 - 62);
    confirmaNao.frame = CGRectMake(18, h - 52, (w - 48) / 2, 38);
    confirmaSim.frame = CGRectMake(30 + (w - 48) / 2, h - 52, (w - 48) / 2, 38);
}
- (void)atualizarPainel {
    HL2EdBotao *b = [self escolhido];
    const Pers *p = [self persEscolhido];
    const Info *info = b && !p ? info_de(b.acao) : NULL;
    unsigned pode = info ? info->pode : 0;
    if (p) pode = PODE_MIRAR | (kModelos[p->modelo].tipo == TIPO_COMANDO ? PODE_ALTERNAR : 0);
    BOOL sel = b != nil;
    nome.hidden = rTamanho.hidden = sTamanho.hidden = !sel;
    bOcultar.hidden = bPadraoDeste.hidden = !sel || p;
    bEditar.hidden = bApagar.hidden = !p;
    rAlternar.hidden = swAlternar.hidden = !(pode & PODE_ALTERNAR);
    rMirar.hidden = swMirar.hidden = !(pode & PODE_MIRAR);
    dica.hidden = rOpacidade.hidden = sOpacidade.hidden = rSticks.hidden = sSticks.hidden = sel;
    if (p) {
        nome.text = nome_pers(p);
        sTamanho.value = p->tamanho;
        swAlternar.on = p->alternar != 0;
        swMirar.on = p->mirar != 0;
    } else if (b) {
        const rt_touch_button *t = &tabela[b.indice];
        const Ajuste *j = &trabalho.botao[b.acao];
        nome.text = info ? @(info->nome) : @"";
        sTamanho.value = j->tamanho > 0 ? j->tamanho : t->size;
        [bOcultar setTitle:j->oculto ? @"Mostrar" : @"Ocultar" forState:UIControlStateNormal];
        bOcultar.enabled = !(pode & SEMPRE_VISIVEL);
        bOcultar.alpha = bOcultar.enabled ? 1 : .5;
        swAlternar.on = j->alternar >= 0 ? j->alternar != 0 : (t->flags & RT_TOUCH_TOGGLE) != 0;
        swMirar.on = j->mirar >= 0 ? j->mirar != 0 : (t->flags & RT_TOUCH_AIM) != 0;
    }
    bNovo.enabled = trabalho.nPers < MAX_PERS;
    bNovo.alpha = bNovo.enabled ? 1 : .5;
    sOpacidade.value = trabalho.opacidade;
    sSticks.value = trabalho.sticks;
    [bMoverPainel setTitle:painelEmbaixo ? @"Painel em cima" : @"Painel embaixo" forState:UIControlStateNormal];
}

// ---- toques ----
- (HL2EdBotao *)botaoEm:(CGPoint)p {
    for (NSInteger i = (NSInteger)botoes.count - 1; i >= 0; --i) {
        HL2EdBotao *b = botoes[(NSUInteger)i];
        CGFloat alcance = MAX(b.tamanho * .5 + 8, 26);
        if (hypot(p.x - b.center.x, p.y - b.center.y) < alcance) return b;
    }
    return nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!confirma.hidden || !folha.hidden || modoArma) return;
    BOOL mudou = NO;
    for (UITouch *t in touches) {
        if (arrasto) break;
        CGPoint p = [t locationInView:self];
        if (CGRectContainsPoint(painel.frame, p)) continue;   // fundo do painel
        HL2EdBotao *b = [self botaoEm:p];
        int antes = selecionado;
        if (b) {
            selecionado = (int)[botoes indexOfObject:b];
            arrasto = t;
            deslocamento = CGPointMake(p.x - b.center.x, p.y - b.center.y);
        } else {
            selecionado = -1;
        }
        mudou |= antes != selecionado;
    }
    if (mudou) [self atualizarPainel];
    [self redesenhar];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    HL2EdBotao *b = [self escolhido];
    if (!arrasto || !b || ![touches containsObject:arrasto]) return;
    CGRect a = [self area];
    if (a.size.width <= 1 || a.size.height <= 1) return;
    CGPoint p = [arrasto locationInView:self];
    float tam;
    [self centroDe:b tamanho:&tam];
    double r = tam / 2.0;
    double cx = limitar(p.x - deslocamento.x, CGRectGetMinX(a) + r, CGRectGetMaxX(a) - r);
    double cy = limitar(p.y - deslocamento.y, CGRectGetMinY(a) + r, CGRectGetMaxY(a) - r);
    double fx = (cx - CGRectGetMinX(a)) / a.size.width, fy = (cy - CGRectGetMinY(a)) / a.size.height;
    Pers *criado = [self persEscolhido];
    if (criado) {
        criado->fx = fx;
        criado->fy = fy;
    } else {
        Ajuste *j = &trabalho.botao[b.acao];
        j->posicao = 1;
        j->fx = fx;
        j->fy = fy;
    }
    [self redesenhar];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (arrasto && [touches containsObject:arrasto]) arrasto = nil;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
- (void)pinca:(UIPinchGestureRecognizer *)g {
    HL2EdBotao *b = [self escolhido];
    if (!b || !confirma.hidden || !folha.hidden || modoArma) return;
    if (g.state == UIGestureRecognizerStateBegan) tamanhoBase = b.tamanho;
    else if (g.state != UIGestureRecognizerStateChanged) return;
    arrasto = nil;
    float tamanho = (float)limitar(tamanhoBase * g.scale, kTamanhoMin, kTamanhoMax);
    Pers *criado = [self persEscolhido];
    if (criado) criado->tamanho = tamanho;
    else trabalho.botao[b.acao].tamanho = tamanho;
    sTamanho.value = tamanho;
    [self redesenhar];
}

// ---- painel ----
- (void)mudouTamanho:(UISlider *)s {
    HL2EdBotao *b = [self escolhido];
    if (!b) return;
    Pers *criado = [self persEscolhido];
    if (criado) criado->tamanho = s.value;
    else trabalho.botao[b.acao].tamanho = s.value;
    [self redesenhar];
}
- (void)mudouOpacidade:(UISlider *)s {
    trabalho.opacidade = s.value;
    [self redesenhar];
}
- (void)mudouSticks:(UISlider *)s {
    trabalho.sticks = s.value;
    [self redesenhar];
}
- (void)mudouAlternar:(UISwitch *)s {
    HL2EdBotao *b = [self escolhido];
    Pers *criado = [self persEscolhido];
    if (criado) criado->alternar = s.on ? 1 : 0;
    else if (b) trabalho.botao[b.acao].alternar = s.on ? 1 : 0;
}
- (void)mudouMirar:(UISwitch *)s {
    HL2EdBotao *b = [self escolhido];
    Pers *criado = [self persEscolhido];
    if (criado) criado->mirar = s.on ? 1 : 0;
    else if (b) trabalho.botao[b.acao].mirar = s.on ? 1 : 0;
}
- (void)tocouNovo {
    if (trabalho.nPers >= MAX_PERS) return;
    pers_novo(&trabalho.pers[trabalho.nPers++], 0);
    [self recriarPersonalizados];
    selecionado = nFixos + trabalho.nPers - 1;
    [self atualizarPainel];
    [self abrirFolha];
}
- (void)tocouEditar {
    [self abrirFolha];
}
- (void)apagarEscolhido {
    HL2EdBotao *b = [self escolhido];
    if (!b || b.pers < 0 || b.pers >= trabalho.nPers) return;
    int i = b.pers;
    memmove(&trabalho.pers[i], &trabalho.pers[i + 1], sizeof(Pers) * (size_t)(trabalho.nPers - i - 1));
    --trabalho.nPers;
    selecionado = -1;
    [self recriarPersonalizados];
    [self atualizarPainel];
    [self redesenhar];
}
- (void)tocouApagar {
    const Pers *p = [self persEscolhido];
    if (!p) return;
    __weak HL2EdTela *fraca = self;
    [self perguntar:[NSString stringWithFormat:@"Tem certeza? O botão \u201c%@\u201d vai ser apagado. Só é gravado "
                                               @"quando você tocar em Concluir.", nome_pers(p)]
                sim:@"Apagar"
               acao:^{ [fraca apagarEscolhido]; }];
}
- (void)tocouOcultar {
    HL2EdBotao *b = [self escolhido];
    const Info *info = b ? info_de(b.acao) : NULL;
    if (!b || b.pers >= 0 || (info && (info->pode & SEMPRE_VISIVEL))) return;
    Ajuste *j = &trabalho.botao[b.acao];
    j->oculto = !j->oculto;
    [self atualizarPainel];
    [self redesenhar];
}
- (void)tocouPadraoDeste {
    HL2EdBotao *b = [self escolhido];
    if (!b || b.pers >= 0) return;
    ajuste_padrao(&trabalho.botao[b.acao]);
    [self atualizarPainel];
    [self redesenhar];
}
- (void)restaurarTudo {
    ajustes_padrao(&trabalho);
    selecionado = -1;
    [self recriarPersonalizados];
    [self atualizarPainel];
    [self redesenhar];
}
- (void)tocouRestaurar {
    __weak HL2EdTela *fraca = self;
    [self perguntar:@"Tem certeza? Todos os botões voltam à posição, ao tamanho e às opções originais, a "
                    @"opacidade e os sticks voltam ao normal, a posição e o FOV das armas voltam aos do jogo, e "
                    @"os botões criados por você são apagados. Só é gravado quando você tocar em Concluir."
                sim:@"Restaurar"
               acao:^{ [fraca restaurarTudo]; }];
}
- (void)tocouMoverPainel {
    painelEmbaixo = !painelEmbaixo;
    [self atualizarPainel];
    [self redesenhar];
}
- (void)tocouCancelar {
    if (ajustes_iguais(&trabalho, &salvos)) {
        editor_fechar(0);
        return;
    }
    [self perguntar:@"Tem certeza? As mudanças feitas desde que o editor abriu vão ser descartadas."
                sim:@"Descartar"
               acao:^{ editor_fechar(0); }];
}
- (void)tocouConcluir {
    int mudou = !ajustes_iguais(&trabalho, &salvos);
    if (mudou) {
        salvos = trabalho;
        gravar(&salvos);
    }
    editor_fechar(mudou);
}

// ---- confirmação ----
- (void)perguntar:(NSString *)texto sim:(NSString *)sim acao:(HL2EdAcao)acao {
    confirmaTexto.text = texto;
    [confirmaSim setTitle:sim forState:UIControlStateNormal];
    confirmaAcao = [acao copy];
    arrasto = nil;
    confirma.hidden = NO;
    [self redesenhar];
}
- (void)tocouSim {
    HL2EdAcao acao = confirmaAcao;
    confirmaAcao = nil;
    confirma.hidden = YES;
    [self redesenhar];
    if (acao) acao();
}
- (void)tocouNao {
    confirmaAcao = nil;
    confirma.hidden = YES;
    [self redesenhar];
}
@end

// O controlador da janela do editor: paisagem, sem barra de estado, e os gestos das bordas
// (voltar à tela inicial) pedem um segundo deslize, como no jogo.
@interface HL2EdControle : UIViewController
@end

@implementation HL2EdControle
- (void)loadView {
    self.view = [[HL2EdTela alloc] initWithFrame:UIScreen.mainScreen.bounds];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
- (BOOL)prefersStatusBarHidden {
    return YES;
}
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}
@end

static void (^ao_fechar)(int);
static CFRunLoopObserverRef observador;

void hl2ios_toque_editor_pausa(void (^pausar)(int pausar)) {
    ao_pausar = [pausar copy];
}

static void editor_fechar(int salvou) {
    if (!janela) return;
    // Depois da ação do botão que pediu para fechar, não no meio dela.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!janela) return;
        devolver_chave();
        ativos = NULL;   // de volta ao gravado
        janela.hidden = YES;
        janela.rootViewController = nil;
        janela = nil;
        if (observador) {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observador, kCFRunLoopCommonModes);
            CFRelease(observador);
            observador = NULL;
        }
        [CATransaction flush];
        fprintf(stderr, "[hl2ios] toque: editor fechado (%s)\n", salvou ? "ajustes gravados" : "sem mudança");
        void (^fechou)(int) = ao_fechar;
        ao_fechar = nil;
        if (fechou) fechou(salvou);
    });
}

void hl2ios_toque_editor_abrir(void (^fechou)(int salvou)) {
    if (janela) return;
    carregar();
    ao_fechar = [fechou copy];
    janela = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    janela.windowLevel = UIWindowLevelNormal + 1;
    janela.backgroundColor = UIColor.clearColor;
    janela.rootViewController = [[HL2EdControle alloc] init];
    janela.hidden = NO;   // sem virar a janela principal: o SDL continua com o foco
    observador = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopExit, true, 0,
        ^(CFRunLoopObserverRef o, CFRunLoopActivity atividade) {
            (void)o;
            (void)atividade;
            if (janela && !janela.hidden) {
                [janela layoutIfNeeded];
                [CATransaction flush];
            }
        });
    CFRunLoopAddObserver(CFRunLoopGetMain(), observador, kCFRunLoopCommonModes);
    [janela layoutIfNeeded];
    [CATransaction flush];
    fprintf(stderr, "[hl2ios] toque: editor aberto\n");
}
