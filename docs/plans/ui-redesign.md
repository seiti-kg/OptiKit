# Plano: interface limpa do OptiKit

Plano de execução para agentes (fases F0 a F5). Cada fase é independente de contexto: leia as seções 4 a 7 antes de qualquer fase e depois execute somente a fase pedida.

## 1. Resumo

A interface atual funciona, mas está poluída: 153 contornos de card só na aba de ajustes, 10 tamanhos de fonte, 33 cores hex espalhadas no código, 2 a 4 badges coloridos por linha, 23 emojis usados como ícone (um deles renderiza como quadrado vazio) e um rodapé que ocupa 1/5 da altura. Na janela mínima (980x660) o botão **Aplicar selecionados** fica cortado e a tabela de inicialização encolhe para 6 px.

O redesign mantém a identidade (tema escuro + ciano), troca as abas do topo por navegação lateral no padrão do Windows 11, substitui cards por linhas sem borda, reduz a tipografia a 4 tamanhos e a paleta a 18 tokens, e esconde o que é secundário (log recolhível, barra de seleção só nas páginas de lista, ações raras movidas para Manutenção). A página de Ajustes ganha uma barra de organização: agrupar por categoria, impacto, risco, reinício ou estado, com filtros combináveis de impacto, risco e estado.

A parte arriscada (templates WPF, layout em tamanho mínimo, componentes de linha) já foi prototipada e validada por render. Os agentes integram esses artefatos, não inventam layout.

Durante a auditoria apareceu um bug funcional (F0): os perfis CS2 e Unreal Engine 5 detectam o executável do VALORANT e aplicariam flags de GPU/FSO no jogo errado.

## 2. Diagnóstico (impeccable: critique)

**Leitura de design:** modo *Operate* (ferramenta em que o usuário executa tarefas). Utilitário Windows para quem otimiza PC gamer; deve parecer nativo do Windows 11, previsível e calmo. A ambição aparece como precisão e contenção, não como decoração.
**Dials (taste-skill):** variação 2/10, movimento 1/10 (sem animações), densidade 5/10.

### 2.1 Linha de base medida (`tools/ui-audit.ps1`, dados sintéticos)

| Métrica | Atual | Meta | Ensaio do plano (seção 10) |
|---|---|---|---|
| Tamanhos de fonte | 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 15, 19 | 12, 14, 16, 20 | 12, 14, 16, 20 |
| Cores fora da paleta | 32 de 40 | 0 | 0 de 15 |
| Textos com emoji | 26 | 0 | 0 |
| Controles fora da janela (980x660) | BtnApplySelected, BtnUndoAll, BtnRefreshStartup | nenhum | nenhum |
| Bordas autorais por página (Ajustes) | 153 | no máximo 4 | 2 |
| Altura da tabela de inicialização (980x660) | 6 px | 300 px ou mais | 440 px |

### 2.2 Heurísticas de Nielsen (0 a 4)

| # | Heurística | Atual | Motivo principal |
|---|---|---|---|
| 1 | Visibilidade do estado | 2 | Status truncado; progresso sempre visível; console ruidoso |
| 2 | Linguagem do usuário | 2 | Mistura "Moderate"/"Médio", "Undo", "Dry-Run", jargão ("Anti-Placebo", "StartupApproved") |
| 3 | Controle e liberdade | 3 | Undo existe, mas "Reverter Tudo" fica ao lado do botão principal |
| 4 | Consistência | 1 | 10 tamanhos, 33 cores, combobox claro no tema escuro, vermelho para "perigo" e para "perfil ativo" |
| 5 | Prevenção de erros | 2 | CTA cortado na janela mínima; exe errado no CS2/UE5 |
| 6 | Reconhecer em vez de lembrar | 2 | Justificativa só no tooltip; legenda "● Aplicado" separada da linha |
| 7 | Eficiência | 2 | Presets e busca bons; sem atalhos; busca deixa cabeçalhos vazios |
| 8 | Estética minimalista | 1 | Cards em tudo, badges em excesso, banner explicativo em cada aba |
| 9 | Recuperação de erros | 2 | Erro some no console; combobox de DoH ilegível |
| 10 | Ajuda | 2 | Tooltips com rationale são bons, mas cheios de emoji |
| | **Total** | **19/40** | Meta após F5: 30/40 ou mais |

### 2.3 Problemas priorizados

| Sev. | Problema | Fase |
|---|---|---|
| P0 | CS2/UE5 recebem o exe do VALORANT (`Find-GameExecutable` usa o fallback do Riot Client para qualquer perfil); badges "Aplicado" falsos | F0 |
| P0 | Em 980x660 o botão Aplicar fica fora da janela e a tabela de inicialização fica com 6 px | F1 |
| P1 | ComboBox de DoH com texto ilegível (template Aero2 ignora Background); preset em combobox claro | F1 |
| P1 | Ruído visual: cards com borda por item, cards aninhados em Jogos, badges coloridos, 10 tamanhos de fonte | F2, F3 |
| P1 | Emoji como ícone (23 glifos; 🩺 vira quadrado) | F1, F2, F3, F4 |
| P2 | Rótulos mistos (inglês/português), Title Case, títulos de diálogo com "(OptiKit)" | F4 |
| P2 | Busca deixa cabeçalhos de categoria vazios e não tem estado vazio | F2 |
| P2 | 60 ajustes em ordem fixa de categoria; sem ordenar por impacto/risco/estado nem filtrar | F2 |
| P2 | Diálogo de "Atualizar apps" mostra `` `r`n `` literal (string em aspas simples) | F4 |
| P3 | Barras de rolagem claras e grossas; sem Ctrl+F; tooltips com prazo de 5 s | F1, F5 |

## 3. Direção de design (decisões fechadas)

### 3.1 Estrutura

```
┌───────────────┬──────────────────────────────────────────────────────────┐
│ OptiKit       │ Título da página                       [ações discretas] │
│ [Buscar...  ] │ Subtítulo de uma linha                                   │
│               │                                                          │
│ ▌Instalar apps│ Ajustes do Windows                                       │
│  Ajustes      │ [Organizar ▾] [Impacto ▾] [Risco ▾] [Estado ▾]  60 ajustes│
│  Jogos        │ Categoria  17                                            │
│  Diagnóstico  │ [ ] Título do ajuste                            Aplicado │
│  Inicialização│     Descrição curta...                     Impacto médio │
│  Manutenção   │ [x] Outro ajuste                                         │
│               │                                                          │
│ CPU           │                                                          │
│ GPU           │                                                          │
│ Desktop · Win │                                                          │
├───────────────┴──────────────────────────────────────────────────────────┤
│ Log  Status da última operação...  [Preset ▾] 15 itens  Limpar  [Reverter selecionados] [Aplicar selecionados] │
└──────────────────────────────────────────────────────────────────────────┘
```

- Navegação lateral (`NavList`, ListBox) ligada por binding ao `SelectedIndex` do `MainTabControl`. O TabControl só troca conteúdo; seu cabeçalho fica oculto.
- Páginas: 0 Instalar apps, 1 Ajustes do Windows, 2 Jogos, 3 Diagnóstico, 4 Inicialização (nova, tirada de Manutenção), 5 Manutenção.
- Cada página: título (20) + subtítulo de uma linha (12) + conteúdo rolável. Sem banner, sem card de cabeçalho.
- Ajustes: barra de organização fixa entre o subtítulo e a lista, com quatro combos compactos (organizar, impacto, risco, estado), contagem de ajustes e botão "Limpar filtros" que só aparece com filtro ativo. Agrupar por categoria, impacto, risco, reinício, estado ou nome; os filtros de impacto, risco e estado são combináveis.
- Rodapé de uma linha. A barra de seleção (preset, contador, Limpar, Reverter, Aplicar) só aparece nas páginas 0 a 2 (DataTrigger no XAML). Progresso de 2 px só durante operações. Log recolhível que abre sozinho em erro.

