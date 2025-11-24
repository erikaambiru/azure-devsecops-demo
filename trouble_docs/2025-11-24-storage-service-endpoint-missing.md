# Storage サービスエンドポイント未設定で ACL 追加に失敗する

**日時**: 2025-11-24
**影響範囲**: `.github/workflows/1-infra-deploy.yml` の `Storage ネットワークルールを同期` ステップ / バックアップ用 Storage Account
**重要度**: 🔴 HIGH（Storage へのアクセスが遮断されバックアップや VM 連携が停止）

---

## 📋 事象の概要

Storage Account のネットワーク ルールを GitHub Actions で自動同期する際、対象サブネットに Azure Storage 用サービスエンドポイントが設定されておらず、`az storage account network-rule add` が `NetworkAclsValidationFailure` で停止した。これにより Storage を利用するワークフロー全体が失敗し、VM のバックアップや ACA→Storage 連携が実行不能となった。

---

## 🐛 症状

- Workflow Run: `Storageネットワーク許可をワークフローで自動化 #87`
- 該当ジョブ: `bicep-deploy`
- ログ抜粋:

```
サブネット snet-vm を許可します
ERROR: (NetworkAclsValidationFailure) ... SubnetsHaveNoServiceEndpointsConfigured ... Add Microsoft.Storage to subnet's ServiceEndpoints collection before trying to ACL Microsoft.Storage resources to these subnets..
```

- Storage Account の `Firewalls and virtual networks` に対象サブネットが追加されず、`defaultAction = Deny` のため全トラフィック遮断。

---

## 🔍 原因

1. `infra/main.bicep` の VNet 定義で VM / Container Apps サブネットに `serviceEndpoints` が未設定だった。
2. 手動 `az storage account network-rule add --subnet ...` はサブネット側に `Microsoft.Storage` (推奨 `Microsoft.Storage.Global`) が登録済みであることを前提にしている。
3. サービスエンドポイントがない状態で ACL だけ追加しようとしたため Azure Resource Manager がバリデーションで拒否。

参考: [Create a virtual network rule for Azure Storage](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-virtual-networks#create-a-virtual-network-rule) では「仮想ネットワークのサブネットで Azure Storage サービスエンドポイントを有効にしてからネットワーク ルールを作成する」ことが明示されている。

---

## ✅ 対応内容（FIX）

1. **IaC 側の恒久対応** (`infra/main.bicep`)

   - VM サブネットと Container Apps サブネットに `serviceEndpoints: [{ service: 'Microsoft.Storage.Global' }]` を追加。
   - コメントで目的を明記し、再デプロイ時に必ずエンドポイントが有効化されるようにした。

2. **ワークフロー側のガード** (`.github/workflows/1-infra-deploy.yml`)

   - `ensure_service_endpoint` 関数を追加し、Storage ACL 更新前に対象サブネットへ `Microsoft.Storage.Global` を付与。
   - 付与後は 10 回まで 10 秒間隔でポーリングし、エンドポイントが有効になったことを確認してから `az storage account network-rule add` を実行。
   - すでに別サービスエンドポイントがある場合は引き継ぎ、重複追加で失敗しないように実装。

3. **検証**
   - `1-infra-deploy` を再実行し、`Storage ネットワークルールを同期` が成功することを確認。
   - Storage Account 側で `virtualNetworkRules` に VM/ACA サブネットが表示され、VM からバックアップコンテナへアクセスできることを手動テスト。

---

## 🧪 再発防止策

- VNet/Bicep を編集する際はサービスエンドポイントの要否を `trouble_docs` で事前確認し、`Microsoft.Storage.Global` をテンプレ化する。
- ネットワーク ACL を自動化するスクリプトでは、サブネットの有効化状態を確認し不足していれば即時に追加するフェイルセーフを実装する。
- Workflow 失敗時のクリティカルログを `trouble_docs` に都度記載し、再発時の初動を短縮する。

---

## 🗂 関連コミット / 参考

- `aff9633`: Storage サービスエンドポイントの自動付与と ACL 同期の堅牢化
- `7c1d342`: Board App UI 追加変更（副次的）
- 参考ドキュメント: [Azure Storage firewall rules / Virtual network rules](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-virtual-networks#create-a-virtual-network-rule)

---

## 🎯 結果

- Workflow が再度成功し、Storage Account の `defaultAction=Deny` を維持したまま VM / ACA からのアクセスを許可できる状態に復旧。
- 今後同様の VNet 変更が発生しても IaC + Workflow の両面でサービスエンドポイントが自動的に整うため、手作業による設定漏れを排除できた。
