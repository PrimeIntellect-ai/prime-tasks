#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

HOME = "/home/user"
INPUT = "/home/user/embeddings.csv"
OUTPUT = "/home/user/metric.txt"


def test_metric_file_exists_and_correct():
    assert os.path.exists(OUTPUT), f"File {OUTPUT} is missing. The Rust program must create it."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a regular file."

    with open(OUTPUT, "r") as f:
        actual_content = f.read().strip()

    expected_content = "2.8750"
    assert actual_content == expected_content, (
        f"The calculated metric in {OUTPUT} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual: '{actual_content}'"
    )


def rust_sources():
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"target", ".git"}]
        for name in files:
            if name.endswith(".rs"):
                found.append(os.path.join(root, name))
    return found


def test_rust_project_exists():
    assert rust_sources(), "No Rust source code (*.rs) found in /home/user. You must write a Rust program."


def compile_candidates():
    candidates = []
    seen = set()

    manifests = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"target", ".git"}]
        if "Cargo.toml" in files:
            manifests.append(os.path.join(root, "Cargo.toml"))

    for manifest in sorted(manifests, key=lambda p: (not p.startswith("/home/user/artifact_tester/"), p)):
        try:
            meta_run = subprocess.run(
                ["cargo", "metadata", "--format-version", "1", "--no-deps", "--offline", "--manifest-path", manifest],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            if meta_run.returncode != 0:
                continue
            metadata = json.loads(meta_run.stdout)
            target_dir = metadata["target_directory"]
            for package in metadata.get("packages", []):
                package_cwd = os.path.dirname(package["manifest_path"])
                for target in package.get("targets", []):
                    if "bin" not in target.get("kind", []):
                        continue
                    build = subprocess.run(
                        ["cargo", "build", "--release", "--offline", "--manifest-path", manifest,
                         "-p", package["name"], "--bin", target["name"]],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=60,
                    )
                    executable = os.path.join(target_dir, "release", target["name"])
                    key = (executable, package_cwd)
                    if build.returncode == 0 and os.path.isfile(executable) and key not in seen:
                        seen.add(key)
                        candidates.append(key)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError):
            pass

    for index, source in enumerate(rust_sources()[:50]):
        executable = f"/tmp/verified_rust_candidate_{index}"
        try:
            build = subprocess.run(
                ["rustc", "--edition=2021", source, "-O", "-o", executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            key = (executable, os.path.dirname(source))
            if build.returncode == 0 and os.path.isfile(executable) and key not in seen:
                seen.add(key)
                candidates.append(key)
        except (OSError, subprocess.SubprocessError):
            pass

    return candidates


def expected_metric(rows):
    kept = []
    for row in rows:
        values = []
        for field in row:
            values.append(0.0 if field == "" or field == "NaN" else float(field))
        if math.sqrt(sum(value * value for value in values)) <= 10.0:
            kept.append(values)

    assert kept, "Verifier generated an invalid empty test case"
    mean = [sum(row[i] for row in kept) / len(kept) for i in range(3)]
    return format(sum(abs(value) for value in mean), ".4f")


def make_case():
    rows = [
        ["6.0", "8.0", "0.0"],
        ["6.0", "8.0001", "0.0"],
        ["", "NaN", "-2.0"],
        ["20.0", "0.0", "0.0"],
    ]
    for _ in range(5):
        values = [(secrets.randbelow(81) - 40) / 10.0 for _ in range(3)]
        rows.append([f"{value:.1f}" for value in values])
    return rows


def test_compiled_rust_program_processes_fresh_inputs():
    candidates = compile_candidates()
    assert candidates, "No Rust source under /home/user could be compiled into an executable program."

    with open(INPUT, "rb") as f:
        original_input = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    cases = [make_case(), make_case()]
    failures = []
    try:
        for executable, cwd in candidates:
            passed = True
            reason = ""
            for rows in cases:
                csv_data = "\n".join(",".join(row) for row in rows) + "\n"
                expected = expected_metric(rows)
                with open(INPUT, "w") as f:
                    f.write(csv_data)
                if os.path.lexists(OUTPUT):
                    os.remove(OUTPUT)

                try:
                    run = subprocess.run(
                        [executable], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, timeout=10,
                    )
                except (OSError, subprocess.SubprocessError) as exc:
                    passed = False
                    reason = f"could not execute: {exc}"
                    break

                if run.returncode != 0:
                    passed = False
                    reason = f"exited with status {run.returncode}"
                    break
                if not os.path.isfile(OUTPUT):
                    passed = False
                    reason = "did not create /home/user/metric.txt"
                    break
                with open(OUTPUT, "r") as f:
                    actual = f.read().strip()
                if actual != expected:
                    passed = False
                    reason = f"expected {expected} for a fresh input, got {actual!r}"
                    break

            if passed:
                return
            failures.append(f"{executable}: {reason}")
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)

    raise AssertionError(
        "No compiled Rust program correctly processed dynamically generated embeddings. "
        + "; ".join(failures[:10])
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
