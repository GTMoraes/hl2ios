// hl2ios: tela de espera pelos dados do jogo.
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do
// build (scripts/baixar-recomp.sh). Sem a pasta Documents/game o runtime sai na hora
// (tela preta e app fechado), o que não se distingue de um travamento. Esta tela diz
// o que copiar, mostra o que ainda falta e só deixa seguir com as sete pastas no lugar.
//
// Chamado por ios/main_ios.c, no thread principal, depois do UIKit iniciado pelo SDL
// e antes de o SDL criar a janela do jogo.
#import <UIKit/UIKit.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

// Arquivo fora do source-recomp: avisos de API antiga ou de parâmetro sem uso não podem
// parar o build (o runtime compila com -Werror).
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunused-parameter"

#define HL2IOS_PASTAS 7
// As mesmas pastas que o tools/ios_device.sh copia (ios_data de tools/games.py).
static const char *const hl2ios_pastas[HL2IOS_PASTAS] = {
    "bin", "platform", "hl2", "episodic", "ep2", "lostcoast", "hl2_complete"};

// Quantas pastas faltam em Documents/game; `lista` recebe os nomes separados por vírgula.
static int hl2ios_faltam(const char *documents, char *lista, size_t tamanho) {
    int faltam = 0;
    if (lista && tamanho) lista[0] = 0;
    for (int i = 0; i < HL2IOS_PASTAS; ++i) {
        char caminho[PATH_MAX];
        struct stat st;
        snprintf(caminho, sizeof(caminho), "%s/game/%s", documents, hl2ios_pastas[i]);
        if (!stat(caminho, &st) && S_ISDIR(st.st_mode)) continue;
        ++faltam;
        if (lista && tamanho) {
            size_t usado = strlen(lista);
            if (usado < tamanho)
                snprintf(lista + usado, tamanho - usado, "%s%s", usado ? ", " : "", hl2ios_pastas[i]);
        }
    }
    return faltam;
}

// O app Arquivos só mostra a pasta de um app em "No Meu iPhone" quando há algo dentro de
// Documents. O source-recomp cria ali a pasta dos saves, mas só depois deste ponto: enquanto
// a tela de espera está aberta, Documents ficaria vazio e a pasta do app não apareceria.
// Então a pasta game já nasce aqui, com um bilhete do que copiar para dentro dela.
static void hl2ios_preparar_pasta(const char *documents) {
    char caminho[PATH_MAX];
    snprintf(caminho, sizeof(caminho), "%s/game", documents);
    mkdir(caminho, 0755);
    snprintf(caminho, sizeof(caminho), "%s/COPIE-PARA-A-PASTA-game.txt", documents);
    FILE *bilhete = fopen(caminho, "w");
    if (!bilhete) return;
    fputs("Half-Life 2 no iPhone\n\n"
          "Copie para dentro da pasta \"game\", da pasta do jogo na Steam\n"
          "(steamapps\\common\\Half-Life 2), estas sete pastas:\n\n"
          "  bin\n  platform\n  hl2\n  episodic\n  ep2\n  lostcoast\n  hl2_complete\n\n"
          "Depois abra o app e toque em Iniciar o jogo.\n", bilhete);
    fclose(bilhete);
}

@interface HL2iosEspera : UIViewController
@property (nonatomic, copy) NSString *documentos;
@property (nonatomic, strong) UILabel *texto;
@property (nonatomic, strong) UIButton *botao;
@property (nonatomic, assign) BOOL iniciar;
- (void)atualizar;
- (void)tocouIniciar;
@end

@implementation HL2iosEspera

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UILabel *texto = [[UILabel alloc] init];
    texto.translatesAutoresizingMaskIntoConstraints = NO;
    texto.numberOfLines = 0;
    texto.textColor = [UIColor whiteColor];
    texto.textAlignment = NSTextAlignmentCenter;
    texto.font = [UIFont systemFontOfSize:16.0];
    texto.adjustsFontSizeToFitWidth = YES;
    texto.minimumScaleFactor = 0.6;
    [self.view addSubview:texto];

    UIButton *botao = [UIButton buttonWithType:UIButtonTypeSystem];
    botao.translatesAutoresizingMaskIntoConstraints = NO;
    [botao setTitle:@"Iniciar o jogo" forState:UIControlStateNormal];
    botao.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
    [botao setTitleColor:[UIColor colorWithRed:0.98 green:0.60 blue:0.05 alpha:1.0] forState:UIControlStateNormal];
    [botao addTarget:self action:@selector(tocouIniciar) forControlEvents:UIControlEventTouchUpInside];
    botao.hidden = YES;
    [self.view addSubview:botao];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [texto.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:24.0],
        [texto.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-24.0],
        [texto.centerYAnchor constraintEqualToAnchor:area.centerYAnchor constant:-28.0],
        [botao.centerXAnchor constraintEqualToAnchor:area.centerXAnchor],
        [botao.topAnchor constraintEqualToAnchor:texto.bottomAnchor constant:14.0]
    ]];

    self.texto = texto;
    self.botao = botao;
    [self atualizar];
}

- (void)tocouIniciar {
    self.iniciar = YES;
}

- (void)atualizar {
    char lista[256] = "";
    const char *documents = self.documentos.fileSystemRepresentation;
    int faltam = documents ? hl2ios_faltam(documents, lista, sizeof(lista)) : HL2IOS_PASTAS;
    NSString *mensagem;
    if (faltam > 0) {
        mensagem = [NSString stringWithFormat:
            @"Half-Life 2: faltam os dados do jogo.\n\n"
            @"No app Arquivos, em No Meu iPhone › Half-Life 2, copie para dentro da pasta \"game\",\n"
            @"da pasta do jogo na Steam: bin, platform, hl2, episodic, ep2, lostcoast e hl2_complete.\n\n"
            @"Ainda faltam: %s.\nEsta tela se atualiza sozinha.", lista[0] ? lista : "todas"];
    } else {
        mensagem =
            @"Half-Life 2: as sete pastas do jogo estão no lugar.\n\n"
            @"Espere a cópia terminar antes de iniciar.\n"
            @"Para ter o registro de erros, ligue antes: Ajustes › Apps › Half-Life 2 › Log.";
    }
    self.texto.text = mensagem;
    self.botao.hidden = faltam > 0;
}

@end

void hl2ios_esperar_dados(const char *documents);

void hl2ios_esperar_dados(const char *documents) {
    if (!documents || !hl2ios_faltam(documents, NULL, 0)) return;
    hl2ios_preparar_pasta(documents);
    fprintf(stderr, "[hl2ios] Documents/game incompleta: tela de espera\n");
    @autoreleasepool {
        UIWindow *janela = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        HL2iosEspera *tela = [[HL2iosEspera alloc] init];
        tela.documentos = [NSString stringWithUTF8String:documents];
        janela.rootViewController = tela;
        [janela makeKeyAndVisible];
        // Laço de eventos aninhado, como o do próprio SDL: a tela responde ao toque e
        // confere as pastas duas vezes por segundo.
        while (!tela.iniciar) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
                [tela atualizar];
            }
        }
        janela.hidden = YES;
        janela.rootViewController = nil;
    }
    fprintf(stderr, "[hl2ios] dados no lugar: seguindo para o jogo\n");
}
