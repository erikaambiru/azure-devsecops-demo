#!/bin/bash
# ============================================================================
# setup-github-secrets_variables.sh
# GitHub Actions の Variables / Secrets に一括設定するスクリプト
# Mac / Linux ユーザー向けのシェルスクリプト版
#
# 用途: プロジェクト初回構築時や環境変数の全体リセット時に使用
# セキュリティ: パスワード類はスクリプト内で規定値を設定していますが、
#              本番環境では必ず変更してください
# ============================================================================

set -e

# --- 設定値(必要に応じて編集) ---
DEFAULT_REPO="aktsmm/ContainerApp-demo2"

# scripts/create-github-actions-sp.sh の出力値を転記する
AZURE_SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AZURE_CLIENT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AZURE_CLIENT_SECRET="xxx~xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
AZURE_TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# インフラ設定
RESOURCE_GROUP_NAME="RG-bbs-app-demo"
LOCATION="japaneast"
ACR_NAME_PREFIX="acrdemo"
STORAGE_ACCOUNT_PREFIX="demo"
AKS_CLUSTER_NAME="aks-demo-dev"
ACA_ENVIRONMENT_NAME="cae-demo-dev"
ADMIN_CONTAINER_APP_NAME="admin-app"
VM_NAME="vm-mysql-demo"
BACKUP_CONTAINER_NAME="mysql-backups"

# 認証情報（デフォルト値、本番では必ず変更）
VM_ADMIN_USERNAME="test-admin"
DB_APP_USERNAME="test-admin"
ACA_ADMIN_USERNAME="test-admin"

# パスワード（後で上書きされる可能性あり）
DEFAULT_PASSWORD="P@ssw0rd!2025"
VM_ADMIN_PASSWORD="$DEFAULT_PASSWORD"
MYSQL_ROOT_PASSWORD="$DEFAULT_PASSWORD"
DB_APP_PASSWORD="$DEFAULT_PASSWORD"
ACA_ADMIN_PASSWORD="$DEFAULT_PASSWORD"

# GitGuardian API Key (オプション)
# https://dashboard.gitguardian.com/api/personal-access-tokens で取得
# 必要なスコープ: scan (必須), incident:read, incident:write
GITGUARDIAN_API_KEY=""

# --- スクリプト本体 ---

DRY_RUN=false
REPO=""

# 使用方法を表示
usage() {
    cat << EOF
使用方法:
    $0 [オプション]

オプション:
    -r, --repo <owner/repo>  対象の GitHub リポジトリ
    -d, --dry-run            gh CLI を実行せず、設定内容のみ表示
    -h, --help               このヘルプを表示

例:
    # デフォルトリポジトリに適用
    $0

    # 別リポジトリに適用
    $0 -r "your-username/your-repo"

    # 設定内容のみ確認（DRY-RUN）
    $0 --dry-run
EOF
    exit 1
}

# GitHub CLI の確認
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        echo "❌ エラー: GitHub CLI (gh) が見つかりません。"
        echo "インストール: https://cli.github.com/"
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        echo "❌ エラー: GitHub CLI にログインしていません。"
        echo "実行してください: gh auth login"
        exit 1
    fi

    echo "✅ GitHub CLI 確認完了"
}

# git remote から リポジトリを取得
get_repo_from_git() {
    if ! command -v git &> /dev/null; then
        return 1
    fi

    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || true)
    
    if [[ -z "$remote_url" ]]; then
        return 1
    fi

    # HTTPS または SSH 形式をパース
    if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

# GitHub Variable を設定
set_github_variable() {
    local name="$1"
    local value="$2"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] gh variable set $name --body ***"
        return
    fi

    gh variable set "$name" --repo "$REPO" --body "$value"
    echo "✅ Variable $name を設定しました"
}

# GitHub Secret を設定
set_github_secret() {
    local name="$1"
    local value="$2"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] gh secret set $name --body ***"
        return
    fi

    gh secret set "$name" --repo "$REPO" --body "$value"
    echo "✅ Secret $name を設定しました"
}

