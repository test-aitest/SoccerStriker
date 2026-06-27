# Soccer Striker (Web) を Cloud Run で配信するための静的サイトコンテナ。
# nginx で web/ の静的ファイル（index.html / src / vendor / assets）を配る。
# Cloud Run は $PORT（既定 8080）で待ち受けることを要求するため、
# nginx 公式イメージのテンプレ機能(envsubst)で listen ポートを差し込む。
FROM nginx:1.27-alpine

# 既定の default.conf を消し、$PORT を埋め込むテンプレートを置く。
RUN rm -f /etc/nginx/conf.d/default.conf
COPY default.conf.template /etc/nginx/templates/default.conf.template

# 静的アセットを配置。
COPY index.html styles.css /usr/share/nginx/html/
COPY src    /usr/share/nginx/html/src
COPY vendor /usr/share/nginx/html/vendor
COPY assets /usr/share/nginx/html/assets

# Cloud Run 既定ポート。run.googleapis.com が PORT を注入すれば上書きされる。
ENV PORT=8080
EXPOSE 8080

# nginx 公式の docker-entrypoint が templates を envsubst して起動する。
# （CMD はベースイメージの "nginx -g 'daemon off;'" をそのまま使用）
