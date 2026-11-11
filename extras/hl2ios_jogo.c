// hl2ios: comandos do console vindos dos botões e a arma guardada.
//
// Arquivo do repositório hl2ios, copiado para runtime/ios/ do source-recomp antes do build
// (scripts/baixar-recomp.sh). O game_state.c chama hl2ios_jogo_poll() a cada SDL_PollEvent,
// no thread do jogo e com a trava do código traduzido tomada (patch 0004).
//
// Comandos: cada linha vai para um arquivo cfg/hl2ios_botao_N.cfg na pasta do jogo, e o jogo o
// executa pelo comando exec (chamado direto, como o game_state.c faz no diagnóstico). É o mesmo
// caminho de uma linha digitada no console: vale para alias, variáveis e comandos do servidor.
//
// Arma guardada: o impulse 200 do Half-Life 2 guarda a arma (animação e EF_NODRAW) mas não
// impede o tiro, e só vale com sv_cheats. O app liga sv_cheats só até o jogo processar o
// impulso (se já estava ligado, não mexe), e trava o tiro na camada de toque. Para saber quando
// o jogo sacou a arma sozinho (arma nova, objeto solto depois do Usar, troca de arma), ele lê a
// cada 50 ms, pela lista de entidades do cliente (VClientEntityList003), a arma ativa do jogador
// (m_hActiveWeapon), os efeitos dela (m_fEffects, bit EF_NODRAW), o veículo (m_hVehicle) e o
// estado de vida (m_lifeState). Os deslocamentos vêm das tabelas de rede do jogo (VClient017,
// GetAllClasses); se a busca falhar, valem os achados no client.so do depot fixado.
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "game_ios.h"
#include "hl2ios_jogo.h"
#include "modules.h"
#include "rt.h"

// game_state.c (patch 0004)
uint32_t rt_ios_find_convar(CPU *c, const char *name);
const char *rt_ios_convar_string(uint32_t convar);
int rt_ios_set_convar(CPU *c, uint32_t convar, const char *value);
void rt_ios_run_console_command(CPU *c, const char *line);

// ---- fila de comandos ----

enum { FILA = 16, LINHA = 480 };
static char fila[FILA][LINHA];
static int fila_inicio, fila_n;
static unsigned arquivos;   // gira entre hl2ios_botao_0 e _15

void hl2ios_jogo_comando(const char *linha) {
    if (!linha || !*linha) return;
    if (fila_n == FILA) {
        fprintf(stderr, "[hl2ios] comando: fila cheia, \"%s\" descartado\n", linha);
        return;
    }
    snprintf(fila[(fila_inicio + fila_n) % FILA], LINHA, "%s", linha);
    ++fila_n;
}

static const char *pasta_cfg(void) {
    static char pasta[1024];
    if (!pasta[0]) {
        const char *home = getenv("HOME");
        snprintf(pasta, sizeof(pasta), "%s/Documents/game/%s/cfg", home ? home : ".", rt_ios_current_game()->mod);
    }
    return pasta;
}

static void executar(CPU *c, const char *linha) {
    char caminho[1200], exec[64];
    unsigned n = arquivos++ % FILA;
    mkdir(pasta_cfg(), 0755);
    snprintf(caminho, sizeof(caminho), "%s/hl2ios_botao_%u.cfg", pasta_cfg(), n);
    FILE *f = fopen(caminho, "w");
    if (!f) {
        fprintf(stderr, "[hl2ios] comando: não consegui gravar %s\n", caminho);
        return;
    }
    fprintf(f, "%s\n", linha);
    fclose(f);
    fprintf(stderr, "[hl2ios] comando: %s\n", linha);
    snprintf(exec, sizeof(exec), "exec hl2ios_botao_%u", n);
    rt_ios_run_console_command(c, exec);
}

// ---- memória do jogo ----

static uint32_t texto_convidado(const char *texto) {
    uint32_t endereco = rt_alloc((uint32_t)strlen(texto) + 1);
    if (endereco) memcpy(GPTR(endereco), texto, strlen(texto) + 1);
    return endereco;
}
static int legivel(uint32_t a, uint32_t n) {
    return n && a >= 0x10000 && a < RT_IMPORT_BASE - n && rt_guest_readable(a) && rt_guest_readable(a + n - 1);
}
static int nome_igual(uint32_t a, const char *nome) {
    uint32_t n = (uint32_t)strlen(nome) + 1;
    return legivel(a, n) && !memcmp(GPTR(a), nome, n);
}
// Interface `nome` do módulo `modulo` (CreateInterface), ou 0.
static uint32_t interface(CPU *c, const char *modulo, const char *nome) {
    const GuestModule *m = rt_find_module(modulo);
    uint32_t criar = m ? rt_module_symbol(m, "CreateInterface") : 0;
    uint32_t texto = criar ? texto_convidado(nome) : 0;
    if (!texto) return 0;
    uint32_t args[2] = {texto, 0};
    uint32_t r = rt_invoke(c, criar, args, 2);
    rt_free(texto);
    return r;
}

