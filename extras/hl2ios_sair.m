// hl2ios: saída do jogo pelo menu (Sair) sem o iOS acusar falha.
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). Chamado pelo patch 0006 nos dois caminhos de saída do jogo: o
// exit() do código traduzido (runtime/process.c) e a volta do main do jogo (src/main.c).
//
// Antes, o processo terminava em primeiro plano, com os threads do jogo (áudio, materiais)
// ainda rodando enquanto a memória do jogo era desfeita (rt_destroy) ou os destrutores do
// processo rodavam (exit): o iOS via um fim abrupto. Agora, como no hlios: o app vai para o
// fundo com a animação normal do sistema (o mesmo que o gesto de voltar à tela inicial), e só
// depois o processo termina, por _exit, sem destrutores.
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <unistd.h>
#include "hl2ios_sair.h"

unsigned rt_guest_suspend(void);       // runtime/scheduler.c
void rt_guest_resume(unsigned saved);
void rt_frame_times_flush(void);       // runtime/frame_times.c

void hl2ios_sair_animar(int status) {
    static int feito;
    if (feito) return;
    feito = 1;
    fprintf(stderr, "[hl2ios] sair: o jogo terminou (código %d), app indo para o fundo\n", status);
    fflush(NULL);
    if (![NSThread isMainThread]) return;   // o UIKit só no thread principal
    UIApplication *app = UIApplication.sharedApplication;
    SEL suspend = NSSelectorFromString(@"suspend");
    if (![app respondsToSelector:suspend]) {
        fprintf(stderr, "[hl2ios] sair: UIApplication sem suspend, fecha direto\n");
        return;
    }
    // O mesmo que ir para a tela inicial; o jogo não roda mais quadros, então a pausa de
    // lifecycle_ios.m não entra. Chamado por ponteiro: o seletor não é público.
    ((void (*)(id, SEL))[app methodForSelector:suspend])(app, suspend);
    // A animação precisa da volta do UIKit: servida por até 1 s (até o app ir para o fundo,
    // mais um pouco). Como na pausa de lifecycle_ios.m, a trava do código traduzido é
    // largada a cada 20 ms.
    CFTimeInterval inicio = CACurrentMediaTime(), fundo = 0;
    while (CACurrentMediaTime() - inicio < 1.5) {
        while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true) == kCFRunLoopRunHandledSource) {}
        if (!fundo && app.applicationState == UIApplicationStateBackground) fundo = CACurrentMediaTime();
        if (fundo && CACurrentMediaTime() - fundo > .3) break;
        unsigned saved = rt_guest_suspend();
        usleep(20000);
        rt_guest_resume(saved);
    }
    fprintf(stderr, "[hl2ios] sair: %s após %.2f s\n", fundo ? "no fundo" : "ainda na frente",
            CACurrentMediaTime() - inicio);
}

void hl2ios_sair_fim(int status) {
    hl2ios_sair_animar(status);
    rt_frame_times_flush();
    fprintf(stderr, "[hl2ios] sair: processo encerrado\n");
    fflush(NULL);
    _exit(status & 0xff);
}
#endif
