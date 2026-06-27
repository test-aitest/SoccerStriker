# Cloud Run へのデプロイ

`web/`（静的サイト）を Google Cloud Run に公開する手順。`Dockerfile`（nginx で配信、`$PORT` 対応）を同梱しているので、`gcloud` のソースデプロイでも Cloud Run MCP でも確実に動く。

参考:
- Cloud Run MCP: https://docs.cloud.google.com/run/docs/use-cloud-run-mcp?hl=ja
- AI Studio → Cloud Run コードラボ: https://codelabs.developers.google.com/deploy-from-aistudio-to-run?hl=ja

---

## 0. 前提（初回のみ）

```bash
# Google Cloud SDK は導入済み（このマシンで確認済み）。
gcloud auth login                       # ← 対話ログイン（自分で実行）
gcloud config set project <PROJECT_ID>
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com
```

> 課金が有効な GCP プロジェクトが必要。`gcloud auth login` は対話操作なので、
> ターミナルで `! gcloud auth login` のように自分で実行してください。

---

## 方法A: gcloud でソースデプロイ（おすすめ・最短）

同梱スクリプトを使う:

```bash
cd web
./deploy.sh <PROJECT_ID> asia-northeast1 soccer-striker
```

または直接:

```bash
cd web
gcloud run deploy soccer-striker \
  --source=. \
  --region=asia-northeast1 \
  --port=8080 \
  --allow-unauthenticated \
  --cpu=1 --memory=256Mi --min-instances=0 --max-instances=3
```

- Cloud Build がサーバ側で `Dockerfile` をビルド → Artifact Registry に push → Cloud Run へデプロイ。**ローカルに Docker は不要**。
- 完了すると `Service URL`（`https://soccer-striker-xxxx.a.run.app`）が表示される。ブラウザで開けばそのまま遊べる。

---

## 方法B: Cloud Run MCP から `/deploy`

AI エージェント（Claude Code など）から直接デプロイする経路。リモート MCP サーバ `https://run.googleapis.com/mcp` を使う。

1. 必要 IAM ロール: Cloud Run Developer / Service Account User / Artifact Registry Reader / MCP Tool User
2. Claude Code に MCP サーバを追加:
   ```bash
   claude mcp add --transport http cloud-run https://run.googleapis.com/mcp
   ```
   （Google Cloud 資格情報 / OAuth で認証）
3. `web/` をカレントにして、エージェントに次を依頼:
   ```
   /deploy soccer-striker --project <PROJECT_ID> --region asia-northeast1
   ```
   MCP 側がコンテナ化〜デプロイを実行する（`Dockerfile` があるのでそれが使われる）。

---

## ローカルでコンテナ動作確認（任意・Docker Desktop 起動時のみ）

```bash
cd web
docker build -t soccer-striker-web .
docker run --rm -p 8080:8080 -e PORT=8080 soccer-striker-web
# → http://localhost:8080/
```

`-e PORT=9090 -p 9090:9090` のように変えても nginx が追従する（テンプレートで `${PORT}` を差し込むため）。

---

## メモ

- **リージョン**: `asia-northeast1`（東京）を既定にしている。変更可。
- **公開設定**: `--allow-unauthenticated` で誰でもアクセス可。組織ポリシーで禁止されている場合は外し、IAM で許可するか、Cloud Run の「未認証の呼び出しを許可」を別途設定する。
- **コスト**: `min-instances=0` なので未アクセス時はゼロスケール。静的配信なので非常に軽量。
- **音声/アセット**: `assets/`（flags・teams・audio）と `vendor/`（three.js）はイメージに含まれる。`.dockerignore` で `Dockerfile` 等のみ除外。
- AI Studio コードラボのように UI からデプロイしたい場合は、このリポジトリ（`web/`）を GitHub に置き、Cloud Run コンソールの「ソースから継続的にデプロイ」でも同じ `Dockerfile` が使われる。
