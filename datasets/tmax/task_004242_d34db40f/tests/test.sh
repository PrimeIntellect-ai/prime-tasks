#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import secrets
import subprocess
import tempfile
import time

SCRIPT = "/home/user/organizer.py"


def run_script(input_path, output_path):
    return subprocess.run(
        ["python3", SCRIPT, input_path, output_path],
        capture_output=True,
        timeout=20,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"


def test_atomic_write_implementation():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original source-level assertion in addition to behavioral checks.
    has_atomic_pattern = any(x in content for x in [
        "os.replace",
        "os.rename",
        "shutil.move",
        "tempfile",
    ])
    assert has_atomic_pattern, (
        "organizer.py does not appear to implement atomic writes "
        "(missing os.replace, os.rename, shutil.move, or tempfile)."
    )


def test_clean_corpus():
    clean_dir = "/app/eval_corpora/clean/"
    assert os.path.isdir(clean_dir), "Clean corpus directory missing."
    clean_files = [
        f for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    ]
    assert len(clean_files) > 0, "No clean files found."

    failed_clean = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(clean_dir, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run_script(input_path, output_path)

            if result.returncode != 0:
                failed_clean.append((filename, f"Exit code {result.returncode} instead of 0"))
            elif not os.path.isfile(output_path):
                failed_clean.append((filename, "Output file was not created"))
            elif not filecmp.cmp(input_path, output_path, shallow=False):
                failed_clean.append((filename, "Output file content does not match input"))

    assert not failed_clean, (
        f"{len(failed_clean)} of {len(clean_files)} clean files failed. "
        f"Examples: {failed_clean[:5]}"
    )


def test_evil_corpus():
    evil_dir = "/app/eval_corpora/evil/"
    assert os.path.isdir(evil_dir), "Evil corpus directory missing."
    evil_files = [
        f for f in os.listdir(evil_dir)
        if os.path.isfile(os.path.join(evil_dir, f))
    ]
    assert len(evil_files) > 0, "No evil files found."

    failed_evil = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(evil_dir, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run_script(input_path, output_path)

            if result.returncode != 1:
                failed_evil.append((filename, f"Exit code {result.returncode} instead of 1"))
            elif os.path.exists(output_path):
                failed_evil.append((filename, "Output file was created for an evil input"))

    assert not failed_evil, (
        f"{len(failed_evil)} of {len(evil_files)} evil files bypassed rejection. "
        f"Examples: {failed_evil[:5]}"
    )


def test_rules_on_generated_inputs_at_unlabelled_paths():
    nonce = secrets.token_hex(12)
    cases = [
        ("ordinary", "Normal report\nNo restricted material here.\n", True),
        ("three_marks", "Allowed punctuation: ***\n", True),
        ("twenty_lines", "\n".join(f"entry {i}" for i in range(20)), True),
        ("near_token", "PHI_RECORD_DETECTE and PHI-RECORD-DETECTED\n", True),
        ("phi", "prefix PHI_RECORD_DETECTED suffix\n", False),
        ("four_marks", "prefix **** suffix\n", False),
        ("many_marks", "prefix ******** suffix\n", False),
        ("twenty_one_lines", "\n".join(f"entry {i}" for i in range(21)), False),
        ("multiple_reasons", "PHI_RECORD_DETECTED\n****\n", False),
    ]

    with tempfile.TemporaryDirectory(prefix=f"dataset-{nonce}-") as root:
        input_dir = os.path.join(root, "incoming", secrets.token_hex(5))
        output_dir = os.path.join(root, "results", secrets.token_hex(5))
        os.makedirs(input_dir)
        os.makedirs(output_dir)

        for index, (label, content, is_clean) in enumerate(cases):
            input_path = os.path.join(input_dir, f"sample-{index}-{secrets.token_hex(4)}.dat")
            output_path = os.path.join(output_dir, f"result-{index}-{secrets.token_hex(4)}.dat")
            with open(input_path, "w", encoding="utf-8", newline="") as f:
                f.write(content)

            old_content = f"sentinel-{nonce}-{label}"
            if not is_clean:
                with open(output_path, "w", encoding="utf-8") as f:
                    f.write(old_content)

            result = run_script(input_path, output_path)
            if is_clean:
                assert result.returncode == 0, f"Generated clean case {label} was rejected"
                assert os.path.isfile(output_path), f"Generated clean case {label} made no output"
                with open(input_path, "rb") as src, open(output_path, "rb") as dst:
                    assert dst.read() == src.read(), f"Generated clean case {label} was not copied exactly"
            else:
                assert result.returncode == 1, f"Generated invalid case {label} was accepted"
                assert os.path.isfile(output_path), f"Invalid case {label} removed an existing output"
                with open(output_path, "r", encoding="utf-8") as f:
                    assert f.read() == old_content, f"Invalid case {label} modified existing output"


def test_valid_write_executes_same_directory_atomic_replace():
    wrapper_source = r'''
import json
import os
import runpy
import shutil
import sys
import traceback

script, input_path, output_path, marker_path = sys.argv[1:5]
events = []
original_replace = os.replace
original_rename = os.rename
original_move = shutil.move

def record(kind, function):
    def wrapped(src, dst, *args, **kwargs):
        result = function(src, dst, *args, **kwargs)
        events.append({"kind": kind, "src": os.fspath(src), "dst": os.fspath(dst)})
        return result
    return wrapped

os.replace = record("replace", original_replace)
os.rename = record("rename", original_rename)
shutil.move = record("move", original_move)
sys.argv = [script, input_path, output_path]
code = 0
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    if exc.code is None:
        code = 0
    elif isinstance(exc.code, int):
        code = exc.code
    else:
        code = 1
except BaseException:
    traceback.print_exc()
    code = 70
finally:
    with open(marker_path, "w", encoding="utf-8") as marker:
        json.dump(events, marker)
sys.exit(code)
'''

    with tempfile.TemporaryDirectory(prefix="atomic-check-") as root:
        wrapper = os.path.join(root, "runner.py")
        input_path = os.path.join(root, f"source-{secrets.token_hex(5)}.txt")
        output_path = os.path.join(root, f"target-{secrets.token_hex(5)}.txt")
        marker_path = os.path.join(root, "events.json")
        with open(wrapper, "w", encoding="utf-8") as f:
            f.write(wrapper_source)

        # One very large line remains a valid file and makes non-atomic truncation/writes observable.
        new_content = (b"Atomic content " + b"A" * (32 * 1024 * 1024) + b"\n")
        old_content = b"preexisting-output-" + secrets.token_bytes(4096)
        with open(input_path, "wb") as f:
            f.write(new_content)
        with open(output_path, "wb") as f:
            f.write(old_content)

        process = subprocess.Popen(
            ["python3", wrapper, SCRIPT, input_path, output_path, marker_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        bad_visible_size = None
        old_size = len(old_content)
        new_size = len(new_content)
        deadline = time.monotonic() + 20
        while process.poll() is None:
            if time.monotonic() > deadline:
                process.kill()
                raise AssertionError("Atomic-write test timed out")
            try:
                size = os.path.getsize(output_path)
            except FileNotFoundError:
                bad_visible_size = "missing"
                break
            if size not in (old_size, new_size):
                bad_visible_size = size
                break

        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == 0, (
            f"Valid input failed atomic-write execution: {process.returncode}; "
            f"stderr={stderr.decode(errors='replace')[:500]}"
        )
        assert bad_visible_size is None, (
            f"Output exposed a non-atomic intermediate state: {bad_visible_size}"
        )
        with open(output_path, "rb") as f:
            assert f.read() == new_content, "Atomic-write case did not produce exact output"

        assert os.path.isfile(marker_path), "Atomic operation trace was not produced"
        with open(marker_path, "r", encoding="utf-8") as f:
            events = json.load(f)

        output_abs = os.path.abspath(output_path)
        qualifying = []
        for event in events:
            src = os.path.abspath(event["src"])
            dst = os.path.abspath(event["dst"])
            if (
                dst == output_abs
                and src != dst
                and os.path.dirname(src) == os.path.dirname(dst)
            ):
                qualifying.append(event)
        assert qualifying, (
            "The successful valid-file path did not execute a move/replace from a "
            "temporary file in the output directory to the requested output path"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
