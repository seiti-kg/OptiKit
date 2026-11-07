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

A janela tem seis abas:

1. **Instalar apps** — catálogo Winget com seleção e instalação silenciosa.
2. **Ajustes do Windows** — busca, filtros, estado atual e aplicação/reversão por seleção.
3. **Jogos** — perfis por título, detecção de executável e ferramentas globais.
4. **Diagnóstico** — leitura de hardware, BIOS, discos, estabilidade, Defender e recomendações para GPU híbrida/RAM/HAGS.
5. **Inicialização** — programas de startup compatíveis com o Gerenciador de Tarefas.
6. **Manutenção** — reset de rede/DNS, SFC/DISM, reparo do app de Configurações, limpeza, reboot para UEFI e atualização via Winget.

Ações globais:

- **Aplicar selecionados** e **Reverter selecionados** usam o estado capturado.
- **Reverter tudo** desfaz ajustes, jogos, energia, USB, DirectX, DNS e Windows Update registrados pelo OptiKit.
- **Exportar relatório** gera um HTML com resumo da sessão e diagnóstico.
- **Atualizar apps** executa `winget upgrade --all`.
- **Reverter DNS** restaura os servidores DNS originais.

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
