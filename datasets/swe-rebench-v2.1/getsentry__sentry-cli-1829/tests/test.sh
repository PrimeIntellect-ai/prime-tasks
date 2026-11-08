#!/bin/bash
set -uo pipefail

WORKDIR=/sentry-cli
TEST_FILES=(tests/integration/_cases/sourcemaps/sourcemaps-upload-help.trycmd)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
set -e
export PATH="/root/.cargo/bin:$PATH" && cargo build --bin sentry-cli
export PATH="/root/.cargo/bin:$PATH" && python3 - <<'PY'
import http.server
import json
import os
import subprocess
import threading

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith("/chunk-upload/"):
            payload = json.dumps({"url": "http://127.0.0.1:%d/api/0/organizations/wat-org/chunk-upload/" % server.server_port, "chunkSize": 8388608, "chunksPerRequest": 64, "maxRequestSize": 33554432, "concurrency": 8, "hashAlgorithm": "sha1", "accept": ["release_files"]}).encode()
        else:
            payload = b"[]"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload)
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        if "assemble" in self.path:
            payload = b'{"state":"created","missingChunks":[]}'
        elif "/releases/wat-release/files/" in self.path:
            payload = b'{"id":"1337","sha1":"f3673e2cea68bcb86bb74254a9efaa381d74929f","name":"~/bundle.min.js.map","size":1522,"dist":null,"headers":{}}'
        elif self.path.endswith("/projects/wat-org/wat-project/releases/"):
            with open("tests/integration/_responses/releases/get-release.json", "rb") as release:
                payload = release.read()
        else:
            payload = b"[]"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = os.environ.copy()
env.update({"SENTRY_URL": "http://127.0.0.1:%d" % server.server_port, "SENTRY_ORG": "wat-org", "SENTRY_PROJECT": "wat-project", "SENTRY_AUTH_TOKEN": "test-token"})
no_files = subprocess.run(["target/debug/sentry-cli", "sourcemaps", "upload", "--strict", "--release", "unused", "--ext", "nomatch", "tests/integration/_fixtures"], env=env, capture_output=True, text=True)
assert no_files.returncode != 0, (no_files.returncode, no_files.stdout, no_files.stderr)
with_files = subprocess.run(["target/debug/sentry-cli", "sourcemaps", "upload", "--strict", "--release", "wat-release", "--no-dedupe", "--ext", "map", "tests/integration/_fixtures/bundle.min.js.map"], env=env, capture_output=True, text=True)
server.shutdown()
assert with_files.returncode == 0, (with_files.returncode, with_files.stdout, with_files.stderr)
PY
cargo test --workspace --verbose integration::sourcemaps::upload
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
