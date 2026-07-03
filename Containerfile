FROM docker.io/marpteam/marp-cli:v4.3.1

# "Rounded Mgen+ 1m" 配布元 (罫線文字を含む記号を等幅グリフとして収録した等幅フォント).
ARG ROUNDED_MGENPLUS_URL=https://ftp.iij.ad.jp/pub/osdn.jp/users/8/8598/rounded-mgenplus-20150602.7z
ARG ROUNDED_MGENPLUS_TTF_NAME=rounded-mgenplus-1m-regular.ttf

# "Zen Kaku Gothic New" 配布元 (google/fonts リポジトリー).
# 実行時に Google Fonts (fonts.googleapis.com) へ接続する @import ではなく,
# ビルド時にコンテナへ同梱することで, 生成 HTML を自己完結させる.
ARG ZEN_KAKU_BASE_URL=https://raw.githubusercontent.com/google/fonts/main/ofl/zenkakugothicnew

# Ambiguous width グリフ半角化パッチ (詳細は patch_ambiguous_width.py を参照).
COPY patch_ambiguous_width.py /tmp/patch_ambiguous_width.py

RUN apt-get update && \
    apt-get install -y wget python3 python3-pip fonts-noto-cjk p7zip-full && \
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/chrome.deb && \
    rm /tmp/chrome.deb && \
    pip install img2pdf matplotlib fonttools --no-cache-dir --break-system-packages && \
    PUPPETEER_SKIP_DOWNLOAD=1 npm install -g @mermaid-js/mermaid-cli && \
    wget -q -O /tmp/rounded-mgenplus.7z "$ROUNDED_MGENPLUS_URL" && \
    mkdir -p /tmp/rounded-mgenplus && \
    7zr x -y /tmp/rounded-mgenplus.7z -o/tmp/rounded-mgenplus >/dev/null && \
    mkdir -p /usr/share/fonts/truetype/rounded-mgenplus && \
    find /tmp/rounded-mgenplus -type f -name "$ROUNDED_MGENPLUS_TTF_NAME" \
        -exec python3 /tmp/patch_ambiguous_width.py {} \
        "/usr/share/fonts/truetype/rounded-mgenplus/$ROUNDED_MGENPLUS_TTF_NAME" \; && \
    fc-cache -f /usr/share/fonts/truetype/rounded-mgenplus && \
    rm -rf /tmp/rounded-mgenplus /tmp/rounded-mgenplus.7z /tmp/patch_ambiguous_width.py && \
    mkdir -p /usr/share/fonts/truetype/zen-kaku-gothic-new && \
    for w in Regular Medium Bold Black; do \
        wget -q -O "/usr/share/fonts/truetype/zen-kaku-gothic-new/ZenKakuGothicNew-${w}.ttf" \
            "$ZEN_KAKU_BASE_URL/ZenKakuGothicNew-${w}.ttf"; \
    done && \
    fc-cache -f /usr/share/fonts/truetype/zen-kaku-gothic-new && \
    apt-get remove -y p7zip-full && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