// ---- tabelas de rede (dt_recv.h do SDK 2013) ----
// RecvTable: props (+0), número de props (+4), nome (+12). RecvProp: 60 bytes, nome (+0), tipo
// (+4; 6 = tabela), tabela (+40), deslocamento (+44). ClientClass: nome (+8), tabela (+12),
// próxima (+16). Conferido no client.so: as RecvProp são gravadas de 60 em 60 bytes.
enum { PROP = 60, PROP_TIPO = 4, PROP_TABELA = 40, PROP_DESLOC = 44, DPT_DATATABLE = 6 };

// Deslocamento de `prop` dentro da tabela `tabela`, procurada a partir de t (sub-tabelas
// incluídas, deslocamentos somados), ou -1.
static int achar_prop(uint32_t t, uint32_t base, const char *tabela, const char *prop, int fundo) {
    if (fundo > 16 || !legivel(t, 16)) return -1;
    uint32_t props = R32(t), n = R32(t + 4);
    if (n > 4096 || (n && !legivel(props, n * PROP))) return -1;
    int esta = nome_igual(R32(t + 12), tabela);
    for (uint32_t i = 0; i < n; ++i) {
        uint32_t p = props + i * PROP;
        if (esta && nome_igual(R32(p), prop)) return (int)(base + R32(p + PROP_DESLOC));
        if (R32(p + PROP_TIPO) == DPT_DATATABLE) {
            int r = achar_prop(R32(p + PROP_TABELA), base + R32(p + PROP_DESLOC), tabela, prop, fundo + 1);
            if (r >= 0) return r;
        }
    }
    return -1;
}

// Deslocamentos no C_HL2_Player e na arma. Valores do client.so do depot fixado em versoes.env
// (achados nas chamadas RecvPropInt do código de inicialização), usados se a busca falhar.
static struct { int efeitos, arma, veiculo, vida, saude; } off = {0x68, 0xdd0, 0x10c8, 0x7f, 0x80};

static void achar_deslocamentos(CPU *c) {
    uint32_t cliente = interface(c, "client.so", "VClient017");
    if (!cliente || !legivel(cliente, 4) || !legivel(R32(cliente) + 8 * 4, 4)) {
        fprintf(stderr, "[hl2ios] arma: VClient017 não achado, deslocamentos fixos\n");
        return;
    }
    uint32_t classe = rt_invoke(c, R32(R32(cliente) + 8 * 4), &cliente, 1);   // GetAllClasses
    uint32_t tabela = 0;
    for (int i = 0; i < 4096 && legivel(classe, 20); ++i, classe = R32(classe + 16)) {
        if (nome_igual(R32(classe + 8), "CHL2_Player")) { tabela = R32(classe + 12); break; }
    }
    if (!tabela) {
        fprintf(stderr, "[hl2ios] arma: classe CHL2_Player não achada, deslocamentos fixos\n");
        return;
    }
    const struct { int *destino; const char *tabela, *prop; } busca[] = {
        {&off.efeitos, "DT_BaseEntity", "m_fEffects"},
        {&off.arma, "DT_BaseCombatCharacter", "m_hActiveWeapon"},
        {&off.veiculo, "DT_BasePlayer", "m_hVehicle"},
        {&off.vida, "DT_BasePlayer", "m_lifeState"},
        {&off.saude, "DT_BasePlayer", "m_iHealth"},
    };
    for (size_t i = 0; i < sizeof(busca) / sizeof(*busca); ++i) {
        int achado = achar_prop(tabela, 0, busca[i].tabela, busca[i].prop, 0);
        fprintf(stderr, "[hl2ios] arma: %s %s %#x (fixo %#x)\n", busca[i].prop, achado >= 0 ? "achado em" : "NÃO achado,",
                achado >= 0 ? achado : *busca[i].destino, *busca[i].destino);
        if (achado >= 0) *busca[i].destino = achado;
    }
}

// ---- estado da arma ----

typedef struct {
    int valido;        // há jogador local
    int vivo, veiculo, tem_arma, oculta;
    uint32_t jogador, arma;   // arma: o handle (EHANDLE) da arma ativa
} Estado;

