FROM docker.io/marpteam/marp-cli:v4.3.1

ARG ROUNDED_NOTO_BASE_URL=https://github.com/sakikuroe/rounded-noto-sans-cjk/releases/download/v0.2.0
ARG NOTO_SANS_JP_URL=https://raw.githubusercontent.com/google/fonts/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf
ARG IBM_PLEX_SANS_JP_BASE_URL=https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/ibmplexsansjp

RUN apt-get update && \
    apt-get install -y wget python3 python3-pip fonts-noto-cjk unzip && \
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/chrome.deb && \
    rm /tmp/chrome.deb && \
    pip install img2pdf matplotlib --no-cache-dir --break-system-packages && \
    PUPPETEER_SKIP_DOWNLOAD=1 npm install -g @mermaid-js/mermaid-cli@11.16.0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 比較用の Noto Sans JP と、コード用の Rounded Noto Code CJK JP。
RUN mkdir -p /usr/share/fonts/truetype/noto-sans-jp /usr/share/fonts/opentype/rounded-noto-code && \
    wget -q -O /usr/share/fonts/truetype/noto-sans-jp/NotoSansJP-Variable.ttf "$NOTO_SANS_JP_URL" && \
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
    wget -q -O /tmp/genei-m-gothic.zip https://okoneya.jp/font/GenEiMGothic_v2.0.zip; \
    unzip -q /tmp/genei-m-gothic.zip -d "$font_root/genei-m-gothic"; \
    rm /tmp/genei-m-gothic.zip; \
    licenses=/usr/share/doc/marp-template-kit/font-licenses; \
    mkdir -p "$licenses"; \
    cp "$font_root/genei-m-gothic/GenEiMGothic_v2.0/OFLicense.txt" "$licenses/GenEi-M-Gothic-OFL.txt"; \
    wget -q -O "$licenses/Rounded-Noto-Code-OFL.txt" \
        https://raw.githubusercontent.com/sakikuroe/rounded-noto-sans-cjk/v0.2.0/licenses/OFL.txt; \
    wget -q -O "$licenses/Noto-Sans-JP-OFL.txt" \
        https://raw.githubusercontent.com/google/fonts/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp/OFL.txt; \
    cp "$font_root/ibmplexsansjp/OFL.txt" "$licenses/IBM-Plex-Sans-JP-OFL.txt"; \
    cp /usr/share/doc/fonts-noto-cjk/copyright "$licenses/Noto-CJK-copyright.txt"; \
    fc-cache -f

WORKDIR /app
