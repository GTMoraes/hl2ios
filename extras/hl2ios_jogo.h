// hl2ios: comandos do console e arma guardada (hl2ios_jogo.c).
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). Tudo roda no thread principal: o do UIKit, que no iOS também é o
// do jogo (o SDL chama o main do jogo nele).
#pragma once

// ---- pedidos da camada de toque e do editor ----

// Põe uma linha do console na fila (várias separadas por ";"). Ela roda no próximo quadro do
// jogo, por um arquivo cfg/hl2ios_botao_N.cfg na pasta do jogo e o comando exec, como se fosse
// digitada no console.
void hl2ios_jogo_comando(const char *linha);

// Guardar arma: alterna entre guardar e sacar (impulse 200, com sv_cheats ligado só pelo tempo
// de o jogo processar o comando).
void hl2ios_jogo_guardar(void);

// Saca a arma guardada (toque no tiro com a arma guardada).
void hl2ios_jogo_sacar(void);

// Botão de guardar apertado (1) ou solto (0): toque curto abaixa ou levanta a arma (estado
// global friendly_encounter, pelo global_set); segurar 0,4 s guarda a arma. Com a arma
// guardada, o botão a saca ao apertar.
void hl2ios_jogo_botao_guardar(int apertou);

// Levanta a arma abaixada pelo botão (primeiro toque no tiro ou no tiro secundário, botões
// de arma).
void hl2ios_jogo_levantar(void);

// 1 enquanto a arma está abaixada pelo botão (e ainda não foi pedido levantar): o toque no tiro
// ou no tiro secundário só a levanta, sem atirar.
int hl2ios_jogo_abaixada(void);

// Fecha (0) ou abre (1) o menu de pausa do jogo (gameui_hide, gameui_activate), no próximo
// quadro: o ajuste da arma no editor mostra o jogo rodando atrás.
void hl2ios_jogo_menu(int mostrar);

// Botão de arma (slot1 a slot6, lastinv) apertado: com a arma guardada, o tiro passa por 3 s,
// porque com hud_fastswitch 0 é ele que confirma a escolha no HUD.
void hl2ios_jogo_selecao(void);

// 1 quando o tiro, o tiro secundário e o recarregar devem ficar travados: a arma foi guardada
// pelo app e continua guardada no jogo, fora de veículo.
int hl2ios_jogo_bloqueia_tiro(void);

// 1 enquanto a arma está guardada ou abaixada pelo app (para acender o botão de guardar).
int hl2ios_jogo_guardada(void);

// Muda sempre que o travamento ou a arma guardada mudam: a camada de toque refaz os ícones.
unsigned hl2ios_jogo_versao(void);

// ---- chamado pelo jogo ----

// A cada SDL_PollEvent (game_state.c, patch 0004), com a trava do código traduzido tomada:
// roda a fila e lê o estado da arma.
void hl2ios_jogo_poll(void);