enum { EF_NODRAW = 0x20, HANDLE_INVALIDO = 0xFFFFFFFFu, INDICE = 0xFFF };
static uint32_t lista;          // IClientEntityList
static int lista_buscada, quebrado;

static uint32_t entidade(CPU *c, uint32_t indice) {
    uint32_t args[2] = {lista, indice};
    return rt_invoke(c, R32(R32(lista) + 3 * 4), args, 2);   // GetClientEntity (3ª entrada)
}

static void ler(CPU *c, Estado *e) {
    memset(e, 0, sizeof(*e));
    if (quebrado) return;
    if (!lista_buscada) {
        lista_buscada = 1;
        lista = interface(c, "client.so", "VClientEntityList003");
        fprintf(stderr, "[hl2ios] arma: lista de entidades %s\n", lista ? "achada" : "NÃO achada");
        if (!lista) { quebrado = 1; return; }
        achar_deslocamentos(c);
    }
    uint32_t jogador = entidade(c, 1);   // um jogador só: o local é a entidade 1
    if (!jogador) return;
    static int conferido;
    if (!conferido) {
        conferido = 1;
        int saude = (int)R32(jogador + (uint32_t)off.saude);
        unsigned vida = R8(jogador + (uint32_t)off.vida);
        fprintf(stderr, "[hl2ios] arma: jogador com saúde %d e estado de vida %u\n", saude, vida);
        if (saude < -1000 || saude > 100000 || vida > 4) {   // m_lifeState: 0 a 4 (LIFE_DISCARDBODY)
            fprintf(stderr, "[hl2ios] arma: leitura não confere, o tiro não vai travar sozinho\n");
            quebrado = 1;
            return;
        }
    }
    e->valido = 1;
    e->jogador = jogador;
    e->vivo = R8(jogador + (uint32_t)off.vida) == 0;
    e->veiculo = R32(jogador + (uint32_t)off.veiculo) != HANDLE_INVALIDO;
    e->arma = R32(jogador + (uint32_t)off.arma);
    if (e->arma == HANDLE_INVALIDO) return;
    uint32_t arma = entidade(c, e->arma & INDICE);
    if (!arma) return;
    e->tem_arma = 1;
    e->oculta = (R32(arma + (uint32_t)off.efeitos) & EF_NODRAW) != 0;
}

enum { NORMAL, GUARDANDO, GUARDADA, SACANDO };
enum { PEDIDO_NENHUM, PEDIDO_ALTERNAR, PEDIDO_SACAR };
static int estado = NORMAL, pedido;
static Estado ultimo;
static uint32_t arma_guardada, jogador_visto;
static uint64_t prazo, jogador_desde, proxima_leitura;
static int cheats_nossos;   // sv_cheats foi ligado pelo app e precisa voltar a 0
static unsigned versao;

static const char *nome_estado(int s) {
    return s == GUARDANDO ? "guardando" : s == GUARDADA ? "guardada" : s == SACANDO ? "sacando" : "normal";
}
static void mudar(int novo, const char *motivo) {
    if (novo == estado) return;
    fprintf(stderr, "[hl2ios] arma: %s -> %s (%s)\n", nome_estado(estado), nome_estado(novo), motivo);
    estado = novo;
}

static void cheats_desligar(CPU *c) {
    if (!cheats_nossos) return;
    cheats_nossos = 0;
    uint32_t cv = rt_ios_find_convar(c, "sv_cheats");
    if (cv && rt_ios_set_convar(c, cv, "0")) fprintf(stderr, "[hl2ios] arma: sv_cheats de volta a 0\n");
}
static void impulso(CPU *c) {
    uint32_t cv = rt_ios_find_convar(c, "sv_cheats");
    if (cv && !strcmp(rt_ios_convar_string(cv), "0") && rt_ios_set_convar(c, cv, "1")) {
        cheats_nossos = 1;
        fprintf(stderr, "[hl2ios] arma: sv_cheats ligado para o impulse 200\n");
    }
    rt_ios_run_console_command(c, "impulse 200");
}

