#!/usr/bin/env bash
# PublicDomainJazzPlayer: 標準の tracks.json 生成（Issue #1 と docs/catalog_generation.md に準拠）
set -euo pipefail
cd "$(dirname "$0")/.."
dart run tools/fetch_loc_catalog.dart \
  --no-item-api \
  --check-urls \
  --url-check-timeout-ms=1200 \
  --output=assets/tracks.json
