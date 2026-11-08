#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile


def test_compromised_ips_log_parsing():
    """Validates that the compromised IPs were correctly extracted and sorted."""
    output_file = "/home/user/compromised_ips.txt"
    assert os.path.isfile(output_file), f"The output file {output_file} does not exist."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_ips = ["10.0.0.5", "203.0.113.42"]
    assert lines == expected_ips, (
        f"The IPs in {output_file} are incorrect or not sorted properly. "
        f"Expected {expected_ips}, but got {lines}. "
        "Ensure you only matched absolute URLs (http:// or https://) with a 302 status."
    )


def test_go_code_credential_rotation():
    """Preserves the source requirements and verifies the source compiles."""
    go_file = "/home/user/app/auth_server.go"
    assert os.path.isfile(go_file), f"The source file {go_file} is missing."

    with open(go_file, "r") as f:
        content = f.read()

    new_password = "Str0ngR0tat1on!88"
    expected_hash = hashlib.sha256(new_password.encode("utf-8")).hexdigest()

    assert expected_hash in content, (
        "The Go code does not contain the correct SHA-256 hash of the new password. "
        f"Expected to find hash: {expected_hash}"
    )
    assert new_password not in content, "The new password must not be stored in plaintext in the code."
    assert "supersecret_legacy" not in content, "The legacy plaintext password is still in the code."
    assert "crypto/sha256" in content, "The 'crypto/sha256' package is not imported in the Go code."

    build_output = "/tmp/verifier_auth_server"
    try:
        result = subprocess.run(
            ["go", "build", "-o", build_output, go_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
            env={**os.environ, "GO111MODULE": "off"},
        )
        assert result.returncode == 0, f"The updated Go source does not compile:\n{result.stdout}"
        assert os.path.isfile(build_output) and os.access(build_output, os.X_OK)
    finally:
        if os.path.exists(build_output):
            os.remove(build_output)


def test_go_code_open_redirect_fix():
    """Preserves the source checks and exercises loginHandler behavior."""
    go_file = "/home/user/app/auth_server.go"
    with open(go_file, "r") as f:
        content = f.read()

    has_slash_check = "HasPrefix" in content or "next[0]" in content or "StartsWith" in content or '"/"' in content
    has_double_slash_check = '"//"' in content
    assert has_slash_check and has_double_slash_check, (
        "The Go code does not appear to properly validate the 'next' parameter for relative paths. "
        "Ensure you check that it starts with '/' and does NOT start with '//'."
    )
    assert "/dashboard" in content, "The fallback redirect to '/dashboard' is missing."

    test_file = "/home/user/app/verifier_behavior_test.go"
    test_source = r'''package main

import (
    "crypto/rand"
    "encoding/hex"
    "net/http"
    "net/http/httptest"
    "net/url"
    "strings"
    "testing"
)

func invokeLogin(password, next string) *httptest.ResponseRecorder {
    target := "/login?next=" + url.QueryEscape(next)
    form := url.Values{"password": []string{password}}
    req := httptest.NewRequest(http.MethodPost, target, strings.NewReader(form.Encode()))
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    rr := httptest.NewRecorder()
    loginHandler(rr, req)
    return rr
}

func randomToken(t *testing.T) string {
    t.Helper()
    b := make([]byte, 12)
    if _, err := rand.Read(b); err != nil {
        t.Fatal(err)
    }
    return hex.EncodeToString(b)
}

func TestVerifierLoginBehavior(t *testing.T) {
    goodPassword := "Str0ngR0tat1on!88"
    token := randomToken(t)
    goodPath := "/account/" + token

    rr := invokeLogin(goodPassword, goodPath)
    if rr.Code != http.StatusFound || rr.Header().Get("Location") != goodPath {
        t.Fatalf("valid relative redirect: status=%d location=%q", rr.Code, rr.Header().Get("Location"))
    }

    badTargets := []string{
        "http://" + token + ".example/phish",
        "https://" + token + ".example/phish",
        "//" + token + ".example/phish",
        "account/" + token,
        "",
    }
    for _, target := range badTargets {
        rr = invokeLogin(goodPassword, target)
        if rr.Code != http.StatusFound || rr.Header().Get("Location") != "/dashboard" {
            t.Fatalf("unsafe target %q was not replaced: status=%d location=%q", target, rr.Code, rr.Header().Get("Location"))
        }
    }

    for _, wrong := range []string{"supersecret_legacy", "wrong-" + token, ""} {
        rr = invokeLogin(wrong, goodPath)
        if rr.Code != http.StatusUnauthorized {
            t.Fatalf("wrong password %q returned status %d", wrong, rr.Code)
        }
    }
}
'''
    try:
        with open(test_file, "w") as f:
            f.write(test_source)
        result = subprocess.run(
            ["go", "test", go_file, test_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
            env={**os.environ, "GO111MODULE": "off"},
        )
        assert result.returncode == 0, f"loginHandler failed behavioral tests:\n{result.stdout}"
    finally:
        if os.path.exists(test_file):
            os.remove(test_file)


def _trace_commands(trace):
    commands = []
    for raw in trace.splitlines():
        line = raw.lstrip("+").strip()
        if not line:
            continue
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        while words and (words[0] in ("exec", "command") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])):
            words.pop(0)
        if words:
            commands.append(words)
    return commands