static void tratar_pedido(CPU *c, uint64_t agora) {
    int p = pedido;
    pedido = PEDIDO_NENHUM;
    if (!ultimo.valido || !ultimo.tem_arma || !ultimo.vivo || ultimo.veiculo) {
        // Sem leitura (quebrado), o botão ainda alterna pelo impulse 200, sem travar o tiro.
        if (quebrado && p == PEDIDO_ALTERNAR) impulso(c);
        else fprintf(stderr, "[hl2ios] arma: nada a guardar agora (sem arma, morto ou em veículo)\n");
        return;
    }
    if (estado == NORMAL && p == PEDIDO_ALTERNAR) {
        if (ultimo.oculta) {   // o jogo já esconde a arma (objeto carregado pelo Usar): não mexe
            fprintf(stderr, "[hl2ios] arma: o jogo já esconde a arma, nada feito\n");
            return;
        }
        impulso(c);
        arma_guardada = ultimo.arma;
        prazo = agora + 2500;
        mudar(GUARDANDO, "botão");
    } else if (estado == GUARDADA) {
        impulso(c);
        prazo = agora + 2500;
        mudar(SACANDO, p == PEDIDO_SACAR ? "toque no tiro" : "botão");
    }
}

static void atualizar(CPU *c, uint64_t agora) {
    Estado e;
    ler(c, &e);
    ultimo = e;
    if (!e.valido) {   // menu, carregamento, troca de mapa: o próximo jogador é novo
        jogador_visto = 0;
        return;
    }
    if (e.jogador != jogador_visto) {
        jogador_visto = e.jogador;
        jogador_desde = agora;
    }
    int saiu = !e.tem_arma || !e.vivo || e.arma != arma_guardada;
    switch (estado) {
    case GUARDANDO:
        if (saiu) { mudar(NORMAL, "a arma mudou durante a animação"); cheats_desligar(c); }
        else if (e.oculta) { mudar(GUARDADA, "a arma sumiu"); cheats_desligar(c); }
        else if (agora > prazo) { mudar(NORMAL, "o impulse 200 não guardou a arma"); cheats_desligar(c); }
        break;
    case SACANDO:
        if (saiu || !e.oculta) { mudar(NORMAL, "a arma apareceu"); cheats_desligar(c); }
        else if (agora > prazo) { mudar(GUARDADA, "o impulse 200 não sacou a arma"); cheats_desligar(c); }
        break;
    case GUARDADA:
        if (saiu) mudar(NORMAL, "o jogo trocou de arma");
        else if (!e.oculta) mudar(NORMAL, "o jogo sacou a arma");
        break;
    default:
        // Jogador novo (save carregado, mapa novo) com a arma escondida e fora de veículo:
        // ela foi guardada antes de salvar.
        if (agora - jogador_desde < 1500 && e.tem_arma && e.oculta && e.vivo && !e.veiculo) {
            arma_guardada = e.arma;
            mudar(GUARDADA, "save com a arma guardada");
        }
        break;
    }
}

static uint64_t selecao_ate;   // seleção de arma aberta pelo HUD: o tiro confirma
static int visto_bloqueia, visto_guardada;

static void conferir_versao(void) {
    int b = hl2ios_jogo_bloqueia_tiro(), g = hl2ios_jogo_guardada();
    if (b != visto_bloqueia || g != visto_guardada) {
        visto_bloqueia = b;
        visto_guardada = g;
        ++versao;
    }
}

void hl2ios_jogo_poll(void) {
    uint64_t agora = SDL_GetTicks64();
    if (!fila_n && !pedido && agora < proxima_leitura) { conferir_versao(); return; }
    CPU *c = rt_foreign_thread_attach();
    if (!c) return;
    while (fila_n) {
        executar(c, fila[fila_inicio]);
        fila_inicio = (fila_inicio + 1) % FILA;
        --fila_n;
    }
    if (agora >= proxima_leitura) {
        proxima_leitura = agora + 50;
        atualizar(c, agora);
    }
    if (pedido) tratar_pedido(c, agora);
    conferir_versao();
}

// ---- consultas da camada de toque ----

void hl2ios_jogo_guardar(void) {
    pedido = PEDIDO_ALTERNAR;
}
void hl2ios_jogo_sacar(void) {
    if (estado == GUARDADA) pedido = PEDIDO_SACAR;
}
// Com hud_fastswitch 0, slot1 a slot6 abrem a seleção do HUD e é o tiro que confirma: depois
// de um botão de arma, o tiro passa por 3 s. O jogo saca a arma escolhida (a mesma também:
// Weapon_Switch chama Deploy se ela está escondida), e a leitura volta ao normal.
void hl2ios_jogo_selecao(void) {
    if (estado != NORMAL) selecao_ate = SDL_GetTicks64() + 3000;
}
int hl2ios_jogo_bloqueia_tiro(void) {
    return estado != NORMAL && !ultimo.veiculo && SDL_GetTicks64() >= selecao_ate;
}
int hl2ios_jogo_guardada(void) {
    return estado == GUARDANDO || estado == GUARDADA;
}
unsigned hl2ios_jogo_versao(void) {
    return versao;
}
#endif
