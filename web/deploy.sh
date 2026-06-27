#!/usr/bin/env bash
# Soccer Striker (Web) を Cloud Run にデプロイする。
# 使い方:
#   ./deploy.sh <PROJECT_ID> [REGION] [SERVICE_NAME]
# 例:
#   ./deploy.sh my-gcp-project asia-northeast1 soccer-striker
#
# 事前準備（初回のみ）:
#   gcloud auth login
#   gcloud config set project <PROJECT_ID>
#   gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
set -euo pipefail

PROJECT="${1:?PROJECT_ID を指定してください: ./deploy.sh <PROJECT_ID> [REGION] [SERVICE]}"
REGION="${2:-asia-northeast1}"
SERVICE="${3:-soccer-striker}"

# このスクリプトのあるディレクトリ（web/）をビルドコンテキストにする。
cd "$(dirname "$0")"

echo "▶ Deploying '$SERVICE' to Cloud Run (project=$PROJECT, region=$REGION) …"
gcloud run deploy "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --source=. \
  --port=8080 \
  --allow-unauthenticated \
  --cpu=1 --memory=256Mi \
  --min-instances=0 --max-instances=3

echo "✅ 完了。上に表示された Service URL を開いてください。"
