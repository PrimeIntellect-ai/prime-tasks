#!/usr/bin/env bash
# Oracle: submit openai/math's own proof of QuinticLienard, i.e. module OAI.Analysis.LienardCycles.Main and the
# 146 OAI modules it imports, placed under Submission/ (see reference.py).
set -euo pipefail
if [ -f /solution/reference.tar.gz ]; then
  tar -xzf /solution/reference.tar.gz -C /workspace
else
  # Fetch only those files at the pinned commit. The task blocks the network while the agent runs,
  # so run the oracle with `harbor run ... --allow-agent-host github.com`.
  tmp=$(mktemp -d)
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin https://github.com/openai/math.git
  git -C "$tmp" config core.sparseCheckout true
  sed -e 's#\.#/#g' -e 's#^#/lean/#' -e 's#$#.lean#' /solution/closure.txt > "$tmp/.git/info/sparse-checkout"
  git -C "$tmp" fetch -q --depth 1 --filter=blob:none origin adc7f1241b42e322a6451854ab7e4b4c146bf78a
  git -C "$tmp" checkout -q FETCH_HEAD
  python3 /solution/reference.py "$tmp/lean" /solution/closure.txt OAI.Analysis.LienardCycles.Main /workspace
  rm -rf "$tmp"
fi
echo "placed the reference proof of QuinticLienard"
