#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

GATEWAY = "/home/user/gateway"
ROUTER = os.path.join(GATEWAY, "router.go")
PROP_TEST = os.path.join(GATEWAY, "router_prop_test.go")
PATCH = os.path.join(GATEWAY, "fix.patch")
LOG = os.path.join(GATEWAY, "test_results.log")

ORIGINAL_ROUTER = r'''package gateway

import (
	"regexp"
	"strings"
)

type Router struct {
	routes map[*regexp.Regexp]string
}

func NewRouter() *Router {
	return &Router{
		routes: make(map[*regexp.Regexp]string),
	}
}

// Register adds a route like "/users/{id:int}"
func (r *Router) Register(pattern string, handlerName string) {
	// BUG: missing anchors ^ and $ causing partial matches
	// BUG: int constraint [0-9]+ will match "123a" partially if not anchored
	regexPattern := strings.ReplaceAll(pattern, "{id:int}", "(?P<id>[0-9]+)")
	compiled := regexp.MustCompile(regexPattern)
	r.routes[compiled] = handlerName
}

// Match returns the handler name and extracted params if it matches
func (r *Router) Match(path string) (string, map[string]string, bool) {
	for regex, handler := range r.routes {
		if regex.MatchString(path) {
			matches := regex.FindStringSubmatch(path)
			params := make(map[string]string)
			for i, name := range regex.SubexpNames() {
				if i != 0 && name != "" {
					params[name] = matches[i]
				}
			}
			return handler, params, true
		}
	}
	return "", nil, false
}
'''

def run(cmd, cwd=GATEWAY):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=120)

def property_test_names():
    with open(PROP_TEST, "r", encoding="utf-8") as f:
        source = f.read()
    return re.findall(r"(?m)^\s*func\s+(Test[A-Za-z0-9_]+)\s*\(", source)

