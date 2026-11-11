// hl2ios: saída do jogo pelo menu sem o iOS acusar falha (hl2ios_sair.m).
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh); chamado pelo patch 0006 (runtime/process.c e src/main.c).
#pragma once

// Manda o app para o fundo com a animação do sistema e espera ele chegar lá (até 1,5 s).
// Só uma vez; fora do thread principal, não faz nada.
void hl2ios_sair_animar(int status);

// hl2ios_sair_animar, se ainda não foi, e termina o processo com _exit(status), sem os
// destrutores do processo.
void hl2ios_sair_fim(int status) __attribute__((noreturn));
