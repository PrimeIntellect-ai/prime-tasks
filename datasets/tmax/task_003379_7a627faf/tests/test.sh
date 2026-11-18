#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import string
import subprocess
import time
import xml.etree.ElementTree as ET

import pytest
import requests

URL = "http://127.0.0.1:8080/process"
AUTH = {"Authorization": "Token v1-automation-secret"}
SERVER_DIR = "/home/user/server"
MASKER_DIR = "/app/pii-masker"
EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")


def run(cmd, cwd=None, timeout=30):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True,
                          timeout=timeout, check=True)


def parse_response(resp):
    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}. Response: {resp.text}"
    assert "application/xml" in resp.headers.get("Content-Type", ""), \
        f"Expected Content-Type: application/xml, got {resp.headers.get('Content-Type')}"
    try:
        root = ET.fromstring(resp.content)
    except ET.ParseError as exc:
        pytest.fail(f"Failed to parse XML response: {exc}. Response body: {resp.text}")
    assert root.tag == "BatchResponse", f"Expected root tag 'BatchResponse', got '{root.tag}'"
    batch = root.find("BatchID")
    assert batch is not None, "Missing 'BatchID' element in XML response"
    items_el = root.find("Items")
    assert items_el is not None, "Missing 'Items' element in XML response"
    results = {}
    for item in items_el.findall("Item"):
        id_el = item.find("ID")
        content_el = item.find("MaskedContent")
        assert id_el is not None, "Missing 'ID' element in Item"
        assert content_el is not None, "Missing 'MaskedContent' element in Item"
        assert id_el.text not in results, f"Duplicate item ID {id_el.text}"
        results[id_el.text] = content_el.text or ""
    return batch.text, results, len(items_el.findall("Item"))


def wait_for_server(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = requests.post(URL, json={"batch_id": "probe", "items": []}, timeout=.3)
            if response.status_code == 401:
                return
        except requests.RequestException:
            pass
        time.sleep(.1)
    pytest.fail("Could not connect to the server at 127.0.0.1:8080")


def listener_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    found = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(pid))
                    break
        except OSError:
            pass
    return found


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(.05)
    assert not listener_pids(), "Unable to stop the existing listener on port 8080"


def test_source_files_module_and_builds():
    masker_path = "/app/pii-masker/masker.go"
    main_path = "/home/user/server/main.go"
    gomod_path = "/home/user/server/go.mod"
    assert os.path.isfile(masker_path), f"The file {masker_path} does not exist."
    assert os.path.isfile(main_path), f"The file {main_path} does not exist."
    assert os.path.isfile(gomod_path), f"The file {gomod_path} does not exist."

    with open(masker_path) as handle:
        content = handle.read()
    # Preserve the original source assertion and additionally prove the package builds.
    assert '"strings"' in content or "\n\tstrings\n" in content or "strings" in content, \
        "The file masker.go is still missing the 'strings' import."
    run(["go", "build", "./..."], cwd=MASKER_DIR)
    run(["go", "build", "./..."], cwd=SERVER_DIR)

    mod = json.loads(run(["go", "mod", "edit", "-json"], cwd=SERVER_DIR).stdout)
    replacements = mod.get("Replace") or []
    assert any(r.get("Old", {}).get("Path") == "example.com/pii-masker" and
               os.path.realpath(os.path.join(SERVER_DIR, r.get("New", {}).get("Path", ""))) == MASKER_DIR
               for r in replacements), \
        "go.mod must replace example.com/pii-masker with /app/pii-masker"
    resolved = run(["go", "list", "-m", "-f", "{{.Dir}}", "example.com/pii-masker"],
                   cwd=SERVER_DIR).stdout.strip()
    assert os.path.realpath(resolved) == MASKER_DIR, f"Masker module resolves to {resolved}, not {MASKER_DIR}"

    analyzer = r'''package main
import (
  "fmt"
  "go/ast"
  "go/parser"
  "go/token"
  "os"
  "strconv"
)
func main() {
  path := os.Args[len(os.Args)-1]
  f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
  if err != nil { panic(err) }
  aliases := map[string]bool{}
  dot := false
  imported := false
  for _, i := range f.Imports {
    p, _ := strconv.Unquote(i.Path.Value)
    if p == "example.com/pii-masker" {
      imported = true
      if i.Name == nil { aliases["piimasker"] = true
      } else if i.Name.Name == "." { dot = true
      } else if i.Name.Name != "_" { aliases[i.Name.Name] = true }
    }
  }
  call, goroutine := false, false
  ast.Inspect(f, func(n ast.Node) bool {
    switch x := n.(type) {
    case *ast.GoStmt:
      goroutine = true
    case *ast.CallExpr:
      switch fn := x.Fun.(type) {
      case *ast.SelectorExpr:
        if id, ok := fn.X.(*ast.Ident); ok && aliases[id.Name] && fn.Sel.Name == "MaskText" { call = true }
      case *ast.Ident:
        if dot && fn.Name == "MaskText" { call = true }
      }
    }
    return true
  })
  if f.Name.Name != "main" || !imported || !call || !goroutine {
    fmt.Fprintf(os.Stderr, "package_main=%v import=%v MaskText_call=%v go_statement=%v\n", f.Name.Name == "main", imported, call, goroutine)
    os.Exit(1)
  }
}
'''
    with open("/tmp/check_server_ast.go", "w") as handle:
        handle.write(analyzer)
    result = subprocess.run(["go", "run", "/tmp/check_server_ast.go", "--", main_path],
                            text=True, capture_output=True)
    assert result.returncode == 0, "main.go must import piimasker, call MaskText, and use a go statement: " + result.stderr


