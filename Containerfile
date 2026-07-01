FROM docker.io/marpteam/marp-cli:v4.3.1

RUN apt-get update && \
    apt-get install -y wget python3 python3-pip && \
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/chrome.deb && \
    rm /tmp/chrome.deb && \
    pip install img2pdf --no-cache-dir --break-system-packages && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
