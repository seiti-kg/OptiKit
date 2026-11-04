# Ajustes rejeitados (placebo ou prejudiciais)

Este documento registra tweaks populares que **não** entram no OptiKit por falta de efeito mensurável, risco de regressão ou conflito com o scheduler/timer moderno do Windows. A lista é parte da política anti-placebo do projeto.

| Tweak popular | Veredito | Motivo técnico |
|---|---|---|
| `bcdedit useplatformclock` / desligar HPET | Rejeitado | O Windows já usa TSC como timer principal. Forçar HPET/`useplatformclock` deixa a leitura do timer mais lenta. |
| `Win32PrioritySeparation` | Rejeitado | Não há ganho de FPS mensurável em Windows 11; o scheduler já prioriza a janela em primeiro plano. |
| `TCPNoDelay` / `TcpAckFrequency` (Nagle) | Rejeitado | Jogos modernos usam UDP; a alteração não afeta o tráfego de gameplay e pode piorar throughput. |
| Timer resolution global de 0,5 ms | Rejeitado | Desde o Windows 10 2004 o timer é por processo. Forçar globalmente só aumenta consumo de energia. |
| Desativar o pagefile | Rejeitado | Causa falhas por falta de memória e instabilidade em jogos com picos de alocação. |
| Mudar o número de núcleos no `msconfig` | Rejeitado | Limita a CPU em vez de liberar recursos; o Windows já gerencia todos os núcleos. |
| Desativar Windows Update ou Defender por completo | Rejeitado | Quebra updates cumulativos, Store, Xbox e a superfície de segurança do sistema. |
| Desativar SysMain em SSD | Rejeitado | Ganho nulo em SSD; o serviço auxilia prefetch e inicialização de apps. |
| “Debloat” destrutivo de serviços de rede/áudio | Rejeitado | Pode quebrar jogos, anti-cheats e periféricos; o OptiKit só altera serviços com efeito documentado. |

## Regra de admissão

Um tweak só entra no catálogo se tiver:

1. Efeito funcional ou mensurável documentado.
2. Risco classificado (`Safe`, `Moderate`, `Advanced`).
3. Reversão via `state.json` ou valor `originalValue`.
4. Justificativa técnica no campo `rationale` do `config/win-tweaks.json`.
