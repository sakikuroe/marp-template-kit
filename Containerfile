FROM docker.io/marpteam/marp-cli:v4.3.1@sha256:199522ca73b6683d2715e2a4273d5b2480661789a2664f38064631513eabd1ab

# Chrome for Testing はバージョンごとの配布URLを維持する。
ARG CHROME_VERSION=154.0.8037.92
ENV CHROME_PATH=/usr/bin/google-chrome

ARG ROUNDED_NOTO_BASE_URL=https://github.com/sakikuroe/rounded-noto-sans-cjk/releases/download/v0.2.0
ARG NOTO_SANS_JP_URL=https://raw.githubusercontent.com/google/fonts/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf
ARG IBM_PLEX_SANS_JP_BASE_URL=https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/ibmplexsansjp

RUN apt-get update && \
    apt-get install -y wget python3 python3-pip fonts-noto-cjk unzip \
        fonts-liberation libasound2 libatk-bridge2.0-0 libatspi2.0-0 \
        libcups2 libgbm1 libgtk-3-0 libnspr4 libnss3 libvulkan1 \
        libxcomposite1 libxdamage1 libxkbcommon0 libxrandr2 && \
    wget -q -O /tmp/chrome.zip "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-linux64.zip" && \
    echo "ff43322f335e436b2f4dcdfeeec5db032299e335a7e8c1c618b326e100ce8732  /tmp/chrome.zip" | sha256sum -c - && \
    unzip -q /tmp/chrome.zip -d /opt && \
    ln -s /opt/chrome-linux64/chrome /usr/bin/google-chrome && \
    rm /tmp/chrome.zip && \
    pip install img2pdf==0.6.3 matplotlib==3.11.2 --no-cache-dir --break-system-packages && \
    PUPPETEER_SKIP_DOWNLOAD=1 npm install -g @mermaid-js/mermaid-cli@11.16.0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 比較用の Noto Sans JP と、コード用の Rounded Noto Code CJK JP。
RUN mkdir -p /usr/share/fonts/truetype/noto-sans-jp /usr/share/fonts/opentype/rounded-noto-code && \
    wget -q -O /usr/share/fonts/truetype/noto-sans-jp/NotoSansJP-Variable.ttf "$NOTO_SANS_JP_URL" && \
    echo "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f  /usr/share/fonts/truetype/noto-sans-jp/NotoSansJP-Variable.ttf" | sha256sum -c - && \
    wget -q -O /usr/share/fonts/opentype/rounded-noto-code/RoundedNotoCodeCJKJP-Regular.otf \
        "$ROUNDED_NOTO_BASE_URL/RoundedNotoCodeCJKJP-Regular.otf" && \
    wget -q -O /usr/share/fonts/opentype/rounded-noto-code/RoundedNotoCodeCJKJP-Bold.otf \
        "$ROUNDED_NOTO_BASE_URL/RoundedNotoCodeCJKJP-Bold.otf" && \
    echo "d167d63ba1a419fc2123e623212ce50ea97fe115b846a2ecd933532e4dc6c12a  /usr/share/fonts/opentype/rounded-noto-code/RoundedNotoCodeCJKJP-Regular.otf" | sha256sum -c - && \
    echo "d0d411f0ebb5d8cdb3495bf160419ce88fe5195dc998771f5905ca88effc996b  /usr/share/fonts/opentype/rounded-noto-code/RoundedNotoCodeCJKJP-Bold.otf" | sha256sum -c - && \
    fc-cache -f

# 本文用の比較候補は IBM Plex Sans JP・源暎エムゴ・Noto Sans JP の3書体。
RUN set -eu; \
    font_root=/usr/share/fonts/truetype/slide-previews; \
    mkdir -p "$font_root/ibmplexsansjp" "$font_root/genei-m-gothic"; \
    wget -q -O "$font_root/ibmplexsansjp/OFL.txt" "$IBM_PLEX_SANS_JP_BASE_URL/OFL.txt"; \
    for weight in Thin ExtraLight Light Regular Medium SemiBold Bold; do \
        wget -q -O "$font_root/ibmplexsansjp/IBMPlexSansJP-$weight.ttf" \
            "$IBM_PLEX_SANS_JP_BASE_URL/IBMPlexSansJP-$weight.ttf"; \
    done; \
    cd "$font_root/ibmplexsansjp"; \
    printf '%s\n' \
        'bd8a98b9b55c9ea3f0fa1ed094c15981788cc9a41b0357f4453014fd1d44da19  IBMPlexSansJP-Bold.ttf' \
        '83b3a8d967295c162938946d6a9395d539c95fd53e161e0e4b01e5d7f39a2ea6  IBMPlexSansJP-ExtraLight.ttf' \
        'f6390231b0ce848866d5599765897d4b882d6b29dc0484dd4d1a5435b05761ba  IBMPlexSansJP-Light.ttf' \
        '1d09f5e25b19e54b2c55da70de58f9962512c3e07ed7c3e1c9bad77ace5c22e6  IBMPlexSansJP-Medium.ttf' \
        '372f8bba95f386856ae435dc0e69f08db1cac29bed513d99171a0ae2d307ba2a  IBMPlexSansJP-Regular.ttf' \
        '5985c29d2d5d444072915cf5874dc80e0a3f5fadbf14a9e3013a03a8fe6d7ff5  IBMPlexSansJP-SemiBold.ttf' \
        '773042bf5e8f428d46fcf81b9255c6a451f20cbd39983f308e96808a2e15e134  IBMPlexSansJP-Thin.ttf' \
        '7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da  OFL.txt' | sha256sum -c -; \
    wget -q -O /tmp/genei-m-gothic.zip https://okoneya.jp/font/GenEiMGothic_v2.0.zip; \
    echo "0e9333fc27a2d2f9882c08c392b5ca6344209db7b27ef44e8873e6017ea46440  /tmp/genei-m-gothic.zip" | sha256sum -c -; \
    unzip -q /tmp/genei-m-gothic.zip -d "$font_root/genei-m-gothic"; \
    rm /tmp/genei-m-gothic.zip; \
    fc-cache -f

WORKDIR /app
