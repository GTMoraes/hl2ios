// hl2ios: editor e ajustes dos controles de toque (hl2ios_toque.m).
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). Os ajustes ficam em Documents/hl2-toque.json, visível no app
// Arquivos; a cópia anterior fica em Documents/hl2-toque-anterior.json.
#pragma once
#include "touch_layout.h"

// Aplica ao botão desta ação o ajuste salvo: centro (cx, cy) e tamanho que a tabela de
// touch_layout.c deu dentro da zona segura (x, y, w, h), e as opções (flags: alternar e mirar
// ao arrastar). Devolve 0 se o botão está oculto.
int hl2ios_toque_ajustar(rt_touch_action acao, double x, double y, double w, double h,
                         double *cx, double *cy, float *tamanho, unsigned *flags);

// Opacidade dos botões e dos sticks (0,15 a 1; padrão 1).
float hl2ios_toque_opacidade(void);

// Escala do raio dos sticks (0,6 a 1,6; padrão 1). Stick maior pede mais curso do dedo
// para chegar ao máximo.
float hl2ios_toque_escala_sticks(void);

// Abre o editor por cima do jogo (thread principal). `fechou` roda quando ele fecha, com 1 se
// os ajustes mudaram e foram gravados.
void hl2ios_toque_editor_abrir(void (^fechou)(int salvou));