def test_fix_patch_exists_and_valid():
    assert os.path.isfile(PATCH), f"{PATCH} is missing"
    with open(PATCH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "---" in content and "+++" in content, f"{PATCH} does not look like a unified diff"
    assert os.path.isfile(ROUTER), f"{ROUTER} is missing"

    patch_bin = shutil.which("patch")
    assert patch_bin, "patch utility is unavailable"
    with tempfile.TemporaryDirectory() as td:
        candidate = os.path.join(td, "router.go")
        with open(candidate, "w", encoding="utf-8") as f:
            f.write(ORIGINAL_ROUTER)
        result = subprocess.run(
            [patch_bin, "--batch", "--forward", "router.go", PATCH],
            cwd=td, capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            "fix.patch does not apply to the original router.go:\n"
            + result.stdout + result.stderr
        )
        with open(candidate, "rb") as f:
            patched = f.read()
        with open(ROUTER, "rb") as f:
            submitted = f.read()
        assert patched == submitted, "fix.patch does not reproduce the submitted router.go from the original"

def test_router_prop_test_exists_and_valid():
    assert os.path.isfile(PROP_TEST), f"{PROP_TEST} is missing"
    with open(PROP_TEST, "r", encoding="utf-8") as f:
        content = f.read()
    assert "testing/quick" in content, f"{PROP_TEST} does not import 'testing/quick'"
    assert "func Test" in content, f"{PROP_TEST} does not contain a test function"
    assert re.search(r"\.\s*Check(?:Equal)?\s*\(", content), "property test does not call testing/quick Check or CheckEqual"
    assert property_test_names(), "no runnable Test function was found in router_prop_test.go"

def test_test_results_log_exists():
    assert os.path.isfile(LOG), f"{LOG} is missing"
    with open(LOG, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    assert "PASS" in content, f"{LOG} does not contain 'PASS'"
    assert "=== RUN" in content, f"{LOG} does not look like verbose go test output"
    for name in property_test_names():
        assert name in content, f"{LOG} does not show that {name} was run"

def test_router_is_fixed_for_general_paths_and_segments():
    hidden = os.path.join(GATEWAY, "hidden_verify_test.go")
    source = r'''package gateway_test

import (
    "fmt"
    "gateway"
    "math/rand"
    "strings"
    "testing"
)

func TestStrictConstraint(t *testing.T) {
    r := gateway.NewRouter()
    r.Register("/users/{id:int}", "userHandler")

    _, _, ok := r.Match("/users/123a")
    if ok {
        t.Errorf("Expected /users/123a to NOT match, but it did")
    }

    _, _, ok = r.Match("/users/123")
    if !ok {
        t.Errorf("Expected /users/123 to match, but it didn't")
    }
}

func TestVerifierRandomStrictBounds(t *testing.T) {
    rng := rand.New(rand.NewSource(7183921))
    badChars := []string{"a", "Z", "_", "-", ".", "é"}

    for i := 0; i < 250; i++ {
        prefix := fmt.Sprintf("svc%c%c%d", 'a'+rune(rng.Intn(26)), 'a'+rune(rng.Intn(26)), i)
        suffix := fmt.Sprintf("view%c", 'a'+rune(rng.Intn(26)))
        pattern := "/" + prefix + "/{id:int}/" + suffix
        router := gateway.NewRouter()
        router.Register(pattern, "handler")

        n := 1 + rng.Intn(18)
        var b strings.Builder
        for j := 0; j < n; j++ {
            b.WriteByte(byte('0' + rng.Intn(10)))
        }
        id := b.String()
        valid := "/" + prefix + "/" + id + "/" + suffix

        handler, params, ok := router.Match(valid)
        if !ok || handler != "handler" || params["id"] != id {
            t.Fatalf("valid path %q did not match with exact id %q: handler=%q params=%v ok=%v", valid, id, handler, params, ok)
        }

        bad := badChars[rng.Intn(len(badChars))]
        at := rng.Intn(len(id) + 1)
        contaminated := id[:at] + bad + id[at:]
        invalid := []string{
            "/" + prefix + "/" + contaminated + "/" + suffix,
            valid + "/overflow",
            valid + "x",
            "/outside" + valid,
            "/" + prefix + "//" + suffix,
        }
        for _, path := range invalid {
            if _, _, matched := router.Match(path); matched {
                t.Fatalf("out-of-bounds or constraint-violating path %q matched pattern %q", path, pattern)
            }
        }
    }
}
'''
    try:
        with open(hidden, "w", encoding="utf-8") as f:
            f.write(source)
        result = run(["go", "test", "-count=1", "-v", "-run", "^(TestStrictConstraint|TestVerifierRandomStrictBounds)$", "./..."])
        assert result.returncode == 0, "hidden randomized router verification failed:\n" + result.stdout + result.stderr
    finally:
        if os.path.exists(hidden):
            os.remove(hidden)

def test_current_complete_suite_really_passes():
    result = run(["go", "test", "-count=1", "-v", "./..."])
    assert result.returncode == 0, "current go test -v ./... failed:\n" + result.stdout + result.stderr
    for name in property_test_names():
        assert re.search(r"--- PASS: " + re.escape(name) + r"(?:\s|$)", result.stdout), (
            f"the current suite did not execute and pass {name}:\n" + result.stdout
        )

def test_property_test_detects_the_original_partial_match_bug():
    names = property_test_names()
    assert names
    with open(ROUTER, "rb") as f:
        saved = f.read()
    expression = "^(" + "|".join(re.escape(name) for name in names) + ")$"
    try:
        with open(ROUTER, "w", encoding="utf-8") as f:
            f.write(ORIGINAL_ROUTER)
        result = run(["go", "test", "-count=1", "-v", "-run", expression, "./..."])
        assert result.returncode != 0, "router_prop_test.go still passes when the original partial-match bug is restored"
        assert any(re.search(r"--- FAIL: " + re.escape(name) + r"(?:\s|$)", result.stdout) for name in names), (
            "the buggy-router run failed for an unrelated build/setup reason rather than because a property test found a counterexample:\n"
            + result.stdout + result.stderr
        )
    finally:
        with open(ROUTER, "wb") as f:
            f.write(saved)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
