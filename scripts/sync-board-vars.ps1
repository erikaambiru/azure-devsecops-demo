<#
.SYNOPSIS
    Bicep パラメータファイルから Kustomize 用の vars.env を生成するスクリプト

.DESCRIPTION
    infra/parameters/main-dev.parameters.json から boardAppNamespace の値を読み取り、
    app/board-app/k8s/vars.env に書き出します。
    Kustomize がこのファイルを参照して K8s マニフェストに Namespace を反映します。

.USAGE
    使用箇所:
    - GitHub Actions: .github/workflows/2-board-app-build-deploy.yml
      「Namespace/Ingress の値を同期」ステップで実行される
    
    実行タイミング:
    - Board App のビルド＆デプロイワークフロー実行時（AKS デプロイ前）
    - Bicep パラメータの boardAppNamespace を変更した場合に自動反映

    ローカル実行例:
    pwsh ./scripts/sync-board-vars.ps1
#>
[CmdletBinding()]
param(
    [string]$ParametersFile = (Join-Path $PSScriptRoot '../infra/parameters/main-dev.parameters.json'),
    [string]$OutputFile = (Join-Path $PSScriptRoot '../app/board-app/k8s/vars.env')
)

# パラメータファイルから Namespace を読み出して vars.env を更新する補助スクリプト
if (-not (Test-Path -Path $ParametersFile)) {
    throw "Parameters file not found: $ParametersFile"
}

$raw = Get-Content -Path $ParametersFile -Raw | ConvertFrom-Json
$namespace = $raw.parameters.boardAppNamespace.value

if ([string]::IsNullOrWhiteSpace($namespace)) {
    throw 'boardAppNamespace is empty in the parameters file.'
}

$content = @(
    '# このファイルは scripts/sync-board-vars.ps1 で自動生成されます',
    "kubernetesNamespace=$namespace"
)

Set-Content -Path $OutputFile -Value $content -Encoding utf8NoBOM
