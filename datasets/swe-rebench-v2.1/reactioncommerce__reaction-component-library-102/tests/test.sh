#!/bin/bash
set -uo pipefail

WORKDIR=/reaction-component-library
TEST_FILES=(package/src/components/CartItem/v1/__snapshots__/CartItem.test.js.snap package/src/components/CartItemDetail/v1/__snapshots__/CartItemDetail.test.js.snap package/src/components/CartSummary/v1/__snapshots__/CartSummary.test.js.snap package/src/components/MiniCart/v1/MiniCart.test.js package/src/components/MiniCartSummary/v1/__snapshots__/MiniCartSummary.test.js.snap package/src/components/Price/v1/__snapshots__/Price.test.js.snap package/src/components/QuantityInput/v1/__snapshots__/QuantityInput.test.js.snap package/src/components/StockWarning/v1/__snapshots__/StockWarning.test.js.snap)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
npx jest --verbose --no-color --maxWorkers=1 --testPathIgnorePatterns='package/src/components/QuantityInput/v1/QuantityInput.test.js' --testNamePattern='^(?!.*(?:basic snapshot with empty props|basic snapshot with props|basic snapshot without props|basic snapshot with vendor attribute|Displays a summary of the current items in the cart|Displays a summary with FREE shipping|Displays a summary with calculated taxes|Displays a summary with applied discount|Renders only subtotal|Renders price without a compare at price|Renders price with a compare at price|Renders stock warning when inventory is low)).*$'
HARBOR_TEST_CMD_EOF

V=/logs/verifier
mkdir -p "$V"
echo 0 > "$V/reward.txt"
cd "$WORKDIR"
EXCLUDES=(.gitmodules '*.tar.gz' '*.tgz' '*.zip' '*.rej')

apply_patch() (
  set +eu +o pipefail
  git reset -q || true
  git update-index -q --refresh || true
  ex=()
  for e in "${EXCLUDES[@]}"; do ex+=("--exclude=$e"); done
  apply=(git apply --verbose "${ex[@]}" --whitespace=nowarn)
  "${apply[@]}" "$1" 2>&1 && exit 0
  keep=()
  while IFS= read -r path; do
    glob=$(printf '%s' "$path" | sed 's/[][*?\\]/\\&/g')
    git apply --summary --include="$glob" "$1" | grep -q "^ create mode" &&
      [ -z "$(git apply --check -R --whitespace=nowarn --include="$glob" "$1" 2>&1)" ] && keep+=("--exclude=$glob")
  done < <(LC_ALL=C "${apply[@]}" --check "$1" 2>&1 | sed -n 's/^error: \(.*\): already exists in working directory$/\1/p')
  "${apply[@]}" "${keep[@]}" "$1" 2>&1 && exit 0
  [ -z "$(git apply --check -R --whitespace=nowarn "${ex[@]}" "$1" 2>&1)" ] && exit 0
  "${apply[@]}" "${keep[@]}" --reject "$1" 2>&1
  exit 1
)

for f in "${TEST_FILES[@]}"; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then git restore "$f" 2>/dev/null; else rm -f "$f"; fi
done
cp /tests/test.patch /tmp/test.patch
if ! apply_patch /tmp/test.patch > "$V/test_patch_apply.log" 2>&1; then
  echo "TEST_PATCH_APPLY_FAILED"
  cat "$V/test_patch_apply.log"
  exit 0
fi

export HARBOR_TEST_CMD="${HARBOR_TEST_CMD%$'\n'}"
bash -lc 'timeout -k 10 1800 bash -lc "$HARBOR_TEST_CMD"' 2>&1 | cat > "$V/test_output.log"
echo "test_cmd exit code: ${PIPESTATUS[0]}"

for PY in /opt/harbor-grader/python3 python3 python /opt/conda/bin/python3 ""; do
  PY=$(command -v "$PY" 2>/dev/null) && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null && break
done
if [ -z "$PY" ]; then
  echo "GRADER_PYTHON_UNAVAILABLE: the image has no Python >= 3.8"
  exit 0
fi
if "$PY" -I -S /tests/grade.py /tests/config.json "$V/test_output.log" "$V/report.json" "$V/test_results.json"; then
  echo 1 > "$V/reward.txt"
fi