### 3.2 Tokens (definidos em `theme.xaml`; nenhum hex fora deles)

| Chave | Cor | Uso | Contraste em `Bg.Window` |
|---|---|---|---|
| `Brush.Bg.Window` | #111214 | Fundo do conteúdo | |
| `Brush.Bg.Rail` | #16171A | Trilho lateral e rodapé | |
| `Brush.Bg.Surface` | #1B1D20 | Inputs, combobox, tooltip, botão secundário | |
| `Brush.Bg.Hover` | #212328 | Hover de linha e botão | |
| `Brush.Bg.Pressed` | #282B30 | Pressionado, item selecionado | |
| `Brush.Border.Subtle` | #25272C | Divisórias | |
| `Brush.Border.Default` | #363940 | Borda de input e checkbox | |
| `Brush.Text.Primary` | #ECEDEF | Texto principal | 16:1 |
| `Brush.Text.Secondary` | #A4A9B0 | Descrições, subtítulos | 7.9:1 |
| `Brush.Text.Tertiary` | #8A8F97 | Metadados (impacto, contagens) | 5.8:1 (4.8:1 sobre hover) |
| `Brush.Text.Disabled` | #5C6168 | Desabilitado | |
| `Brush.Accent` | #2BC4E0 | Só: botão primário, seleção, foco, link | 9.0:1 |
| `Brush.Accent.Hover` / `.Pressed` | #55D3EA / #1FA6C0 | Estados do primário | |
| `Brush.OnAccent` | #0B0D10 | Texto sobre o acento | 9.3:1 sobre o acento |
| `Brush.Success` | #3FB97A | "Aplicado", diagnóstico OK | 7.5:1 |
| `Brush.Warning` | #E0A43B | Risco moderado, aviso, exe ausente | 8.5:1 |
| `Brush.Danger` | #E5534B | Risco avançado, bloqueado, erro, "Reverter tudo" | 5.1:1 |

O ciano passou de #00E5FF (neon, saturação 100%) para #2BC4E0 e deixou de colorir cabeçalhos, contadores e bordas.

### 3.3 Tipografia, espaço e forma

- Família: Segoe UI (interface), `Cascadia Mono, Consolas` (log e comandos), `Segoe Fluent Icons, Segoe MDL2 Assets` (ícones).
- Escala fixa: `Text.Caption` 12 (descrição, metadados), `Text.Body` 14 (padrão), `Text.Subtitle` 16 SemiBold (grupos), `Text.Title` 20 SemiBold (páginas). Pesos: Regular e SemiBold. Nada de Bold.
- Espaçamento em múltiplos de 4: 2 entre linhas de uma lista, 8 dentro de grupos, 16 entre cabeçalho e conteúdo, 24 a 32 entre grupos e seções.
- Raio único de 4 px (checkbox 3 px). Sem sombra, sem gradiente, sem brilho.
- `TextOptions.TextFormattingMode="Display"` e `UseLayoutRounding="True"` na janela (texto nítido em 12 a 14 px).

### 3.4 Componentes

| Componente | Estrutura | Onde |
|---|---|---|
| Linha selecionável | CheckBox inteira clicável (hover `Bg.Hover`). Linha 1: título 14 + estado à direita ("Aplicado" verde, "Bloqueado" vermelho). Linha 2: descrição 12 cortada + metadados 12 à direita ("Risco moderado" em âmbar, "Impacto médio", "Requer reinício") | Apps, Ajustes, Jogos |
| Cabeçalho de grupo | Nome 16 SemiBold + contagem 12 terciária | Apps, Ajustes |
| Barra de organização | Quatro ComboBoxes compactos (organizar, impacto, risco, estado), contagem 12 à direita e "Limpar filtros" discreto quando há filtro ativo. Agrupa e ordena sem card | Ajustes |
| Grade responsiva | UniformGrid; colunas = largura / mínimo (apps 260 px, ajustes e jogos 560 px) | Apps (2 a 5 col.), Ajustes e Jogos (1 col. até ~1450 px de janela) |
| Seção de jogo | Tile 36x36 com monograma (VAL/CS2/UE5/GLB) e cor de identidade + nome 16 + contagem; à direita "engine · anti-cheat" e status ("Executável detectado", "Executável não encontrado", "Ferramentas globais"). Aviso 12; linha "Executável: arquivo.exe" + botão discreto Alterar/Selecionar; linhas de otimização. Sem card | Jogos |
| Linha de diagnóstico | Ícone de estado colorido + título 14 SemiBold + rótulo de estado à direita; resumo; detalhe; link de ação. Ordenado por gravidade, separado por divisória | Diagnóstico |
| Linha de ação | Título 14 + descrição 12 à esquerda; botões com verbo curto à direita; divisória entre linhas | Manutenção |
| Tooltip | Título, descrição, "Justificativa técnica", metadados, alerta de bloqueio. Fica 30 s; aparece também em item desabilitado | Todas as linhas |

Ícones (código MDL2/Fluent, validados): apps `E71D`, ajustes `E713`, jogos `E7FC`, diagnóstico `E9D9`, inicialização `E7E8`, manutenção `E90F`, busca `E721`, limpar `E711`, OK `E930`, aviso `E7BA`, problema `EA39`, informativo `E946`, não verificado `E9CE`. Em código use `[char]0xE930`, nunca o glifo literal.

### 3.5 Para onde foi cada coisa

| Antes | Depois |
|---|---|
| Cabeçalho com subtítulo "System & Gaming Optimizer", hardware em uma linha e busca | Trilho: nome, busca, hardware em linhas separadas. Subtítulo removido |
| 5 abas no topo com emoji | 6 itens no trilho com ícone MDL2 |
| Banner explicativo em cada aba | Subtítulo de uma linha |
| Legenda "● Aplicado na máquina" | Removida: "Aplicado" aparece na própria linha |
| Badges de impacto, risco e bloqueio | Texto discreto; cor só para risco e bloqueio |
| Cards por item e cards aninhados em Jogos | Linhas sem borda; seções separadas por espaço |
| Ordem fixa de categorias, sem filtro | Barra de organização: agrupar por categoria/impacto/risco/reinício/estado e filtrar por impacto/risco/estado |
| 12 botões em WrapPanel com emoji | 10 linhas de ação em 5 seções |
| Gerenciador de inicialização dentro de Manutenção | Página Inicialização com a tabela ocupando a altura |
| "Ver alterações aplicadas" e "Reverter tudo" no rodapé | Manutenção > Histórico e reversão |
| Console de 60 px sempre visível | Botão "Log"; abre sozinho em erro |
| Barra de progresso sempre visível | 2 px no topo do rodapé, só durante operações |

### 3.6 Texto (impeccable: clarify)

- Português do Brasil, frase com inicial maiúscula só na primeira palavra ("Aplicar selecionados", não "Aplicar Selecionados").
- Sem emoji, sem travessão (—) em texto de interface, sem "(OptiKit)" em títulos de diálogo.
- Botão diz a ação: Aplicar, Reverter, Limpar, Executar, Exportar. Confirmação nomeia o que acontece.
- Rótulos do catálogo traduzidos na exibição (o JSON não muda): `Moderate` vira "Risco moderado", `Advanced` vira "Risco avançado", `Safe` não aparece; `Alto/Médio/Baixo` viram "Impacto alto/médio/baixo"; `Situacional` fica igual.
- Barra de organização: "Organizar: categoria/impacto/risco/reinício/estado/nome", "Impacto: todos/alto/médio/baixo/situacional", "Risco: todos/seguro/moderado/avançado", "Estado: todos/aplicado/não aplicado/parcial/desconhecido". Vazio: "Nenhum ajuste com esses filtros. Ajuste a organização ou limpe os filtros."
- Contagens com plural correto ("1 item selecionado", "15 itens selecionados", "Nenhum item selecionado").

