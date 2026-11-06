# Funcionalidades

> Estado da versão **0.3.0**. Para a lista técnica de cada ajuste, consulte [tweaks.md](tweaks.md).

## Números atuais

- **60 ajustes** de sistema e debloat, classificados por impacto, risco e compatibilidade de SO.
- **46 aplicativos** instaláveis via Winget, com bootstrap automático em instalações novas.
- **3 perfis de jogos** (VALORANT, Counter-Strike 2 e Unreal Engine 5/AAA) e **3 ferramentas globais** de jogos.
- **4 presets** prontos: `GamerRecomendado`, `MinimoSeguro`, `PerfilValorant` e `Notebook`.
- **6 abas** na interface: Instalar apps, Ajustes do Windows, Jogos, Diagnóstico, Inicialização e Manutenção.

## Interface

A interface WPF é gerada dinamicamente a partir dos catálogos JSON e inclui:

- Busca global por apps, ajustes e otimizações.
- Filtros de impacto, risco e estado; agrupamento por categoria.
- Badges de “Aplicado”, “Não aplicado” e “Bloqueado”.
- Aplicar e reverter itens selecionados.
- Reverter tudo a partir do `state.json`.
- Exportação de relatório HTML da sessão.
- Aviso de nova versão publicada no GitHub.
- Modo de simulação (`-DryRun`) sem alterar o sistema.

## Instalação de pacotes (Winget)

- Catálogo com 46 softwares: navegadores, launchers, utilitários, runtimes C++/DirectX e ferramentas de desenvolvimento.
- Instalação silenciosa via Winget, com detecção de pacote já instalado.
- Bootstrap automático do Winget em instalações recém-formatadas.
- Atualização de aplicativos com `winget upgrade --all`.

## Desempenho e energia

- Desativação do Xbox Game DVR e da gravação em segundo plano.
- Mouse 1:1, sem aceleração de ponteiro.
- Gerenciamento inteligente de plano de energia para Desktop, Notebook e CPUs AMD Ryzen X3D.
- HAGS situacional (recomendado para Frame Generation; pode custar ~1 GB de VRAM em 6/8 GB) e Game Mode.
- Otimização de portas USB para polling de 1000 Hz a 8000 Hz.
- Controle de Hibernação e Fast Startup.
- Ajustes de visual effects, atraso de inicialização e otimizações para jogos em janela (Flip Model DX10/11).

## Privacidade e debloat

- Redução de telemetria e do serviço de diagnóstico (`DiagTrack`).
- Desativação de ID de anúncio, histórico de atividades e tarefas de telemetria.
- Bloqueio do Windows Recall e do Copilot.
- Restauração do menu de contexto clássico no Windows 11.
- Desativação da busca web do Bing no Menu Iniciar.
- Remoção seletiva de pacotes Appx, preservando Store, Calculadora, Captura de Tela e serviços Xbox.
- Controle de widgets, sugestões do Menu Iniciar, tela de bloqueio e atalho das Teclas de Aderência.

## Diagnóstico de hardware (somente leitura)

- RAM sem XMP/EXPO.
- Monitor abaixo da taxa máxima.
- VBS/HVCI ativo.
- Estado de HAGS, Game Mode e plano de energia.
- Ausência do driver `amd3dvcache` em Ryzen X3D dual-CCD.
- Drivers de GPU com mais de 180 dias.
- BIOS/firmware: Secure Boot, TPM, modelo e versão.
- Saúde e desgaste dos discos, espaço livre.
- Erros WHEA/Kernel-Power e reinicialização pendente.
- Estado do Microsoft Defender.
- Ação recomendada por card.

## Perfis de jogos

- **VALORANT:** flags FSO/High DPI, preferência por GPU dedicada no DirectX, desativação de economia de energia na placa de rede (EEE) e limpeza de inicialização do Riot Client.
- **Counter-Strike 2:** preferência por GPU dedicada, flags FSO/High DPI e limpeza de cache de shaders.
- **Unreal Engine 5/AAA:** preferência por GPU dedicada, flags FSO/High DPI e limpeza de cache de shaders.
- **Ferramentas globais:** limpeza de cache DirectX/NVIDIA/AMD, otimização de NIC e de portas USB.
- Detecção de executável e seleção manual quando o jogo não é encontrado.

## Windows Update

- Bloqueio de drivers automáticos do Windows Update.
- Fixação da versão atual do Windows (feature updates) via `TargetReleaseVersion`.
- Desativação do Armazenamento Reservado.
- Undo pelo `state.json`.

## Rede e atualizações

- DNS over HTTPS nativo no Windows 11: Cloudflare, Google, Quad9 e AdGuard, IPv4 e IPv6.
- Captura do DNS original para Undo.
- Reset da pilha de rede e do DNS.
- Atualização de aplicativos via Winget (`upgrade --all`).

## Limpeza avançada

- Cache do Windows Update.
- Delivery Optimization.
- Lixeira.
- Prefetch.
- Component Store via `DISM /StartComponentCleanup`.
- Contabilização do espaço liberado.

## Manutenção e inicialização

- Reset de rede/DNS.
- `DISM /RestoreHealth` + `SFC /scannow` em segundo plano, com cancelamento.
- Reparo do app de Configurações do Windows (`windows.immersivecontrolpanel`) e da dependência `Microsoft.UI.Xaml.CBS`.
- Limpeza de arquivos temporários.
- Reinício para a BIOS/UEFI na próxima inicialização.
- Gerenciador de programas de inicialização compatível com o Gerenciador de Tarefas (`StartupApproved`).

## Automação e reversão

- Modo desatendido com `-Preset` ou `-Config -Apply -Silent`.
- Exportação e importação de perfil de seleção.
- Reverter tudo a partir do estado capturado.
- Relatório HTML da sessão.
- Aviso de nova versão.
- Saída com códigos `0` (sucesso), `1` (falhas parciais) e `2` (uso/perfil inválido).

## Limitações conhecidas

- **Appx:** a reversão reinstala o pacote via Store ID do Winget. O pacote precisa estar disponível na Store, e os dados locais do aplicativo podem não ser restaurados.
- **Ponto de Restauração:** a criação é tentativa, dependente da Proteção do Sistema estar habilitada. Os backups `.reg` e o `state.json` continuam sendo a camada de reversão principal.
- **Escopo do Undo:** o `state.json` cobre apenas alterações registradas pelo OptiKit. Alterações feitas por outros programas, GPOs ou VPNs podem sobrescrever ajustes.
- **Windows 10:** o alvo principal é Windows 11; Windows 10 22H2 é suportado em melhor esforço.
- **Anti-cheats:** os guardrails reduzem o risco de conflito, mas não garantem compatibilidade com todos os anti-cheats ou versões futuras.
- **Distribuição:** o projeto é um script PowerShell sem instalador assinado nem auto-update; o aviso de nova versão é apenas informativo. O Windows pode exibir aviso do SmartScreen/antivírus.

Consulte também as [diretrizes técnicas](guidelines.md) e os [tweaks rejeitados](rejected.md).
