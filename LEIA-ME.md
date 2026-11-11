# Half-Life 2 no iPhone (hl2ios)

App de iPhone com o Half-Life 2, o Episode One, o Episode Two e o Lost Coast, gerado pelo
[source-recomp](https://github.com/kanapitsas/source-recomp): o código x86 da versão Linux do jogo
é traduzido para C e compilado para ARM64, sem emulador e sem JIT. O build roda no GitHub Actions
(runner macOS) e o app chega pelo TestFlight, como o `hlios` e o `nfios`.

**Estado:** em 10/11/2026 o jogo rodou no iPhone 17 (Metal, 238 MB de código, build de 48 min).
Em 11/11/2026 entrou o editor dos controles de toque (versão 0.2.0), ainda não compilado.

## Regra deste repositório: nada da Valve aqui

O repositório é público, e por isso:

| O que é da Valve | Onde fica |
|---|---|
| Binários Linux do jogo (depot 224) | Repositório privado `GTMoraes/hl2ios-depot`, numa Release. O workflow baixa com o segredo `DEPOT_TOKEN`. |
| Código traduzido (C gerado e objetos) | Só no runner. O cache dele é cifrado com o segredo `CACHE_SENHA`. |
| O app pronto (leva o código traduzido e o depot dentro) | Vai direto do runner para o TestFlight. Nunca vira artifact. |
| Dados do jogo (10 GB) | Só no seu PC e no iPhone. Não passam pelo GitHub. |
| Logo do Half-Life 2 | Segredo `APP_ICON_SVG`. |

O único artifact são os logs, e os trechos de código saem deles (`sem_trechos` em
`scripts/comum.sh`). O `.gitignore` barra zip, binários, dados do jogo e imagens. **Antes de
qualquer `git add`, confira no `git status` que não aparece nada disso.**

## Peças

| Peça | Versão | Onde está fixada |
|---|---|---|
| source-recomp | commit `adb7546` (09/11/2026) | `versoes.env` |
| mtld3d (Direct3D 9 sobre Metal) | commit `101f37d`, o mesmo que o source-recomp fixa | `versoes.env` |
| Depot 224 | zip de 199 MB, SHA-256 em `versoes.env` | repositório privado |
| Xcode | o 26 mais novo do runner `macos-26` | `scripts/escolher-xcode.sh` |
| App | "Half-Life 2", `com.gtm.halflife2`, iOS 17 ou mais novo, só iPhone | `versoes.env` |

## Estrutura

```
.github/workflows/build-ipa.yml   o build inteiro, passo a passo
versoes.env                       versões fixadas
patches/                          mudanças sobre o source-recomp (git apply)
extras/hl2ios_dados.m             tela de espera pelos dados do jogo (arquivo novo do runtime)
extras/hl2ios_toque.m e .h        editor dos controles de toque e os ajustes salvos
raizes/hl2-extras.json            alvos de chamada indireta achados no iPhone (começa vazio)
app/direitos.plist                direitos do app (Increased Memory Limit)
app/PrivacyInfo.xcprivacy         manifesto de privacidade
scripts/                          um script por passo do workflow
```

## O que muda em relação ao source-recomp

O projeto foi feito para um Mac com o iPhone no cabo. Aqui não há Mac, então:

1. **Assinatura** (`patches/0001`): sai a do projeto (perfil de desenvolvimento do Xcode), entra a
   gerenciada pela Apple, no envio ao TestFlight (`scripts/enviar-testflight.sh`).
2. **SDK declarado** (`patches/0001`): o projeto declara o SDK 18 no executável para o UIKit manter
   o ciclo de vida clássico. O App Store Connect recusa SDK antigo, então o app declara o SDK de
   verdade e o build usa o Xcode 26, que ainda não exige UIScene (o mesmo critério do `hlios`).
3. **`prep` e `linux` dentro do app** (`patches/0002`): o projeto copia essas duas pastas para o
   iPhone pelo cabo. Aqui elas vão junto no app, e no iPhone só falta a pasta `game`. Uma pasta
   `prep` ou `linux` em Documents, se existir, continua valendo primeiro.
4. **Tela de espera** (`extras/hl2ios_dados.m`): sem a pasta `game` o runtime fecharia na hora. A
   tela diz o que copiar, mostra o que falta e libera o botão Iniciar com as sete pastas no lugar.
5. **Ícone, Info.plist e privacidade** (`scripts/montar-app.sh`): ícone em catálogo, chaves que o
   App Store Connect confere, só iPhone.
6. **Editor dos controles** (`patches/0003` e `extras/hl2ios_toque.m`): dois botões novos na tabela
   (pulo agachado e a engrenagem do editor), e a camada de toque passa a aplicar os ajustes salvos.
   Detalhes na seção "Editor dos controles".
7. **Botões de comando e arma guardada** (`patches/0004` e `0005`, `extras/hl2ios_jogo.c`): botões
   criados no editor rodam comandos do console, e o botão de guardar a arma trava o tiro enquanto
   ela está guardada. Detalhes em "Botões criados" e "Guardar arma".
8. **Sair sem falha** (`patches/0006`, `extras/hl2ios_sair.m`): ao sair pelo menu do jogo, o app vai
   para o fundo com a animação do sistema e só depois fecha.
9. **Posição e FOV da arma** (`patches/0007`, `extras/hl2ios_arma.c`): o balanço da arma ao andar
   (`AddViewmodelBob` do `client.so`) passa por uma função do app, que roda a original e depois
   desloca a arma. Detalhes em "Posição e FOV da arma".
10. **Abaixar a arma** (`patches/0008`, `extras/hl2ios_jogo.c`): toque curto no botão de guardar
   abaixa a arma; o primeiro toque no tiro só a levanta. Detalhes em "Guardar arma".
11. **Munição de reserva em triplo** (`extras/hl2ios_jogo.c`): o máximo de cada munição que o
   jogador carrega é o triplo do jogo. Detalhes em "Munição de reserva".
12. **Escopeta com o dobro de bagos** (`extras/hl2ios_jogo.c` e `scripts/ajustar-depot.py`): o
   tiro cheio dá 1,5 vez o dano original. Detalhes em "Escopeta".

O binário de Mac que vem esquecido no depot (`bin/ffmpegsumo.so`) é tirado do app: binário Mach-O
solto é recusado no envio, e o jogo não usa esse arquivo.

## Segredos (Settings › Secrets and variables › Actions)

| Segredo | O que é |
|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID` | Chave da API do App Store Connect (a mesma do `nfios` e do `hlios`) |
| `DEPOT_TOKEN` | Token de leitura do `hl2ios-depot`. Quando vencer, o passo "Baixar os binários" falha: gere outro |
| `CACHE_SENHA` | Senha do cache cifrado. Se trocar, a build seguinte só refaz o cache |
| `APP_ICON_SVG` | O texto do SVG do logo. Sem ele o app sai com um ícone simples |

## Subir pela primeira vez

No PowerShell:

```powershell
cd C:\claudin\gtm\2026\random\hl2-ios

# 1. o zip do depot sai da pasta do repositório (o .gitignore barra, mas é melhor nem estar aqui)
Move-Item depot_224.zip ..\depot_224.zip

# 2. o workflow vai para o lugar dele (a ponte do Claude não grava dentro de .github)
New-Item -ItemType Directory -Force .github\workflows | Out-Null
Move-Item PARA-A-PASTA-.github-workflows\build-ipa.yml .github\workflows\build-ipa.yml
Remove-Item PARA-A-PASTA-.github-workflows

# 3. liga a pasta ao repositório que já existe no GitHub
git init -b main
git remote add origin https://github.com/GTMoraes/hl2ios.git
git pull origin main

# 4. confere e sobe
git add -A
git status
git commit -m "Etapa 1: build do Half-Life 2 para o TestFlight"
git push -u origin main
```

No `git status` devem aparecer só: `.gitattributes`, `.gitignore`, `.github/`, `LEIA-ME.md`,
`versoes.env`, `app/`, `extras/`, `patches/`, `raizes/` e `scripts/`. Se aparecer zip, `.so`,
`.svg` ou `.png`, pare e me avise.

O push já dispara a build (aba Actions).

## A build

- **Tempo:** a primeira leva de uma a duas horas (estimativa; o autor leva 10 a 20 minutos num M3
  Pro, e o runner tem 3 núcleos de M1 e 7 GB). As seguintes reaproveitam o cache.
- **Resumo:** a página da execução mostra o tempo, o tamanho do executável, se o Metal entrou e se
  o envio foi feito.
- **Se falhar:** o passo "Resumo dos erros" junta as linhas de erro. Me mande o artifact
  `logs-N` (ou o texto desse passo).
- **Limite da Apple:** executável com mais de 500 MB de código é recusado. O resumo mostra quanto
  deu. Se passar, o plano B é um IPA assinado pela conta paga, fora do TestFlight.
- **Sem Metal:** se a biblioteca do Metal não compilar, a build continua com OpenGL e avisa no
  resumo. O jogo roda, mais lento e mais escuro.

## No iPhone

1. Instale pelo TestFlight e abra uma vez. Aparece a tela de espera, e o app cria a pasta `game`
   (com um bilhete ao lado). É isso que faz a pasta "Half-Life 2" aparecer no app Arquivos: o iOS
   não mostra a pasta de um app enquanto ela está vazia.
2. Copie para dentro de `game`, de `steamapps\common\Half-Life 2`: `bin`, `platform`, `hl2`,
   `episodic`, `ep2`, `lostcoast` e `hl2_complete` (uns 10 GB).
3. O destino é app Arquivos › No Meu iPhone › Half-Life 2 › game. Pelo cabo, o app Dispositivos
   Apple do Windows mostra essa mesma pasta na aba Arquivos, e é o caminho mais rápido para 10 GB.
4. Ligue Ajustes › Apps › Half-Life 2 › Log. O registro fica em `game.log`, na mesma pasta.
5. Abra o app. Com as sete pastas no lugar e a cópia terminada, toque em Iniciar.

Os episódios e o Lost Coast abrem pelo menu do jogo. Os saves ficam em `hl2-userdata`.

## Editor dos controles

A engrenagem no alto (à direita do botão de stick/trackpad) pausa o jogo e abre o editor por cima
do menu de pausa.

- **Mover:** arraste o botão. Nada sai da zona segura da tela.
- **Tamanho:** pince com dois dedos, ou use o controle Tamanho do painel (28 a 140 pontos).
- **Ocultar / Mostrar:** o botão some do jogo e fica apagado no editor, marcado "(oculto)". A
  engrenagem não pode ser ocultada.
- **Alternar** (tiro, tiro secundário, agachar, correr): um toque liga, outro desliga, em vez de
  segurar.
- **Mira ao arrastar** (botões de ação): o dedo que segura o botão também gira a câmera ao
  arrastar, como o tiro faz por padrão.
- **Sem botão escolhido:** opacidade de todos os botões e dos sticks, e tamanho dos sticks (um
  stick maior pede mais curso do dedo até o máximo). Os dois anéis mostram os sticks em repouso.
- **Padrão deste** volta só o botão escolhido; **Restaurar tudo** volta tudo e pergunta antes.
- **Concluir** grava e volta ao jogo; **Cancelar** descarta e pergunta antes, se houve mudança.
- **Painel embaixo / em cima:** tira o painel de cima dos botões do alto.

A linha tracejada no meio é a divisa dos sticks: o dedo que começa à esquerda anda, o que começa à
direita mexe a câmera. Ela não muda no editor.

**Pulo agachado** (botão laranja, à esquerda do recarregar): aperta pulo e agachar juntos, o
equivalente no Half-Life 2 ao pulo longo dos outros jogos. Se o agachar alternado estiver ligado,
ele continua agachado depois.

### Botões criados

**Novo botão** (no painel) cria um botão a mais, até 24. Ele aparece no alto, no meio da tela, e
abre a folha dele:

- **Modelo:** Guardar arma, Arma 1 a Arma 6 (`slot1` a `slot6`), Última arma (`lastinv`, o Q do PC)
  ou Comando.
- **Comando:** o que vai no console do jogo, digitado no campo. Vários separados por `;`. Os que
  começam com `+` (como `+attack2` ou `+jump; +duck`) ficam apertados enquanto o dedo segura e são
  soltos (`-attack2`, `-jump;-duck`) quando ele sai; com **Alternar** ligado, um toque aperta e o
  outro solta. Comandos que pedem `sv_cheats` continuam pedindo.
- **Cor e ícone:** escolhidos na folha. **Pronto** fecha a folha.

Com o botão criado escolhido, o painel tem Tamanho, **Editar** (abre a folha de novo), **Apagar**
(pergunta antes) e Mira ao arrastar. Nada é gravado antes de Concluir; Restaurar tudo apaga os
botões criados (e pergunta antes).

Com `hud_fastswitch 0` (o padrão do jogo), Arma 1 a 6 abrem a seleção na tela e o tiro confirma,
como no PC. Para trocar na hora, ligue a troca rápida de armas nas opções do jogo (Teclado ›
Avançado) ou use um botão de Comando com `hud_fastswitch 1`.

### Guardar arma

O botão do modelo Guardar arma faz duas coisas:

- **toque curto:** abaixa a arma, na mesma posição de quando se mira um aliado; o toque seguinte a
  levanta. Com ela abaixada, o primeiro toque no tiro ou no tiro secundário só levanta a arma, sem
  atirar (o próximo toque atira); o recarregar recarrega na hora e a arma volta abaixada; um botão
  de arma levanta e troca. O botão fica aceso enquanto ela está abaixada;
- **segurar (0,4 s):** guarda a arma com a animação (o `impulse 200` do jogo); com ela guardada,
  apertar o botão saca de novo.

Abaixar usa o estado global `friendly_encounter`, o mesmo que o jogo usa para abaixar a arma
(no `server.so`, só `WeaponShouldBeLowered` o lê). O app o liga e desliga pelo comando
`global_set` do servidor, chamado direto, sem `sv_cheats`. O estado vai junto no save e atravessa
a troca de mapa; abaixada pelo app, ela continua abaixada ao carregar um save. A arma de
gravidade não tem animação de abaixar e fica como está.

Com a arma guardada:

- o tiro, o tiro secundário e o recarregar mostram um cadeado e não disparam; tocar num deles
  saca a arma, sem atirar;
- o botão fica aceso;
- o app lê do próprio jogo a arma na mão e se ela está escondida. Quando o jogo saca a arma
  sozinho (arma nova pega, objeto solto depois do Usar, troca de arma, veículo), os botões voltam
  ao normal na hora;
- num save feito com a arma guardada, ela continua guardada ao carregar, e o cadeado volta junto.

O `impulse 200` só vale com `sv_cheats 1`. O app liga o `sv_cheats` só pelo instante em que o jogo
processa o comando e volta a 0 em seguida (se já estava em 1, não mexe). O registro mostra tudo
nas linhas `[hl2ios] arma:`.

### Munição de reserva

O jogador carrega o triplo da munição de reserva do jogo (pistola 150 vira 450, granadas 5 viram
15 e assim por diante). O carregador de cada arma não muda. O máximo de cada munição vem das
variáveis `sk_max_*` (`sk_max_pistol`, `sk_max_357`, `sk_max_smg1`, `sk_max_smg1_grenade`,
`sk_max_ar2`, `sk_max_ar2_altfire`, `sk_max_buckshot`, `sk_max_crossbow`, `sk_max_rpg_round`,
`sk_max_grenade`), que o `skill.cfg` do jogo põe. Uma vez por segundo o app confere cada uma:
se o valor não é o que ele pôs, é um valor novo do jogo, e o app põe o triplo dele. Elas não são
de trapaça, então o `sv_cheats` não as afeta. O registro mostra cada troca nas linhas
`[hl2ios] munição:`. Para mudar o fator, troque `MUNICAO_FATOR` em `extras/hl2ios_jogo.c`.

### Escopeta

O tiro normal e o tiro duplo da escopeta têm o dobro de bagos, e o dano de cada bago do jogador
cai a 3/4: o tiro cheio (todos os bagos acertando) dá 1,5 vez o dano original.

| Tiro | Original | Agora |
|---|---|---|
| Normal | 7 bagos x 8 = 56 | 14 bagos x 6 = 84 |
| Duplo | 12 bagos x 8 = 96 | 24 bagos x 6 = 144 |

- O tiro normal usa a variável `sk_plr_num_shotgun_pellets` (dobrada pelo app) e o dano de cada
  bago, `sk_plr_dmg_buckshot` (posta a 3/4 pelo app), do mesmo jeito que a munição de reserva.
  Os fatores ficam em `BAGOS_FATOR` e `DANO_TIRO_CHEIO`, em `extras/hl2ios_jogo.c`.
- O tiro duplo tem os 12 bagos fixos no código do jogo. O `scripts/ajustar-depot.py` troca esse
  número por 24 no `server.so` logo depois de baixar o depot (o `scripts/baixar-depot.sh` o chama),
  antes da tradução; ele confere os bytes originais e para o build se não conferirem.
- O dano dos NPCs com escopeta (`sk_npc_dmg_buckshot`) não muda.
- Ao mudar a lista de ajustes de bytes, suba `DEPOT_AJUSTES` em `versoes.env`: o build seguinte
  refaz os módulos preparados e a tradução inteira (uma a duas horas).

### Posição e FOV da arma

**Arma** (no painel) mostra só uma barra no alto, fecha o menu de pausa (`gameui_hide`) e deixa o
jogo rodando atrás, para ver a arma ao vivo, balançando. Os controles de toque ficam bloqueados enquanto isso:
faça o ajuste num lugar sem inimigo.

- **Frente** (+ afasta, - aproxima), **Lado** (+ direita) e **Altura** (+ sobe): de -12 a +12
  unidades do jogo, em passos de 0,5.
- **FOV da arma:** de 20 a 110 (o do jogo é 54). Vale só para a arma, não para o mundo.
- Cada arma guarda o seu ajuste; a barra mostra a que está na mão. Troque de arma (pelo jogo ou
  pelos botões) com a barra aberta para ajustar outra.
- **Padrão desta arma** volta a arma na mão para o do jogo. **Copiar para todas** leva o ajuste
  dela para todas as outras, inclusive as que ainda não foram ajustadas (pergunta antes).
- **Voltar ao editor** pausa o jogo de novo. Como o resto, só é gravado em Concluir.

O FOV vai direto na variável `viewmodel_fov` do jogo, sem `sv_cheats`. Quando o jogo a devolve ao
padrão (por exemplo, depois de guardar a arma), o app põe de novo em até 50 ms. O registro mostra
a arma na mão e o FOV nas linhas `[hl2ios] arma`.

### Arquivo dos ajustes

Os ajustes e os botões criados ficam em `hl2-toque.json`, na pasta do app no Arquivos, e a versão anterior em
`hl2-toque-anterior.json`. Para começar do zero fora do editor, apague o `hl2-toque.json` com o app
fechado. O registro (`game.log`) mostra o que foi lido e gravado, nas linhas `[hl2ios] toque:`.

## Quando travar

É esperado, mais nos episódios: o tradutor não acha sozinho toda função chamada por ponteiro, e a
ferramenta que acha essas funções roda o jogo num Mac. O runtime para e escreve no `game.log` uma
linha com "target not recompiled" e o endereço.

1. Me mande o `game.log` (Arquivos › Half-Life 2).
2. O endereço vira uma linha em `raizes/hl2-extras.json`, no formato do `config/hl2-roots.json`
   do source-recomp (por exemplo `"client.so:code:0x5a0935"`).
3. Push, build nova, TestFlight. A tradução é refeita; os objetos que não mudaram vêm do cache.

## Riscos conhecidos desta etapa

- **O jogo ainda não rodou no iPhone.** A build passa e o app abre; daqui em diante é terreno novo.
- **Memória do runner (7 GB)** na tradução e na ligação de um executável deste tamanho.
- **Limite de 500 MB de código** do App Store Connect.
- **`prep` e `linux` dentro do app** não é como o projeto roda. A pasta do app é só de leitura; se
  o jogo tentar gravar ali, o conserto é copiar essas pastas para Documents no primeiro uso.
- **Arquivos ELF e DLL dentro do app** (o depot): não conheço regra do envio contra eles, mas é a
  primeira vez que passam por ele.
- **iPhone 17:** o projeto só foi testado num iPhone 15 Pro Max.
- **Editor numa janela própria:** o laço do SDL não deixa o UIKit desenhar sozinho, então o editor
  força cada desenho (como a camada de toque do projeto faz). Se ele abrir sem responder ou sem
  atualizar a tela, é aqui.
- **Teclado do campo de comando:** o editor pega o foco do SDL enquanto o campo está em uso e o
  devolve depois. Se o teclado não abrir, ou o jogo não responder a teclas depois de fechar o
  editor, é aqui.
- **Leitura da arma:** os endereços vêm das tabelas de rede do próprio jogo; se a busca falhar, o
  app usa os que achei no `client.so` do depot 224. Se nada conferir, o botão ainda guarda e saca,
  mas o tiro não trava (o registro diz "leitura não confere").
- **Controle ou teclado físico** não passam pela trava do tiro.
- **Sair:** o app usa a mesma chamada do `hlios` para ir ao fundo (`suspend`, não pública).
- **Posição da arma:** a troca da função só acontece se os bytes dela no `client.so` forem os do
  depot 224. Num depot diferente o build avisa ("remplacement natif ... ignoré") e a arma fica na
  posição do jogo; o FOV continua valendo. `P2_NATIVE_HL2IOS_ARMA=0` desliga a troca.

## Atualizar

- **source-recomp:** troque `RECOMP_COMMIT` em `versoes.env`. Os patches podem deixar de aplicar
  (o passo "Baixar o source-recomp" avisa qual). Confira também se o `setup.sh` novo fixa outro
  commit do mtld3d (`MTLD3D_REV`) e copie para `MTLD3D_COMMIT`.
- **Depot:** se a Valve atualizar o jogo, o depot novo pede outro zip na Release, outro
  `DEPOT_SHA256` e, quase sempre, um source-recomp que já o suporte.
- **Versão do app:** `APP_VERSAO` em `versoes.env`. O número da build é o da execução no Actions.

## Licença

Os scripts e patches deste repositório seguem a GPL v3 do source-recomp. O Half-Life 2 é da Valve:
o app e o código traduzido são para uso próprio e não devem ser distribuídos.
