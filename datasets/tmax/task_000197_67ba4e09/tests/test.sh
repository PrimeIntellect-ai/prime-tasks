#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import subprocess
import tempfile


def test_red_frame_count():
    path = "/home/user/red_frame_count.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "14", f"Expected red frame count to be '14', but got '{content}'"


def run_sanitizer(script_path, directory):
    try:
        return subprocess.run(
            ["/bin/bash", script_path, directory],
            capture_output=True,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_sanitizer_script():
    script_path = "/home/user/sanitizer.sh"
    assert os.path.isfile(script_path), f"Missing required script: {script_path}"

    evil_corpus = "/app/corpus/evil"
    clean_corpus = "/app/corpus/clean"

    evil_bypassed = []
    if os.path.isdir(evil_corpus):
        for item in os.listdir(evil_corpus):
            item_path = os.path.join(evil_corpus, item)
            if os.path.isdir(item_path):
                if run_sanitizer(script_path, item_path) != 1:
                    evil_bypassed.append(item)

    clean_modified = []
    if os.path.isdir(clean_corpus):
        for item in os.listdir(clean_corpus):
            item_path = os.path.join(clean_corpus, item)
            if os.path.isdir(item_path):
                if run_sanitizer(script_path, item_path) != 0:
                    clean_modified.append(item)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} clean modified (rejected): {', '.join(clean_modified)}")
    assert not error_msgs, "Sanitizer script failed on corpora: " + "; ".join(error_msgs)

    # Build a fresh, nonempty corpus at verification time so the sanitizer is
    # necessarily exercised. Random directory names prevent path-name answers.
    with tempfile.TemporaryDirectory(prefix="sanitizer-corpus-") as corpus:
        cases = []

        def new_case(expected):
            path = tempfile.mkdtemp(prefix="case-", dir=corpus)
            cases.append((path, expected))
            return path

        clean = new_case(0)
        os.makedirs(os.path.join(clean, "one", "two", "three"))
        with open(os.path.join(clean, "one", "data.txt"), "w") as f:
            f.write("ordinary data")

        clean = new_case(0)
        os.mkdir(os.path.join(clean, "real_dir"))
        with open(os.path.join(clean, "real_dir", "payload"), "w") as f:
            f.write("payload")
        os.symlink("real_dir", os.path.join(clean, "dir_alias"))
        os.symlink("real_dir/payload", os.path.join(clean, "file_alias"))

        clean = new_case(0)
        with open(os.path.join(clean, "target"), "w") as f:
            f.write("target")
        os.symlink("target", os.path.join(clean, "link_one"))
        os.symlink("link_one", os.path.join(clean, "link_two"))

        bad = new_case(1)
        os.symlink(".", os.path.join(bad, "self"))

        bad = new_case(1)
        os.makedirs(os.path.join(bad, "level1", "level2"))
        os.symlink("../..", os.path.join(bad, "level1", "level2", "back"))

        bad = new_case(1)
        os.symlink("second", os.path.join(bad, "first"))
        os.symlink("first", os.path.join(bad, "second"))

        bad = new_case(1)
        os.symlink("middle", os.path.join(bad, "start"))
        os.symlink("end", os.path.join(bad, "middle"))
        os.symlink("start", os.path.join(bad, "end"))

        bad = new_case(1)
        os.makedirs(os.path.join(bad, "nested"))
        os.symlink("missing-target", os.path.join(bad, "nested", "broken"))

        random.SystemRandom().shuffle(cases)
        failures = []
        for directory, expected in cases:
            actual = run_sanitizer(script_path, directory)
            if actual != expected:
                failures.append(f"{os.path.basename(directory)} expected {expected}, got {actual}")

        assert not failures, "Sanitizer failed generated cases: " + "; ".join(failures)


def test_failed_dat_manifest():
    manifest_path = "/home/user/failed_dat_manifest.txt"
    assert os.path.isfile(manifest_path), f"Missing required file: {manifest_path}"

    log_path = "/app/backup_runs.log"
    targets = []
    if os.path.isfile(log_path):
        with open(log_path, "r") as f:
            content = f.read().split("--")
            for block in content:
                lines = [line.strip() for line in block.strip().split("\n") if line.strip()]
                target = None
                status = None
                for line in lines:
                    if line.startswith("Target:"):
                        target = line.split(":", 1)[1].strip()
                    elif line.startswith("Status:"):
                        status = line.split(":", 1)[1].strip()
                if status == "FAILED" and target:
                    targets.append(target)

    expected_lines = []
    for target in targets:
        if os.path.isdir(target):
            try:
                output = subprocess.check_output(
                    ["find", target, "-type", "f", "-name", "*.dat", "-mtime", "-7"],
                    text=True,
                ).strip()
                if output:
                    for filepath in output.split("\n"):
                        if os.path.isfile(filepath):
                            with open(filepath, "rb") as f:
                                digest = hashlib.sha256(f.read()).hexdigest()
                            expected_lines.append(f"{digest}  {filepath}")
            except subprocess.CalledProcessError:
                pass

    expected_lines.sort(key=lambda x: x.split("  ")[1])
    expected_manifest = "\n".join(expected_lines) + "\n" if expected_lines else ""

    with open(manifest_path, "r") as f:
        actual_manifest = f.read()

    assert actual_manifest.strip() == expected_manifest.strip(), "Manifest content does not match expected output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
