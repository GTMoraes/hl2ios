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
// gravado antes de Concluir; Cancelar e Restaurar tudo perguntam antes.
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
    return 1;
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
    fprintf(stderr, "[hl2ios] toque: hl2-toque.json com %d botões ajustados, opacidade %.2f, sticks %.2f\n",
            lidos, salvos.opacidade, salvos.sticks);
}

static double arredondar(double v, double passo) {
    return round(v / passo) * passo;
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
    NSDictionary *raiz = @{
        @"versao": @1,
        @"opacidade": @(arredondar(a->opacidade, .01)),
        @"sticks": @(arredondar(a->sticks, .01)),
        @"botoes": botoes,
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
    fprintf(stderr, "[hl2ios] toque: %s hl2-toque.json (%lu botões ajustados)\n", ok ? "gravado" : "NÃO consegui gravar",
            (unsigned long)botoes.count);
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

// ---- editor ----

static void editor_fechar(int salvou);

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

// Um botão no editor: o círculo com o ícone, e o nome embaixo.
@interface HL2EdBotao : UIView
@property (nonatomic) rt_touch_action acao;
@property (nonatomic) int indice;   // posição na tabela de touch_layout.c
@property (nonatomic) float tamanho;
@property (nonatomic, copy) NSString *simbolo;
@property (nonatomic, strong) UIImageView *icone;
@property (nonatomic, strong) UILabel *rotulo;
- (instancetype)initWithAcao:(rt_touch_action)acao simbolo:(NSString *)simbolo cor:(UIColor *)cor;
- (void)mostrarEm:(CGPoint)centro tamanho:(float)tamanho;
@end

@implementation HL2EdBotao
- (instancetype)initWithAcao:(rt_touch_action)acao simbolo:(NSString *)simbolo cor:(UIColor *)cor {
    if ((self = [super initWithFrame:CGRectZero])) {
        _acao = acao;
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
@end

typedef void (^HL2EdAcao)(void);

// A tela do editor: os botões, a divisa dos sticks, o painel e a confirmação.
@interface HL2EdTela : UIView
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
    UIView *confirma, *caixa;
    UILabel *confirmaTexto;
    UIButton *confirmaSim, *confirmaNao;
    HL2EdAcao confirmaAcao;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        carregar();
        trabalho = salvos;
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
        [self montarPainel];
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
    // linha 1, sem botão escolhido
    dica = [self rotulo:@"Toque num botão para ajustá-lo. Arraste para mover, pince para o tamanho."
                tamanho:12 peso:UIFontWeightRegular em:painel];
    dica.numberOfLines = 2;
    rOpacidade = [self rotulo:@"Opacidade" tamanho:13 peso:UIFontWeightRegular em:painel];
    sOpacidade = [self deslizador:kOpacidadeMin max:1 acao:@selector(mudouOpacidade:)];
    rSticks = [self rotulo:@"Sticks" tamanho:13 peso:UIFontWeightRegular em:painel];
    sSticks = [self deslizador:kSticksMin max:kSticksMax acao:@selector(mudouSticks:)];
    // linha 2
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
        BOOL oculto = trabalho.botao[b.acao].oculto != 0;
        b.alpha = oculto ? .25 : MAX(.3, trabalho.opacidade);
        const Info *info = info_de(b.acao);
        NSString *texto = info ? @(info->nome) : @"";
        b.rotulo.text = oculto ? [texto stringByAppendingString:@" (oculto)"] : texto;
        b.layer.borderColor = (b == escolhido ? laranja() : [UIColor colorWithWhite:1 alpha:.45]).CGColor;
        b.layer.borderWidth = b == escolhido ? 3 : 2;
    }
    [self bringSubviewToFront:painel];
    [self bringSubviewToFront:confirma];
    [self disporPainel:a];
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
        NSArray<UIView *> *v = @[nome, rTamanho, sTamanho, bOcultar, rAlternar, swAlternar, rMirar, swMirar];
        const CGFloat w[] = {150, 58, 120, 80, 58, 40, 108, 40};
        fim1 = enfileirar(v, w, margem, margem, linha);
    } else {
        NSArray<UIView *> *v = @[dica, rOpacidade, sOpacidade, rSticks, sSticks];
        const CGFloat w[] = {250, 70, 120, 46, 120};
        fim1 = enfileirar(v, w, margem, margem, linha);
    }
    NSArray<UIView *> *v2 = @[bPadraoDeste, bRestaurar, bMoverPainel, bCancelar, bConcluir];
    const CGFloat w2[] = {108, 120, 128, 92, 100};
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
    const Info *info = b ? info_de(b.acao) : NULL;
    unsigned pode = info ? info->pode : 0;
    BOOL sel = b != nil;
    nome.hidden = rTamanho.hidden = sTamanho.hidden = bOcultar.hidden = bPadraoDeste.hidden = !sel;
    rAlternar.hidden = swAlternar.hidden = !(pode & PODE_ALTERNAR);
    rMirar.hidden = swMirar.hidden = !(pode & PODE_MIRAR);
    dica.hidden = rOpacidade.hidden = sOpacidade.hidden = rSticks.hidden = sSticks.hidden = sel;
    if (b) {
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
    if (!confirma.hidden) return;
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
    Ajuste *j = &trabalho.botao[b.acao];
    j->posicao = 1;
    j->fx = (cx - CGRectGetMinX(a)) / a.size.width;
    j->fy = (cy - CGRectGetMinY(a)) / a.size.height;
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
    if (!b || !confirma.hidden) return;
    if (g.state == UIGestureRecognizerStateBegan) tamanhoBase = b.tamanho;
    else if (g.state != UIGestureRecognizerStateChanged) return;
    arrasto = nil;
    trabalho.botao[b.acao].tamanho = (float)limitar(tamanhoBase * g.scale, kTamanhoMin, kTamanhoMax);
    sTamanho.value = trabalho.botao[b.acao].tamanho;
    [self redesenhar];
}

// ---- painel ----
- (void)mudouTamanho:(UISlider *)s {
    HL2EdBotao *b = [self escolhido];
    if (!b) return;
    trabalho.botao[b.acao].tamanho = s.value;
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
    if (b) trabalho.botao[b.acao].alternar = s.on ? 1 : 0;
}
- (void)mudouMirar:(UISwitch *)s {
    HL2EdBotao *b = [self escolhido];
    if (b) trabalho.botao[b.acao].mirar = s.on ? 1 : 0;
}
- (void)tocouOcultar {
    HL2EdBotao *b = [self escolhido];
    const Info *info = b ? info_de(b.acao) : NULL;
    if (!b || (info && (info->pode & SEMPRE_VISIVEL))) return;
    Ajuste *j = &trabalho.botao[b.acao];
    j->oculto = !j->oculto;
    [self atualizarPainel];
    [self redesenhar];
}
- (void)tocouPadraoDeste {
    HL2EdBotao *b = [self escolhido];
    if (!b) return;
    ajuste_padrao(&trabalho.botao[b.acao]);
    [self atualizarPainel];
    [self redesenhar];
}
- (void)restaurarTudo {
    ajustes_padrao(&trabalho);
    selecionado = -1;
    [self atualizarPainel];
    [self redesenhar];
}
- (void)tocouRestaurar {
    __weak HL2EdTela *fraca = self;
    [self perguntar:@"Tem certeza? Todos os botões voltam à posição, ao tamanho e às opções originais, e a "
                    @"opacidade e os sticks voltam ao normal. Só é gravado quando você tocar em Concluir."
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

static UIWindow *janela;
static void (^ao_fechar)(int);
static CFRunLoopObserverRef observador;

static void editor_fechar(int salvou) {
    if (!janela) return;
    // Depois da ação do botão que pediu para fechar, não no meio dela.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!janela) return;
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
