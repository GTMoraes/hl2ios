# Half-Life 2 no iPhone (hl2ios)

App de iPhone com o Half-Life 2, o Episode One, o Episode Two e o Lost Coast, gerado pelo
[source-recomp](https://github.com/kanapitsas/source-recomp): o código x86 da versão Linux do jogo
é traduzido para C e compilado para ARM64, sem emulador e sem JIT. O build roda no GitHub Actions
(runner macOS) e o app chega pelo TestFlight, como o `hlios` e o `nfios`.

**Estado: etapa 1, escrita em 10/11/2026 e ainda não compilada nenhuma vez.** O objetivo desta
etapa é a build chegar ao TestFlight e o app abrir. Os scripts foram conferidos no que dá para
conferir fora de um Mac (sintaxe, patches aplicando, cache cifrado, ícone, Info.plist); a parte de
Xcode só se prova rodando.

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

1. Instale pelo TestFlight e abra uma vez. Aparece a tela de espera.
2. No PC, crie uma pasta `game` e copie para dentro dela, de `steamapps\common\Half-Life 2`:
   `bin`, `platform`, `hl2`, `episodic`, `ep2`, `lostcoast` e `hl2_complete` (uns 10 GB).
3. Leve a pasta `game` para o iPhone: app Arquivos › No Meu iPhone › Half-Life 2. Pelo cabo, o app
   Dispositivos Apple do Windows mostra essa mesma pasta na aba Arquivos.
4. Ligue Ajustes › Apps › Half-Life 2 › Log. O registro fica em `game.log`, na mesma pasta.
5. Abra o app. Com as sete pastas no lugar e a cópia terminada, toque em Iniciar.

Os episódios e o Lost Coast abrem pelo menu do jogo. Os saves ficam em `hl2-userdata`.

## Quando travar

É esperado, mais nos episódios: o tradutor não acha sozinho toda função chamada por ponteiro, e a
ferramenta que acha essas funções roda o jogo num Mac. O runtime para e escreve no `game.log` uma
linha com "target not recompiled" e o endereço.

1. Me mande o `game.log` (Arquivos › Half-Life 2).
2. O endereço vira uma linha em `raizes/hl2-extras.json`, no formato do `config/hl2-roots.json`
   do source-recomp (por exemplo `"client.so:code:0x5a0935"`).
3. Push, build nova, TestFlight. A tradução é refeita; os objetos que não mudaram vêm do cache.

## Riscos conhecidos desta etapa

- **Nunca rodou.** A primeira build pode parar em algum passo que só um Mac mostra.
- **Memória do runner (7 GB)** na tradução e na ligação de um executável deste tamanho.
- **Limite de 500 MB de código** do App Store Connect.
- **`prep` e `linux` dentro do app** não é como o projeto roda. A pasta do app é só de leitura; se
  o jogo tentar gravar ali, o conserto é copiar essas pastas para Documents no primeiro uso.
- **Arquivos ELF e DLL dentro do app** (o depot): não conheço regra do envio contra eles, mas é a
  primeira vez que passam por ele.
- **Tela de espera** escrita sem compilar. Se ela falhar ao compilar, só esse arquivo é refeito na
  build seguinte.
- **iPhone 17:** o projeto só foi testado num iPhone 15 Pro Max.

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
