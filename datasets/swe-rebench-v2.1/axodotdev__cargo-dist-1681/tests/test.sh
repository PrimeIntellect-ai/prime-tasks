#!/bin/bash
set -uo pipefail

WORKDIR=/cargo-dist
TEST_FILES=(cargo-dist/tests/snapshots/axolotlsay_cross2.snap)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
cargo test -p cargo-dist --test integration-tests axolotlsay_cross2 -- --nocapture && python3 - <<'PY'
import json
import pathlib
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix="cargo-dist-apt-xwin-") as tmp:
    root = pathlib.Path(tmp)
    (root / "src").mkdir()
    (root / "Cargo.toml").write_text('''[package]\nname = "apt-xwin-probe"\nversion = "0.1.0"\nedition = "2021"\nrepository = "https://github.com/example/apt-xwin-probe"\n\n[[bin]]\nname = "apt-xwin-probe"\npath = "src/main.rs"\n''')
    (root / "src" / "main.rs").write_text("fn main() {}\n")
    (root / "dist-workspace.toml").write_text('''[workspace]\nmembers = ["cargo:."]\n\n[dist]\ncargo-dist-version = "0.27.1"\ntargets = ["aarch64-pc-windows-msvc"]\nci = ["github"]\nallow-dirty = ["ci"]\n\n[dist.dependencies.apt]\nlibllvm18 = "*"\n''')
    dist_cli = pathlib.Path.cwd() / "target" / "debug" / "dist"
    result = subprocess.run(
        [str(dist_cli), "plan", "--output-format=json"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    plan = json.loads(result.stdout)
    jobs = plan["ci"]["github"]["artifacts_matrix"]["include"]
    job = next(job for job in jobs if "aarch64-pc-windows-msvc" in job["targets"])
    assert job["container"]["package_manager"] == "apt"
    assert "libllvm18" in job["packages_install"]
PY
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
