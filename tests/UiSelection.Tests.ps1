# Regressão: o botão Limpar chama Select-OptiKitPreset com PresetKey vazio

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\ui\ui-builder.ps1')
}

Describe 'Limpar seleção (Select-OptiKitPreset com PresetKey vazio)' {
    It 'Aceita PresetKey vazio e desmarca tweaks, apps e otimizações de jogo' {
        $ui = @{
            SuppressConfirmDialog = $false
            SelectedTweakIds      = (New-Object 'System.Collections.Generic.HashSet[string]')
            AppCheckboxes         = @{ App1 = [pscustomobject]@{ CheckBox = [pscustomobject]@{ IsChecked = $true } } }
            GameOptCheckboxes     = @{ Opt1 = [pscustomobject]@{ CheckBox = [pscustomobject]@{ IsChecked = $true } } }
            TweaksCategoriesHost  = $null
            TxtSelectionCounter   = [pscustomobject]@{ Text = '3 itens selecionados' }
        }
        [void]$ui.SelectedTweakIds.Add('Tweak1')

        { Select-OptiKitPreset -Ui $ui -PresetKey '' } | Should -Not -Throw

        $ui.SelectedTweakIds.Count | Should -Be 0
        $ui.AppCheckboxes['App1'].CheckBox.IsChecked | Should -BeFalse
        $ui.GameOptCheckboxes['Opt1'].CheckBox.IsChecked | Should -BeFalse
        $ui.SelectionCount | Should -Be 0
        $ui.TxtSelectionCounter.Text | Should -Be 'Nenhum item selecionado'
    }
}
