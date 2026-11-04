# ⚡ OptiKit — Multi-OS System & Gaming Optimizer

[![CI Build & Verify](https://img.shields.io/github/actions/workflow/status/SEU_USUARIO/optikit/ci-build.yml?branch=main&label=CI%20Build&style=flat-square)](https://github.com/SEU_USUARIO/optikit/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-00E5FF.svg?style=flat-square)](LICENSE)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?style=flat-square&logo=powershell)](win.ps1)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat-square&logo=windows)](win.ps1)

Utilitário open-source, modular, transparente e **100% reversível** de pós-formatação, debloat e otimização de sistema e jogos para **Windows (10/11)** (e em breve Linux), executável com uma única linha de comando no terminal.

---

## 🚀 Execução Rápida (One-Liner)

Abra o **PowerShell como Administrador** e execute:

```powershell
irm https://raw.githubusercontent.com/SEU_USUARIO/optikit/main/win.ps1 | iex
```

### Execução Local / Modo de Simulação (`-DryRun`)

Se você clonou o repositório e deseja inspecionar a interface gráfica e simular as operações no console **sem alterar nenhuma chave do sistema**:

```powershell
powershell -ExecutionPolicy Bypass -File .\win.ps1 -DryRun
```

Também é possível pré-selecionar um preset ao abrir:

```powershell
powershell -ExecutionPolicy Bypass -File .\win.ps1 -Preset GamerRecomendado
```

---

## 🎯 Filosofia do Projeto ("Anti-Placebo")

1. **Zero Efeito Placebo:** Todo ajuste em [`config/win-tweaks.json`](config/win-tweaks.json) e [`config/game-profiles.json`](config/game-profiles.json) possui classificação honesta de **Impacto** (`Alto`, `Médio`, `Baixo`, `Situacional`), **Nível de Risco** (`Safe`, `Moderate`, `Advanced`) e **Justificativa Técnica (`rationale`)** documentada. Ajustes situacionais ou de ganho marginal ficam sempre **desmarcados por padrão** em todos os presets.
2. **Reversibilidade Total (Híbrido `state.json` + Fallback):** Antes de aplicar qualquer ajuste, o motor de backup captura o valor real presente na máquina em `%ProgramData%\optikit\state.json` (seguindo a regra *first-capture-wins* para preservar o valor original mesmo se aplicado várias vezes), exporta as chaves `.reg` em `%ProgramData%\optikit\backups\<sessão>\` e cria um Ponto de Restauração do Sistema. Ao clicar em **Reverter Selecionados (Undo)**, o valor original capturado é restaurado (ou o padrão de fábrica do Windows caso não haja captura prévia).
3. **Compatibilidade com Anti-Cheats Kernel-Level (Riot Vanguard / FACEIT / EAC):** Guardrails estáticos (validados em CI) e em tempo de execução proíbem qualquer alteração nos serviços `vgc` / `vgk.sys`, TPM 2.0, Secure Boot ou desativação global do VBS. O único ajuste avançado que toca em virtualização (`WPFTweaksDisableHVCI`) exige confirmação explícita em diálogo modal alertando sobre requisitos do Riot Vanguard no Windows 11.
4. **Arquitetura 100% Orientada a Dados (Data-Driven):** A interface gráfica WPF em modo escuro (`#121212` / `#1E1E1E` / `#00E5FF` / `#FF4655`) é gerada dinamicamente a partir dos catálogos em [`config/`](config/).

---

## 📦 Funcionalidades Principais (Windows 10 & 11)

- **📦 Instalador Pós-Formatação (Winget):** Mais de 40 aplicativos essenciais categorizados em *Navegadores*, *Comunicação*, *Jogos & Launchers*, *Runtimes & Utilitários* e *Desenvolvimento*, com detecção e bootstrap automático do Microsoft App Installer caso o Winget esteja ausente em instalações recém-formatadas.
- **⚡ Otimizações, Energia & Debloat:**
  - **Desempenho & Energia:** Desativação do Xbox Game DVR, Mouse 1:1 (sem curva de aceleração EPP), **Gerenciamento de Energia Inteligente** (detecta Desktop vs Notebook e recomenda/aplica o plano *Equilibrado* em CPUs **AMD Ryzen X3D** para o funcionamento correto do Core Parking 3D V-Cache), otimização de portas USB (1000Hz a 8000Hz), HAGS, Game Mode, desativação de Hibernação e Fast Startup.
  - **Privacidade & Telemetria:** Redução de telemetria e serviços `DiagTrack`/`dmwappushservice`, desativação do **Windows Recall (IA)** no Windows 11, bloqueio de Advertising ID, Histórico de Atividades e tarefas CEIP/Compatibility Appraiser (`CompatTelRunner.exe`).
  - **Interface & Windows 11:** Restauração do Menu de Contexto Clássico no Windows 11, remoção da busca web do Bing no Menu Iniciar, desativação de Widgets (`WindowsWebExperiencePack`), Copilot, sugestões comerciais e atalho das Teclas de Aderência (5x Shift).
  - **Remoção Seletiva de Bloatware (Appx):** Remove pacotes pré-instalados para todos os usuários e do provisionamento (com Undo via reinstalação pelo `storeId` na Microsoft Store), preservando pacotes críticos (Microsoft Store, Calculadora, Captura de Tela e Xbox Identity Provider). Inclui desinstalação segura do OneDrive com trava contra perda de pastas redirecionadas (*Known Folder Move*).
- **🎮 Perfis de Jogos (Game Optimizer):**
  - **VALORANT:** Detecção automática do `VALORANT-Win64-Shipping.exe` (via caminhos padrão, registro e `RiotClientInstalls.json`), preferência de GPU dedicada no DirectX (`GpuPreference=2`), flags FSO/High DPI, desativação de economia de energia Ethernet (EEE/Green Ethernet) e desativação da inicialização automática do Riot Client (preservando o Vanguard).
  - **Ferramentas Globais:** Limpador seguro de Cache de Shaders (`D3DSCache`, `NVIDIA DXCache/GLCache`, `AMD DxCache/DxcCache`), otimizador de NIC e portas USB.
- **🛠️ Manutenção, Reparo & Inicialização:**
  - Reset completo de Rede e DNS (`flushdns`, `winsock reset`, `int ip reset`).
  - Execução assistida de `DISM /RestoreHealth` + `SFC /scannow` em segundo plano com transmissão ao console e botão de cancelamento.
  - Limpador de arquivos temporários (`%TEMP%` e `C:\Windows\Temp`).
  - **Gerenciador de Inicialização Nativo:** Lê e controla programas de inicialização usando a chave oficial `StartupApproved` do Gerenciador de Tarefas do Windows.

👉 Consulte o catálogo completo gerado automaticamente em **[`docs/tweaks.md`](docs/tweaks.md)**.

---

## 🗂️ Estrutura do Repositório

```text
/
├── README.md                       # Documentação principal
├── LICENSE                         # Licença MIT
├── VERSION                         # Versão semântica do projeto
├── win.ps1                         # Script monolítico final do Windows (gerado por build.ps1)
├── build.ps1                       # Compilador determinístico (src/ + config/ -> win.ps1 + docs/tweaks.md)
├── config/                         # Catálogos JSON (Single Source of Truth)
│   ├── apps.json                   # Catálogo multiplataforma de aplicativos
│   ├── win-tweaks.json             # Tweaks de sistema, privacidade, energia e Appx
│   ├── game-profiles.json          # Perfis de jogos (VALORANT + Ferramentas Globais)
│   └── presets.json                # Presets rápidos (Gamer Recomendado, Mínimo Seguro, VALORANT, Notebook)
├── src/windows/
│   ├── main.ps1                    # Inicializador, elevação UAC, STA e Worker Runspace
│   ├── ui/
│   │   ├── theme.xaml              # Layout WPF em modo escuro
│   │   └── ui-builder.ps1          # Construtor dinâmico de cards, filtros e badges
│   ├── core/
│   │   ├── logger.ps1              # Logs em tempo real e ponto único de mutação (Invoke-Mutation)
│   │   ├── backup.ps1              # Ponto de Restauração, reg export e state.json atômico
│   │   └── state-checker.ps1       # Verificador de ajustes aplicados na máquina
│   └── modules/
│       ├── hardware-utils.ps1      # Detecção de CPU/GPU/Chassi/X3D, energia e portas USB
│       ├── winget-engine.ps1       # Motor Winget + bootstrap oficial e remoção segura do OneDrive
│       ├── tweak-engine.ps1        # Executor Apply/Undo de Registro, Serviços, Tasks e Appx
│       ├── game-engine.ps1         # Otimizações de jogos, Shader Cache e NIC
│       ├── maintenance.ps1         # Reset de rede, SFC/DISM cancelável e limpeza de Temp
│       └── startup-manager.ps1     # Gerenciador de inicialização via StartupApproved
├── docs/
│   └── tweaks.md                   # Documentação gerada a partir dos JSONs
└── tests/                          # Suíte de testes automatizados (Pester 5)
```

---

## 🛠️ Como Contribuir e Compilar

1. Edite os catálogos em `config/*.json` ou os módulos em `src/windows/`.
2. Compile o `win.ps1` e atualize a documentação técnica:
   ```powershell
   .\build.ps1 -Docs
   ```
3. Execute o analisador estático e a suíte de testes Pester 5:
   ```powershell
   Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
   Invoke-Pester -Path .\tests -Output Detailed
   ```
