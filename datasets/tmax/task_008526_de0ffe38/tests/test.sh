#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import shutil
import subprocess
import tempfile
import textwrap
import pytest

AUTH_SERVICE_DIR = "/home/user/auth-service"
RESOLUTION_FILE = "/home/user/resolution.json"


def test_go_build_success():
    """Test that go build runs successfully without linker errors."""
    assert os.path.isdir(AUTH_SERVICE_DIR), f"Directory {AUTH_SERVICE_DIR} does not exist."

    try:
        subprocess.run(
            ["go", "build"],
            cwd=AUTH_SERVICE_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=120,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'go build' failed with exit code {e.returncode}. Stderr: {e.stderr}")


def test_built_service_runs_and_uses_generate_token():
    """Build and execute the service, and verify main really calls GenerateToken."""
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "auth-service")
        try:
            subprocess.run(
                ["go", "build", "-o", binary, "."],
                cwd=AUTH_SERVICE_DIR,
                capture_output=True,
                text=True,
                check=True,
                timeout=120,
            )
            result = subprocess.run(
                [binary],
                cwd=AUTH_SERVICE_DIR,
                capture_output=True,
                text=True,
                check=True,
                timeout=30,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"Built auth-service did not execute successfully: {e}")

        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert any(re.fullmatch(r"admin-\d+", line) for line in lines), (
            f"Service output did not contain an admin token: {result.stdout!r}"
        )

    checker = os.path.join(td if False else "/tmp", "check_auth_main_ast.go")
    with open(checker, "w") as f:
        f.write(textwrap.dedent(r'''
            package main

            import (
                "fmt"
                "go/ast"
                "go/parser"
                "go/token"
                "os"
            )

            func main() {
                path := os.Args[len(os.Args)-1]
                file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
                if err != nil {
                    fmt.Fprintln(os.Stderr, err)
                    os.Exit(2)
                }
                found := false
                for _, decl := range file.Decls {
                    fn, ok := decl.(*ast.FuncDecl)
                    if !ok || fn.Name.Name != "main" || fn.Body == nil {
                        continue
                    }
                    ast.Inspect(fn.Body, func(n ast.Node) bool {
                        call, ok := n.(*ast.CallExpr)
                        if !ok {
                            return true
                        }
                        id, ok := call.Fun.(*ast.Ident)
                        if ok && id.Name == "GenerateToken" {
                            found = true
                        }
                        return true
                    })
                }
                if !found {
                    fmt.Fprintln(os.Stderr, "main does not call GenerateToken")
                    os.Exit(1)
                }
            }
        '''))
    result = subprocess.run(
        ["go", "run", checker, "--", os.path.join(AUTH_SERVICE_DIR, "main.go")],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr


def test_go_test_race_success():
    """Test that go test -race passes reliably."""
    try:
        subprocess.run(
            ["go", "test", "-race", "./..."],
            cwd=AUTH_SERVICE_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=180,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'go test -race ./...' failed with exit code {e.returncode}. Stderr: {e.stderr}\nStdout: {e.stdout}")


def test_independent_concurrent_generate_token():
    """Run a verifier-owned race test without trusting repository test files."""
    with tempfile.TemporaryDirectory() as td:
        for name in os.listdir(AUTH_SERVICE_DIR):
            source = os.path.join(AUTH_SERVICE_DIR, name)
            if name.endswith(".go") and not name.endswith("_test.go") and os.path.isfile(source):
                shutil.copy2(source, os.path.join(td, name))

        assert any(name.endswith(".go") for name in os.listdir(td)), "No production Go files found"

        with open(os.path.join(td, "go.mod"), "w") as f:
            f.write("module verifier-auth-service\n\ngo 1.18\n")

        with open(os.path.join(td, "verifier_concurrency_test.go"), "w") as f:
            f.write(textwrap.dedent(r'''
                package main

                import (
                    "fmt"
                    "reflect"
                    "regexp"
                    "sync"
                    "testing"
                )

                func verifierCacheLookup(key string) (string, bool) {
                    if sm, ok := interface{}(&tokenCache).(*sync.Map); ok {
                        value, found := sm.Load(key)
                        if !found {
                            return "", false
                        }
                        s, ok := value.(string)
                        return s, ok
                    }

                    value := reflect.ValueOf(tokenCache)
                    if value.Kind() != reflect.Map || value.Type().Key().Kind() != reflect.String {
                        return "", false
                    }
                    item := value.MapIndex(reflect.ValueOf(key))
                    if !item.IsValid() || item.Kind() != reflect.String {
                        return "", false
                    }
                    return item.String(), true
                }

                func TestVerifierConcurrentGenerateToken(t *testing.T) {
                    const workers = 1200
                    results := make(chan string, workers)
                    var wg sync.WaitGroup

                    for i := 0; i < workers; i++ {
                        wg.Add(1)
                        go func(i int) {
                            defer wg.Done()
                            user := fmt.Sprintf("verifier-user-%d", i%31)
                            token := GenerateToken(user)
                            matched, err := regexp.MatchString("^"+regexp.QuoteMeta(user)+"-[0-9]+$", token)
                            if err != nil || !matched {
                                t.Errorf("GenerateToken(%q) returned malformed token %q", user, token)
                            }
                            results <- token
                        }(i)
                    }
                    wg.Wait()
                    close(results)

                    seen := make(map[string]bool)
                    for token := range results {
                        seen[token] = true
                    }
                    for i := 0; i < 31; i++ {
                        user := fmt.Sprintf("verifier-user-%d", i)
                        cached, ok := verifierCacheLookup(user)
                        if !ok {
                            t.Fatalf("tokenCache has no usable entry for %q", user)
                        }
                        if !seen[cached] {
                            t.Fatalf("tokenCache entry %q for %q was not returned by GenerateToken", cached, user)
                        }
                    }
                }
            '''))

        try:
            subprocess.run(
                ["go", "test", "-race", "-count=3", "."],
                cwd=td,
                capture_output=True,
                text=True,
                check=True,
                timeout=240,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(
                "Verifier-owned concurrent GenerateToken test failed. "
                f"Stderr: {e.stderr}\nStdout: {e.stdout}"
            )


def test_main_go_cgo_removed():
    """Test that CGO directives are removed from main.go."""
    main_go_path = os.path.join(AUTH_SERVICE_DIR, "main.go")
    assert os.path.isfile(main_go_path), f"File {main_go_path} does not exist."

    with open(main_go_path, "r") as f:
        content = f.read()

    assert "#cgo" not in content, "CGO directives (#cgo) are still present in main.go."
    assert "import \"C\"" not in content, "import \"C\" is still present in main.go."


def test_auth_go_mutex_added():
    """Test that a mutex is used in auth.go to protect tokenCache."""
    auth_go_path = os.path.join(AUTH_SERVICE_DIR, "auth.go")
    assert os.path.isfile(auth_go_path), f"File {auth_go_path} does not exist."

    with open(auth_go_path, "r") as f:
        content = f.read()

    has_mutex = "sync.Mutex" in content or "sync.RWMutex" in content or "sync.Map" in content
    assert has_mutex, "auth.go does not seem to use sync.Mutex, sync.RWMutex, or sync.Map to fix the race condition."


def test_resolution_json_contents():
    """Test that resolution.json exists and contains the correct answers."""
    assert os.path.isfile(RESOLUTION_FILE), f"File {RESOLUTION_FILE} does not exist."

    with open(RESOLUTION_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESOLUTION_FILE} is not a valid JSON file.")

    assert "build_fix" in data, "Key 'build_fix' missing in resolution.json"
    assert "bug_type" in data, "Key 'bug_type' missing in resolution.json"
    assert "fixed_variable" in data, "Key 'fixed_variable' missing in resolution.json"

    build_fix = str(data["build_fix"]).lower()
    bug_type = str(data["bug_type"]).lower()
    fixed_var = str(data["fixed_variable"])

    assert "main.go" in build_fix or "cgo" in build_fix, f"Expected 'build_fix' to mention main.go or cgo, got: {data['build_fix']}"
    assert "race" in bug_type, f"Expected 'bug_type' to mention race condition, got: {data['bug_type']}"
    assert fixed_var == "tokenCache", f"Expected 'fixed_variable' to be 'tokenCache', got: {data['fixed_variable']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
