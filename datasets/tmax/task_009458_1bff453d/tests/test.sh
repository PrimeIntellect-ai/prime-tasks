#!/bin/bash
set -e
mkdir -p /logs/verifier
git config --global --add safe.directory /home/user/cimonitor >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import pathlib
import secrets
import subprocess
import pytest

WORK = "/home/user/cimonitor"
AMD64 = "/home/user/cimonitor_amd64"
ARM64 = "/home/user/cimonitor_arm64"


def run(cmd, cwd=None, env=None, timeout=30, text=True):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(cmd, cwd=cwd, env=merged, capture_output=True,
                          text=text, timeout=timeout)


def git(*args, text=True):
    return run(["git", "-c", f"safe.directory={WORK}", "-C", WORK, *args], text=text)


def assert_ok(result, description):
    assert result.returncode == 0, (
        f"{description} failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def file_output(path):
    result = run(["file", path])
    assert_ok(result, f"file {path}")
    return result.stdout


def assert_program_output(stdout):
    lines = [line for line in stdout.splitlines() if line]
    assert lines and lines[0] == "Starting cimonitor on arch: amd64", stdout
    expected = collections.Counter([
        "Processed: state-helper_val: pipeline started",
        "Processed: state-helper_val: tests running",
        "Processed: state-helper_val: deployment failed",
    ])
    assert collections.Counter(lines[1:]) == expected, stdout
    # Preserve the original required assertion explicitly.
    assert "Processed: state-helper_val: pipeline started" in stdout, stdout


def test_git_history_and_patch_match_committed_fix():
    assert os.path.isdir(os.path.join(WORK, ".git")), "git repository is missing"

    count = git("rev-list", "--count", "HEAD")
    assert_ok(count, "reading git history")
    assert count.stdout.strip() == "2", "repository must contain the broken-state commit and the fixes commit"

    parent_parents = git("rev-list", "--parents", "-n", "1", "HEAD~1")
    assert_ok(parent_parents, "checking the initial commit")
    assert len(parent_parents.stdout.split()) == 1, "HEAD~1 must be the root broken-state commit"

    assert_ok(git("diff", "--quiet", "HEAD"), "checking tracked working-tree changes")
    assert_ok(git("diff", "--cached", "--quiet", "HEAD"), "checking staged changes")

    original_state = git("show", "HEAD~1:state/state.go")
    original_parser = git("show", "HEAD~1:parser/parser.go")
    original_processor = git("show", "HEAD~1:processor/processor.go")
    original_x86 = git("show", "HEAD~1:sys/sys_linux_x86.go")
    original_arm = git("show", "HEAD~1:sys/sys_linux_arm.go")
    for result in (original_state, original_parser, original_processor, original_x86, original_arm):
        assert_ok(result, "reading broken-state commit")
    assert '"cimonitor/parser"' in original_state.stdout
    assert '"cimonitor/state"' in original_parser.stdout
    assert "wg.Wait()" in original_processor.stdout and "for r := range results" in original_processor.stdout
    assert "//go:build" not in original_x86.stdout
    assert "//go:build" not in original_arm.stdout

    changed = git("diff", "--name-only", "HEAD~1", "HEAD")
    assert_ok(changed, "listing committed fixes")
    changed_paths = set(changed.stdout.splitlines())
    assert "processor/processor.go" in changed_paths
    assert "sys/sys_linux_x86.go" in changed_paths
    assert "sys/sys_linux_arm.go" in changed_paths
    assert changed_paths.intersection({"parser/parser.go", "state/state.go"}), "cycle-breaking source was not committed"

    patch_path = "/home/user/fixes.patch"
    assert os.path.isfile(patch_path), f"{patch_path} is missing."
    with open(patch_path, "rb") as f:
        supplied_patch = f.read()
    expected_patch = git("diff", "HEAD~1", "HEAD", text=False)
    assert_ok(expected_patch, "generating expected patch")
    assert supplied_patch == expected_patch.stdout, "fixes.patch is not exactly git diff HEAD~1 HEAD"
    content = supplied_patch.decode("utf-8", errors="replace")
    assert "diff --git" in content or "--- " in content, f"{patch_path} does not look like a valid patch file."


def test_cimonitor_amd64_exists_and_arch():
    assert os.path.isfile(AMD64), f"{AMD64} is missing."
    assert os.access(AMD64, os.X_OK), f"{AMD64} is not executable."
    output = file_output(AMD64)
    assert "ELF 64-bit" in output and ("x86-64" in output or "AMD64" in output.upper()), \
        f"{AMD64} is not an x86-64 executable. file output: {output}"


def test_cimonitor_arm64_exists_and_arch():
    assert os.path.isfile(ARM64), f"{ARM64} is missing."
    assert os.access(ARM64, os.X_OK), f"{ARM64} is not executable."
    output = file_output(ARM64)
    assert "ELF 64-bit" in output and ("aarch64" in output or "ARM aarch64" in output), \
        f"{ARM64} is not an ARM64 executable. file output: {output}"


def test_binaries_are_go_cimonitor_binaries():
    for binary in (AMD64, ARM64):
        result = run(["go", "version", "-m", binary])
        assert_ok(result, f"reading Go build information from {binary}")
        assert any(line.strip() == "path\tcimonitor" for line in result.stdout.splitlines()), \
            f"{binary} is not the cimonitor main package:\n{result.stdout}"


def test_build_summary_log_exact():
    log_path = "/home/user/build_summary.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."
    with open(log_path, "rb") as f:
        content = f.read()

    expected = run(["file", AMD64, ARM64], text=False)
    assert_ok(expected, "running file on both binaries")
    assert content == expected.stdout, "build_summary.log must be exactly file's stdout, AMD64 then ARM64"

    decoded = content.decode("utf-8", errors="replace")
    assert AMD64 in decoded, "build_summary.log missing amd64 binary info."
    assert ARM64 in decoded, "build_summary.log missing arm64 binary info."
    assert "ELF 64-bit" in decoded, "build_summary.log does not contain expected 'file' output."


def test_build_tags_select_only_the_correct_linux_architecture():
    x86 = pathlib.Path(WORK, "sys/sys_linux_x86.go").read_text()
    arm = pathlib.Path(WORK, "sys/sys_linux_arm.go").read_text()
    assert any(line.startswith("//go:build") for line in x86.splitlines()[:5])
    assert any(line.startswith("//go:build") for line in arm.splitlines()[:5])

    cases = {
        ("linux", "amd64"): {"sys_linux_x86.go"},
        ("linux", "arm64"): {"sys_linux_arm.go"},
        ("windows", "amd64"): set(),
        ("windows", "arm64"): set(),
        ("linux", "386"): set(),
    }
    for (goos, goarch), expected in cases.items():
        result = run(
            ["go", "list", "-e", "-f", "{{range .GoFiles}}{{println .}}{{end}}", "./sys"],
            cwd=WORK, env={"GOOS": goos, "GOARCH": goarch}
        )
        assert_ok(result, f"listing sys files for {goos}/{goarch}")
        assert set(result.stdout.split()) == expected, (
            f"wrong sys files selected for {goos}/{goarch}: {result.stdout}"
        )


def test_go_build_and_vet_succeed_for_both_targets():
    assert os.path.isdir(WORK), f"{WORK} directory is missing."

    # Preserve the original native go build assertion.
    native = run(["go", "build"], cwd=WORK)
    assert_ok(native, f"go build in {WORK}")

    for arch in ("amd64", "arm64"):
        env = {"GOOS": "linux", "GOARCH": arch, "CGO_ENABLED": "0"}
        build = run(["go", "build", "./..."], cwd=WORK, env=env)
        assert_ok(build, f"go build ./... for linux/{arch}")
        vet = run(["go", "vet", "./..."], cwd=WORK, env=env)
        assert_ok(vet, f"go vet ./... for linux/{arch}")


def test_parser_and_state_logic_on_verifier_generated_inputs():
    values = [
        "audit-" + secrets.token_hex(12),
        "spaces and punctuation !? " + secrets.token_hex(5),
        "",
    ]
    quoted = ", ".join(json.dumps(value) for value in values)
    test_path = pathlib.Path(WORK, "parser/zz_verifier_dynamic_test.go")
    source = f'''package parser_test

import (
    "testing"
    "cimonitor/parser"
    "cimonitor/state"
)

func TestVerifierGeneratedParsingInputs(t *testing.T) {{
    if parser.Helper() != "helper_val" {{
        t.Fatalf("Helper output changed: %q", parser.Helper())
    }}
    if state.NewMachine().State() != "state-helper_val" {{
        t.Fatalf("State output changed: %q", state.NewMachine().State())
    }}
    for _, line := range []string{{{quoted}}} {{
        want := "state-helper_val: " + line
        if got := parser.Parse(line); got != want {{
            t.Fatalf("Parse(%q) = %q, want %q", line, got, want)
        }}
    }}
}}
'''
    test_path.write_text(source)
    try:
        result = run(["go", "test", "./..."], cwd=WORK, timeout=60)
        assert_ok(result, "dynamic Go parsing/state tests")
    finally:
        test_path.unlink(missing_ok=True)


def test_source_builds_matching_architectures_and_runs_without_deadlock():
    temp_amd = "/tmp/verifier_cimonitor_amd64"
    temp_arm = "/tmp/verifier_cimonitor_arm64"
    for arch, output in (("amd64", temp_amd), ("arm64", temp_arm)):
        result = run(
            ["go", "build", "-o", output, "."], cwd=WORK,
            env={"GOOS": "linux", "GOARCH": arch, "CGO_ENABLED": "0"}, timeout=60
        )
        assert_ok(result, f"building source for linux/{arch}")
    assert "x86-64" in file_output(temp_amd)
    assert "aarch64" in file_output(temp_arm)

    for binary in (AMD64, temp_amd):
        for _ in range(3):
            try:
                result = run([binary], timeout=5)
            except subprocess.TimeoutExpired:
                pytest.fail(f"{binary} deadlocked (timed out after 5 seconds).")
            assert result.returncode == 0, (
                f"cimonitor failed to run. Output:\n{result.stderr}\n{result.stdout}"
            )
            assert_program_output(result.stdout)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
