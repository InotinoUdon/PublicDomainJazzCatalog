# PublicDomainJazzCatalog

GitHub Pages で `tracks.json` と法務 Markdown（プライバシーポリシー・利用規約）を公開するリポジトリです。モバイルアプリ [PublicDomainJazzPlayer](https://github.com/InotinoUdon/PublicDomainJazzPlayer) の既定 URL から参照されます。

## 公開物

| パス（Pages） | ソース |
|---------------|--------|
| `/tracks.json` | CI が `tools/fetch_loc_catalog.dart` で生成 |
| `/privacy_policy.md` | `docs/privacy_policy.md` をコピー |
| `/terms_of_use.md` | `docs/terms_of_use.md` をコピー |

## ポリシー類の同期

`docs/privacy_policy.md` と `docs/terms_of_use.md` は、**PublicDomainJazzPlayer の `docs/` と内容を揃える**こと（発効日・条項の整合）。片方だけ古い状態にしないでください。

## ワークフロー

`.github/workflows/publish_catalog.yml` — `main` の push / 手動 dispatch / スケジュールで `gh-pages` にデプロイします。