### 3.7 Fora de escopo

Tema claro, animações, bibliotecas externas de UI (MahApps, ModernWpf: o `irm | iex` precisa de um único `.ps1`), mudanças nos textos do catálogo (`config/*.json`), novas funcionalidades e mudanças nos motores, exceto F0.

## 4. Artefatos prontos

| Arquivo | O que é | Validação feita |
|---|---|---|
| `docs/plans/ui-redesign/theme.xaml` | Substituto completo de `src/windows/ui/theme.xaml`: tokens, estilos (botões, checkbox de linha, combobox escuro, busca, tooltip, scrollbar fina, tabela, navegação), barra de organização e todas as páginas | Renderizado em 1240x850 e 980x660; app real rodou o fluxo de smoke com ele sem erro |
| `docs/plans/ui-redesign/components.ps1` | Funções de componente para colar em `ui-builder.ps1`, incluindo linhas, grupos, organização por categoria/impacto/risco/reinício/estado e filtros | PSScriptAnalyzer: 0; renderizado com o catálogo real |
| `docs/plans/ui-redesign/preview.ps1` | Monta as listas com os componentes e salva PNGs em `scratch/ui-redesign/preview/` | Referência visual do alvo |
| `tools/ui-audit.ps1` | Renderiza a GUI fora da tela, mede cada página e salva `report.json` + PNGs | PSScriptAnalyzer: 0; roda contra `src`, `win.ps1` ou um tema candidato (`-ThemePath`) |

Uso do auditor:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -OutDir .\scratch\ui-audit\F1
powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -NoPng -Size 980x660 -OutDir .\scratch\ui-audit\rapido
```

Campos do `report.json` usados nos critérios: `FontSizes`, `FontFamilies`, `OffPalette`, `OffPaletteWhere` (onde cada cor fora da paleta aparece), `EmojiTexts`, `OutOfBounds`, e por página em `Sizes[].Tabs[]`: `PrimaryAction` (`visivel`, `oculto`, `cortado`), `AuthoredBorders`, `FontSizes`, `StartupGridHeight`.

## 5. Contratos que não podem quebrar

1. **Nomes de controle.** `main.ps1` e `ui-builder.ps1` usam `FindName`. Todos estes nomes precisam existir no XAML (o candidato já tem todos): `BadgeDryRun`, `BadgeUpdate`, `TxtUpdateBadge`, `TxtHardwareSummary`, `TxtSearchBox`, `BtnClearSearch`, `MainTabControl`, `AppsCategoriesHost`, `BtnUncheckAllApps`, `TweaksCategoriesHost`, `BtnRefreshState`, `BtnUncheckAllTweaks`, `CmbTweakSort`, `CmbTweakImpact`, `CmbTweakRisk`, `CmbTweakStatus`, `BtnClearTweakFilters`, `TxtTweakCount`, `GameProfilesHost`, `BtnRefreshDiagnostics`, `TxtDiagnosticsSummary`, `DiagnosticsHost`, `BtnResetNetwork`, `BtnRunSfcDism`, `BtnCancelMaintenance`, `BtnClearTemp`, `BtnOpenBackupsDir`, `BtnExportProfile`, `BtnImportProfile`, `BtnExportReport`, `CmbDohProvider`, `BtnApplyDoh`, `BtnUndoDoh`, `BtnWingetUpgrade`, `BtnAdvancedCleanup`, `GridStartupItems`, `BtnEnableStartup`, `BtnDisableStartup`, `BtnRefreshStartup`, `CmbPresets`, `BtnClearSelection`, `TxtSelectionCounter`, `BtnViewApplied`, `BtnUndoSelected`, `BtnUndoAll`, `BtnApplySelected`, `MainProgressBar`, `TxtStatusMessage`, `TxtConsoleOutput`. Novos: `NavList`, `SelectionBar`, `LogPanel`, `BtnToggleLog`, `TxtAppsEmpty`, `TxtTweaksEmpty`, `TxtGamesEmpty`.
2. **Entradas do `$ui`.** `main.ps1` lê estas chaves; mantenha-as em toda entrada:
   - `$ui.AppCheckboxes[id] = @{ CheckBox; Card; Config; SearchText }`
   - `$ui.TweakCheckboxes[id] = @{ CheckBox; Card; BadgeApplied; Config; BlockReason; SearchText; Category; Impact; Risk; RequiresReboot }` (somente linhas visíveis após filtro)
   - `$ui.GameOptCheckboxes[id] = @{ CheckBox; Card; BadgeApplied; ProfileKey; Profile; Config; SearchText }`
   - `Card` passa a ser a própria CheckBox da linha. `BadgeApplied` é o TextBlock "Aplicado".
   - Também: `CustomGameExePaths`, `SuppressConfirmDialog`, `LastStateReport`, `DohSupported`. Novos: `SelectionCount`, `SearchGroups`, `ResponsiveGrids`, `TweakDefinitions` (todas as definições compatíveis), `TweakDefinitionMap` (ID → definição), `TweakStatuses` (ID → Applied/NotApplied/Partial/Unknown), `TweakViewState` (`Sort`, `Impact`, `Risk`, `Status`), `SelectedTweakIds` (HashSet de IDs marcados, inclusive fora do filtro), `TweaksFilteredEmpty`.
3. **Funções públicas** (mesmo nome e parâmetros): `Initialize-OptiKitUi`, `Update-SelectionCounter`, `Select-OptiKitPreset`, `Set-OptiKitSelectionFromProfile`, `Update-OptiKitStateBadges`, `Update-OptiKitDiagnosticsUi`, `Invoke-SearchFilter`, `Show-AppliedChangesDialog`. Novas: `Update-OptiKitTweakPage`, `Set-OptiKitTweakView`, `Update-OptiKitTweakFilterButton`, `Add-OptiKitComboOption`, `Get-OptiKitTweakGroupInfo`. O smoke test e o auditor chamam várias delas.
4. **Testes existentes.** `tests/Build.Tests.ps1` exige que o XAML contenha "Instalar Apps" (`-Match` não diferencia maiúsculas; o título "Instalar apps" atende). `tests/Smoke.Tests.ps1` abre a GUI, aplica o preset `MinimoSeguro`, filtra "Mouse" e fecha.
5. **Build.** `win.ps1` é gerado: nunca edite à mão. Rode `.\build.ps1 -Docs` antes dos testes; ele regrava `src/` em UTF-8 com BOM (sem BOM, o PowerShell 5.1 lê acentos errado e `'Médio'` deixa de casar). O XAML não pode ter linha começando com `'@`. Acentos no XAML e no `.ps1` são convertidos para ASCII pelo build.
6. **Seleção de ajustes.** A seleção vive em `SelectedTweakIds`, não no estado visual da linha. Checkar/desmarcar atualiza o HashSet; `Update-SelectionCounter` conta `SelectedTweakIds.Count` + apps + jogos; `main.ps1` (`executeBatchAction` e exportação de perfil) itera `SelectedTweakIds` e resolve a config por `TweakDefinitionMap`. Assim, mudar ordenação ou filtro não perde seleção; itens marcados e filtrados continuam contando e sendo aplicados/exportados. `Select-OptiKitPreset`, `Set-OptiKitSelectionFromProfile` e "Desmarcar ajustes" limpam o HashSet e chamam `Update-OptiKitTweakPage`.

## 6. Gates (rodar ao final de toda fase, nesta ordem)

```powershell
.\build.ps1 -Docs
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1   # esperado: nada
Invoke-ScriptAnalyzer -Path .\build.ps1 -Settings .\PSScriptAnalyzerSettings.psd1     # esperado: nada
Invoke-Pester -Path .\tests                                                              # esperado: 0 falhas (cerca de 70 s)
powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -OutDir .\scratch\ui-audit\F<n>
```

