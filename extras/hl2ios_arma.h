// hl2ios: posição e FOV da arma na mão (hl2ios_arma.c, hl2ios_toque.m, hl2ios_jogo.c).
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh).
#pragma once

// Ajuste da arma desta classe ("CWeaponSMG1"; "" sem arma): deslocamento em unidades do jogo
// (frente, lado à direita, altura) e FOV da arma (0: o do jogo). Vem do editor (hl2ios_toque.m):
// o que está em edição enquanto o editor está aberto, o gravado fora dele.
void hl2ios_toque_arma(const char *classe, float *frente, float *lado, float *altura, float *fov);

// Classe da última arma desenhada na mão ("" se nenhuma ainda), lida do próprio jogo.
const char *hl2ios_arma_classe(void);
