---
marp: true
theme: modern
title: 朝会報告
author: 山田
date: 2026-06-16
paginate: true
header: 朝会報告 | 2026-06-16
_class: cover
---

# 朝会報告

2026-06-16 (月) / 山田

---

## #32 ストリーミングパーサーの実装

マルチラインログの結合処理に取り組んでいる。

- <img class="inline-icon" src="../icons/status_checkbox_done.svg" > 行単位のログ読み込み処理
- <img class="inline-icon" src="../icons/status_checkbox_done.svg" > タイムスタンプのパース処理
- <img class="inline-icon" src="../icons/status_checkbox_doing.svg" > マルチラインログの結合処理
- <img class="inline-icon" src="../icons/status_checkbox_doing.svg" > エラーリカバリ処理
- <img class="inline-icon" src="../icons/status_checkbox_todo.svg" > ベンチマークの実施

> 結合処理で使う正規表現パターンについて後ほど相談したい。
> PR #43 をドラフトで作成済み。

---

## #35 フィルタ構文の実装

本日から作業を開始する。まず構文の定義から着手し、レキサーの実装まで進めたい。

- <img class="inline-icon" src="../icons/status_checkbox_todo.svg" > 構文定義をBNF記法で整理する
- <img class="inline-icon" src="../icons/status_checkbox_todo.svg" > レキサーの実装
- <img class="inline-icon" src="../icons/status_checkbox_todo.svg" > パーサーの実装
- <img class="inline-icon" src="../icons/status_checkbox_todo.svg" > 評価器の実装

---

## #29 JSON出力フォーマッタ

昨日すべての作業を完了し、マージした。

- <img class="inline-icon" src="../icons/status_checkbox_done.svg" > 出力構造体の定義
- <img class="inline-icon" src="../icons/status_checkbox_done.svg" > シリアライズ処理の実装
- <img class="inline-icon" src="../icons/status_checkbox_done.svg" > PR #41 のマージ

---

## 共有・相談

<img class="inline-icon" src="../icons/blocker.svg" > **ブロッカー**
CI環境でメモリリークテストが不安定になっている。原因を調査中だが、再現条件がまだ絞れていない。

<img class="inline-icon" src="../icons/consultation.svg" > **相談**
マルチラインログの結合ルールを正規表現ベースで進めてよいか確認したい。スタックトレースの判定が難しく、インデントベースの方が安定する可能性がある。

<img class="inline-icon" src="../icons/info.svg" > **共有**
Rust 1.80で非同期処理周りに改善が入るため、来月のアップデートを検討している。