Depois: um commit por fase, incluindo `win.ps1` e `docs/tweaks.md` regenerados (o CI falha se estiverem desatualizados). Não faça push. Se o modelo aceitar imagem, compare `scratch/ui-audit/F<n>/1240x850_tab<k>.png` com `scratch/ui-redesign/preview/1240x850_tab<k>.png` (gere a prévia com `powershell -ExecutionPolicy Bypass -File .\docs\plans\ui-redesign\preview.ps1`).

## 7. Armadilhas conhecidas (WPF + PowerShell 5.1)

1. `@($hashtable.Lista)` com `List[object]` de hashtables lança "Os tipos de argumento não correspondem". Itere direto: `foreach ($g in $Ui.SearchGroups)`.
2. Elementos nomeados dentro de `ControlTemplate`/`Style` não são achados por `FindName`. Controle nomeado fica sempre no corpo do XAML.
3. O conteúdo de cada aba herda `Foreground` do `TabItem` (preto no Aero2). O estilo implícito de `TabItem` do candidato corrige; não o remova.
4. `StaticResource` só enxerga recursos declarados antes. Na própria `Window`, use `DynamicResource` (já feito para Background/Foreground).
5. `DockPanel`: quem é encaixado primeiro recebe espaço primeiro. Por isso o rodapé encaixa `BtnApplySelected` antes de tudo.
6. Aspas simples não expandem `` `r`n ``. Para quebra de linha em diálogo, use aspas duplas.
7. Não use `$Host`, `$Profile`, `$input`, `$args`, `$Matches`, `$Error` como nome de variável ou parâmetro.
8. Handlers de evento seguem o padrão do arquivo: scriptblock com `.GetNewClosure()`, usando `$ui` capturado; `$this` é o remetente.
9. Nada de hex em `.ps1`: use `Get-OptiKitUiResource -Ui $Ui -Key 'Brush.Text.Secondary'`. Nada de `FontSize` fora de 12/14/16/20 (ícones MDL2 são exceção).
10. Tooltip em controle desabilitado só aparece com `ToolTipService.ShowOnDisabled` (já está no estilo do CheckBox).
11. Evite `SelectionChanged` do TabControl: o evento borbulha de ComboBox e DataGrid internos. Visibilidade por página é feita com `DataTrigger` no XAML.

## 8. Fases

Ordem: F0, F1, F2, F3, F4, F5. Uma fase por agente, sequencial, na mesma cópia de trabalho (todas regeneram `win.ps1`; em paralelo os commits conflitam). Sugestão de branch: `feat/ui-redesign` a partir de `feat/v0.3.0`.

### F0. Correção: detecção do executável por perfil

**Arquivos:** `src/windows/modules/game-engine.ps1`, `config/game-profiles.json`, `tests/GameEngine.Tests.ps1`.

1. Em `config/game-profiles.json`, no objeto `ProfileValorant.executableDetection`, adicione `"riotClientFallback": true`. Não mexa nos outros perfis.
2. Em `Find-GameExecutable`, envolva o bloco que lê `RiotClientInstalls.json` (começa em `if (-not $RiotInstallsPath) {`) em `if ($det.riotClientFallback -eq $true) { ... }`. O resto da função não muda.
3. Em `tests/GameEngine.Tests.ps1`, no teste existente, adicione `riotClientFallback = $true` em `$profileViaJson.executableDetection`.
4. Adicione o teste abaixo dentro do mesmo `Describe`:

```powershell
    It 'Não deve usar o RiotClientInstalls.json para perfis que não são do Riot Client' {
        $fakeRiotDir = Join-Path $TestDrive 'Riot Games\VALORANT\live'
        $fakeBinDir = Join-Path $fakeRiotDir 'ShooterGame\Binaries\Win64'
        New-Item -Path $fakeBinDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeBinDir 'VALORANT-Win64-Shipping.exe') -Value 'dummy-binary'
        $riotInstallsFile = Join-Path $TestDrive 'RiotClientInstalls.json'
        @{ associated_client = @{ ($fakeRiotDir -replace '\\', '/') = 'C:/Riot Games/Riot Client/RiotClientServices.exe' } } |
            ConvertTo-Json | Set-Content -LiteralPath $riotInstallsFile -Encoding UTF8

        $cs2Profile = [pscustomobject]@{
            gameName            = 'Counter-Strike 2'
            executableDetection = [pscustomobject]@{
                defaultPaths     = @('C:\Caminho\Inexistente\cs2.exe')
                registryFallback = $null
            }
        }
        (Find-GameExecutable -ProfileConfig $cs2Profile -RiotInstallsPath $riotInstallsFile) | Should -BeNullOrEmpty
    }
```

**Aceite:** gates verdes; o teste novo falha antes da mudança do passo 2 e passa depois.
**Commit:** `fix(games): restringir fallback do Riot Client ao perfil VALORANT`

### F1. Casca nova (navegação, tokens, rodapé)

**Arquivos:** `src/windows/ui/theme.xaml`, `src/windows/ui/ui-builder.ps1`, `src/windows/main.ps1`.

1. Substitua o conteúdo de `src/windows/ui/theme.xaml` pelo de `docs/plans/ui-redesign/theme.xaml`, sem alterações.
2. Em `ui-builder.ps1`, logo depois da função `ConvertFrom-HexBrush`, cole de `components.ps1` as funções `Get-OptiKitUiResource`, `Format-OptiKitCount`, `Format-OptiKitSelectionCount` e `Format-OptiKitHardwareSummary`.
3. Em `Update-SelectionCounter`, troque o bloco final por:

```powershell
    $Ui.SelectionCount = $count
    if ($Ui.TxtSelectionCounter) {
        $Ui.TxtSelectionCounter.Text = Format-OptiKitSelectionCount -Count $count
    }
```

4. Em `Initialize-OptiKitUi`:
   - No hashtable `$ui = @{ ... }`, acrescente `SelectionCount = 0`.
   - Em `$controlNames`, acrescente `'NavList', 'SelectionBar', 'LogPanel', 'BtnToggleLog', 'TxtAppsEmpty', 'TxtTweaksEmpty', 'TxtGamesEmpty'`.
   - Troque `$ui.TxtHardwareSummary.Text = $Hardware.Summary` por `$ui.TxtHardwareSummary.Text = Format-OptiKitHardwareSummary -Summary $Hardware.Summary`.
   - No item fixo dos presets, troque `'Selecione um Preset...'` por `'Escolher preset'`.
   - Na seção `# 5. Eventos de Busca e Limpeza`, acrescente:

```powershell
    if ($ui.BtnToggleLog -and $ui.LogPanel) {
        $ui.BtnToggleLog.Add_Click({
            $ui.LogPanel.Visibility = if ($ui.LogPanel.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
        }.GetNewClosure())
    }
```

5. Em `main.ps1`, no `$uiTimer.Add_Tick({ ... })`, troque o trecho do início do bloco até a linha `$ui.BtnUndoSelected.IsEnabled = (-not $busy)` por:

```powershell
        $logItem = $null
        $appended = $false
        $lastLevel = $null
        while ($sync.LogQueue.TryDequeue([ref]$logItem)) {
            $ui.TxtConsoleOutput.AppendText($logItem.Formatted + [Environment]::NewLine)
            $appended = $true
            $lastLevel = [string]$logItem.Level
            if (($lastLevel -eq 'ERROR') -and $ui.LogPanel) {
                $ui.LogPanel.Visibility = 'Visible'
            }
        }
        if ($appended) {
            $ui.TxtConsoleOutput.ScrollToEnd()
        }
        if ($lastLevel) {
            $statusBrushKey = switch ($lastLevel) {
                'ERROR' { 'Brush.Danger' }
                'WARN' { 'Brush.Warning' }
                default { 'Brush.Text.Secondary' }
            }
            $ui.TxtStatusMessage.Foreground = $window.FindResource($statusBrushKey)
        }

        $ui.MainProgressBar.Value = [double]$sync.Progress
        $ui.TxtStatusMessage.Text = [string]$sync.StatusText

        $busy = [bool]$sync.IsBusy
        $ui.MainProgressBar.Visibility = if ($busy) { 'Visible' } else { 'Hidden' }
        $hasSelection = ([int]$ui.SelectionCount -gt 0)
        $ui.BtnApplySelected.IsEnabled = ((-not $busy) -and $hasSelection)
        $ui.BtnUndoSelected.IsEnabled = ((-not $busy) -and $hasSelection)
```

