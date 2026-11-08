#!/bin/bash
set -uo pipefail

WORKDIR=/rust-contracts-stylus
TEST_FILES=(lib/e2e-proc/Cargo.toml lib/e2e/Cargo.toml)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
python3 -c 'import collections, pathlib, tomllib; root=tomllib.loads(pathlib.Path("Cargo.toml").read_text()); shared=collections.defaultdict(list); members=root["workspace"]["members"]; sections=("dependencies", "dev-dependencies", "build-dependencies"); [shared[name].append((manifest, spec)) for member in members for manifest in pathlib.Path(member).rglob("Cargo.toml") for data in (tomllib.loads(manifest.read_text()),) for section in sections for name, spec in data.get(section, {}).items()]; workspace=root["workspace"].get("dependencies", {}); failures=[f"{manifest}: {name} inherits a dependency absent from the workspace" for member in members for manifest in pathlib.Path(member).rglob("Cargo.toml") for data in (tomllib.loads(manifest.read_text()),) for section in sections for name, spec in data.get(section, {}).items() if isinstance(spec, dict) and spec.get("workspace") is True and name not in workspace]; failures += [f"{manifest}: {name} must inherit its workspace dependency" for name, declarations in shared.items() if len(declarations) >= 2 and name in workspace for manifest, spec in declarations if not (isinstance(spec, dict) and spec.get("workspace") is True)]; assert not failures, "\\n".join(failures); print("shared workspace dependency declarations are inherited")' && cargo test --locked --features std --all-targets --no-fail-fast
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
