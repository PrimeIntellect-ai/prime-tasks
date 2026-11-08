#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = "/home/user/sec_logger"
RUST_DIR = os.path.join(ROOT, "rust_lib")
GO_DIR = os.path.join(ROOT, "go_cli")
REPORT = os.path.join(ROOT, "final_report.txt")
SCRIPT = os.path.join(ROOT, "ci_build.sh")
EXPECTED_REPORT = "Detected 3 SQLi attempts\n"


def run(cmd, cwd=None, timeout=180):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def test_final_report_exists_and_correct():
    assert os.path.exists(REPORT), f"Final report missing at {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read()
    assert content == EXPECTED_REPORT, (
        f"Expected final report to contain exactly {EXPECTED_REPORT!r}, but got {content!r}"
    )


def test_project_was_organized():
    assert os.path.isfile(os.path.join(RUST_DIR, "src", "lib.rs"))
    assert os.path.isfile(os.path.join(GO_DIR, "main.go"))
    assert os.path.isfile(os.path.join(GO_DIR, "go.mod"))
    assert os.path.isfile(os.path.join(ROOT, "logs.jsonl"))
    assert not os.path.exists("/home/user/raw_source/analyzer.rs"), "analyzer.rs was copied rather than moved"
    assert not os.path.exists("/home/user/raw_source/main.go"), "main.go was copied rather than moved"
    assert not os.path.exists("/home/user/raw_source/logs.jsonl"), "logs.jsonl was copied rather than moved"


