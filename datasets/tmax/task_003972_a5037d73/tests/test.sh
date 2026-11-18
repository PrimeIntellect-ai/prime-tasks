#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest


def get_ground_truth(test_dir):
    """Derive labels from the required ELF properties."""
    gt = set()
    if not os.path.isdir(test_dir):
        return gt

    for fname in os.listdir(test_dir):
        fpath = os.path.join(test_dir, fname)
        if not os.path.isfile(fpath):
            continue

        try:
            with open(fpath, "rb") as f:
                if f.read(5) != b"\x7fELF\x02":
                    continue
        except Exception:
            continue

        try:
            dyn = subprocess.run(
                ["readelf", "-W", "--dyn-syms", fpath],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if not (
                " system@" in dyn.stdout
                or " popen@" in dyn.stdout
                or " system " in dyn.stdout
                or " popen " in dyn.stdout
            ):
                continue
        except Exception:
            continue

        try:
            strs = subprocess.run(
                ["strings", fpath], capture_output=True, text=True, timeout=10
            )
            if "HTTP_USER_AGENT" not in strs.stdout:
                continue
        except Exception:
            continue

        gt.add(fname)

    return gt


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def test_evidence_extracted():
    evidence_dir = "/home/user/evidence"
    assert os.path.isdir(evidence_dir), (
        f"Directory {evidence_dir} does not exist. Did you extract the evidence.zip file?"
    )

    files = os.listdir(evidence_dir)
    assert len(files) > 0, (
        f"Directory {evidence_dir} is empty. Evidence files were not extracted properly."
    )

    # Verify that the encrypted archive's actual contents were extracted intact.
    with tempfile.TemporaryDirectory(prefix="expected_evidence_") as expected_dir:
        result = subprocess.run(
            [
                "unzip",
                "-qq",
                "-P",
                "delta charlie niner",
                "/app/evidence.zip",
                "-d",
                expected_dir,
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, "Verifier could not open the evidence archive"

        expected_files = []
        for root, _, names in os.walk(expected_dir):
            for name in names:
                expected_files.append(os.path.relpath(os.path.join(root, name), expected_dir))
        assert expected_files, "The evidence archive unexpectedly contains no files"

        for relpath in expected_files:
            expected_path = os.path.join(expected_dir, relpath)
            submitted_path = os.path.join(evidence_dir, relpath)
            assert os.path.isfile(submitted_path), f"Extracted evidence is missing {relpath}"
            assert sha256(submitted_path) == sha256(expected_path), (
                f"Extracted evidence file {relpath} does not match the archive"
            )


def score_script(agent_script, test_dir, timeout=60):
    ground_truth_set = get_ground_truth(test_dir)
    assert ground_truth_set, "Ground truth set is empty"

    try:
        result = subprocess.run(
            ["bash", agent_script, test_dir],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"The script execution timed out after {timeout} seconds.")
    except Exception as exc:
        pytest.fail(f"Failed to execute the script: {exc}")

    assert result.returncode == 0, (
        f"Scanner exited with status {result.returncode}: {result.stderr[:1000]}"
    )

    predicted = {p.strip() for p in result.stdout.splitlines() if p.strip()}
    tp = len(predicted & ground_truth_set)
    fp = len(predicted - ground_truth_set)
    fn = len(ground_truth_set - predicted)
    precision = tp / (tp + fp) if tp + fp else 0
    recall = tp / (tp + fn) if tp + fn else 0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0

    assert f1 >= 0.95, (
        f"F1 Score {f1:.4f} is below the threshold of 0.95.\n"
        f"True Positives: {tp}, False Positives: {fp}, False Negatives: {fn}\n"
        f"Precision: {precision:.4f}, Recall: {recall:.4f}"
    )


def compile_template(source, output):
    src = output + ".c"
    with open(src, "w") as f:
        f.write(source)
    result = subprocess.run(
        ["gcc", "-O0", src, "-o", output], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr


def test_scan_cgi_f1_score():
    agent_script = "/home/user/scan_cgi.sh"
    fixed_test_dir = "/app/hidden_test"

    assert os.path.isfile(agent_script), f"Script not found at {agent_script}"
    assert os.path.isdir(fixed_test_dir), (
        f"Hidden test directory not found at {fixed_test_dir}"
    )

    # Retain the original corpus check.
    score_script(agent_script, fixed_test_dir)

    # Build a fresh held-out corpus only after the agent has finished. Random,
    # label-independent basenames prevent hardcoded filename solutions.
    with tempfile.TemporaryDirectory(prefix="cgi_verifier_") as root:
        build_dir = os.path.join(root, "build")
        corpus_dir = os.path.join(root, "corpus")
        os.mkdir(build_dir)
        os.mkdir(corpus_dir)
        sentinel = os.path.join(root, "executed_" + secrets.token_hex(12))

        common = f'''\n#include <stdio.h>\n__attribute__((constructor)) static void verifier_trip(void) {{\n    FILE *f = fopen("{sentinel}", "w");\n    if (f) {{ fputs("executed", f); fclose(f); }}\n}}\n'''
        sources = {
            "mal_system": common + '''\n#include <stdlib.h>\nint main(void) { volatile const char *s = "HTTP_USER_AGENT"; return system(":") + (s == 0); }\n''',
            "mal_popen": common + '''\n#include <stdlib.h>\nint main(void) { volatile const char *s = "HTTP_USER_AGENT"; FILE *f = popen(":", "r"); if (f) pclose(f); return s == 0; }\n''',
            "ben_system": common + '''\n#include <stdlib.h>\nint main(void) { return system(":"); }\n''',
            "ben_string": common + '''\nint main(void) { volatile const char *s = "HTTP_USER_AGENT"; puts((const char *)s); return 0; }\n''',
            "ben_clean": common + '''\nint main(void) { return 0; }\n''',
        }

        templates = {}
        for key, source in sources.items():
            output = os.path.join(build_dir, secrets.token_hex(10))
            compile_template(source, output)
            templates[key] = output

        kinds = (
            ["mal_system"] * 40
            + ["mal_popen"] * 40
            + ["ben_system"] * 35
            + ["ben_string"] * 35
            + ["ben_clean"] * 30
            + ["plain"] * 20
            + ["fake_elf"] * 20
        )
        random.SystemRandom().shuffle(kinds)

        for kind in kinds:
            name = secrets.token_hex(16)
            destination = os.path.join(corpus_dir, name)
            if kind == "plain":
                with open(destination, "wb") as f:
                    f.write(os.urandom(96))
            elif kind == "fake_elf":
                with open(destination, "wb") as f:
                    f.write(b"\x7fELF\x02" + os.urandom(91))
            else:
                shutil.copy2(templates[kind], destination)

        # Do not expose labeled template/source names to the scanner.
        shutil.rmtree(build_dir)

        ground_truth = get_ground_truth(corpus_dir)
        assert len(ground_truth) == 80, "Generated corpus labels are inconsistent"
        score_script(agent_script, corpus_dir)
        assert not os.path.exists(sentinel), (
            "The scanner executed a tested binary instead of inspecting it safely"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
