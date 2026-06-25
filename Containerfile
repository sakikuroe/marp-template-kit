# build.sh で使用するツールをまとめたコンテナイメージ.
# Google Chrome (PDF 印刷) と img2pdf (PNG→PDF 結合) を同一イメージに収める.
# build.sh は --entrypoint でツールを使い分ける.

FROM ubuntu:24.04

# Google Chrome stable: ブラウザ印刷と同等の品質で HTML を PDF に変換する.
# img2pdf: PNG を PDF に結合する (PNG 経由 PDF ルート用).
# --break-system-packages: Ubuntu 24.04 の PEP 668 制限を回避して pip でインストールする.
RUN apt-get update && \
    apt-get install -y wget ca-certificates python3 python3-pip && \
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/chrome.deb && \
    rm /tmp/chrome.deb && \
    pip install img2pdf --no-cache-dir --break-system-packages && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
