# OptiKit

[![CI Build & Verify](https://img.shields.io/github/actions/workflow/status/seiti-kg/OptiKit/ci-build.yml?branch=main&label=CI%20Build&style=flat-square)](https://github.com/seiti-kg/OptiKit/actions)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-00E5FF.svg?style=flat-square)](LICENSE)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?style=flat-square&logo=powershell)](win.ps1)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat-square&logo=windows)](win.ps1)

Utilitário open-source de pós-formatação, debloat e otimização de sistema e jogos para Windows 10/11. Construído com foco em ajustes reais (zero efeito placebo), reversibilidade completa e compatibilidade com anti-cheats de nível de kernel.

<!-- Screenshot da interface (descomente quando adicionar a imagem):
![Interface do OptiKit](docs/screenshot.png)
-->

## Uso Rápido

Execute no PowerShell (como Administrador):

```powershell
irm https://raw.githubusercontent.com/seiti-kg/OptiKit/main/win.ps1 | iex
```

Para executar localmente em modo de simulação (sem alterar o sistema):

```powershell
powershell -ExecutionPolicy Bypass -File .\win.ps1 -DryRun
```

## Funcionalidades

- **Instalação de Pacotes (Winget):** Catálogo com mais de 40 softwares essenciais (navegadores, launchers, utilitários, runtimes C++/DirectX e ferramentas de desenvolvimento), incluindo bootstrap automático do Winget em instalações recém-formatadas.
- **Desempenho e Energia:** Desativação de Xbox Game DVR, Mouse 1:1 (sem aceleração de ponteiro), gerenciamento inteligente de planos de energia (detecção de Desktop, Notebook e CPUs AMD Ryzen X3D), ativação de HAGS/Game Mode, otimização de portas USB (1000Hz–8000Hz) e controle de Hibernação/Fast Startup.
- **Privacidade e Debloat:** Redução de telemetria e serviços de diagnóstico (`DiagTrack`), bloqueio do Windows Recall e Copilot, restauração do menu de contexto clássico no Windows 11, desativação da busca web do Bing no Menu Iniciar e remoção seletiva de pacotes Appx (preservando Microsoft Store, Calculadora, Captura de Tela e serviços Xbox).
- **Perfis de Jogos:** Perfil dedicado para VALORANT (detecção automática de executável, flags FSO/High DPI, preferência de GPU dedicada no DirectX, desativação de economia de energia na placa de rede e controle de inicialização do Riot Client) e limpador global de Cache de Shaders (DirectX, NVIDIA e AMD).
- **Manutenção e Inicialização:** Reset de rede/DNS, execução de `DISM /RestoreHealth` + `SFC /scannow` em segundo plano, limpeza de temporários e gerenciador de programas de inicialização compatível com o Gerenciador de Tarefas (`StartupApproved`).

Consulte a lista técnica de todos os ajustes e justificativas em [`docs/tweaks.md`](docs/tweaks.md).

## Diretrizes Técnicas

- **Zero Placebo:** Todos os ajustes possuem classificação de impacto, nível de risco e justificativa técnica documentada nos arquivos JSON. Ajustes situacionais ficam desmarcados por padrão nos presets.
- **Reversibilidade (Undo Engine):** Antes de qualquer alteração, o estado original da máquina é salvo em `%ProgramData%\optikit\state.json`, as chaves de registro afetadas são exportadas (`.reg`) em `%ProgramData%\optikit\backups\` e um Ponto de Restauração é criado.
- **Segurança Anti-Cheat:** Bloqueio estático e em runtime contra modificações nos serviços `vgc`/`vgk.sys`, TPM 2.0, Secure Boot ou desativação global de VBS. Ajustes avançados como HVCI exigem confirmação manual explícita.
- **Orientado a Dados:** A interface WPF e os catálogos são gerados dinamicamente a partir dos arquivos em `config/`.

## Estrutura do Projeto

```text
/
├── win.ps1                         # Script monolítico compilado para execução via irm | iex
├── build.ps1                       # Compilador que empacota src/ + config/ em win.ps1 e gera docs/tweaks.md
├── config/                         # Catálogos JSON (apps, win-tweaks, game-profiles, presets)
├── src/windows/                    # Código-fonte modular (core, modules, ui, main.ps1)
├── docs/tweaks.md                  # Catálogo técnico gerado automaticamente
└── tests/                          # Testes automatizados (Pester 5)
```

## Desenvolvimento e Build

Após editar arquivos em `config/` ou `src/windows/`, recompile o script principal e rode a suíte de testes:

```powershell
.\build.ps1 -Docs
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests -Output Detailed
```

## Licença

Distribuído sob a licença [Apache 2.0](LICENSE).
