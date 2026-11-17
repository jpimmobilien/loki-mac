#!/bin/bash
# Prüfläufe mit der gebauten App und eigenem Datenordner (echte Benutzerdaten bleiben unberührt).
#   scripts/run_qa.sh snapshot qa/snapshots
#   QA_MODEL=mlx-community/Qwen3-0.6B-4bit scripts/run_qa.sh selftest qa/selftest
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$1"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
BIN="$ROOT/build/LOKI.app/Contents/MacOS/LOKI"
test -x "$BIN" || { echo "✗ $BIN fehlt"; exit 1; }
DATA="$(mktemp -d)"

case "$MODE" in
    snapshot)
        ARGS=(--snapshot "$OUT"); LIMIT=600 ;;
    selftest)
        ARGS=(--selftest "$OUT" --catalog-check --download "${QA_MODEL:-mlx-community/Qwen3-0.6B-4bit}"); LIMIT=2400 ;;
    *) echo "Modus: snapshot | selftest"; exit 2 ;;
esac

echo "▸ $MODE → $OUT"
LOKI_DATA_DIR="$DATA" perl -e 'alarm shift; exec @ARGV' "$LIMIT" "$BIN" "${ARGS[@]}" > "$OUT/protokoll.txt" 2>&1
STATUS=$?
tail -n 80 "$OUT/protokoll.txt"
if [ $STATUS -ne 0 ]; then
    echo "✗ App beendet mit Status $STATUS"
    sleep 8
    cp "$HOME"/Library/Logs/DiagnosticReports/LOKI* "$OUT/" 2>/dev/null || true
    ls "$OUT"
    exit $STATUS
fi
echo "✓ $MODE abgeschlossen"
