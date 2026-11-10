#!/usr/bin/env bash
# Junta as linhas de erro de todos os logs (roda quando a build falha)
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ/logs" 2>/dev/null || { echo "sem logs"; exit 0; }
for f in *.log; do
	[ -f "$f" ] || continue
	achados="$(grep -nE "error:|Error:|ERROR|fatal:|FAILED|ITMS-|erro:|Traceback" "$f" | head -40 || true)"
	if [ -n "$achados" ]; then
		echo "== $f"
		echo "$achados"
	fi
done