# パラメータ解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo)
            REPO="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "❌ 不明なオプション: $1"
            usage
            ;;
    esac
done

echo ""
echo "================================"
echo "🔐 パスワード設定"
echo "================================"
echo ""
echo "現在のデフォルトパスワード: $DEFAULT_PASSWORD"
echo ""
read -p "デフォルトパスワードをランダムな値に一括変更しますか？ (Y/N): " response

if [[ "$response" == "Y" || "$response" == "y" ]]; then
    RANDOM_SUFFIX=$((RANDOM % 89999 + 10000))
    NEW_PASSWORD="P@ssw0rd!${RANDOM_SUFFIX}"
    VM_ADMIN_PASSWORD="$NEW_PASSWORD"
    MYSQL_ROOT_PASSWORD="$NEW_PASSWORD"
    DB_APP_PASSWORD="$NEW_PASSWORD"
    ACA_ADMIN_PASSWORD="$NEW_PASSWORD"
    echo ""
    echo "✅ 新しいパスワード: $NEW_PASSWORD"
    echo "   このパスワードは全ての項目に適用されます"
    echo ""
else
    echo ""
    echo "⚠️  デフォルトパスワードを使用します (推奨しません)"
    echo ""
fi

# GitHub CLI 確認
check_gh_cli

# リポジトリを決定
if [[ -z "$REPO" && -n "$DEFAULT_REPO" ]]; then
    REPO="$DEFAULT_REPO"
fi

if [[ -z "$REPO" ]]; then
    REPO=$(get_repo_from_git || true)
fi

if [[ -z "$REPO" ]]; then
    read -p "適用対象の GitHub リポジトリ (owner/repo) を入力してください: " REPO
fi

if [[ -z "$REPO" ]]; then
    echo "❌ エラー: 対象リポジトリが特定できませんでした。"
    echo "-r 'owner/repo' を指定するか、DEFAULT_REPO に既定値を設定してください。"
    exit 1
fi

echo ""
echo "対象リポジトリ: $REPO"
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] gh CLI には適用せず、設定内容のみを表示します。"
fi

echo ""
echo "--- Repository Variables ---"

# Azure 認証関連
set_github_variable "AZURE_CLIENT_ID" "$AZURE_CLIENT_ID"
set_github_variable "AZURE_CLIENT_SECRET" "$AZURE_CLIENT_SECRET"
set_github_variable "AZURE_TENANT_ID" "$AZURE_TENANT_ID"

# インフラ設定
set_github_variable "RESOURCE_GROUP_NAME" "$RESOURCE_GROUP_NAME"
set_github_variable "LOCATION" "$LOCATION"
set_github_variable "ACR_NAME_PREFIX" "$ACR_NAME_PREFIX"
set_github_variable "STORAGE_ACCOUNT_PREFIX" "$STORAGE_ACCOUNT_PREFIX"
set_github_variable "AKS_CLUSTER_NAME" "$AKS_CLUSTER_NAME"
set_github_variable "ACA_ENVIRONMENT_NAME" "$ACA_ENVIRONMENT_NAME"
set_github_variable "ADMIN_CONTAINER_APP_NAME" "$ADMIN_CONTAINER_APP_NAME"
set_github_variable "VM_NAME" "$VM_NAME"
set_github_variable "BACKUP_CONTAINER_NAME" "$BACKUP_CONTAINER_NAME"

# 認証情報
set_github_variable "VM_ADMIN_USERNAME" "$VM_ADMIN_USERNAME"
set_github_variable "VM_ADMIN_PASSWORD" "$VM_ADMIN_PASSWORD"
set_github_variable "MYSQL_ROOT_PASSWORD" "$MYSQL_ROOT_PASSWORD"
set_github_variable "DB_APP_USERNAME" "$DB_APP_USERNAME"
set_github_variable "DB_APP_PASSWORD" "$DB_APP_PASSWORD"
set_github_variable "ACA_ADMIN_USERNAME" "$ACA_ADMIN_USERNAME"
set_github_variable "ACA_ADMIN_PASSWORD" "$ACA_ADMIN_PASSWORD"

