# Desenvolvimento e build

## Estrutura

```text
/
├── win.ps1                         # Script monolítico gerado para execução via irm | iex
├── build.ps1                       # Empacota src/ + config/ em win.ps1 e gera docs/tweaks.md
├── config/                         # Catálogos JSON (apps, win-tweaks, game-profiles, presets)
├── src/windows/                    # Código-fonte modular
│   ├── core/                       # Logger, backup/state, verificação de estado
│   ├── modules/                    # Tweaks, jogos, Winget, hardware, rede, manutenção, startup e benchmark
│   ├── ui/                         # Tema XAML e construção da interface WPF
│   └── main.ps1                    # Entrada, CLI, orquestração e modo desatendido
├── docs/                           # Documentação
├── tests/                          # Testes Pester
└── .github/workflows/ci-build.yml  # CI de build, testes e ShellCheck
```

## Fluxo de alteração

1. Edite os catálogos em `config/` ou o código em `src/windows/`.
2. Recompile o script e a documentação técnica.
3. Rode o analisador estático e a suíte Pester.
4. Valide a interface ou o modo desatendido afetado.

```powershell
.\build.ps1 -Docs
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests -Output Detailed
```

## Build

`build.ps1`:

- Valida e empacota os arquivos de `src/` e `config/`.
- Injeta os catálogos e o logo no `win.ps1`.
- Gera `docs/tweaks.md` a partir de `config/win-tweaks.json`, `config/game-profiles.json` e `config/apps.json`.
- Mantém o script final executável via `irm | iex`.

Não edite `win.ps1` manualmente: alterações são sobrescritas pelo build.

## Testes e CI

- Pester 5+ em Windows PowerShell 5.1.
- Cobertura de configuração, build, backup, undo, tweaks, jogos, Winget, benchmark, automação, Appx, whitelist e smoke.
- `Invoke-ScriptAnalyzer` com as regras do repositório.
- CI no GitHub Actions: job Windows (build + Pester) e job Linux condicional de ShellCheck.

## Adicionando um tweak

1. Adicione a definição em `config/win-tweaks.json` com `title`, `category`, `impact`, `riskLevel`, `rationale` e demais campos exigidos.
2. Inclua a ação de Apply/Undo em `src/windows/modules/tweak-engine.ps1` quando o tipo não for coberto pelo motor existente.
3. Adicione ou ajuste o preset em `config/presets.json`, se aplicável.
4. Rode `.\build.ps1 -Docs` e os testes.
5. Atualize [tweaks.md](tweaks.md) via build e, se necessário, [rejected.md](rejected.md).

## Adicionando um aplicativo

1. Adicione a entrada em `config/apps.json` com o ID do Winget e a categoria.
2. Rode o build para regenerar [tweaks.md](tweaks.md).
3. Rode os testes de configuração.
