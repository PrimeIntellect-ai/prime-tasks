#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile


def sanitize_records(records):
    accepted = []
    window = []
    for r in records:
        if r.get("tag") == "ERR_77":
            continue

        current_val = r.get("val", 0)
        current_sum = sum(window) + current_val
        if current_sum > 500:
            continue

        accepted.append(r)
        window.append(current_val)
        if len(window) > 2:
            window.pop(0)

    return accepted


def test_cron_schedule():
    cron_path = "/home/user/pipeline.cron"
    assert os.path.exists(cron_path), f"Cron file missing at {cron_path}"

    with open(cron_path, "r") as f:
        content = f.read().strip()

    valid_expressions = [
        "*/15 * * * 1-5 /home/user/run_pipeline.sh",
        "0,15,30,45 * * * 1-5 /home/user/run_pipeline.sh"
    ]

    normalized_content = " ".join(content.split())
    assert any(normalized_content.endswith(expr) or expr in normalized_content for expr in valid_expressions), \
        f"Cron expression in {cron_path} does not match expected schedules."


def test_sanitizer_executable():
    bin_path = "/home/user/sanitizer"
    assert os.path.isfile(bin_path), f"Sanitizer binary missing at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Sanitizer binary at {bin_path} is not executable"
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled native executable"


def run_case(bin_path, records):
    with tempfile.TemporaryDirectory(prefix="sanitizer-hidden-") as tmpdir:
        token = secrets.token_hex(12)
        in_path = os.path.join(tmpdir, token + ".json")
        out_path = os.path.join(tmpdir, secrets.token_hex(12) + ".json")
        with open(in_path, "w") as f:
            json.dump(records, f, separators=(",", ":"))

        proc = subprocess.run(
            [bin_path, in_path, out_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert proc.returncode == 0, \
            f"{bin_path} failed on valid input: {proc.stderr[:500]}"
        assert os.path.isfile(out_path), f"{bin_path} did not create its output file"
        with open(out_path, "r") as f:
            actual = json.load(f)
        assert actual == sanitize_records(records), \
            f"{bin_path} produced an incorrect sanitized array"


def assert_exact_argument_count(bin_path):
    with tempfile.TemporaryDirectory(prefix="sanitizer-argc-") as tmpdir:
        in_path = os.path.join(tmpdir, "input.json")
        out_path = os.path.join(tmpdir, "output.json")
        with open(in_path, "w") as f:
            json.dump([], f)

        invocations = [
            [bin_path],
            [bin_path, in_path],
            [bin_path, in_path, out_path, "extra"],
        ]
        for argv in invocations:
            proc = subprocess.run(
                argv,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode != 0, \
                f"{bin_path} accepted {len(argv) - 1} arguments; exactly two are required"


def generated_cases():
    cases = [
        [
            {"id": 91001, "val": 500, "tag": "INFO"},
            {"id": 91002, "val": 1, "tag": "WARN"},
            {"id": 91003, "val": -25, "tag": "DEBUG"},
            {"id": 91004, "val": 25, "tag": "INFO"},
        ],
        [
            {"id": 92001, "val": 400, "tag": "INFO"},
            {"id": 92002, "val": 999, "tag": "ERR_77"},
            {"id": 92003, "val": 100, "tag": "WARN"},
            {"id": 92004, "val": 1, "tag": "DEBUG"},
            {"id": 92005, "val": -250, "tag": "INFO"},
            {"id": 92006, "val": 300, "tag": "ERR_770"},
        ],
        [
            {"id": 93001, "val": 200, "tag": "A"},
            {"id": 93002, "val": 200, "tag": "B"},
            {"id": 93003, "val": 101, "tag": "C"},
            {"id": 93004, "val": 100, "tag": "D"},
            {"id": 93005, "val": 200, "tag": "E"},
        ],
    ]

    rng = random.SystemRandom()
    tags = ["INFO", "DEBUG", "WARN", "TRACE", "ERR_77", "ERR_7", "ERR_770"]
    next_id = rng.randrange(1000000, 9000000)
    for _ in range(10):
        records = []
        for _ in range(rng.randrange(18, 46)):
            records.append({
                "id": next_id,
                "val": rng.randrange(-180, 721),
                "tag": rng.choice(tags),
            })
            next_id += rng.randrange(1, 8)
        cases.append(records)
    return cases


def test_adversarial_corpus():
    bin_path = "/home/user/sanitizer"
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.exists(clean_dir), "Clean corpus directory missing"
    assert os.path.exists(evil_dir), "Evil corpus directory missing"
    assert {"clean1.json", "clean2.json"}.issubset(set(os.listdir(clean_dir))), \
        "Required clean corpus files are missing"
    assert {"evil1.json", "evil2.json"}.issubset(set(os.listdir(evil_dir))), \
        "Required evil corpus files are missing"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]

    clean_modified = []
    evil_bypassed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = os.path.join(tmpdir, "out.json")

        for f in clean_files:
            in_path = os.path.join(clean_dir, f)
            subprocess.run([bin_path, in_path, out_path], check=True, capture_output=True, timeout=10)
            with open(in_path, "r") as fin:
                in_data = json.load(fin)
            with open(out_path, "r") as fout:
                out_data = json.load(fout)
            if in_data != out_data:
                clean_modified.append(f)

        for f in evil_files:
            in_path = os.path.join(evil_dir, f)
            subprocess.run([bin_path, in_path, out_path], check=True, capture_output=True, timeout=10)
            with open(in_path, "r") as fin:
                in_data = json.load(fin)
            with open(out_path, "r") as fout:
                out_data = json.load(fout)
            expected_data = sanitize_records(in_data)
            if out_data != expected_data:
                evil_bypassed.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not error_msgs, " | ".join(error_msgs)


def test_hidden_generated_inputs_and_argument_count():
    bin_path = "/home/user/sanitizer"
    cases = generated_cases()
    for records in cases:
        run_case(bin_path, records)
    assert_exact_argument_count(bin_path)


def test_rust_project_rebuilds_to_working_release_binary():
    project = "/home/user/sanitizer_project"
    manifest = os.path.join(project, "Cargo.toml")
    source = os.path.join(project, "src", "main.rs")
    assert os.path.isdir(project), "Rust project directory is missing"
    assert os.path.isfile(manifest), "Rust project Cargo.toml is missing"
    assert os.path.isfile(source), "Rust project src/main.rs is missing"

    proc = subprocess.run(
        ["cargo", "build", "--release", "--message-format=json"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f"Rust project failed to build in release mode: {proc.stderr[-1500:]}"

    candidates = []
    for line in proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") != "compiler-artifact":
            continue
        target = message.get("target", {})
        executable = message.get("executable")
        if executable and "bin" in target.get("kind", []):
            candidates.append(executable)

    candidates = list(dict.fromkeys(candidates))
    assert candidates, "Cargo did not produce a release binary"

    cases = generated_cases()
    failures = []
    for candidate in candidates:
        try:
            assert os.path.isfile(candidate) and os.access(candidate, os.X_OK)
            with open(candidate, "rb") as f:
                assert f.read(4) == b"\x7fELF"
            for records in cases:
                run_case(candidate, records)
            assert_exact_argument_count(candidate)
            return
        except Exception as exc:
            failures.append(f"{candidate}: {exc}")

    raise AssertionError("No release binary produced by the Rust project implements the sanitizer: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
