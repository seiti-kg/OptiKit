<p align="center">
  <img src="assets/optikit_logo.jpg" alt="OptiKit" width="360">
</p>

<h1 align="center">OptiKit</h1>

<p align="center">
  <em>pós-formatação, debloat e otimização de sistema e jogos para Windows 10/11</em>
</p>

<p align="center">
  <a href="VERSION"><img src="https://img.shields.io/badge/version-0.3.0-blue" alt="version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-green" alt="license"></a>
  <a href="win.ps1"><img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE" alt="PowerShell"></a>
  <a href="win.ps1"><img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6" alt="Windows"></a>
  <a href="https://github.com/seiti-kg/OptiKit/actions"><img src="https://img.shields.io/github/actions/workflow/status/seiti-kg/OptiKit/ci-build.yml?branch=main&label=CI" alt="CI"></a>
</p>

<p align="center">
  aplica <strong>tweaks reversíveis</strong>, remove bloatware e ajusta energia, rede e jogos<br>
  interface WPF nativa. modo desatendido para pós-formatação.
</p>

Utilitário open-source de pós-formatação, debloat e otimização de sistema e jogos para Windows 10/11. Construído com foco em ajustes reais (zero efeito placebo), reversão via `state.json`/Undo (com limitações documentadas para pacotes Appx) e compatibilidade com anti-cheats de nível de kernel.

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

### Modo desatendido (pós-formatação)

```powershell
# Aplica um preset sem abrir a interface
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/seiti-kg/OptiKit/main/win.ps1))) -Preset GamerRecomendado -Apply -Silent

# Importa um perfil exportado em outro PC
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/seiti-kg/OptiKit/main/win.ps1))) -Config .\optikit-profile.json -Apply -Silent
```

O modo desatendido exige Administrador (UAC) e retorna `0` em sucesso, `1` em falhas parciais e `2` em erro de uso ou perfil inválido. Sem `-Apply`, ele apenas imprime o que seria aplicado.

## Funcionalidades

- **Instalação de Pacotes (Winget):** Catálogo com mais de 40 softwares essenciais (navegadores, launchers, utilitários, runtimes C++/DirectX e ferramentas de desenvolvimento), incluindo bootstrap automático do Winget em instalações recém-formatadas.
- **Desempenho e Energia:** Desativação de Xbox Game DVR, Mouse 1:1 (sem aceleração de ponteiro), gerenciamento inteligente de planos de energia (detecção de Desktop, Notebook e CPUs AMD Ryzen X3D), ativação de HAGS/Game Mode, otimização de portas USB (1000Hz–8000Hz) e controle de Hibernação/Fast Startup.
- **Privacidade e Debloat:** Redução de telemetria e serviços de diagnóstico (`DiagTrack`), bloqueio do Windows Recall e Copilot, restauração do menu de contexto clássico no Windows 11, desativação da busca web do Bing no Menu Iniciar e remoção seletiva de pacotes Appx (preservando Microsoft Store, Calculadora, Captura de Tela e serviços Xbox).
- **Diagnóstico de Hardware (somente leitura):** Detecta RAM sem XMP/EXPO, monitor abaixo da taxa máxima, VBS/HVCI ativo, HAGS/Game Mode/plano de energia, ausência do driver `amd3dvcache` em Ryzen X3D dual-CCD e drivers de GPU com mais de 180 dias. Inclui BIOS/firmware (Secure Boot, TPM, modelo/versão), saúde/desgaste dos discos, espaço livre, erros WHEA/Kernel-Power, reinicialização pendente e estado do Microsoft Defender, com ação recomendada por card.
- **Perfis de Jogos:** Perfis ativos para VALORANT, Counter-Strike 2 e jogos Unreal Engine 5/AAA (detecção de executável, flags FSO/High DPI, preferência de GPU dedicada no DirectX, desativação de economia de energia na placa de rede e limpeza de Cache de Shaders DirectX/NVIDIA/AMD).
- **Windows Update:** Bloqueio de drivers automáticos, fixação da versão atual do Windows (feature updates) e desativação do Armazenamento Reservado, com Undo pelo `state.json`.
- **Rede e Atualizações:** DNS over HTTPS nativo no Windows 11 (Cloudflare, Google, Quad9 e AdGuard, IPv4/IPv6) com captura do DNS original para Undo; reset de pilha de rede e atualização de aplicativos via Winget (`upgrade --all`).
- **Limpeza Avançada:** Remoção do cache do Windows Update, Delivery Optimization, lixeira, prefetch e Component Store via `DISM /StartComponentCleanup`, com contabilização de espaço liberado.
- **Automação e Reversão:** Modo desatendido (`-Preset`/`-Config -Apply -Silent`), exportação/importação de perfil de seleção, **Reverter Tudo** a partir do estado capturado, relatório HTML da sessão e aviso de nova versão.
- **Manutenção e Inicialização:** Reset de rede/DNS, execução de `DISM /RestoreHealth` + `SFC /scannow` em segundo plano, limpeza de temporários, reinício para a BIOS/UEFI na próxima inicialização e gerenciador de programas de inicialização compatível com o Gerenciador de Tarefas (`StartupApproved`).

Consulte a lista técnica de todos os ajustes e justificativas em [`docs/tweaks.md`](docs/tweaks.md).

## Diretrizes Técnicas

- **Zero Placebo:** Todos os ajustes possuem classificação de impacto, nível de risco e justificativa técnica documentada nos arquivos JSON. Ajustes situacionais ficam desmarcados por padrão nos presets.
- **Reversibilidade (Undo Engine):** Antes de qualquer alteração, o estado original da máquina é salvo em `%ProgramData%\optikit\state.json`, as chaves de registro afetadas são exportadas (`.reg`) em `%ProgramData%\optikit\backups\` e um Ponto de Restauração é criado.
- **Suporte a Windows:** Windows 11 é o alvo principal; Windows 10 22H2 é suportado em melhor esforço. Ajustes exclusivos de Windows 11 são ocultados na interface e ignorados automaticamente no modo desatendido quando o sistema não atende aos requisitos.
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
├── docs/rejected.md                # Tweaks placebo rejeitados e critérios de admissão
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