As linhas seguintes do timer (`$ui.BtnUndoAll.IsEnabled = ...` em diante) continuam iguais.

**Aceite (além dos gates):**
- `OutOfBounds` vazio.
- `PrimaryAction` = `visivel` nas páginas 0 a 2 e `oculto` nas páginas 3 a 5, nos dois tamanhos.
- `StartupGridHeight` da página 4 em 980x660: 300 ou mais (o protótipo deu 440).
- Páginas 4 e 5: `FontSizes` contido em 12, 14, 16, 20.
- As listas ainda usam os cards antigos dentro da casca nova; isso é esperado até F2.

**Commit:** `style(ui): nova casca com navegação lateral, tokens e rodapé enxuto`

### F2. Linhas limpas para Instalar apps e Ajustes do Windows

**Arquivos:** `src/windows/ui/ui-builder.ps1`, `src/windows/ui/theme.xaml`, `src/windows/main.ps1`.

1. Cole de `components.ps1`, logo depois das funções coladas na F1: `New-OptiKitText`, `New-OptiKitRun`, `Get-OptiKitImpactLabel`, `Get-OptiKitRiskLabel`, `New-OptiKitToolTipContent`, `New-OptiKitItemRow`, `New-OptiKitGroupHeader`, `New-OptiKitResponsiveGrid`, `Update-OptiKitResponsiveGrids`, `Register-OptiKitResponsiveHost`, `Add-OptiKitComboOption`, `Get-OptiKitTweakCategoryOrder`, `Get-OptiKitTweakImpactOrder`, `Get-OptiKitTweakRiskOrder`, `Get-OptiKitTweakStatusOrder`, `Get-OptiKitTweakStatusLabel`, `Get-OptiKitTweakGroupInfo`, `Update-OptiKitTweakFilterButton`, `Update-OptiKitTweakPage`, `Set-OptiKitTweakView`.
2. Substitua a função `Invoke-SearchFilter` inteira pela de `components.ps1`.
3. No hashtable `$ui = @{ ... }` de `Initialize-OptiKitUi`, acrescente `SearchGroups = (New-Object 'System.Collections.Generic.List[object]')`, `ResponsiveGrids = @{}`, `TweakDefinitions = (New-Object 'System.Collections.Generic.List[object]')`, `TweakDefinitionMap = @{}`, `TweakStatuses = @{}`, `TweakViewState = @{ Sort = 'Category'; Impact = 'All'; Risk = 'All'; Status = 'All' }`, `SelectedTweakIds = (New-Object 'System.Collections.Generic.HashSet[string]')` e `TweaksFilteredEmpty = $false`. Em `$controlNames`, acrescente `CmbTweakSort`, `CmbTweakImpact`, `CmbTweakRisk`, `CmbTweakStatus`, `BtnClearTweakFilters` e `TxtTweakCount`.
4. Substitua todo o trecho que vai do comentário `# 1. Construir Aba de Apps` até a linha anterior a `# 3. Construir Aba de Perfis de Jogos` pelo bloco:

```powershell
    foreach ($responsiveHost in @('AppsCategoriesHost', 'TweaksCategoriesHost', 'GameProfilesHost')) {
        Register-OptiKitResponsiveHost -Ui $ui -Container $responsiveHost
    }

    # 1. Instalar apps
    $appCategoryOrder = @(
        'Navegadores',
        'Comunicação',
        'Jogos & Launchers',
        'Runtimes & Utilitários',
        'Desenvolvimento'
    )
    $appProps = @($Configs.Apps.PSObject.Properties)
    $firstGroup = $true

    foreach ($catName in $appCategoryOrder) {
        $catItems = @($appProps | Where-Object { $_.Value.category -eq $catName })
        if ($catItems.Count -eq 0) { continue }

        $header = New-OptiKitGroupHeader -Ui $ui -Text $catName -Count $catItems.Count -First:$firstGroup
        $firstGroup = $false
        $grid = New-OptiKitResponsiveGrid -Ui $ui -Container 'AppsCategoriesHost' -MinColumnWidth 260
        $entries = New-Object 'System.Collections.Generic.List[object]'

        foreach ($ap in $catItems) {
            $appKey = $ap.Name
            $appVal = $ap.Value
            $tip = New-OptiKitToolTipContent -Ui $ui -Title $appVal.name -Body $appVal.description -Footer ('winget: {0}' -f $appVal.winget)
            $row = New-OptiKitItemRow -Ui $ui -Title $appVal.name -Description $appVal.description -ToolTipContent $tip -Tag $appKey
            $row.CheckBox.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $row.CheckBox.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$grid.Children.Add($row.CheckBox)

            $entry = @{
                CheckBox   = $row.CheckBox
                Card       = $row.CheckBox
                Config     = $appVal
                SearchText = ("{0} {1} {2} {3}" -f $appVal.name, $appVal.winget, $appVal.category, $appVal.description).ToLowerInvariant()
            }
            $ui.AppCheckboxes[$appKey] = $entry
            [void]$entries.Add($entry)
        }

        [void]$ui.AppsCategoriesHost.Children.Add($header)
        [void]$ui.AppsCategoriesHost.Children.Add($grid)
        [void]$ui.SearchGroups.Add(@{ Page = 'Apps'; Header = $header; Container = $grid; Entries = $entries })
    }

    # 2. Ajustes do Windows
    $osTag = if ($Hardware.IsWin11) { 'Win11' } else { 'Win10' }
    $tweakProps = @($Configs.WinTweaks.PSObject.Properties)

    foreach ($tp in $tweakProps) {
        $t = $tp.Value
        if ((@($t.osSupport) -notcontains $osTag) -or ($null -ne $t.minBuild -and $Hardware.OsBuild -lt [int]$t.minBuild)) {
            continue
        }

        $definition = @{
            Key            = [string]$tp.Name
            Config         = $t
            Title          = [string]$t.title
            Description    = [string]$t.description
            Rationale      = [string]$t.rationale
            Category       = [string]$t.category
            Impact         = [string]$t.impact
            Risk           = [string]$t.riskLevel
            RequiresReboot = [bool]$t.requiresReboot
            BlockReason    = (Test-OptiKitTweakBlocked -Tweak $t -Hardware $Hardware)
            SearchText     = ("{0} {1} {2} {3} {4} {5}" -f $t.title, $t.description, $t.rationale, $t.category, $t.impact, $t.riskLevel).ToLowerInvariant()
        }
        [void]$ui.TweakDefinitions.Add($definition)
        $ui.TweakDefinitionMap[$tp.Name] = $definition
    }

    Update-OptiKitTweakPage -Ui $ui

    if ($ui.CmbTweakSort) {
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: categoria' -Value 'Category'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: impacto' -Value 'Impact'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: risco' -Value 'Risk'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: reinício' -Value 'Reboot'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: estado' -Value 'Status'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: nome' -Value 'Title'

        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: todos' -Value 'All'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: alto' -Value 'Alto'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: médio' -Value 'Médio'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: baixo' -Value 'Baixo'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: situacional' -Value 'Situacional'

        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: todos' -Value 'All'
        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: seguro' -Value 'Safe'
        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: moderado' -Value 'Moderate'
        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: avançado' -Value 'Advanced'

        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: todos' -Value 'All'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: aplicado' -Value 'Applied'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: não aplicado' -Value 'NotApplied'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: parcial' -Value 'Partial'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: desconhecido' -Value 'Unknown'

        $ui.CmbTweakSort.SelectedIndex = 0
        $ui.CmbTweakImpact.SelectedIndex = 0
        $ui.CmbTweakRisk.SelectedIndex = 0
        $ui.CmbTweakStatus.SelectedIndex = 0

        $ui.CmbTweakSort.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())
        $ui.CmbTweakImpact.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())
        $ui.CmbTweakRisk.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())
        $ui.CmbTweakStatus.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())

        if ($ui.BtnClearTweakFilters) {
            $ui.BtnClearTweakFilters.Add_Click({
                $ui.CmbTweakSort.SelectedIndex = 0
                $ui.CmbTweakImpact.SelectedIndex = 0
                $ui.CmbTweakRisk.SelectedIndex = 0
                $ui.CmbTweakStatus.SelectedIndex = 0
                Set-OptiKitTweakView -Ui $ui
            }.GetNewClosure())
        }
    }

```

