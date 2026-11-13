# Uso e automação

## Requisitos

- Windows 11 ou Windows 10 22H2 (suporte em melhor esforço).
- PowerShell 5.1+ (o modo GUI usa Windows PowerShell/WPF).
- Administrador para aplicar alterações; o UAC é solicitado pelo script.
- Internet para o one-liner, para o Winget e para a checagem de nova versão.

## Execução rápida

Abra o PowerShell como Administrador:

```powershell
irm https://raw.githubusercontent.com/seiti-kg/OptiKit/main/win.ps1 | iex
```

O comando sempre baixa o `win.ps1` da branch `main`. Para uma versão fixa, baixe o `win.ps1` de uma release e execute localmente.

## Execução local e simulação

Depois de clonar o repositório e compilar:

```powershell
.\build.ps1 -Docs
powershell -ExecutionPolicy Bypass -File .\win.ps1 -DryRun
```

`-DryRun` registra no log o que seria alterado, sem aplicar nada. Para abrir a interface sem simulação:

```powershell
powershell -ExecutionPolicy Bypass -File .\win.ps1
```

## Interface

A janela tem dez abas:

1. **Instalar apps** — catálogo Winget com seleção e instalação silenciosa.
2. **Ajustes do Windows** — busca, filtros, estado atual e aplicação/reversão por seleção.
3. **Jogos** — perfis por título, detecção de executável e ferramentas globais.
4. **Segundo plano** — apps com janela; suspender e retomar processos selecionados.
5. **Desinstalar** — programas Win32 e pacotes Appx instalados.
6. **Duplicados** — localizador por tamanho, fingerprint e SHA-256 com envio para a Lixeira.
7. **Drivers** — inventário, links oficiais e backup via `pnputil`.
8. **Discos** — saúde, porcentagem, temperatura, desgaste e detalhes de cada HD/SSD.
9. **Diagnóstico** — leitura de hardware, BIOS, estabilidade, Defender e recomendações para GPU híbrida/RAM/HAGS.
10. **Inicialização** — programas de startup compatíveis com o Gerenciador de Tarefas.
11. **Manutenção** — reset de rede/DNS, SFC/DISM, reparo do app de Configurações, limpeza, reboot para UEFI e atualização via Winget.

Ações globais:

- **Aplicar selecionados** e **Reverter selecionados** usam o estado capturado.
- **Reverter tudo** desfaz ajustes, jogos, energia, USB, DirectX, DNS e Windows Update registrados pelo OptiKit.
- **Exportar relatório** gera um HTML com resumo da sessão e diagnóstico.
- **Atualizar apps** executa `winget upgrade --all`.
- **Reverter DNS** restaura os servidores DNS originais.

### Segundo plano

Selecione um app com janela e use **Suspender**. O processo fica congelado até **Retomar**; **Retomar todos** libera todos os apps suspensos. O OptiKit retoma os apps automaticamente ao fechar. Serviços, shell, anti-cheats e o próprio OptiKit são bloqueados.

### Desinstalar

A aba lista programas Win32 e pacotes Appx instalados. Use a busca, selecione um item e confirme em **Desinstalar**. O comando oficial do programa é executado; o OptiKit não remove sobras manualmente.

### Duplicados

Escolha uma pasta de dados, o tamanho mínimo e clique em **Escanear**. Marque os arquivos que deseja remover e clique em **Mover para Lixeira**. É obrigatório manter pelo menos uma cópia de cada grupo; pastas de sistema são bloqueadas.

### Drivers

A aba **Drivers** lista dispositivos relevantes com versão, data, fabricante e estado. Selecione um item e use **Abrir site** para ir ao site oficial (AMD, NVIDIA ou Intel). Dispositivos sem fabricante mapeado mostram um aviso para usar o Windows Update. **Ver atualizações** consulta o Windows Update e lista as atualizações de driver pendentes com versão atual/disponível, data, tamanho e necessidade de reinício; nada é instalado automaticamente. **Atualizações opcionais** abre a página correspondente do Windows para seleção manual. **Backup** exporta os drivers via `pnputil /export-driver` para uma pasta escolhida.

### Discos

A aba **Discos** mostra uma tabela com os discos físicos: modelo, tipo, capacidade, saúde, **Saúde %** (`100% - desgaste`), temperatura, desgaste, horas ligado e ciclos. Selecione um disco para ver firmware, serial, barramento, erros não corrigidos e localização. Os dados vêm de `Get-PhysicalDisk` e dos contadores de confiabilidade do Windows; quando o driver não expõe um contador, o campo aparece como `—`. Use **Atualizar** para consultar novamente. A verificação é somente leitura e não altera drivers.

### Reparar as Configurações do Windows

Se `Win+I` não abrir o app de Configurações, use **Manutenção > Configurações do Windows > Reparar**. A ação re-registra `Microsoft.UI.Xaml.CBS` e `windows.immersivecontrolpanel` para o usuário atual. Se o manifesto do app não existir, execute primeiro o reparo SFC/DISM.

## Modo desatendido

O modo desatendido não abre a interface. Sem `-Apply`, ele apenas imprime o que seria aplicado.

### Aplicar um preset

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/seiti-kg/OptiKit/main/win.ps1))) -Preset GamerRecomendado -Apply -Silent
```

Presets disponíveis: `GamerRecomendado`, `MinimoSeguro`, `PerfilValorant` e `Notebook`.

### Importar um perfil exportado

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/seiti-kg/OptiKit/main/win.ps1))) -Config .\optikit-profile.json -Apply -Silent
```

O perfil pode ser exportado pela própria interface e contém tweaks, otimizações de jogos, apps e preset de origem.

### Códigos de saída

| Código | Significado |
|---|---|
| `0` | Sucesso, incluindo itens ignorados por hardware/sem efeito. |
| `1` | Uma ou mais operações falharam. |
| `2` | Erro de uso, preset inexistente ou perfil inválido. |

O log da execução fica em `%ProgramData%\optikit\logs\optikit_<sessão>.log`.

## Dados e backups

| Caminho | Conteúdo |
|---|---|
| `%ProgramData%\optikit\state.json` | Estado original dos ajustes aplicados, usado pelo Undo. |
| `%ProgramData%\optikit\backups\` | Exportações `.reg` das chaves afetadas. |
| `%ProgramData%\optikit\logs\` | Logs por sessão. |

O `state.json` é gravado de forma atômica. Chaves de registro são exportadas antes da alteração. A criação de Ponto de Restauração é tentada antes de aplicar uma seleção, mas depende da Proteção do Sistema estar habilitada.

## Limitações operacionais

- A remoção de Appx é revertida reinstalando o pacote via Store ID; o pacote precisa existir na Store e os dados locais podem não voltar.
- Ajustes aplicados por outros programas, GPOs ou VPNs podem sobrescrever o estado do OptiKit.
- O one-liner aponta para `main`; para reprodutibilidade, use uma release fixa.
- O projeto não possui instalador assinado nem auto-update; o Windows pode exibir aviso do SmartScreen/antivírus.

Consulte [funcionalidades](features.md), [diretrizes técnicas](guidelines.md) e o [catálogo técnico](tweaks.md).