# GitGuardian API Key (オプション)
if [[ -n "$GITGUARDIAN_API_KEY" ]]; then
    set_github_variable "GITGUARDIAN_API_KEY" "$GITGUARDIAN_API_KEY"
else
    echo ""
    echo "⚠️  GITGUARDIAN_API_KEY が設定されていません（スキップ）"
    echo ""
    echo "📋 GitGuardian API Key の取得手順:"
    echo "  1. https://dashboard.gitguardian.com/api/personal-access-tokens にアクセス"
    echo "  2. 新しいトークンを作成し、以下のスコープを選択:"
    echo "     ✅ scan (必須)"
    echo "     ✅ incident:read"
    echo "     ✅ incident:write"
    echo "  3. スクリプト内の GITGUARDIAN_API_KEY にトークンを設定"
    echo "  4. 再度スクリプトを実行"
    echo ""
    echo "💡 GitGuardian を使用しない場合は、このまま続行できます。"
    echo "   ワークフローで GitGuardian スキャンはスキップされます。"
    echo ""
fi

echo ""
echo "--- Repository Secrets ---"
set_github_secret "AZURE_SUBSCRIPTION_ID" "$AZURE_SUBSCRIPTION_ID"

echo ""
echo "================================"
echo "✅ GitHub Actions の初期設定が完了しました"
echo "================================"
echo ""

# 設定値一覧を表示
cat << EOF
========================================
設定された Variables と Secrets の一覧
========================================
リポジトリ: $REPO

【GitHub Secrets】
  AZURE_SUBSCRIPTION_ID = $AZURE_SUBSCRIPTION_ID

【GitHub Variables】
  AZURE_CLIENT_ID = $AZURE_CLIENT_ID
  AZURE_CLIENT_SECRET = ********
  AZURE_TENANT_ID = $AZURE_TENANT_ID
  RESOURCE_GROUP_NAME = $RESOURCE_GROUP_NAME
  LOCATION = $LOCATION
  ACR_NAME_PREFIX = $ACR_NAME_PREFIX
  STORAGE_ACCOUNT_PREFIX = $STORAGE_ACCOUNT_PREFIX
  AKS_CLUSTER_NAME = $AKS_CLUSTER_NAME
  ACA_ENVIRONMENT_NAME = $ACA_ENVIRONMENT_NAME
  ADMIN_CONTAINER_APP_NAME = $ADMIN_CONTAINER_APP_NAME
  VM_NAME = $VM_NAME
  BACKUP_CONTAINER_NAME = $BACKUP_CONTAINER_NAME
  VM_ADMIN_USERNAME = $VM_ADMIN_USERNAME
  DB_APP_USERNAME = $DB_APP_USERNAME
  ACA_ADMIN_USERNAME = $ACA_ADMIN_USERNAME

【パスワード項目（安全な場所に保管してください）】
  VM_ADMIN_PASSWORD = $VM_ADMIN_PASSWORD
  MYSQL_ROOT_PASSWORD = $MYSQL_ROOT_PASSWORD
  DB_APP_PASSWORD = $DB_APP_PASSWORD
  ACA_ADMIN_PASSWORD = $ACA_ADMIN_PASSWORD

EOF

if [[ -n "$GITGUARDIAN_API_KEY" ]]; then
    echo "【GitGuardian API Key】"
    echo "  GITGUARDIAN_API_KEY = $GITGUARDIAN_API_KEY"
    echo "  スコープ: scan, incident:read, incident:write"
else
    echo "【GitGuardian API Key】"
    echo "  ⚠️  未設定 - GitGuardian スキャンはスキップされます"
    echo "  取得URL: https://dashboard.gitguardian.com/api/personal-access-tokens"
    echo "  必要なスコープ: scan (必須), incident:read, incident:write"
fi

echo ""
echo "========================================"
echo ""
echo "💡 値を変更する場合は本スクリプトの変数を更新してください。"
echo ""