5. Ajuste seleção, estado, busca e `main.ps1` para a nova organização:
   - `Update-SelectionCounter`: conte `$Ui.SelectedTweakIds.Count` + apps + jogos (não itere `TweakCheckboxes`).
   - `Select-OptiKitPreset` e `Set-OptiKitSelectionFromProfile`: limpem `SelectedTweakIds`, resolvam cada ID em `TweakDefinitionMap`, ignorem `BlockReason` e chamem `Update-OptiKitTweakPage` no fim.
   - `Update-OptiKitStateBadges`: grave `$Ui.TweakStatuses` a partir de `StateReport.Tweaks`; se `TweakViewState.Sort -eq 'Status'` ou `Status -ne 'All'`, reconstrua a página; caso contrário, atualize os badges visíveis.
   - Handler de `BtnUncheckAllTweaks`: limpe `SelectedTweakIds`, chame `Update-OptiKitTweakPage` e `Update-SelectionCounter`.
   - `Invoke-SearchFilter`: quando `TweaksFilteredEmpty` e a busca estiver vazia, mantenha a mensagem "Nenhum ajuste com esses filtros.".
   - `Show-AppliedChangesDialog`: liste os ajustes aplicados por `TweakStatuses` + `TweakDefinitionMap`, não por `TweakCheckboxes`, para não omitir itens filtrados.
   - Em `main.ps1`, a exportação de perfil e o `executeBatchAction` devem iterar `$ui.SelectedTweakIds` e resolver a config por `$ui.TweakDefinitionMap[$id].Config` (não por `TweakCheckboxes`, que contém só linhas visíveis).
6. Em `docs/plans/ui-redesign/preview.ps1`, adicione `CmbTweakSort`, `CmbTweakImpact`, `CmbTweakRisk`, `CmbTweakStatus`, `BtnClearTweakFilters` e `TxtTweakCount` ao `FindName`, preencha os combos com `Add-OptiKitComboOption` e defina `TxtTweakCount.Text = '60 ajustes'`.
7. Atualize o construtor da página de Ajustes no XAML: três linhas (cabeçalho, barra de organização, lista) e os controles `CmbTweakSort`, `CmbTweakImpact`, `CmbTweakRisk`, `CmbTweakStatus`, `BtnClearTweakFilters`, `TxtTweakCount` (o `theme.xaml` candidato já está pronto).

**Aceite (além dos gates):**
- Páginas 0 e 1: `AuthoredBorders` até 4 e `FontSizes` contido em 12, 14, 16, 20.
- `OffPaletteWhere` não cita `AppsCategoriesHost` nem `TweaksCategoriesHost`.
- Ainda é esperado ver em `EmojiTexts` o "● Aplicado" e os "🎮" de Jogos e as setas de Diagnóstico: saem na F3.
- Ordenação: "categoria" mostra os 6 grupos na ordem fixa; "impacto" mostra Impacto alto/médio/baixo/Situacional; "risco" mostra avançado/moderado/seguro; "estado" mostra Aplicado/Desconhecido antes do primeiro refresh; "nome" mostra "Todos os ajustes".
- Filtros: `Impacto: alto` deixa **4 de 60**; `Risco: avançado` deixa **2 de 60**; combinar filtros e busca mantém a mensagem de vazio correta.
- Seleção: com filtro `Impacto: alto`, aplicar o preset `GamerRecomendado` seleciona **23** tweaks; o rodapé mostra **28 itens selecionados** (23 tweaks + 4 apps + 1 jogo) e só **4** linhas visíveis. Limpar o filtro mostra as 23 marcadas; aplicar/exportar usa todos os 23.
- Em 980x660 a barra de organização pode quebrar em duas linhas, mas nenhum controle fica fora da janela (`OutOfBounds` vazio).
- Manual (opcional): buscar "xyzabc" mostra "Nenhum resultado para..." e esconde todos os grupos; apagar a busca restaura tudo.

**Commit:** `style(ui): linhas limpas e organização dos ajustes`

### F3. Jogos e Diagnóstico sem cards

**Arquivos:** `src/windows/ui/ui-builder.ps1`, `config/game-profiles.json`.

1. Cole de `components.ps1`, logo depois de `Register-OptiKitResponsiveHost`: `Get-OptiKitDiagnosticVisual`, `Format-OptiKitDiagnosticsSummary`, `New-OptiKitDiagnosticRow`, `Get-OptiKitGameIdentity`, `New-OptiKitGameSection`, `Set-OptiKitGameExeLabel`.
2. Em `config/game-profiles.json`, adicione `shortName` e `accent` em cada perfil: VALORANT (`VAL`, `Valorant`), CS2 (`CS2`, `CS2`), UE5 (`UE5`, `UE5`), Ferramentas Globais (`GLB`, `Global`). `accent` mapeia para `Brush.Danger`, `Brush.Warning`, `Brush.Accent` e `Brush.Success`; o fallback é `Brush.Text.Tertiary`.
3. Substitua todo o trecho de `# 3. Construir Aba de Perfis de Jogos` até a linha anterior a `# 4. Popular ComboBox de Presets` por:

```powershell
    # 3. Jogos
    $firstSection = $true
    foreach ($gp in $Configs.GameProfiles.PSObject.Properties) {
        $profKey = $gp.Name
        $prof = $gp.Value

        $detectedExe = $null
        if ($prof.status -eq 'active') {
            $detectedExe = Find-GameExecutable -ProfileConfig $prof
            if ($detectedExe) {
                $ui.CustomGameExePaths[$profKey] = $detectedExe
            }
        }

        $section = New-OptiKitGameSection -Ui $ui -ProfileKey $profKey -GameProfile $prof -ExePath $detectedExe -First:$firstSection
        $firstSection = $false

        if ($section.BrowseButton) {
            $exeText = $section.ExeText
            $btnBrowse = $section.BrowseButton
            $btnBrowse.Add_Click({
                $dlg = New-Object System.Windows.Forms.OpenFileDialog
                $dlg.Filter = 'Executáveis (*.exe)|*.exe'
                $dlg.Title = ("Selecionar executável de {0}" -f $prof.gameName)
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $ui.CustomGameExePaths[$profKey] = $dlg.FileName
                    Set-OptiKitGameExeLabel -Ui $ui -Label $exeText -Button $btnBrowse -ExePath $dlg.FileName
                }
            }.GetNewClosure())
        }

        $entries = New-Object 'System.Collections.Generic.List[object]'
        foreach ($opt in @($prof.optimizations)) {
            $tip = New-OptiKitToolTipContent -Ui $ui -Title $opt.title -Body $opt.description -DetailLabel 'Justificativa técnica' -Detail $opt.rationale -Footer (Get-OptiKitImpactLabel -Impact $opt.impact)
            $row = New-OptiKitItemRow -Ui $ui -Title $opt.title -Description $opt.description -Impact $opt.impact -Risk $opt.riskLevel -ToolTipContent $tip -Tag $opt.id
            $row.CheckBox.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $row.CheckBox.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$section.Grid.Children.Add($row.CheckBox)

            $entry = @{
                CheckBox     = $row.CheckBox
                Card         = $row.CheckBox
                BadgeApplied = $row.BadgeApplied
                ProfileKey   = $profKey
                Profile      = $prof
                Config       = $opt
                SearchText   = ("{0} {1} {2} {3}" -f $prof.gameName, $opt.title, $opt.description, $opt.rationale).ToLowerInvariant()
            }
            $ui.GameOptCheckboxes[$opt.id] = $entry
            [void]$entries.Add($entry)
        }
        if ($entries.Count -eq 0) {
            $section.Grid.Visibility = 'Collapsed'
        }

        [void]$ui.GameProfilesHost.Children.Add($section.Panel)
        [void]$ui.SearchGroups.Add(@{ Page = 'Games'; Header = $null; Container = $section.Panel; Entries = $entries })
    }

```

