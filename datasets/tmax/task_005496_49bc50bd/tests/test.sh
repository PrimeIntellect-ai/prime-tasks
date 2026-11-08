#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

WORKSPACE = "/home/user/workspace"


def test_test_results_log():
    log_path = os.path.join(WORKSPACE, "test_results.log")
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    assert "PASS" in content, f"Expected 'PASS' in {log_path}, but it was not found."


def test_ids_alerts_log():
    log_path = os.path.join(WORKSPACE, "ids_alerts.log")
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    expected_alert = "[ALERT] Path traversal attempt blocked for filename:"
    assert expected_alert in content, f"Expected '{expected_alert}' in {log_path}, but it was not found."


def test_go_files_exist():
    required_files = [
        os.path.join(WORKSPACE, "server.go"),
        os.path.join(WORKSPACE, "middleware.go"),
        os.path.join(WORKSPACE, "server_test.go"),
        os.path.join(WORKSPACE, "go.mod"),
    ]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file {file_path} is missing."


def test_go_tests_pass():
    result = subprocess.run(
        ["go", "test"], cwd=WORKSPACE, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"'go test' failed with output:\n{result.stdout}\n{result.stderr}"
    )


def _without_comments(text):
    text = re.sub(r"/\\*.*?\\*/", "", text, flags=re.S)
    return re.sub(r"//[^\\n]*", "", text)