def test_run_isolated_script():
    """Checks the script text, then executes it with a harmless unshare shim."""
    script_file = "/home/user/run_isolated.sh"
    target_binary = "/home/user/app/auth_server"
    assert os.path.isfile(script_file), f"The script {script_file} is missing."

    st = os.stat(script_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {script_file} is not executable (chmod +x)."

    with open(script_file, "r") as f:
        content = f.read()

    assert re.search(r"go\s+build", content), "The script does not contain a 'go build' command to compile the executable."
    assert "auth_server" in content, "The script does not reference the 'auth_server' executable."

    unshare_match = re.search(r"unshare\s+(.*)", content)
    assert unshare_match, "The script does not use the 'unshare' command."
    unshare_args = unshare_match.group(1)
    assert "-n" in unshare_args.split() or "--net" in unshare_args.split(), (
        "The 'unshare' command does not include the flag for network namespace isolation (-n or --net)."
    )

    real_go = shutil.which("go")
    assert real_go, "Go compiler is unavailable."

    with tempfile.TemporaryDirectory(prefix="verifier-bin-") as fakebin:
        go_log = os.path.join(fakebin, "go.log")
        unshare_log = os.path.join(fakebin, "unshare.log")

        go_shim = os.path.join(fakebin, "go")
        with open(go_shim, "w") as f:
            f.write(f'''#!/bin/bash
{{
  echo "PWD=$PWD"
  for arg in "$@"; do echo "ARG=$arg"; done
  echo END
}} >> "$VERIFY_GO_LOG"
exec {shlex.quote(real_go)} "$@"
''')

        unshare_shim = os.path.join(fakebin, "unshare")
        with open(unshare_shim, "w") as f:
            f.write('''#!/bin/bash
{
  echo "PWD=$PWD"
  for arg in "$@"; do echo "ARG=$arg"; done
  echo END
} >> "$VERIFY_UNSHARE_LOG"
exit 0
''')
        os.chmod(go_shim, 0o755)
        os.chmod(unshare_shim, 0o755)

        if os.path.lexists(target_binary):
            os.remove(target_binary)

        env = os.environ.copy()
        env["PATH"] = fakebin + os.pathsep + env.get("PATH", "")
        env["VERIFY_GO_LOG"] = go_log
        env["VERIFY_UNSHARE_LOG"] = unshare_log
        env["GO111MODULE"] = "off"

        result = subprocess.run(
            ["bash", "-x", script_file],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, f"run_isolated.sh failed when executed:\n{result.stdout}"
        assert os.path.isfile(target_binary), "Executing run_isolated.sh did not create /home/user/app/auth_server."
        assert os.access(target_binary, os.X_OK), "The compiled auth_server is not executable."
        with open(target_binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "auth_server is not a compiled Linux executable."

        commands = _trace_commands(result.stdout)
        go_commands = [c for c in commands if os.path.basename(c[0]) == "go" and "build" in c[1:]]
        assert go_commands, f"No active go build command was executed:\n{result.stdout}"

        unshare_commands = [c for c in commands if os.path.basename(c[0]) == "unshare"]
        assert unshare_commands, f"No active unshare command was executed:\n{result.stdout}"
        assert os.path.isfile(unshare_log), "The active script did not invoke unshare through PATH."

        with open(unshare_log, "r") as f:
            logged = f.read().splitlines()
        args = [line[4:] for line in logged if line.startswith("ARG=")]
        assert "-n" in args or "--net" in args or any(a.startswith("--net=") for a in args), (
            f"The executed unshare command lacked network namespace isolation; arguments were {args}."
        )
        assert any(os.path.basename(a.rstrip("/")) == "auth_server" for a in args), (
            f"The executed unshare command did not run auth_server; arguments were {args}."
        )
        assert os.path.isfile(go_log), "The active script did not invoke go build through PATH."


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
