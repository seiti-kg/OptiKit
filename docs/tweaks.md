# Catálogo Técnico de Otimizações e Pacotes (`OptiKit`)

> Documento gerado automaticamente por `./build.ps1 -Docs` a partir dos arquivos em `config/`.

## 1. Otimizações de Sistema e Debloat (`config/win-tweaks.json`)

| ID | Título | Categoria | Impacto | Risco | SO | Requer Reboot |
|---|---|---|---|---|---|---|
| `WPFTweaksDisableGameDVR` | Desativar Xbox Game DVR e Gravação em 2º Plano | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksMouseRawInput` | Mouse 1:1 (Desativar Aprimorar Precisão do Ponteiro) | Desempenho & Energia | **Alto** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksSmartPowerPlan` | Gerenciamento de Energia Inteligente (Desktop / Ryzen X3D / Notebook) | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksUltimatePowerPlan` | Ativar Plano Desempenho Máximo (Ultimate Performance) | Desempenho & Energia | **Baixo** | `Moderate` | Win10, Win11 | Não |
| `WPFTweaksDisableHibernation` | Desativar Hibernação e Liberar Espaço no SSD (hiberfil.sys) | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableFastStartup` | Desativar Inicialização Rápida (Fast Startup) | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksUsbPollingOptimization` | Otimizar Portas USB para Alto Polling Rate (1000Hz a 8000Hz) | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableMPO` | Desativar Multiplane Overlay (MPO) no DWM | Desempenho & Energia | **Situacional** | `Moderate` | Win10, Win11 | Sim |
| `WPFTweaksEnableGameMode` | Garantir Modo de Jogo (Windows Game Mode) Ativo | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksEnableHAGS` | Ativar Agendamento de GPU Acelerado por Hardware (HAGS) | Desempenho & Energia | **Médio** | `Safe` | Win10, Win11 | Sim |
| `WPFTweaksNetworkThrottling` | Desativar Throttling de Rede Multimídia (MMCSS) | Desempenho & Energia | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableTelemetry` | Reduzir Telemetria do Windows e Serviços de Diagnóstico | Privacidade & Telemetria | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableAdvertisingId` | Desativar ID de Anúncio e Experiências Personalizadas | Privacidade & Telemetria | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableActivityHistory` | Desativar Histórico de Atividades e Sincronização de Timeline | Privacidade & Telemetria | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableTelemetryTasks` | Desativar Tarefas Agendadas de Telemetria (CEIP e Compatibility Appraiser) | Privacidade & Telemetria | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableRecall` | Desativar Windows Recall (Captura de Tela por IA) | Privacidade & Telemetria | **Médio** | `Safe` | Win11 | Não |
| `WPFTweaksDisableLocationTracking` | Desativar Rastreamento de Localização do Sistema | Privacidade & Telemetria | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableFeedbackPrompts` | Desativar Notificações de Feedback do Windows | Privacidade & Telemetria | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksClassicContextMenu` | Restaurar Menu de Contexto Clássico no Windows 11 | Interface & Windows 11 | **Alto** | `Safe` | Win11 | Não |
| `WPFTweaksDisableBingSearch` | Desativar Busca Web do Bing no Menu Iniciar | Interface & Windows 11 | **Alto** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableWidgets` | Desativar Widgets e Notícias/Interesses na Barra de Tarefas | Interface & Windows 11 | **Alto** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableCopilot` | Desativar Windows Copilot e Remover Botão da Barra de Tarefas | Interface & Windows 11 | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksShowFileExtensions` | Mostrar Extensões de Arquivos no Explorer | Interface & Windows 11 | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableStartSuggestions` | Desativar Sugestões, Dicas e Anúncios no Menu Iniciar e Tela de Bloqueio | Interface & Windows 11 | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksDisableStickyKeys` | Desativar Atalho das Teclas de Aderência (5x Shift) | Interface & Windows 11 | **Médio** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveClipchamp` | Remover Microsoft Clipchamp (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveFeedbackHub` | Remover Hub de Comentários / Feedback Hub (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveGetHelp` | Remover Obter Ajuda / Get Help (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveBingNewsWeather` | Remover Bing Notícias e Clima (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveSolitaire` | Remover Microsoft Solitaire Collection (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveNewOutlook` | Remover Novo Outlook for Windows (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveTeamsPersonal` | Remover Microsoft Teams Pessoal (Chat Integrado) | Remoção de Bloatware (Appx) | **Médio** | `Safe` | Win11 | Não |
| `WPFTweaksRemoveCortana` | Remover Cortana Legada (Appx) | Remoção de Bloatware (Appx) | **Baixo** | `Safe` | Win10, Win11 | Não |
| `WPFTweaksRemoveOneDrive` | Desinstalar Microsoft OneDrive de Forma Limpa e Segura | Remoção de Bloatware (Appx) | **Médio** | `Moderate` | Win10, Win11 | Não |
| `WPFTweaksDisableHVCI` | Desativar Integridade da Memória (HVCI / Isolamento de Núcleo) | Avançado | **Situacional** | `Advanced` | Win10, Win11 | Sim |

### Detalhamento Técnico e Justificativa (Anti-Placebo)

#### Desativar Xbox Game DVR e Gravação em 2º Plano (`WPFTweaksDisableGameDVR`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Desativa a gravação contínua de tela do Xbox Game Bar, reduzindo o uso de GPU/Vídeo e eliminando micro-stutterings em jogos.
- **Justificativa Técnica (Rationale):** O recurso Historical Capture mantém sessões de codificação de vídeo (NVENC/AMF) e buffers D3D ativos em segundo plano. Desativá-lo preserva a Xbox Game Bar para convites de amigos, mas impede gravação contínua involuntária. Fonte: Documentação Microsoft Policy CSP ApplicationManagement/AllowGameDVR.

#### Mouse 1:1 (Desativar Aprimorar Precisão do Ponteiro) (`WPFTweaksMouseRawInput`)
- **Categoria:** Desempenho & Energia | **Impacto:** Alto | **Risco:** Safe
- **Descrição:** Desativa a curva de aceleração de ponteiro do Windows (MouseSpeed=0, MouseThreshold1=0, MouseThreshold2=0) para resposta linear 1:1.
- **Justificativa Técnica (Rationale):** Jogos sem Raw Input nativo ou menus de inventário baseados no cursor do sistema herdam a curva de aceleração EPP (Enhance Pointer Precision) do Windows, prejudicando a memória muscular em FPS competitivos. Fonte: Documentação Win32 SystemParametersInfo SPI_SETMOUSE.

#### Gerenciamento de Energia Inteligente (Desktop / Ryzen X3D / Notebook) (`WPFTweaksSmartPowerPlan`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Ativa Alto Desempenho em Desktops, mantém Equilibrado em processadores AMD Ryzen X3D (exigido pelo Core Parking 3D V-Cache) e preserva a bateria em Notebooks.
- **Justificativa Técnica (Rationale):** Em CPUs AMD Ryzen 7000X3D/9000X3D com múltiplos CCDs, o driver AMD 3D V-Cache Performance Optimizer exige o plano Equilibrado (Balanced) para estacionar o CCD sem cache durante jogos. Em demais desktops, Alto Desempenho evita latência de transição de estados P-State. Fonte: Guia Oficial de Review AMD Ryzen X3D.

#### Ativar Plano Desempenho Máximo (Ultimate Performance) (`WPFTweaksUltimatePowerPlan`)
- **Categoria:** Desempenho & Energia | **Impacto:** Baixo | **Risco:** Moderate
- **Descrição:** Desbloqueia e ativa o plano oculto Ultimate Performance da Microsoft (sem duplicar esquemas existentes).
- **Justificativa Técnica (Rationale):** Reduz micro-latências de gerenciamento de energia de dispositivos e frequência de CPU. Em CPUs modernas com SpeedShift/CPPC o ganho sobre Alto Desempenho é marginal, e aumenta o consumo em idle; não recomendado para Ryzen dual-CCD X3D ou notebooks.

#### Desativar Hibernação e Liberar Espaço no SSD (hiberfil.sys) (`WPFTweaksDisableHibernation`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Executa powercfg -h off e desativa a hibernação, liberando vários gigabytes no SSD do sistema.
- **Justificativa Técnica (Rationale):** O arquivo hiberfil.sys reserva cerca de 40% da capacidade da memória RAM no drive principal. Em desktops com SSD, desativar a hibernação recupera espaço em disco imediatamente e evita gravações desnecessárias ao desligar. Fonte: Microsoft Docs powercfg.

#### Desativar Inicialização Rápida (Fast Startup) (`WPFTweaksDisableFastStartup`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Garante que o comando Desligar encerre completamente a sessão do kernel e recarregue drivers do zero.
- **Justificativa Técnica (Rationale):** Com Fast Startup ativo (HiberbootEnabled=1), desligar o PC apenas hiberna a sessão do kernel, acumulando uptime de drivers de GPU/áudio/anti-cheat por semanas e causando instabilidade. Em SSDs NVMe a diferença no tempo de boot é mínima.

#### Otimizar Portas USB para Alto Polling Rate (1000Hz a 8000Hz) (`WPFTweaksUsbPollingOptimization`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Desativa a Suspensão Seletiva de USB no plano de energia ativo e impede que o Windows desligue os USB Root Hubs para economizar energia.
- **Justificativa Técnica (Rationale):** Mouses e teclados competitivos (1000Hz a 8000Hz) podem sofrer desconexões momentâneas ou jitter de input quando o controlador USB entra em estado de baixo consumo (Selective Suspend). Fonte: Microsoft USB Selective Suspend documentation.

#### Desativar Multiplane Overlay (MPO) no DWM (`WPFTweaksDisableMPO`)
- **Categoria:** Desempenho & Energia | **Impacto:** Situacional | **Risco:** Moderate
- **Descrição:** Aplica OverlayTestMode=5 no Desktop Window Manager para diagnosticar ou corrigir piscadas de tela e travamentos ao dar Alt+Tab.
- **Justificativa Técnica (Rationale):** O MPO permite que o DWM componha planos de hardware diretamente na GPU, mas apresenta bugs conhecidos em combinações de monitores multi-refresh rate com vídeos acelerados por hardware. Nota: em builds recentes do Windows 11 24H2+, a chave OverlayTestMode pode ser ignorada pelo DWM. Fonte: NVIDIA Support KB 5157.

#### Garantir Modo de Jogo (Windows Game Mode) Ativo (`WPFTweaksEnableGameMode`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Ativa o Modo de Jogo do Windows para priorizar threads do jogo ativo e suspender indexação/Windows Update durante a partida.
- **Justificativa Técnica (Rationale):** No Windows 10 1903+ e Windows 11, o Game Mode é essencial para o agendador de threads (especialmente em CPUs híbridas Intel P/E-cores e AMD Ryzen X3D) e impede reinícios ou downloads do Windows Update durante jogos.

#### Ativar Agendamento de GPU Acelerado por Hardware (HAGS) (`WPFTweaksEnableHAGS`)
- **Categoria:** Desempenho & Energia | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Habilita o Hardware-Accelerated GPU Scheduling (HwSchMode=2), exigido para DLSS 3 Frame Generation e redução de overhead de CPU.
- **Justificativa Técnica (Rationale):** Transfere o gerenciamento de fila de memória de vídeo do kernel do Windows para o processador dedicado da GPU. Obrigatório para NVIDIA DLSS 3 Frame Generation. Requer reinicialização. Fonte: Microsoft DirectX Developer Blog.

#### Desativar Throttling de Rede Multimídia (MMCSS) (`WPFTweaksNetworkThrottling`)
- **Categoria:** Desempenho & Energia | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Configura NetworkThrottlingIndex=0xFFFFFFFF e SystemResponsiveness=10 no perfil multimídia do Windows.
- **Justificativa Técnica (Rationale):** O Multimedia Class Scheduler Service (MMCSS) aplica por padrão um limite de processamento de pacotes de rede (10 pacotes/ms) quando fluxos de áudio/mídia estão ativos. Desativar o limite evita picos de ping quando jogos e apps de voz rodam juntos. Fonte: Microsoft KB 948066.

#### Reduzir Telemetria do Windows e Serviços de Diagnóstico (`WPFTweaksDisableTelemetry`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Reduz o nível de coleta de dados de diagnóstico ao mínimo suportado e desativa os serviços DiagTrack e dmwappushservice.
- **Justificativa Técnica (Rationale):** Interrompe o envio contínuo de telemetria de uso em segundo plano pelo serviço Connected User Experiences and Telemetry (DiagTrack). Nota transparente: AllowTelemetry=0 só tem efeito em edições Enterprise/Education; no Windows Home/Pro o sistema aplica o nível mínimo 1 (Required).

#### Desativar ID de Anúncio e Experiências Personalizadas (`WPFTweaksDisableAdvertisingId`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Impede que aplicativos UWP/Win32 usem o identificador de publicidade do usuário e desativa recomendações baseadas em diagnóstico.
- **Justificativa Técnica (Rationale):** Desliga o rastreamento por Advertising ID e o uso de dados de diagnóstico para personalizar dicas, anúncios e recomendações na interface do Windows.

#### Desativar Histórico de Atividades e Sincronização de Timeline (`WPFTweaksDisableActivityHistory`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Impede que o Windows armazene e envie à nuvem o histórico de aplicativos abertos, arquivos e navegação.
- **Justificativa Técnica (Rationale):** Desativa as políticas EnableActivityFeed, PublishUserActivities e UploadUserActivities, reduzindo gravações em disco e sincronização em segundo plano.

#### Desativar Tarefas Agendadas de Telemetria (CEIP e Compatibility Appraiser) (`WPFTweaksDisableTelemetryTasks`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Desativa as tarefas agendadas Microsoft Compatibility Appraiser, ProgramDataUpdater e Customer Experience Improvement Program.
- **Justificativa Técnica (Rationale):** O processo CompatTelRunner.exe (acionado pelo Microsoft Compatibility Appraiser) é conhecido por causar alto uso de CPU e leitura intensa de disco em segundo plano.

#### Desativar Windows Recall (Captura de Tela por IA) (`WPFTweaksDisableRecall`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Bloqueia via política de grupo a análise de dados por IA e o salvamento de snapshots de tela do Windows Recall no Windows 11.
- **Justificativa Técnica (Rationale):** Aplica as políticas oficiais DisableAIDataAnalysis e TurnOffSavingSnapshots documentadas pela Microsoft para impedir que o Recall capture e indexe a tela periodicamente. Fonte: Microsoft Policy CSP WindowsAI.

#### Desativar Rastreamento de Localização do Sistema (`WPFTweaksDisableLocationTracking`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Bloqueia o acesso global à localização geográfica para aplicativos e serviços do Windows.
- **Justificativa Técnica (Rationale):** Em desktops e setups gamers, o serviço de localização é desnecessário e expõe metadados geográficos a aplicativos UWP.

#### Desativar Notificações de Feedback do Windows (`WPFTweaksDisableFeedbackPrompts`)
- **Categoria:** Privacidade & Telemetria | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Define a frequência de solicitações de avaliação do Windows (SIUF) como Nunca.
- **Justificativa Técnica (Rationale):** Evita popups de pesquisa de satisfação do Windows interrompendo sessões de uso ou jogos.

#### Restaurar Menu de Contexto Clássico no Windows 11 (`WPFTweaksClassicContextMenu`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Alto | **Risco:** Safe
- **Descrição:** Exibe diretamente o menu de clique direito completo no Windows 11 sem precisar clicar em 'Mostrar mais opções'.
- **Justificativa Técnica (Rationale):** Registra o override COM em HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32, eliminando a camada extra de latência do menu XAML do Windows 11.

#### Desativar Busca Web do Bing no Menu Iniciar (`WPFTweaksDisableBingSearch`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Alto | **Risco:** Safe
- **Descrição:** Configura DisableSearchBoxSuggestions=1 para que a pesquisa do Menu Iniciar busque apenas arquivos, configurações e programas locais.
- **Justificativa Técnica (Rationale):** Remove requisições HTTP ao Bing a cada tecla digitada no Menu Iniciar, deixando a pesquisa local instantânea e eliminando resultados web indesejados. Fonte: Microsoft Policy Explorer/DisableSearchBoxSuggestions.

#### Desativar Widgets e Notícias/Interesses na Barra de Tarefas (`WPFTweaksDisableWidgets`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Alto | **Risco:** Safe
- **Descrição:** Desativa o painel de Widgets do Windows 11 (WindowsWebExperiencePack) e o feed de Notícias e Interesses do Windows 10.
- **Justificativa Técnica (Rationale):** O painel de Widgets mantém processos WebView2 (msedgewebview2.exe) residentes em memória RAM mesmo sem o usuário abrir o painel. A política AllowNewsAndInterests=0 encerra o recurso completamente.

#### Desativar Windows Copilot e Remover Botão da Barra de Tarefas (`WPFTweaksDisableCopilot`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Oculta o botão do Copilot na barra de tarefas, aplica a política de bloqueio e remove o pacote Appx Microsoft.Copilot.
- **Justificativa Técnica (Rationale):** Em versões recentes do Windows 11 (23H2/24H2+), a política TurnOffWindowsCopilot sozinha foi substituída pelo pacote Appx Microsoft.Copilot. Combinar a remoção do pacote com a política e ocultação do botão garante desativação completa.

#### Mostrar Extensões de Arquivos no Explorer (`WPFTweaksShowFileExtensions`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Configura HideFileExt=0 para exibir sempre a extensão real de todos os arquivos (.exe, .ps1, .dll, .txt).
- **Justificativa Técnica (Rationale):** Prática essencial de segurança e usabilidade: evita execução acidental de arquivos maliciosos com dupla extensão (ex: documento.pdf.exe).

#### Desativar Sugestões, Dicas e Anúncios no Menu Iniciar e Tela de Bloqueio (`WPFTweaksDisableStartSuggestions`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Desativa o ContentDeliveryManager para impedir instalação silenciosa de apps promovidos e recomendações comerciais no Iniciar.
- **Justificativa Técnica (Rationale):** O Windows ContentDeliveryManager baixa e sugere aplicativos patrocinados automaticamente no Menu Iniciar em instalações recém-formatadas.

#### Desativar Atalho das Teclas de Aderência (5x Shift) (`WPFTweaksDisableStickyKeys`)
- **Categoria:** Interface & Windows 11 | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Impede que pressionar a tecla Shift 5 vezes seguidas minimize o jogo com o alerta das Teclas de Aderência.
- **Justificativa Técnica (Rationale):** Em jogos onde a tecla Shift é usada para agachar ou caminhar (crouch/walk em VALORANT e CS2), o atalho padrão Flags=510 abre um diálogo modal e tira o foco da janela do jogo.

#### Remover Microsoft Clipchamp (Appx) (`WPFTweaksRemoveClipchamp`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove o editor de vídeo web-wrapper Clipchamp para todos os usuários e do provisionamento do sistema (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** Pré-instalado no Windows 11, ocupa espaço e registra tarefas de atualização sem necessidade para quem usa editores dedicados.

#### Remover Hub de Comentários / Feedback Hub (Appx) (`WPFTweaksRemoveFeedbackHub`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove o aplicativo Microsoft.WindowsFeedbackHub do sistema e do provisionamento (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** Utilitário de envio de telemetria e feedback da Microsoft raramente utilizado por usuários finais.

#### Remover Obter Ajuda / Get Help (Appx) (`WPFTweaksRemoveGetHelp`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove o assistente de suporte Microsoft.GetHelp (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** Substitui o antigo suporte básico por um chat web desnecessário para usuários técnicos.

#### Remover Bing Notícias e Clima (Appx) (`WPFTweaksRemoveBingNewsWeather`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove os pacotes Microsoft.BingNews e Microsoft.BingWeather (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** Aplicativos MSN pré-instalados que executam tarefas de atualização de blocos dinâmicos e notificações em segundo plano.

#### Remover Microsoft Solitaire Collection (Appx) (`WPFTweaksRemoveSolitaire`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove o pacote de jogos casuais com anúncios Microsoft.MicrosoftSolitaireCollection (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** Bloatware clássico pré-instalado em todas as edições de consumidor do Windows 10 e 11.

#### Remover Novo Outlook for Windows (Appx) (`WPFTweaksRemoveNewOutlook`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove o cliente web-wrapper Microsoft.OutlookForWindows pré-instalado no Windows 11 23H2/24H2 (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** Aplicativo baseado em WebView2 que substituiu o app Email e inicia processos em segundo plano mesmo para quem usa webmail no navegador.

#### Remover Microsoft Teams Pessoal (Chat Integrado) (`WPFTweaksRemoveTeamsPersonal`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Médio | **Risco:** Safe
- **Descrição:** Remove o pacote MicrosoftTeams (versão pessoal integrada ao Windows 11, preservando o Teams corporativo se instalado) (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** O Teams pessoal pré-instalado carrega instâncias do Edge WebView2 no login do usuário.

#### Remover Cortana Legada (Appx) (`WPFTweaksRemoveCortana`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Baixo | **Risco:** Safe
- **Descrição:** Remove o aplicativo descontinuado da Cortana (Microsoft.549981C3F5F10) (reversível via reinstalação).
- **Justificativa Técnica (Rationale):** A Microsoft encerrou o suporte ao app standalone da Cortana no Windows, tornando o pacote obsoleto.

#### Desinstalar Microsoft OneDrive de Forma Limpa e Segura (`WPFTweaksRemoveOneDrive`)
- **Categoria:** Remoção de Bloatware (Appx) | **Impacto:** Médio | **Risco:** Moderate
- **Descrição:** Desinstala o cliente de sincronização OneDrive apenas após verificar que as pastas Área de Trabalho e Documentos não estão redirecionadas (KFM).
- **Justificativa Técnica (Rationale):** O OneDrive inicia junto com o Windows e sincroniza continuamente a pasta do usuário, causando uso de rede e I/O de disco durante jogos. A trava de verificação de Known Folder Move (KFM) impede que o usuário perca atalhos da Área de Trabalho.

#### Desativar Integridade da Memória (HVCI / Isolamento de Núcleo) (`WPFTweaksDisableHVCI`)
- **Categoria:** Avançado | **Impacto:** Situacional | **Risco:** Advanced
- **Descrição:** Desativa apenas o Hypervisor-Protected Code Integrity (HVCI), mantendo o TPM 2.0 e Secure Boot intactos.
- **Justificativa Técnica (Rationale):** A verificação de integridade de código em páginas de memória do kernel via hipervisor adiciona overhead mensurável de CPU em jogos limitados por processador (5% a 12% em CPUs sem suporte nativo a MBEC). A própria Microsoft documenta a opção de desativar o HVCI para ganho de desempenho em jogos, mas alerta sobre a redução de segurança e possíveis exigências do Riot Vanguard / FACEIT no Windows 11. Fonte: Microsoft Support 'Options to optimize gaming performance in Windows 11'.

## 2. Perfis de Jogos (`config/game-profiles.json`)

### VALORANT (`ProfileValorant`)
- **Engine:** Unreal Engine 4 | **Anti-Cheat:** Riot Vanguard (Kernel)
- **Aviso:** O Riot Vanguard exige TPM 2.0 e Secure Boot ativos. Este perfil aplica apenas otimizações 100% seguras e compatíveis com o Vanguard.

| ID | Otimização | Action | Impacto | Justificativa |
|---|---|---|---|---|
| `Val_FSO_HighDPI` | Aplicar Flags FSO e High DPI Bypass no Executável | `Set-AppCompatFlags` | **Situacional** | Define Application High DPI Scaling no executável Win64-Shipping para evitar escalonamento via DWM. Nota transparente: no Windows 11 com DXGI Flip Model moderno, a latência em janela sem bordas já equivale à tela cheia exclusiva; o ganho é situacional para setups com escala de tela > 100% ou Windows 10. |
| `Val_DirectX_HighPerf` | Forçar GPU de Alto Desempenho no DirectX | `Set-DirectXGpuPreference` | **Médio** | Garante que o DXGI selecione sempre a GPU dedicada (dGPU) e o perfil de alto desempenho gráfico, essencial em processadores com vídeo integrado (iGPU AMD/Intel) ativo. |
| `Val_Network_NoEEE` | Otimizar Placa de Rede para Servidores 128-Tick (Anti-Jitter) | `Optimize-NetworkAdapterGaming` | **Situacional** | Adaptadores Ethernet com EEE (IEEE 802.3az) colocam o link físico em Low Power Idle entre rajadas de pacotes, adicionando micro-latência de despertar na transmissão UDP constante de servidores 128-tick. Causa reconexão rápida (~2s) ao aplicar. |
| `Val_RiotClient_Cleanup` | Desativar Inicialização Automática do Riot Client com o Windows | `Disable-RiotClientStartup` | **Médio** | Desabilita apenas o launcher RiotClientServices.exe na chave de inicialização (StartupApproved), sem alterar o serviço vgc nem o driver vgk.sys do Riot Vanguard. |

### Counter-Strike 2 (`ProfileCS2`)
- **Engine:** Source 2 | **Anti-Cheat:** VAC / FACEIT Anti-Cheat
- **Aviso:** Em breve: detecção automática via biblioteca Steam, preferência de GPU DX11/Vulkan e limpeza de cache Source 2.

### Jogos Unreal Engine 5 / AAA (`ProfileUE5`)
- **Engine:** Unreal Engine 5 | **Anti-Cheat:** Easy Anti-Cheat / BattlEye
- **Aviso:** Em breve: otimização de compilação de shaders PSO, preferência de GPU por executável e ajustes de streaming.

### Ferramentas Globais de Gaming (`GlobalGamingTools`)
- **Engine:** DirectX / Vulkan / Hardware | **Anti-Cheat:** Universal (Compatível)
- **Aviso:** Ferramentas aplicáveis a qualquer jogo instalado no sistema.

| ID | Otimização | Action | Impacto | Justificativa |
|---|---|---|---|---|
| `Global_ClearShaderCache` | Limpar Cache de Shaders (DirectX, NVIDIA e AMD) | `Clear-ShaderCache` | **Alto** | Caches de shaders corrompidos ou antigos após múltiplos updates de driver causam frame drops severos. Arquivos em uso pelo sistema são ignorados com segurança. |
| `Global_OptimizeNIC` | Otimizar Rede / NIC (Desativar Economia de Energia Ethernet) | `Optimize-NetworkAdapterGaming` | **Situacional** | Evita transições de estado de energia no controlador de rede durante sessões online competitivas. |
| `Global_OptimizeUSB` | Otimizar Portas USB (Desativar Suspensão Seletiva e Economia nos Hubs) | `Optimize-UsbPower` | **Médio** | Estabiliza a entrega de pacotes USB para periféricos de 1000Hz a 8000Hz. |

## 3. Catálogo de Aplicativos (`config/apps.json`)

| ID | Nome | Categoria | Winget ID | Flatpak ID |
|---|---|---|---|---|
| `Brave` | Brave Browser | Navegadores | `Brave.Brave` | `com.brave.Browser` |
| `Firefox` | Mozilla Firefox | Navegadores | `Mozilla.Firefox` | `org.mozilla.firefox` |
| `Chrome` | Google Chrome | Navegadores | `Google.Chrome` | `com.google.Chrome` |
| `LibreWolf` | LibreWolf | Navegadores | `LibreWolf.LibreWolf` | `io.gitlab.librewolf-community` |
| `ZenBrowser` | Zen Browser | Navegadores | `Zen-Team.Zen-Browser` | `app.zen_browser.zen` |
| `UngoogledChromium` | Ungoogled Chromium | Navegadores | `eloston.ungoogled-chromium` | `io.github.ungoogled_software.ungoogled_chromium` |
| `Discord` | Discord | Comunicação | `Discord.Discord` | `com.discordapp.Discord` |
| `Vesktop` | Vesktop (Vencord Desktop) | Comunicação | `Vencord.Vesktop` | `dev.vencord.Vesktop` |
| `Telegram` | Telegram Desktop | Comunicação | `Telegram.TelegramDesktop` | `org.telegram.desktop` |
| `TeamSpeak` | TeamSpeak Client | Comunicação | `TeamSpeakSystems.TeamSpeakClient` | `com.teamspeak.TeamSpeak` |
| `Steam` | Steam | Jogos & Launchers | `Valve.Steam` | `com.valvesoftware.Steam` |
| `EpicGames` | Epic Games Launcher | Jogos & Launchers | `EpicGames.EpicGamesLauncher` | - |
| `Heroic` | Heroic Games Launcher | Jogos & Launchers | `HeroicGamesLauncher.HeroicGamesLauncher` | `com.heroicgameslauncher.hgl` |
| `GOGGalaxy` | GOG Galaxy | Jogos & Launchers | `GOG.Galaxy` | - |
| `EAApp` | EA App | Jogos & Launchers | `ElectronicArts.EADesktop` | - |
| `UbisoftConnect` | Ubisoft Connect | Jogos & Launchers | `Ubisoft.Connect` | - |
| `Playnite` | Playnite | Jogos & Launchers | `Playnite.Playnite` | - |
| `MSIAfterburner` | MSI Afterburner | Jogos & Launchers | `Guru3D.Afterburner` | - |
| `RTSS` | RivaTuner Statistics Server (RTSS) | Jogos & Launchers | `Guru3D.RTSS` | - |
| `CapFrameX` | CapFrameX | Jogos & Launchers | `CXWorld.CapFrameX` | - |
| `OBSStudio` | OBS Studio | Jogos & Launchers | `OBSProject.OBSStudio` | `com.obsproject.Studio` |
| `HWiNFO` | HWiNFO | Jogos & Launchers | `REALiX.HWiNFO` | - |
| `CPUZ` | CPUID CPU-Z | Jogos & Launchers | `CPUID.CPU-Z` | - |
| `GPUZ` | TechPowerUp GPU-Z | Jogos & Launchers | `TechPowerUp.GPU-Z` | - |
| `NVCleanstall` | TechPowerUp NVCleanstall | Jogos & Launchers | `TechPowerUp.NVCleanstall` | - |
| `DDU` | Display Driver Uninstaller (DDU) | Jogos & Launchers | `Wagnardsoft.DisplayDriverUninstaller` | - |
| `VCRedistX64` | Visual C++ Redistributable 2015-2022 (x64) | Runtimes & Utilitários | `Microsoft.VCRedist.2015+.x64` | - |
| `VCRedistX86` | Visual C++ Redistributable 2015-2022 (x86) | Runtimes & Utilitários | `Microsoft.VCRedist.2015+.x86` | - |
| `DotNetDesktop8` | .NET Desktop Runtime 8 (LTS) | Runtimes & Utilitários | `Microsoft.DotNet.DesktopRuntime.8` | - |
| `DirectXRuntime` | DirectX End-User Runtime | Runtimes & Utilitários | `Microsoft.DirectX` | - |
| `SevenZip` | 7-Zip | Runtimes & Utilitários | `7zip.7zip` | - |
| `NanaZip` | NanaZip | Runtimes & Utilitários | `M2Team.NanaZip` | - |
| `Everything` | Everything (voidtools) | Runtimes & Utilitários | `voidtools.Everything` | - |
| `WizTree` | WizTree | Runtimes & Utilitários | `AntibodySoftware.WizTree` | - |
| `PowerToys` | Microsoft PowerToys | Runtimes & Utilitários | `Microsoft.PowerToys` | - |
| `ShareX` | ShareX | Runtimes & Utilitários | `ShareX.ShareX` | - |
| `VLC` | VLC Media Player | Runtimes & Utilitários | `VideoLAN.VLC` | `org.videolan.VLC` |
| `qBittorrent` | qBittorrent | Runtimes & Utilitários | `qBittorrent.qBittorrent` | `org.qbittorrent.qBittorrent` |
| `Bitwarden` | Bitwarden | Runtimes & Utilitários | `Bitwarden.Bitwarden` | `com.bitwarden.desktop` |
| `NotepadPlusPlus` | Notepad++ | Runtimes & Utilitários | `Notepad++.Notepad++` | - |
| `Git` | Git | Desenvolvimento | `Git.Git` | - |
| `VSCode` | Visual Studio Code | Desenvolvimento | `Microsoft.VisualStudioCode` | `com.visualstudio.code` |
| `VSCodium` | VSCodium | Desenvolvimento | `VSCodium.VSCodium` | `com.vscodium.codium` |
| `WindowsTerminal` | Windows Terminal | Desenvolvimento | `Microsoft.WindowsTerminal` | - |
| `Python312` | Python 3.12 | Desenvolvimento | `Python.Python.3.12` | - |
| `NodeJSLTS` | Node.js (LTS) | Desenvolvimento | `OpenJS.NodeJS.LTS` | - |