def test_independent_security_behavior():
    # Test a clean copy of implementation files only. This prevents an authored
    # server_test.go or TestMain from suppressing the verifier's tests.
    tempdir = tempfile.mkdtemp(prefix="upload-verifier-")
    try:
        for name in os.listdir(WORKSPACE):
            src = os.path.join(WORKSPACE, name)
            if name in ("go.mod", "go.sum") or (name.endswith(".go") and not name.endswith("_test.go")):
                if os.path.isfile(src):
                    shutil.copy2(src, os.path.join(tempdir, name))

        sources = []
        for name in os.listdir(tempdir):
            if name.endswith(".go"):
                with open(os.path.join(tempdir, name), encoding="utf-8") as f:
                    sources.append(f.read())
        joined = "\n".join(sources)
        cleaned = _without_comments(joined)

        package_match = re.search(r"(?m)^\\s*package\\s+([A-Za-z_][A-Za-z0-9_]*)", cleaned)
        assert package_match, "Could not determine the implementation package."
        package_name = package_match.group(1)

        middleware_exprs = []
        # Standard middleware: func(http.Handler) http.Handler
        for name in re.findall(
            r"func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_]*\\s+http\\.Handler\\s*\\)\\s+http\\.Handler\\b",
            cleaned, re.S
        ):
            middleware_exprs.append(name)
        # Also accept the equivalent HandlerFunc form.
        for name in re.findall(
            r"func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_]*\\s+http\\.HandlerFunc\\s*\\)\\s+http\\.HandlerFunc\\b",
            cleaned, re.S
        ):
            middleware_exprs.append(
                "func(n http.Handler) http.Handler { return %s(http.HandlerFunc(n.ServeHTTP)) }" % name
            )
        middleware_exprs = list(dict.fromkeys(middleware_exprs))
        assert middleware_exprs, "No HTTP middleware function was found."

        handler_names = re.findall(
            r"func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_]*\\s+http\\.ResponseWriter\\s*,\\s*[A-Za-z_][A-Za-z0-9_]*\\s+\\*http\\.Request\\s*\\)",
            cleaned, re.S
        )
        handler_names = list(dict.fromkeys(handler_names))
        assert handler_names, "No HTTP upload handler function was found."

        router_names = re.findall(
            r"func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\s*\\)\\s+http\\.Handler\\b",
            cleaned, re.S
        )
        router_names = list(dict.fromkeys(router_names))

        with open(os.path.join(WORKSPACE, "server.go"), encoding="utf-8") as f:
            server_source = _without_comments(f.read())
        assert "/upload" in server_source, "server.go does not register the /upload endpoint."
        assert "POST" in server_source or "MethodPost" in server_source, "server.go does not restrict the upload endpoint to POST."

        middleware_list = ",\n        ".join(middleware_exprs)
        handler_list = ",\n        ".join("http.HandlerFunc(%s)" % n for n in handler_names)
        router_list = ",\n        ".join("%s" % n for n in router_names)

        verifier_go = r'''package %s

import (
    "crypto/hmac"
    "crypto/sha256"
    "encoding/base64"
    "fmt"
    "net/http"
    "net/http/httptest"
    "os"
    "strings"
    "testing"
    "time"
)

const verifierSecret = "network-sec-secret-2024"

type verifierMiddleware func(http.Handler) http.Handler

func verifierToken(alg string, exp int64, secret string) string {
    enc := base64.RawURLEncoding
    header := enc.EncodeToString([]byte(fmt.Sprintf(`{"alg":%%q,"typ":"JWT"}`, alg)))
    payload := enc.EncodeToString([]byte(fmt.Sprintf(`{"sub":"verifier","exp":%%d}`, exp)))
    unsigned := header + "." + payload
    mac := hmac.New(sha256.New, []byte(secret))
    mac.Write([]byte(unsigned))
    return unsigned + "." + enc.EncodeToString(mac.Sum(nil))
}

func verifierRequest(token, filename string) *http.Request {
    req := httptest.NewRequest(http.MethodPost, "/upload", nil)
    if token != "" {
        req.AddCookie(&http.Cookie{Name: "session_token", Value: token})
    }
    req.Header.Set("X-File-Name", filename)
    return req
}

func checkMiddleware(mw verifierMiddleware) error {
    valid := verifierToken("HS256", time.Now().Add(time.Hour).Unix(), verifierSecret)
    called := false
    next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        called = true
        w.WriteHeader(http.StatusOK)
    })

    rr := httptest.NewRecorder()
    mw(next).ServeHTTP(rr, verifierRequest(valid, "report.pdf"))
    if rr.Code != http.StatusOK || !called {
        return fmt.Errorf("valid JWT and safe filename: got status %%d, next called=%%v", rr.Code, called)
    }

    invalid := []struct{name, token string}{
        {"missing", ""},
        {"malformed", "not-a-jwt"},
        {"wrong secret", verifierToken("HS256", time.Now().Add(time.Hour).Unix(), "wrong-secret")},
        {"expired", verifierToken("HS256", time.Now().Add(-time.Hour).Unix(), verifierSecret)},
        {"wrong algorithm", verifierToken("HS384", time.Now().Add(time.Hour).Unix(), verifierSecret)},
    }
    for _, tc := range invalid {
        called = false
        rr = httptest.NewRecorder()
        mw(next).ServeHTTP(rr, verifierRequest(tc.token, "report.pdf"))
        if rr.Code != http.StatusUnauthorized || called {
            return fmt.Errorf("%%s token: got status %%d, next called=%%v", tc.name, rr.Code, called)
        }
    }

    logPath := "/home/user/workspace/ids_alerts.log"
    if err := os.Remove(logPath); err != nil && !os.IsNotExist(err) {
        return fmt.Errorf("remove old IDS log: %%v", err)
    }
    malicious := []string{"../../../etc/passwd", `..\\windows\\system.ini`, "/etc/passwd"}
    for _, filename := range malicious {
        called = false
        rr = httptest.NewRecorder()
        mw(next).ServeHTTP(rr, verifierRequest(valid, filename))
        if rr.Code != http.StatusForbidden || called {
            return fmt.Errorf("traversal %%q: got status %%d, next called=%%v", filename, rr.Code, called)
        }
    }
    data, err := os.ReadFile(logPath)
    if err != nil {
        return fmt.Errorf("IDS log was not created: %%v", err)
    }
    logText := string(data)
    for _, filename := range malicious {
        exact := "[ALERT] Path traversal attempt blocked for filename: " + filename
        found := false
        for _, line := range strings.Split(logText, "\n") {
            if line == exact {
                found = true
                break
            }
        }
        if !found {
            return fmt.Errorf("IDS log lacks exact alert line %%q", exact)
        }
    }
    return nil
}

func TestVerifierAuthenticationAndIDS(t *testing.T) {
    candidates := []verifierMiddleware{
        %s
    }
    var failures []string
    for _, candidate := range candidates {
        if err := checkMiddleware(candidate); err == nil {
            return
        } else {
            failures = append(failures, err.Error())
        }
    }
    t.Fatalf("no middleware candidate implemented the required controls: %%s", strings.Join(failures, "; "))
}

func TestVerifierUploadHandler(t *testing.T) {
    candidates := []http.Handler{
        %s
    }
    for _, candidate := range candidates {
        rr := httptest.NewRecorder()
        candidate.ServeHTTP(rr, httptest.NewRequest(http.MethodPost, "/upload", nil))
        if rr.Code == http.StatusOK && rr.Body.String() == "Upload successful" {
            return
        }
    }
    t.Fatal("no upload handler returned status 200 with the exact body Upload successful")
}
''' % (package_name, middleware_list, handler_list)

        if router_names:
            verifier_go += r'''
func TestVerifierExposedRouter(t *testing.T) {
    factories := []func() http.Handler{
        %s
    }
    token := verifierToken("HS256", time.Now().Add(time.Hour).Unix(), verifierSecret)
    for _, factory := range factories {
        handler := factory()
        if handler == nil {
            continue
        }
        rr := httptest.NewRecorder()
        handler.ServeHTTP(rr, verifierRequest(token, "report.pdf"))
        if rr.Code == http.StatusOK && rr.Body.String() == "Upload successful" {
            return
        }
    }
    t.Fatal("no exposed router served authenticated POST /upload correctly")
}
''' % router_list

        with open(os.path.join(tempdir, "verifier_external_test.go"), "w", encoding="utf-8") as f:
            f.write(verifier_go)

        result = subprocess.run(
            ["go", "test", "-run", "^TestVerifier", "-count=1", "-v"],
            cwd=tempdir,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            "Independent security tests failed:\n" + result.stdout + "\n" + result.stderr
        )
    finally:
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