3. Substitua a função `Update-OptiKitDiagnosticsUi` inteira por:

```powershell
function Update-OptiKitDiagnosticsUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][array]$Items
    )

    if (-not $Ui.DiagnosticsHost) {
        return
    }
    $Ui.DiagnosticsHost.Children.Clear()

    if ($Ui.TxtDiagnosticsSummary) {
        $Ui.TxtDiagnosticsSummary.Text = Format-OptiKitDiagnosticsSummary -Items $Items
    }

    $ordered = for ($i = 0; $i -lt $Items.Count; $i++) {
        [pscustomobject]@{
            Item  = $Items[$i]
            Order = (Get-OptiKitDiagnosticVisual -Status $Items[$i].Status).Order
            Index = $i
        }
    }
    $sorted = @($ordered | Sort-Object Order, Index)

    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ($i -gt 0) {
            $divider = New-Object System.Windows.Controls.Border
            $divider.Style = Get-OptiKitUiResource -Ui $Ui -Key 'Divider'
            [void]$Ui.DiagnosticsHost.Children.Add($divider)
        }
        [void]$Ui.DiagnosticsHost.Children.Add((New-OptiKitDiagnosticRow -Ui $Ui -Item $sorted[$i].Item))
    }
}
```

**Aceite (além dos gates):**
- `OffPalette` vazio e `EmojiTexts` vazio no relatório inteiro.
- Páginas 2 e 3: `AuthoredBorders` até 4 e `FontSizes` contido em 12, 14, 16, 20.
- Jogos: cada perfil tem tile com monograma e cor própria (VAL vermelho, CS2 âmbar, UE5 ciano, GLB verde), contagem de otimizações, engine/anti-cheat e status à direita. O status alterna entre "Executável detectado" (verde), "Executável não encontrado" (âmbar) e "Ferramentas globais" (terciário).
- Jogos: CS2 e UE5 mostram "Executável não encontrado no caminho padrão." (depende de F0) e o botão "Selecionar executável" troca o texto para "Executável: arquivo.exe" depois da escolha.

**Commit:** `style(ui): identidade por jogo e diagnóstico sem cards`

### F4. Texto e limpeza de código

**Arquivos:** `src/windows/ui/ui-builder.ps1`, `src/windows/main.ps1`, `src/windows/ui/theme.xaml`.

1. Remova de `ui-builder.ps1` as funções que ficaram sem uso: `New-OptiKitBadge`, `Get-ImpactColors`, `Get-RiskColors`, `Get-DiagnosticColors` e, se não houver mais chamadas, `ConvertFrom-HexBrush`. Confirme com `Select-String -Path .\src\windows -Pattern 'New-OptiKitBadge|Get-ImpactColors|Get-RiskColors|Get-DiagnosticColors|ConvertFrom-HexBrush' -Recurse` (esperado: nenhuma ocorrência).
2. Remova de `theme.xaml` o estilo transitório `ActionButtonStyle` (e o comentário acima dele) depois de confirmar que nada chama `FindResource('ActionButtonStyle')`.
3. Em `Show-AppliedChangesDialog`: `'=== AJUSTES ATIVOS DETECTADOS NA MÁQUINA ==='` vira `'Ajustes ativos nesta máquina:'`; `'Nenhum tweak do catálogo está marcado como aplicado no momento.'` vira `'Nenhum ajuste do catálogo está aplicado no momento.'`; `'=== HISTÓRICO DE CAPTURA PARA REVERSÃO (state.json) ==='` vira `'Registrado para reversão (state.json):'`; o título vira `'Alterações aplicadas'`.
4. Em `main.ps1`, títulos e textos de diálogo:

| Local | Novo texto |
|---|---|
| Erro ao importar perfil (título) | `'Importar perfil'` |
| `BtnUndoAll` | mensagem `("Reverter {0}?`r`n`r`nIsso desfaz ajustes, otimizações de jogos, plano de energia, USB, DirectX, DNS e Windows Update registrados pelo OptiKit." -f (Format-OptiKitCount -Count $state.Count -Singular 'alteração registrada' -Plural 'alterações registradas'))`; título `'Reverter tudo'` |
| `BtnApplyDoh` | mensagem `("Aplicar DNS over HTTPS com {0}?`r`n`r`nO DNS dos adaptadores físicos ativos será alterado. O DNS atual fica salvo para reverter." -f $providerName)`; título `'Aplicar DNS over HTTPS'` |
| `BtnUndoDoh` | título `'Reverter DNS over HTTPS'` |
| `BtnWingetUpgrade` | mensagem em **aspas duplas**: `"Atualizar todos os aplicativos gerenciados pelo winget?`r`n`r`nPode demorar, e alguns aplicativos podem pedir reinicialização."`; título `'Atualizar aplicativos'` |
| `BtnAdvancedCleanup` | título `'Limpeza avançada'` |
| Confirmação em lote | `$modeTitle` = `'Aplicar selecionados'` ou `'Reverter selecionados'`; linhas `"• Ajustes do Windows: ..."`, `"• Otimizações de jogos: ..."`, `"• Aplicativos (winget): ..."`; reinício: `"Exigem reinicialização:"`; simulação: `"Modo simulação ativo: nada será gravado no Windows. Para aplicar de verdade, execute o win.ps1 sem -DryRun."`; título `'Confirmar'` |
| Badge de atualização | `("Versão {0} disponível" -f $update.Version)` |

5. Verificação de emoji e hex:

```powershell
Get-ChildItem .\src\windows -Recurse -Include *.ps1, *.xaml |
    Select-String -Encoding UTF8 -Pattern '[\u2190-\u21FF\u2300-\u23FF\u2460-\u27BF\u2B00-\u2BFF\uFE0F]|[\uD83C-\uD83E][\uDC00-\uDFFF]'   # esperado: nada
Select-String -Path .\src\windows\ui\ui-builder.ps1, .\src\windows\main.ps1 -Pattern "'#[0-9A-Fa-f]{6}'"                          # esperado: nada
```

**Aceite:** gates verdes; as duas verificações acima vazias; `report.json` igual ao da F3 nos critérios (nenhuma regressão).
**Commit:** `refactor(ui): textos claros e remoção dos helpers de badge`

### F5. Polimento e trava de regressão

**Arquivos:** `src/windows/ui/ui-builder.ps1`, `tests/UiAudit.Tests.ps1` (novo), `.github/workflows/ci-build.yml`.

1. Atalhos: em `Initialize-OptiKitUi`, antes do `return $ui`, acrescente:

