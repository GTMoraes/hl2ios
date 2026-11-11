// hl2ios: editor e ajustes dos controles de toque (hl2ios_toque.m).
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). Os ajustes e os botões criados ficam em Documents/hl2-toque.json,
// visível no app Arquivos; a cópia anterior fica em Documents/hl2-toque-anterior.json.
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

// Como o editor fecha (0) ou abre (1) o menu de pausa do jogo: o ajuste da arma mostra o jogo
// rodando atrás. Chamado pelo touch_controls.m antes de abrir o editor.
void hl2ios_toque_editor_pausa(void (^pausar)(int pausar));

// ---- botões criados no editor (até 24: ações RT_TOUCH_CUSTOM a RT_TOUCH_CUSTOM_LAST) ----

// Quantos botões criados existem.
int hl2ios_toque_personalizados(void);

// Botão criado número i dentro da zona segura (x, y, w, h): centro, tamanho, opções (alternar e
// mirar), ícone SF Symbols, cor (r, g, b, a) e 1 em `guardar` se ele guarda a arma. Devolve a
// ação (RT_TOUCH_CUSTOM + i), ou -1 se o botão não existe.
int hl2ios_toque_personalizado(int i, double x, double y, double w, double h, double *cx, double *cy,
                               float *tamanho, unsigned *flags, const char **simbolo, float rgba[4], int *guardar);

// O dedo apertou (1) ou soltou (0) o botão criado número i: roda o que ele faz.
void hl2ios_toque_executar(int i, int apertou);