def test_server_unauthorized():
    payload = {"batch_id": "test-1", "items": [{"id": 1, "content": "Email test@example.com"}]}
    try:
        resp = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:8080. Is it running?")
    assert resp.status_code == 401, f"Expected HTTP 401 for missing auth, got {resp.status_code}"
    resp = requests.post(URL, json=payload, headers={"Authorization": "Token wrong-secret"}, timeout=2)
    assert resp.status_code == 401, f"Expected HTTP 401 for incorrect auth, got {resp.status_code}"


def test_server_process_success_original_case():
    payload = {
        "batch_id": "B-992",
        "items": [
            {"id": 1, "content": "Contact me at john.doe@example.com immediately."},
            {"id": 2, "content": "My phone is 555-0199."}
        ]
    }
    try:
        resp = requests.post(URL, json=payload, headers=AUTH, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:8080. Is it running?")
    batch, results, count = parse_response(resp)
    assert batch == "B-992", f"Expected BatchID 'B-992', got '{batch}'"
    assert count == 2, f"Expected 2 items in XML response, got {count}"
    assert "1" in results, "Item with ID 1 missing from response"
    assert "2" in results, "Item with ID 2 missing from response"
    assert results["1"] == "Contact me at [REDACTED_EMAIL] immediately.", f"Incorrect masked content for ID 1: {results['1']}"
    assert results["2"] == "My phone is 555-0199.", f"Incorrect masked content for ID 2: {results['2']}"


def test_arbitrary_batch_is_processed():
    nonce = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(14))
    batch_id = "batch-" + nonce
    contents = [
        f"first {nonce}.one+tag@example.org and second_{nonce}@sub.example.net done",
        f"No email here: {nonce} & <safe>.",
        f"Prefix user-{nonce}@mail.co.uk suffix",
        f"{nonce}@example.com,{nonce}2@example.io",
        f"literal [REDACTED_EMAIL] plus a{nonce}@b.dev",
        f"Mixed CASE_{nonce}@Example.COM remains otherwise unchanged",
        f"phone 555-{random.randint(1000,9999)} only"
    ]
    ids = random.sample(range(10000, 90000), len(contents))
    payload = {"batch_id": batch_id,
               "items": [{"id": item_id, "content": text} for item_id, text in zip(ids, contents)]}
    resp = requests.post(URL, json=payload, headers=AUTH, timeout=3)
    batch, results, count = parse_response(resp)
    assert batch == batch_id
    assert count == len(contents)
    expected = {str(i): EMAIL_RE.sub("[REDACTED_EMAIL]", text) for i, text in zip(ids, contents)}
    assert results == expected, f"Arbitrary batch was not processed correctly: {results}"


def test_server_really_calls_masker_and_processes_in_parallel():
    masker_path = os.path.join(MASKER_DIR, "masker.go")
    with open(masker_path, "rb") as handle:
        original_masker = handle.read()
    nonce = "VERIFIER_" + ''.join(random.SystemRandom().choice(string.ascii_letters) for _ in range(18))
    instrumented = f'''package piimasker
import "time"
func MaskText(content string) string {{
    time.Sleep(250 * time.Millisecond)
    return "{nonce}<" + content + ">"
}}
'''
    proc = None
    restored = False
    try:
        with open(masker_path, "w") as handle:
            handle.write(instrumented)
        run(["go", "build", "-o", "/tmp/verifier_instrumented_server", "."], cwd=SERVER_DIR)
        with open(masker_path, "wb") as handle:
            handle.write(original_masker)
        restored = True

        stop_server()
        proc = subprocess.Popen(["/tmp/verifier_instrumented_server"], cwd=SERVER_DIR,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                start_new_session=True)
        wait_for_server()

        values = [f"runtime-value-{nonce}-{i}" for i in range(8)]
        ids = list(range(701, 709))
        payload = {"batch_id": "runtime-" + nonce,
                   "items": [{"id": i, "content": value} for i, value in zip(ids, values)]}
        start = time.monotonic()
        resp = requests.post(URL, json=payload, headers=AUTH, timeout=5)
        elapsed = time.monotonic() - start
        batch, results, count = parse_response(resp)
        assert batch == "runtime-" + nonce
        assert count == len(values)
        expected = {str(i): f"{nonce}<{value}>" for i, value in zip(ids, values)}
        assert results == expected, "The running server did not use piimasker.MaskText from the replaced local module"
        # Eight sequential instrumented calls take at least two seconds. This permits
        # substantial scheduling overhead and worker pools while requiring real overlap.
        assert elapsed < 1.5, f"Items were not processed in parallel (8 x 250ms calls took {elapsed:.2f}s)"
    finally:
        if proc is not None:
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        stop_server()
        if not restored:
            with open(masker_path, "wb") as handle:
                handle.write(original_masker)
        # Restore a genuine server on the required address after verification.
        try:
            run(["go", "build", "-o", "/tmp/verifier_original_server", "."], cwd=SERVER_DIR)
            subprocess.Popen(["/tmp/verifier_original_server"], cwd=SERVER_DIR,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
