# ZeroServer Control

A native macOS menu bar app for controlling [ZeroServer Community Cloud](https://zeroserver.cc) provider nodes — this Mac's own agent and every node on your account, remotely.

**🇺🇸 [English](#english)** · **🇧🇷 [Português](#português)**

---

## English

### What it does

ZeroServer Control lives in your Mac's menu bar and gives you two things, without ever opening a terminal or a dashboard tab:

- **This Mac's own `zsc-agent`** — start, stop, and check the status of the local provider-node LaunchDaemon, straight from a menu.
- **Every node on your account, remotely** — see all your nodes' live status (online/idle/busy/overloaded/offline), pause or resume the ones that are online, force-stop any of them, and glance at live CPU/RAM/Disk usage per node — right where you'd check the time.

### Why it exists

Running a ZeroServer Community Cloud provider node today means either watching a terminal window or checking a web dashboard to know whether your machine — or any other node on your account — is healthy, busy, or needs attention. ZeroServer Control puts that one click away, using the same account-wide GraphQL API a web dashboard would, but as a lightweight, always-available system-tray-style utility instead of a browser tab you have to remember to keep open.

### Requirements

- macOS 13 (Ventura) or later — that's the minimum for SwiftUI's `MenuBarExtra`, which this whole app is built on.
- Xcode Command Line Tools. **Full Xcode is not required** — this is a plain Swift Package Manager executable, not an `.xcodeproj`. (You *can* still open `Package.swift` directly in Xcode later if you want the full IDE experience.)

### Build & run

```sh
swift build              # debug build — fastest way to catch compile errors
swift run                 # runs directly (shows a Dock icon; that's expected — an
                              # unbundled binary has no Info.plist to hide it)
swift build -c release   # release build
Scripts/build-app-bundle.sh   # assembles the real, double-clickable
                                       # dist/"ZeroServer Control.app" (Info.plist,
                                       # icon, ad-hoc code signature — no Developer
                                       # ID needed)
Scripts/run-tests.sh          # runs the test suite (see Testing below)
```

First launch of the packaged `.app` needs a right-click → Open once, since it's ad-hoc signed rather than notarized through the App Store or a paid Developer ID.

### Connecting to production

By default — with no configuration at all — the app talks to production, `https://api.zeroserver.cc`. Just build and run it, then sign in with your real ZeroServer account from the menu.

Your credentials are never written to disk in plaintext. Only a refresh token is persisted, and it goes straight into the macOS Keychain, scoped to this app specifically — nothing else on your Mac can read it, and it's never logged or transmitted anywhere except back to ZeroServer's own API to refresh your session.

### Local development setup

To point the app at a local `zsc-backend` dev stack instead of production:

```sh
ZSC_CONTROL_API_BASE_URL=http://localhost:3001 swift run
```

You'll need `zsc-backend` running locally (with its own Postgres/RabbitMQ dev stack) and a dev account to sign in with — see that repo's own README/seed data for how to get one; nothing here duplicates real or fixture credentials.

**Testing the local-agent controls without a real `zsc-agent` install**: `Scripts/devtest-daemon-install.sh` (needs `sudo`) installs a harmless throwaway LaunchDaemon (`cc.zeroserver.control-devtest`, just a `sleep` loop) so you can exercise the exact same start/stop/status code path as the real agent, without needing Docker or a real provider-node install:

```sh
sudo Scripts/devtest-daemon-install.sh
ZSC_CONTROL_DEV_LABEL=cc.zeroserver.control-devtest swift run
# ... test Start/Stop/status in the running app's Settings window ...
sudo Scripts/devtest-daemon-uninstall.sh
```

Never confuse `cc.zeroserver.control-devtest` with the real agent's label (`cc.zeroserver.agent`) — `ZSC_CONTROL_DEV_LABEL` is only ever meant to be set manually on the command line; the packaged `.app` never sets it, so a normal launch always controls your real, actual agent.

### Folder structure

```
zsc-osx-app/
├── .github/workflows/ci.yml         # build + tests + secrets/localization guards on every push/PR
├── Package.swift                    # SPM manifest (macOS 13+, one executable target)
├── Packaging/
│   └── Info.plist                   # template (__VERSION__/__BUILD__ filled in at build time)
├── BrandAssets/                      # packaging-time only, never read by the running app
│   ├── RawIcons/                    # source brand PNGs (green background, black glyph)
│   ├── AppIcon.iconset/             # generated working files (gitignored)
│   └── AppIcon.icns                 # generated full-color app icon
├── Scripts/
│   ├── build-app-bundle.sh          # assembles dist/"ZeroServer Control.app"
│   ├── generate-icons.sh            # regenerates every derived icon asset
│   ├── run-tests.sh                 # compiles & runs the test suite
│   ├── check-localization-parity.sh # fails if en/pt-BR Localizable.strings keys drift
│   ├── devtest-daemon*              # throwaway LaunchDaemon fixture (see above)
│   └── tests/                       # hand-rolled test drivers run-tests.sh compiles
├── Sources/ZeroServerControl/
│   ├── ZeroServerControlApp.swift   # @main entry point — the MenuBarExtra + windows
│   ├── Account/                     # sign-in session, GraphQL/API clients, Keychain storage
│   ├── Remote/                      # polls and controls every node on the account
│   ├── Model/                       # RemoteNode, AgentStatus, and their decoding/business logic
│   ├── Controller/                  # this Mac's own agent, controlled via launchctl
│   ├── Login/                       # "Launch at Login" toggle (SMAppService)
│   ├── UI/                          # the menu, the Settings window, the sign-in window
│   └── Resources/                   # menu bar icons, login logo, localization (en/pt-BR)
└── .gitignore
```

### Testing

There's deliberately no `.testTarget` in `Package.swift`. On a machine with only the Xcode Command Line Tools installed (no full Xcode.app), neither `XCTest.framework` nor a working `swift-testing` setup is available — and baking machine-specific absolute paths into the manifest to force one to work would break portability to any other machine or CI runner.

Instead, `Scripts/run-tests.sh` compiles the real production source files under `Sources/ZeroServerControl/{Account,Remote,Model}/` directly together with hand-rolled test drivers in `Scripts/tests/`, using plain `swiftc` — one executable, no test framework dependency at all — and runs the result. It's a real regression gate (exits non-zero on any failure), not just a manual smoke check.

This deliberately excludes `Sources/ZeroServerControl/{UI,Controller,Login}/` and the app entry point, since those need SwiftUI/AppKit/`MenuBarExtra` and can only meaningfully be exercised by actually running the app. If you install full Xcode.app, a proper `.testTarget` becomes straightforward to add.

### Contributing

1. Fork the repo (or branch directly, if you have write access) and create a branch named `feat/short-description` or `fix/short-description`.
2. Write commits as `type(scope): summary` — e.g. `fix(control): stop node list reshuffling on every poll`. `type` is one of `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
3. Run `Scripts/run-tests.sh` before opening a PR — it must pass.
4. UI-layer changes (`Sources/ZeroServerControl/{UI,Controller,Login}/`) have no automated coverage, so describe what you tested manually in the PR (a screenshot or short clip helps a lot for anything visual).
5. Open a PR against `main` with a clear description of the *why*, not just the *what* — the diff already shows what changed.
6. CI (`.github/workflows/ci.yml`) runs `swift build`, `Scripts/run-tests.sh`, and two guards — a secrets/`CLAUDE.md` check and an en/pt-BR `Localizable.strings` key-parity check — on every push and PR against `main`. All of it must be green before merging.

### Security

- Never commit `.env` files, API tokens, machine tokens, or any real Keychain export.

### License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## Português

### O que o aplicativo faz

O ZeroServer Control vive na barra de menus do seu Mac e oferece duas coisas, sem nunca precisar abrir um terminal ou uma aba de dashboard:

- **O próprio `zsc-agent` deste Mac** — inicie, pare e veja o status do LaunchDaemon do node provedor local, direto do menu.
- **Todos os nodes da sua conta, remotamente** — veja o status em tempo real de todos os seus nodes (online/idle/busy/overloaded/offline), pause ou retome os que estiverem online, force a parada de qualquer um deles, e acompanhe o uso de CPU/RAM/Disco em tempo real por node — no mesmo lugar onde você olharia a hora.

### Por que ele existe

Hoje, operar um node provedor no ZeroServer Community Cloud significa ficar de olho em uma janela de terminal ou verificar um dashboard web para saber se sua máquina — ou qualquer outro node da sua conta — está saudável, ocupada, ou precisando de atenção. O ZeroServer Control coloca isso a um clique de distância, usando a mesma API GraphQL, disponível para toda a conta, que um dashboard web usaria — mas como um utilitário leve e sempre disponível na barra de menus, em vez de uma aba do navegador que você precisa lembrar de manter aberta.

### Requisitos

- macOS 13 (Ventura) ou mais recente — esse é o mínimo exigido pelo `MenuBarExtra` do SwiftUI, sobre o qual todo o app é construído.
- Xcode Command Line Tools. **O Xcode completo não é necessário** — este é um executável puro do Swift Package Manager, não um `.xcodeproj`. (Você *pode* abrir o `Package.swift` diretamente no Xcode depois, se quiser a experiência completa de IDE.)

### Build e execução

```sh
swift build              # build de debug — forma mais rápida de detectar erros de compilação
swift run                 # executa diretamente (mostra um ícone no Dock; isso é esperado —
                              # um binário fora do bundle não tem Info.plist para escondê-lo)
swift build -c release   # build de release
Scripts/build-app-bundle.sh   # monta o app real, clicável, em
                                       # dist/"ZeroServer Control.app" (Info.plist,
                                       # ícone, assinatura ad-hoc — sem precisar de
                                       # Developer ID)
Scripts/run-tests.sh          # executa a suíte de testes (veja Testes abaixo)
```

O primeiro lançamento do `.app` empacotado precisa de um clique com o botão direito → Abrir uma vez, já que ele é assinado ad-hoc em vez de notarizado pela App Store ou por um Developer ID pago.

### Conectando à produção

Por padrão — sem nenhuma configuração — o app se conecta à produção, `https://api.zeroserver.cc`. Basta compilar e executar, e então entrar com sua conta real do ZeroServer pelo menu.

Suas credenciais nunca são gravadas em disco em texto puro. Apenas um refresh token é persistido, e ele vai direto para o Keychain do macOS, vinculado especificamente a este app — nenhum outro programa no seu Mac consegue lê-lo, e ele nunca é registrado em log nem transmitido a lugar nenhum além da própria API do ZeroServer, para renovar sua sessão.

### Configuração de desenvolvimento local

Para apontar o app para uma stack local do `zsc-backend` em vez da produção:

```sh
ZSC_CONTROL_API_BASE_URL=http://localhost:3001 swift run
```

Você vai precisar do `zsc-backend` rodando localmente (com sua própria stack de desenvolvimento Postgres/RabbitMQ) e de uma conta de desenvolvimento para entrar — veja o README/seed data daquele repositório para conseguir uma; nada aqui duplica credenciais reais ou fictícias.

**Testando os controles do agente local sem uma instalação real do `zsc-agent`**: o `Scripts/devtest-daemon-install.sh` (precisa de `sudo`) instala um LaunchDaemon descartável e inofensivo (`cc.zeroserver.control-devtest`, apenas um loop de `sleep`) para você exercitar exatamente o mesmo caminho de código de start/stop/status do agente real, sem precisar de Docker ou de uma instalação real de node provedor:

```sh
sudo Scripts/devtest-daemon-install.sh
ZSC_CONTROL_DEV_LABEL=cc.zeroserver.control-devtest swift run
# ... teste Start/Stop/status na janela de Configurações do app em execução ...
sudo Scripts/devtest-daemon-uninstall.sh
```

Nunca confunda `cc.zeroserver.control-devtest` com o label do agente real (`cc.zeroserver.agent`) — a variável `ZSC_CONTROL_DEV_LABEL` deve ser usada apenas manualmente, na linha de comando; o `.app` empacotado nunca a define, então uma execução normal sempre controla seu agente real.

### Estrutura de pastas

```
zsc-osx-app/
├── .github/workflows/ci.yml         # build + testes + verificações de segredos/localização em todo push/PR
├── Package.swift                    # manifesto do SPM (macOS 13+, um executable target)
├── Packaging/
│   └── Info.plist                   # template (__VERSION__/__BUILD__ preenchidos no build)
├── BrandAssets/                      # usado só no empacotamento, nunca lido pelo app em execução
│   ├── RawIcons/                    # PNGs de origem da marca (fundo verde, glifo preto)
│   ├── AppIcon.iconset/             # arquivos de trabalho gerados (no .gitignore)
│   └── AppIcon.icns                 # ícone do app gerado, em cores
├── Scripts/
│   ├── build-app-bundle.sh          # monta o dist/"ZeroServer Control.app"
│   ├── generate-icons.sh            # regenera todos os ícones derivados
│   ├── run-tests.sh                 # compila e executa a suíte de testes
│   ├── check-localization-parity.sh # falha se as chaves do en/pt-BR Localizable.strings divergirem
│   ├── devtest-daemon*              # fixture de LaunchDaemon descartável (veja acima)
│   └── tests/                       # drivers de teste que o run-tests.sh compila
├── Sources/ZeroServerControl/
│   ├── ZeroServerControlApp.swift   # ponto de entrada @main — o MenuBarExtra e as janelas
│   ├── Account/                     # sessão de login, clientes GraphQL/API, Keychain
│   ├── Remote/                      # consulta e controla todos os nodes da conta
│   ├── Model/                       # RemoteNode, AgentStatus, e sua lógica de decodificação
│   ├── Controller/                  # o próprio agente deste Mac, controlado via launchctl
│   ├── Login/                       # o toggle de "Abrir no Login" (SMAppService)
│   ├── UI/                          # o menu, a janela de Configurações, a janela de login
│   └── Resources/                   # ícones da barra de menus, logo de login, localização (en/pt-BR)
└── .gitignore
```

### Testes

Propositalmente, não há `.testTarget` no `Package.swift`. Em uma máquina com apenas as Xcode Command Line Tools instaladas (sem o Xcode completo), nem o `XCTest.framework` nem uma configuração funcional do `swift-testing` estão disponíveis — e embutir caminhos absolutos específicos de uma máquina no manifesto, só para forçar isso a funcionar, quebraria a portabilidade para qualquer outra máquina ou executor de CI.

Em vez disso, o `Scripts/run-tests.sh` compila os arquivos de código de produção reais em `Sources/ZeroServerControl/{Account,Remote,Model}/` diretamente junto com drivers de teste escritos à mão em `Scripts/tests/`, usando `swiftc` puro — um único executável, sem nenhuma dependência de framework de testes — e executa o resultado. É um gate de regressão real (termina com código diferente de zero em qualquer falha), não apenas uma verificação manual.

Isso exclui propositalmente `Sources/ZeroServerControl/{UI,Controller,Login}/` e o ponto de entrada do app, já que esses precisam de SwiftUI/AppKit/`MenuBarExtra` e só podem ser verificados de forma significativa executando o app de fato. Se você instalar o Xcode completo, adicionar um `.testTarget` de verdade se torna simples.

### Como contribuir

1. Faça um fork do repositório (ou crie uma branch diretamente, se tiver acesso de escrita) com o nome `feat/descricao-curta` ou `fix/descricao-curta`.
2. Escreva os commits como `type(scope): resumo` — por exemplo, `fix(control): stop node list reshuffling on every poll`. `type` é um de `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
3. Execute `Scripts/run-tests.sh` antes de abrir um PR — ele precisa passar.
4. Mudanças na camada de UI (`Sources/ZeroServerControl/{UI,Controller,Login}/`) não têm cobertura automatizada, então descreva no PR o que você testou manualmente (uma captura de tela ou um vídeo curto ajuda bastante em qualquer coisa visual).
5. Abra um PR contra a `main` com uma descrição clara do *porquê*, não só do *o quê* — o diff já mostra o que mudou.
6. O CI (`.github/workflows/ci.yml`) executa `swift build`, `Scripts/run-tests.sh`, e duas verificações de segurança — checagem de segredos/`CLAUDE.md` e paridade de chaves entre `Localizable.strings` en/pt-BR — em todo push e PR contra a `main`. Tudo precisa estar verde antes de fazer merge.

### Segurança

- Nunca faça commit de arquivos `.env`, tokens de API, tokens de máquina, ou qualquer exportação real do Keychain.

### Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.
