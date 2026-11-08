#!/bin/bash
set -uo pipefail

WORKDIR=/terraform-provider-openapi
TEST_FILES=(tests/integration/resource_cdns_test.go)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
set -e
echo "== contract: go.mod declares go 1.16 =="
grep -Eq '^go 1\.16$' go.mod
echo "== contract: .travis.yml builds with Go 1.16.x =="
grep -Eq '1\.16' .travis.yml
echo "== contract: .travis.yml installs GoReleaser via go install =="
grep -Eq 'go install' .travis.yml
echo "== contract: .travis.yml does not use the legacy GoReleaser curl installer =="
if grep -Eq 'install\.goreleaser\.com/github\.com/goreleaser/goreleaser\.sh' .travis.yml; then
  echo "legacy GoReleaser curl installer is still configured" >&2
  false
fi
echo "== contract: README documents Go >= 1.16 =="
grep -Eq 'Go.*1\.16' README.md
echo "== contract: GoReleaser uses the Go toolchain selected by Travis =="
if grep -Eq '^[[:space:]]*go:[[:space:]]*' .goreleaser.yml; then
  echo "GoReleaser overrides the selected Go toolchain" >&2
  false
fi
echo "== contract: GoReleaser does not select a Go version older than 1.16 =="
if grep -Eq '^[[:space:]]*go:[[:space:]]*[^0-9]*1\.(0|[1-9]|1[0-5])([.]|[^0-9]|$)' .goreleaser.yml; then
  echo "GoReleaser is configured with a Go version older than 1.16" >&2
  false
fi
echo "== unit tests =="
go test -v $(go list ./... | grep -v "examples\|vendor\|integration\|e2e")
echo "ALL CONTRACT CHECKS PASSED"
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