def test_cargo_toml_configuration():
    cargo_toml_path = os.path.join(RUST_DIR, "Cargo.toml")
    assert os.path.exists(cargo_toml_path), f"Cargo.toml missing at {cargo_toml_path}"
    with open(cargo_toml_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "staticlib" in content, "Cargo.toml does not define crate-type containing 'staticlib'"
    assert "proptest" in content, "Cargo.toml does not contain 'proptest' dependency"

    result = run(["cargo", "metadata", "--format-version", "1", "--no-deps"], cwd=RUST_DIR)
    assert result.returncode == 0, result.stderr
    metadata = json.loads(result.stdout)
    package = metadata["packages"][0]
    assert any("staticlib" in target.get("kind", []) for target in package["targets"]), (
        "The Rust library target is not actually configured as a staticlib"
    )
    assert any(dep["name"] == "proptest" and dep.get("kind") == "dev" for dep in package["dependencies"]), (
        "proptest must be a real dev-dependency"
    )


def test_rust_ffi_and_property_test_source():
    lib_path = os.path.join(RUST_DIR, "src", "lib.rs")
    src = open(lib_path, encoding="utf-8").read()
    uncommented = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    uncommented = re.sub(r"(?m)//.*$", "", uncommented)

    assert re.search(r"pub\s+(?:unsafe\s+)?extern\s+\"C\"\s+fn\s+analyze_payload", uncommented), (
        "analyze_payload is not exported through the C ABI"
    )
    assert "#[no_mangle]" in uncommented or "#[unsafe(no_mangle)]" in uncommented
    assert "CStr" in uncommented and re.search(r"\.is_null\s*\(", uncommented), (
        "The FFI function must safely handle a C string pointer"
    )

    macro_pos = uncommented.find("proptest!")
    assert macro_pos >= 0, "No proptest! property test was found in lib.rs"
    assert re.search(r"any\s*::\s*<\s*String\s*>|any\s*\(\s*\)|[\"']\.\*[\"']", uncommented[macro_pos:]), (
        "The property test does not generate arbitrary strings"
    )

    safe_functions = re.findall(r"fn\s+([A-Za-z_]\w*)\s*\([^)]*&\s*str[^)]*\)", uncommented)
    assert safe_functions, "No safe/internal Rust string-analysis function was found"
    assert any(uncommented[:macro_pos].count(name) >= 2 and name in uncommented[macro_pos:] for name in safe_functions), (
        "The property test and C wrapper must exercise the same safe/internal string logic"
    )


def test_go_worker_pool_and_cgo_source():
    main_path = os.path.join(GO_DIR, "main.go")
    src = open(main_path, encoding="utf-8").read()
    assert re.search(r'#cgo\s+LDFLAGS:.*-L\.\./rust_lib/target/release.*-lrust_lib', src), (
        "CGO does not link the release Rust static library"
    )
    assert "-ldl" in src and "-lm" in src
    assert re.search(r'import\s+(?:\([^)]*)?\s*"C"', src, re.S), "main.go does not import C"
    assert re.search(r"C\.analyze_payload\s*\(", src), "Go does not call the Rust FFI function"
    assert re.search(r"make\s*\(\s*chan\b|\bchan\s+", src), "No Go channel was found"
    assert re.search(r"\bgo\s+(?:func\s*\(|[A-Za-z_]\w*\s*\()", src), "No goroutine was found"
    assert "json.Unmarshal" in src or "json.NewDecoder" in src


def test_ci_build_script():
    assert os.path.exists(SCRIPT), f"CI script missing at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"CI script at {SCRIPT} is not executable"
    script_text = open(SCRIPT, encoding="utf-8").read()
    assert re.search(r"set\s+-[^\n]*e", script_text), "CI script does not stop on command failure"
    assert re.search(r"cargo\s+test", script_text), "CI script does not run Rust tests"
    assert re.search(r"cargo\s+build[^\n]*(?:--release|-r) |cargo\s+build\s+(?:--release|-r)", script_text + " "), (
        "CI script does not build Rust in release mode"
    )
    assert re.search(r"go\s+build[^\n]*-o\s+(?:\./)?scanner", script_text), "CI script does not build scanner"
    assert "logs.jsonl" in script_text and "final_report.txt" in script_text and ">" in script_text, (
        "CI script does not run scanner on logs.jsonl and redirect its output"
    )

    # Remove build products so a successful verifier run requires the pipeline to recreate them.
    shutil.rmtree(os.path.join(RUST_DIR, "target"), ignore_errors=True)
    for path in (os.path.join(GO_DIR, "scanner"), REPORT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run([SCRIPT], cwd=ROOT, timeout=300)
    assert result.returncode == 0, (
        f"CI script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    archive = os.path.join(RUST_DIR, "target", "release", "librust_lib.a")
    scanner = os.path.join(GO_DIR, "scanner")
    assert os.path.isfile(archive) and os.path.getsize(archive) > 0, "CI did not produce librust_lib.a"
    assert os.path.isfile(scanner) and os.access(scanner, os.X_OK), "CI did not produce an executable scanner"
    with open(scanner, "rb") as f:
        assert f.read(4) == b"\x7fELF", "scanner is not a compiled executable"
    assert open(REPORT).read() == EXPECTED_REPORT


def test_cargo_test_passes():
    result = run(["cargo", "test"], cwd=RUST_DIR, timeout=240)
    assert result.returncode == 0, f"cargo test failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert "test result: ok" in result.stdout, "cargo test output did not indicate successful test results"
    assert "0 passed" not in result.stdout, "cargo test ran but no tests passed (expected at least one proptest)"


def test_rust_static_library_behavior_through_c_abi():
    archive = os.path.join(RUST_DIR, "target", "release", "librust_lib.a")
    assert os.path.isfile(archive)
    c_source = r'''
#include <stdbool.h>
#include <stddef.h>
extern bool analyze_payload(const char *);
int main(void) {
    const char invalid[] = {(char)0xff, 0};
    if (analyze_payload(NULL)) return 1;
    if (analyze_payload("ordinary request")) return 2;
    if (!analyze_payload("x UNION SELECT password")) return 3;
    if (!analyze_payload("admin or 1=1 --")) return 4;
    if (!analyze_payload("DrOp TaBlE accounts")) return 5;
    if (analyze_payload("union then select")) return 6;
    if (analyze_payload(invalid)) return 7;
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "ffi_check.c")
        binary = os.path.join(td, "ffi_check")
        open(source, "w").write(c_source)
        result = run(["cc", source, archive, "-ldl", "-lm", "-lpthread", "-o", binary])
        assert result.returncode == 0, f"Could not link Rust staticlib through C ABI: {result.stderr}"
        result = run([binary])
        assert result.returncode == 0, f"Rust analyze_payload behavior failed case {result.returncode}"


def test_scanner_on_derived_non_sample_input():
    scanner = os.path.join(GO_DIR, "scanner")
    payloads = [
        "harmless", "UNION SELECT x", "prefix 1=1 suffix", "drop table audit",
        "union then select", "DROP  TABLE x", "normal request", "aUnIoN SeLeCt b",
        "one equals one", "1=10", "please DROP TABLE users", "select union",
        "alpha", "xx1=1yy", "nothing suspicious here", "DROP TABLE",
    ]
    expected = sum(
        any(marker in payload.lower() for marker in ("union select", "1=1", "drop table"))
        for payload in payloads
    )
    assert expected != 3, "Verifier fixture must not have the sample's fixed answer"

    with tempfile.TemporaryDirectory() as td:
        log_path = os.path.join(td, "alternate.jsonl")
        with open(log_path, "w", encoding="utf-8") as f:
            for i, payload in enumerate(payloads):
                f.write(json.dumps({"id": i + 100, "payload": payload}) + "\n")
        result = run([scanner, log_path], cwd=GO_DIR, timeout=30)
        assert result.returncode == 0, f"scanner failed: {result.stderr}"
        assert result.stdout == f"Detected {expected} SQLi attempts\n", (
            "The built Go/FFI application did not compute the result for alternate input"
        )

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