```powershell
    $Window.Add_PreviewKeyDown({
        param($keySender, $keyArgs)
        if (($keyArgs.Key -eq 'F') -and ([System.Windows.Input.Keyboard]::Modifiers -eq 'Control')) {
            [void]$ui.TxtSearchBox.Focus()
            $ui.TxtSearchBox.SelectAll()
            $keyArgs.Handled = $true
        }
        elseif (($keyArgs.Key -eq 'Escape') -and $ui.TxtSearchBox.IsKeyboardFocused -and $ui.TxtSearchBox.Text) {
            $ui.TxtSearchBox.Text = ''
            $keyArgs.Handled = $true
        }
    }.GetNewClosure())
```

2. Busca a partir de páginas sem lista: troque o handler `TxtSearchBox.Add_TextChanged` por:

```powershell
        $ui.TxtSearchBox.Add_TextChanged({
            $counts = Invoke-SearchFilter -Ui $ui -Query $ui.TxtSearchBox.Text
            if ((-not [string]::IsNullOrWhiteSpace($ui.TxtSearchBox.Text)) -and ($ui.MainTabControl.SelectedIndex -gt 2)) {
                $pages = @('Apps', 'Tweaks', 'Games')
                $target = @(0, 1, 2) | Where-Object { $counts[$pages[$_]] -gt 0 } | Select-Object -First 1
                if ($null -ne $target) {
                    $ui.MainTabControl.SelectedIndex = $target
                }
            }
        }.GetNewClosure())
```

3. Crie `tests/UiAudit.Tests.ps1`:

```powershell
# Trava de regressão visual: roda tools/ui-audit.ps1 com dados sintéticos e confere as metas do redesign

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $outDir = Join-Path $TestDrive 'ui-audit'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $psExe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $script:RepoRoot 'tools\ui-audit.ps1') -NoPng -OutDir $outDir | Out-Null
    $script:ExitCode = $LASTEXITCODE
    $script:Report = Get-Content -LiteralPath (Join-Path $outDir 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe 'Auditoria de layout da GUI (tools/ui-audit.ps1)' {
    It 'Deve renderizar todas as páginas sem erro' {
        $script:ExitCode | Should -Be 0
    }

    It 'Deve usar somente a escala tipográfica 12/14/16/20' {
        @($script:Report.FontSizes | Where-Object { $_ -notin @(12, 14, 16, 20) }) | Should -BeNullOrEmpty
    }

    It 'Deve usar somente cores da paleta definida no theme.xaml' {
        $script:Report.OffPalette | Should -BeNullOrEmpty
    }

    It 'Não deve usar emoji como ícone' {
        $script:Report.EmojiTexts | Should -BeNullOrEmpty
    }

    It 'Não deve cortar controles fixos em nenhum tamanho' {
        $script:Report.OutOfBounds | Should -BeNullOrEmpty
    }

    It 'Deve manter Aplicar visível nas páginas de lista e oculto nas demais' {
        foreach ($size in $script:Report.Sizes) {
            foreach ($tab in $size.Tabs) {
                $expected = if ($tab.Index -le 2) { 'visivel' } else { 'oculto' }
                $tab.PrimaryAction | Should -Be $expected -Because ("{0}, página {1}" -f $size.Size, $tab.Index)
            }
        }
    }

    It 'Deve dar altura útil à tabela de inicialização no tamanho mínimo' {
        $minSize = $script:Report.Sizes | Where-Object { $_.Size -eq '980x660' }
        $startup = $minSize.Tabs | Where-Object { $null -ne $_.StartupGridHeight }
        $startup.StartupGridHeight | Should -BeGreaterOrEqual 300
    }

    It 'Não deve usar mais de 4 contornos autorais por página' {
        foreach ($size in $script:Report.Sizes) {
            foreach ($tab in $size.Tabs) {
                $tab.AuthoredBorders | Should -BeLessOrEqual 4 -Because ("{0}, página {1}" -f $size.Size, $tab.Index)
            }
        }
    }
}
```

4. Em `.github/workflows/ci-build.yml` (quebras de linha LF), no passo do PSScriptAnalyzer, acrescente `Invoke-ScriptAnalyzer -Path .\tools -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` como terceira linha dentro de `$issues = @( ... )`.
5. Opcional: gere `powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -Size 1240x850 -OutDir .\scratch\shot`, copie `scratch\shot\1240x850_tab1.png` para `docs/screenshot.png` e descomente o bloco de screenshot no topo do `README.md`. Use os dados sintéticos (padrão) para não expor caminhos pessoais.

**Aceite:** gates verdes com o teste novo incluído; Ctrl+F foca a busca; Esc limpa; digitar na busca estando em Diagnóstico leva à primeira página com resultado.
**Commit:** `test(ui): auditoria de layout no CI e atalhos de busca`

## 9. Checklist final (impeccable: polish)

- [ ] Primeira olhada em cada página revela o principal (lista), o secundário (subtítulo, ações discretas) e a ação primária (rodapé).
- [ ] Um único botão primário visível por vez; "Reverter tudo" só em Manutenção.
- [ ] Hover, foco por teclado (contorno ciano), desabilitado e vazio existem em todos os controles interativos.
- [ ] Item bloqueado mostra "Bloqueado" e o motivo no tooltip, mesmo desabilitado.
- [ ] Texto de interface em português, sem emoji, sem Title Case, sem "(OptiKit)" nos diálogos.
- [ ] Nenhum hex fora do bloco de tokens; nenhum tamanho de fonte fora da escala.
- [ ] Ajustes: organizar por categoria/impacto/risco/reinício/estado/nome; filtros combináveis; "Limpar filtros" só com filtro ativo; seleção sobrevive à troca de ordenação/filtro.
- [ ] 980x660: nada cortado, tabela de inicialização utilizável, Aplicar visível.
- [ ] Smoke test, Pester completo, PSScriptAnalyzer e build determinístico verdes.

## 10. Ensaio do plano

O plano foi executado de ponta a ponta (F0 a F5) num worktree descartável a partir de `90b14a0`, copiando os blocos de código desta página e as funções de `components.ps1` exatamente como estão. Resultado:

- `.\build.ps1 -Docs`: OK. PSScriptAnalyzer em `src`, `build.ps1` e `tools`: 0 problemas.
- Verificações da F4 (emoji, hex, helpers mortos): vazias.
- Pester completo: 79 de 79 (69 existentes, 1 novo da F0, 8 de `UiAudit.Tests.ps1`, 1 de identidade dos jogos) em 87 s.
- Auditor com dados reais: fontes 12/14/16/20, 15 cores e todas da paleta, nenhum emoji, nada fora da janela, 2 contornos por página, tabela de inicialização com 440 px em 980x660.
- Jogos: VAL/CS2/UE5/GLB com tile, cor de identidade, contagem de otimizações, engine/anti-cheat e status próprio (detectado, não encontrado ou ferramentas globais).
- Ordenação/filtros validados no ensaio: 6 grupos por categoria; 4 por impacto; 4 por risco; `Impacto: alto` = 4 de 60; `Risco: avançado` = 2 de 60; estado Aplicado/Desconhecido; nome = "Todos os ajustes". Com filtro de impacto alto, o preset `GamerRecomendado` marcou 23 tweaks (4 visíveis) e o rodapé mostrou 28 itens; a seleção sobreviveu à troca de ordenação.

Se um passo não bater com o código (marcador não encontrado, função com outro nome), pare e reporte em vez de improvisar: o código-alvo é o de `90b14a0` mais as fases anteriores.

## 11. Prompt sugerido por fase

```
Leia docs/plans/ui-redesign.md, seções 4, 5, 6 e 7. Execute somente a fase <F?> da seção 8, passo a passo e na ordem.
Altere apenas os arquivos listados na fase. Não edite win.ps1 à mão. Não invente layout: use os artefatos de docs/plans/ui-redesign/.
Ao terminar, rode os gates da seção 6, cole o resumo impresso pelo tools/ui-audit.ps1 e confira cada critério de aceite da fase.
Se um critério falhar, corrija antes de commitar. Faça um único commit com a mensagem indicada. Não faça push.
```
