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
    fc-cache -f

# フォントのライセンスはプロジェクトの MIT License と別に保持する。
RUN set -eu; \
    notices=/usr/share/doc/marp-template-kit/font-licenses; \
    mkdir -p "$notices"; \
    wget -q -O "$notices/Rounded-Noto-Code-OFL.txt" \
        https://raw.githubusercontent.com/sakikuroe/rounded-noto-sans-cjk/v0.2.0/licenses/OFL.txt; \
    wget -q -O "$notices/Noto-Sans-JP-OFL.txt" \
        https://raw.githubusercontent.com/google/fonts/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp/OFL.txt; \
    cp /usr/share/fonts/truetype/slide-previews/ibmplexsansjp/OFL.txt "$notices/IBM-Plex-Sans-JP-OFL.txt"; \
    cp /usr/share/fonts/truetype/slide-previews/genei-m-gothic/GenEiMGothic_v2.0/OFLicense.txt "$notices/GenEi-M-Gothic-OFL.txt"; \
    cp /usr/share/doc/fonts-noto-cjk/copyright "$notices/Noto-CJK-copyright.txt"

# Rounded Noto の元フォントの著作権・商標表示は name テーブルにある。
# 配布元の文書とともに UTF-8 の一覧へ残し、フォント本体は変更しない。
RUN node -e '\
    const fs = require("node:fs"); \
    const root = "/usr/share/doc/marp-template-kit/font-licenses"; \
    const sections = []; \
    for (const weight of ["Regular", "Bold"]) { \
        const name = `RoundedNotoCodeCJKJP-${weight}.otf`; \
        const font = fs.readFileSync(`/usr/share/fonts/opentype/rounded-noto-code/${name}`); \
        let offset; \
        for (let i = 0; i < font.readUInt16BE(4); i++) { \
            const record = 12 + i * 16; \
            if (font.toString("ascii", record, record + 4) === "name") offset = font.readUInt32BE(record + 8); \
        } \
        if (offset === undefined) throw new Error(`Missing font names: ${name}`); \
        const strings = offset + font.readUInt16BE(offset + 4); \
        const notices = new Set(); \
        for (let i = 0; i < font.readUInt16BE(offset + 2); i++) { \
            const record = offset + 6 + i * 12; \
            const platform = font.readUInt16BE(record); \
            const id = font.readUInt16BE(record + 6); \
            if (![0, 7].includes(id) || ![0, 3].includes(platform)) continue; \
            const start = strings + font.readUInt16BE(record + 10); \
            const bytes = font.subarray(start, start + font.readUInt16BE(record + 8)); \
            notices.add(new TextDecoder("utf-16be").decode(bytes)); \
        } \
        if (!notices.size) throw new Error(`Missing font copyright: ${name}`); \
        sections.push(`${name}\n${[...notices].join("\n")}`); \
    } \
    for (const name of fs.readdirSync(root).sort()) { \
        const encoding = name === "GenEi-M-Gothic-OFL.txt" ? "shift_jis" : "utf-8"; \
        const text = new TextDecoder(encoding, { fatal: true }).decode(fs.readFileSync(`${root}/${name}`)); \
        sections.push(`${name}\n${text}`); \
    } \
    fs.writeFileSync("/usr/share/doc/marp-template-kit/FONT-LICENSES.txt", \
        "Font copyrights and licenses (separate from the project MIT License)\n\n" + sections.join("\n\n========================================\n\n")); \
    '

WORKDIR /app
