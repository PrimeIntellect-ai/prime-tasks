#!/bin/bash
set -e
mkdir -p /logs/verifier

run_checks() {
    cat << 'GO_EOF' > /tmp/check_fuzz.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strings"
)

func main() {
    path := "/app/healthd/parser_test.go"
    file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    found := false
    for _, decl := range file.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Body == nil || !strings.HasPrefix(fn.Name.Name, "Fuzz") {
            continue
        }

        targetsInput := false
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            fuzzCall, ok := n.(*ast.CallExpr)
            if !ok {
                return true
            }
            sel, ok := fuzzCall.Fun.(*ast.SelectorExpr)
            if !ok || sel.Sel.Name != "Fuzz" {
                return true
            }

            for _, arg := range fuzzCall.Args {
                callback, ok := arg.(*ast.FuncLit)
                if !ok || callback.Type.Params == nil {
                    continue
                }
                params := map[string]bool{}
                for _, field := range callback.Type.Params.List {
                    for _, name := range field.Names {
                        params[name.Name] = true
                    }
                }

                ast.Inspect(callback.Body, func(inner ast.Node) bool {
                    call, ok := inner.(*ast.CallExpr)
                    if !ok {
                        return true
                    }
                    ident, ok := call.Fun.(*ast.Ident)
                    if !ok || ident.Name != "ParseTags" || len(call.Args) == 0 {
                        return true
                    }
                    input, ok := call.Args[0].(*ast.Ident)
                    if ok && params[input.Name] {
                        targetsInput = true
                    }
                    return true
                })
            }
            return true
        })

        if targetsInput {
            fmt.Println(fn.Name.Name)
            found = true
        }
    }

    if !found {
        fmt.Fprintln(os.Stderr, "parser_test.go has no real fuzz function that passes fuzzed input to ParseTags")
        os.Exit(1)
    }
}
GO_EOF

    cat << 'GO_EOF' > /app/healthd/verifier_dynamic_test.go
package main

import (
    "math/rand"
    "testing"
    "time"
)

func TestVerifierParseTags(t *testing.T) {
    // Every unsigned high-byte length must be rejected rather than converted
    // through int8, recursed upon, or interpreted as payload.
    for n := 128; n <= 255; n++ {
        input := []byte{byte(n), 'x', 'y', 'z'}
        if got := ParseTags(input); got != "" {
            t.Fatalf("high invalid length %d: got %q, want empty", n, got)
        }
    }

    // Zero and truncated positive lengths are invalid as well.
    if got := ParseTags([]byte{0}); got != "" {
        t.Fatalf("zero length: got %q, want empty", got)
    }
    for n := 1; n < 128; n++ {
        input := make([]byte, n)
        input[0] = byte(n)
        if got := ParseTags(input); got != "" {
            t.Fatalf("truncated length %d: got %q, want empty", n, got)
        }
    }

    // Exercise varied valid recursive records and check their parsed output.
    r := rand.New(rand.NewSource(time.Now().UnixNano()))
    for trial := 0; trial < 100; trial++ {
        records := 1 + r.Intn(12)
        input := make([]byte, 0)
        expected := make([]byte, 0)
        for record := 0; record < records; record++ {
            size := 1 + r.Intn(40)
            payload := make([]byte, size)
            for i := range payload {
                payload[i] = byte('a' + r.Intn(26))
            }
            input = append(input, byte(size))
            input = append(input, payload...)
            expected = append(expected, payload...)
        }
        if got := ParseTags(input); got != string(expected) {
            t.Fatalf("trial %d: got %q, want %q", trial, got, string(expected))
        }
    }
}
GO_EOF
    trap 'rm -f /app/healthd/verifier_dynamic_test.go /tmp/check_fuzz.go /tmp/test_final_state.py' RETURN

    cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import requests


def test_malicious_tag_extracted():
    """Verify that the malicious tag was properly extracted to the required file."""
    path = "/home/user/malicious_tag.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "len=128;payload=recursive_doom"
    assert content == expected, f"Expected tag content '{expected}', but got '{content}'."


