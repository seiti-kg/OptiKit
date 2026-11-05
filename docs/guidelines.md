# Diretrizes técnicas

## Zero Placebo

Todos os ajustes possuem classificação de impacto, nível de risco e justificativa técnica documentada nos arquivos JSON. Ajustes situacionais ficam desmarcados por padrão nos presets. Tweaks sem efeito mensurável ou com risco de regressão ficam registrados em [rejected.md](rejected.md).

## Reversibilidade

Antes de qualquer alteração:

- O estado original da máquina é salvo em `%ProgramData%\optikit\state.json`.
- As chaves de registro afetadas são exportadas (`.reg`) em `%ProgramData%\optikit\backups\`.
- O script tenta criar um Ponto de Restauração do Sistema.

A gravação do `state.json` é atômica. O Ponto de Restauração é **best effort**: ele só é criado quando a Proteção do Sistema está habilitada e a operação é permitida; caso contrário, os backups `.reg` e o `state.json` continuam sendo a camada de reversão.

### Limitações de reversão

- **Appx:** a reinstalação usa o Store ID via Winget. O pacote precisa estar disponível na Store e os dados locais do aplicativo podem não ser restaurados.
- **Escopo:** o Undo cobre apenas o que foi registrado pelo OptiKit. Alterações posteriores feitas por outros programas, GPOs ou VPNs podem sobrescrever o estado.
- **Estado perdido:** sem o `state.json`, a reversão automática não conhece os valores originais; os backups `.reg` podem ser importados manualmente.
- **Falhas parciais:** o “Reverter tudo” continua pelas entradas seguintes e retorna código `1` quando alguma reversão falha.

## Suporte a Windows

- Windows 11 é o alvo principal.
- Windows 10 22H2 é suportado em melhor esforço.
- Ajustes exclusivos de Windows 11 são ocultados na interface e ignorados automaticamente no modo desatendido quando o sistema não atende aos requisitos.
- Ajustes com `minBuild` ou hardware incompatível são bloqueados antes da execução.

## Segurança anti-cheat

- Bloqueio estático e em runtime contra modificações nos serviços `vgc`/`vgk.sys`, TPM 2.0, Secure Boot ou desativação global de VBS.
- Ajustes avançados como HVCI exigem confirmação manual explícita.
- Os guardrails reduzem o risco de conflito, mas **não garantem** compatibilidade com todos os anti-cheats ou versões futuras.

## Orientação a dados

- A interface WPF e os catálogos são gerados dinamicamente a partir dos arquivos em `config/`.
- O `build.ps1` empacota `src/` + `config/` no `win.ps1` e gera [tweaks.md](tweaks.md).
- Não edite `win.ps1` diretamente; ele é gerado pelo build.

## Privacidade

O OptiKit não envia telemetria própria. A checagem de nova versão consulta a API pública do GitHub, e as instalações/atualizações usam o Winget. Logs e relatórios ficam locais, em `%ProgramData%\optikit` ou no caminho escolhido ao exportar o HTML.
