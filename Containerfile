# img2pdf を実行するための専用コンテナイメージ.
#
# build.sh が PDF を生成する際, marp-cli の Chromium PDF エクスポートでは
# backdrop-filter が正しく描画されない問題 (Chromium Issue #41477207) があるため,
# 一度 PNG に書き出してから img2pdf で PDF に結合する方式を採用している.
# この img2pdf の実行をコンテナ化することで次のメリットを得る.
#   - ホスト環境に img2pdf をインストール不要.
#   - --network=none で外部通信を遮断でき, セキュリティリスクを最小化できる.
#   - marp-cli イメージと役割を分離し, それぞれの責務を明確にする.

# Python 公式スリムイメージをベースにする.
# slim バリアントは不要なパッケージを除いたイメージで, サイズが小さくなる.
FROM docker.io/python:3-slim

# img2pdf: PNG / JPEG などのラスター画像を PDF に変換するライブラリ.
# --no-cache-dir: pip キャッシュをイメージレイヤーに残さず, イメージサイズを削減する.
RUN pip install img2pdf --no-cache-dir

# コンテナ起動時に img2pdf CLI として直接動作させる.
# build.sh は --pagesize や入力ファイル, -o などの引数をこのエントリーポイントに渡す.
ENTRYPOINT ["python3", "-m", "img2pdf"]