def test_fuzz_test_exists():
    """Verify that a Go fuzz test was written in parser_test.go."""
    path = "/app/healthd/parser_test.go"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "testing.F" in content, f"Fuzz test must use 'testing.F', not found in {path}."
    assert "func Fuzz" in content, f"Fuzz test function (e.g., func Fuzz...) not found in {path}."


def test_healthd_good_request():
    """Verify that the healthd service correctly handles a good target."""
    url = "http://127.0.0.1:8080/check?url=http://127.0.0.1:8081/good"
    try:
        resp = requests.get(url, timeout=5)
    except requests.RequestException as e:
        assert False, f"Request to healthd failed: {e}. Is the service running?"

    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}. Body: {resp.text}"
    assert "status: healthy" in resp.text, f"Expected 'status: healthy' in response body, got: {resp.text}"
    assert resp.text == "status: healthy, tags: okay", f"Parsed good tag output was incorrect: {resp.text!r}"


def test_healthd_bad_request_does_not_crash():
    """Verify that the healthd service handles the malicious payload without crashing."""
    bad_url = "http://127.0.0.1:8080/check?url=http://127.0.0.1:8081/bad"
    try:
        resp = requests.get(bad_url, timeout=5)
    except requests.exceptions.ReadTimeout:
        assert False, "Request timed out. The service likely entered an infinite loop."
    except requests.exceptions.ConnectionError:
        assert False, "Connection error. The service likely crashed (stack overflow)."
    except requests.RequestException as e:
        assert False, f"Request failed unexpectedly: {e}"

    assert resp.text == "status: healthy, tags: ", f"Invalid high length was not handled correctly: {resp.text!r}"

    good_url = "http://127.0.0.1:8080/check?url=http://127.0.0.1:8081/good"
    try:
        resp_good = requests.get(good_url, timeout=5)
        assert resp_good.status_code == 200, f"Service is up but returned {resp_good.status_code} after bad request."
    except requests.RequestException as e:
        assert False, f"Service crashed or became unresponsive after malicious payload: {e}"


def test_healthd_varied_parser_outputs():
    """Exercise the running service with verifier-generated valid and invalid records."""
    routes = {}
    expected = {}

    for i in range(8):
        pieces = [secrets.token_hex(2 + (i % 4)) for _ in range(1 + (i % 3))]
        body = b"".join(bytes([len(piece)]) + piece.encode("ascii") for piece in pieces)
        path = "/valid-" + secrets.token_hex(8)
        routes[path] = body
        expected[path] = "".join(pieces)

    for length in (128, 129, 191, 200, 254, 255):
        path = "/invalid-" + secrets.token_hex(8)
        routes[path] = bytes([length]) + secrets.token_bytes(1 + secrets.randbelow(8))
        expected[path] = ""

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in routes:
                self.send_response(404)
                self.end_headers()
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(routes[self.path])

        def log_message(self, format, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        for path, wanted_tags in expected.items():
            target = f"http://127.0.0.1:{port}{path}"
            response = requests.get(
                "http://127.0.0.1:8080/check",
                params={"url": target},
                timeout=5,
            )
            assert response.status_code == 200, response.text
            assert response.text == f"status: healthy, tags: {wanted_tags}", (
                f"For target payload {routes[path]!r}, got {response.text!r}"
            )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
PY_EOF

    cd /app/healthd || return 1

    # Compile all submitted test code and directly verify ParseTags behavior.
    GOMAXPROCS=2 timeout 45s go test -count=1 -run '^TestVerifierParseTags$' . || return 1

    # Parse the Go syntax tree so comments cannot masquerade as a fuzz test,
    # then run each real fuzzer against the fixed parser.
    fuzz_names=$(go run /tmp/check_fuzz.go) || return 1
    [ -n "$fuzz_names" ] || return 1
    while IFS= read -r fuzz_name; do
        [ -n "$fuzz_name" ] || continue
        GOMAXPROCS=2 timeout 45s go test -count=1 -parallel=1 -run "^${fuzz_name}$" -fuzz "^${fuzz_name}$" -fuzztime=1s . || return 1
    done <<< "$fuzz_names"

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
