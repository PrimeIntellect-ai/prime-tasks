#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import secrets
import shutil
import subprocess


def test_link_target_content():
    target_file = "/home/user/link_target.txt"
    assert os.path.isfile(target_file), f"Expected output file {target_file} is missing."

    with open(target_file, "r") as f:
        content = f.read()

    expected_content = "/home/user/mirror/libcore-1.10.0.so"
    assert content == expected_content, f"Content of {target_file} is incorrect. Expected '{expected_content}', got '{content}'."


def test_resolve_script_exists():
    script_file = "/home/user/resolve.py"
    assert os.path.isfile(script_file), f"Expected script {script_file} is missing."


def test_resolver_behavior_on_generated_index():
    script = "/home/user/resolve.py"
    mirror = "/home/user/mirror"
    index_path = os.path.join(mirror, "index.csv")
    output_path = "/home/user/link_target.txt"
    assert os.path.isfile(script), f"Expected script {script} is missing."

    token = secrets.token_hex(8)
    dependency = f"dep{token}"
    other_dependency = f"other{token}"
    original_index = open(index_path, "rb").read()
    output_existed = os.path.exists(output_path)
    original_output = open(output_path, "rb").read() if output_existed else None
    created_files = []

    versions = ["0.9.0", "1.2.0", "1.10.0", "1.11.0", "2.0.0"]
    candidates = []
    rows = []

    try:
        for version in versions:
            filename = f"artifact-{token}-{secrets.token_hex(4)}.so"
            path = os.path.join(mirror, filename)
            data = secrets.token_bytes(31) + version.encode("ascii")
            with open(path, "wb") as f:
                f.write(data)
            created_files.append(path)

            actual_hash = hashlib.sha256(data).hexdigest()
            expected_hash = actual_hash
            if version == "1.11.0":
                expected_hash = "0" * 64

            rows.append(
                f"{dependency},{version},"
                f"{base64.b64encode(filename.encode()).decode()},"
                f"{expected_hash}"
            )
            candidates.append({
                "dependency": dependency,
                "version": tuple(int(x) for x in version.split(".")),
                "path": path,
                "actual_hash": actual_hash,
                "expected_hash": expected_hash,
            })

        other_filename = f"unrelated-{token}.so"
        other_path = os.path.join(mirror, other_filename)
        other_data = secrets.token_bytes(29)
        with open(other_path, "wb") as f:
            f.write(other_data)
        created_files.append(other_path)
        rows.append(
            f"{other_dependency},99.0.0,"
            f"{base64.b64encode(other_filename.encode()).decode()},"
            f"{hashlib.sha256(other_data).hexdigest()}"
        )

        secrets.SystemRandom().shuffle(rows)
        with open(index_path, "w", newline="") as f:
            f.write("\n".join(rows) + "\n")

        cases = [
            (f"{dependency} >= 1.2.0, < 2.0.0", lambda v: v >= (1, 2, 0) and v < (2, 0, 0)),
            (f"{dependency} > 1.10.0, <= 2.0.0", lambda v: v > (1, 10, 0) and v <= (2, 0, 0)),
            (f"{dependency} >= 1.10.0, < 2.0.0", lambda v: v >= (1, 10, 0) and v < (2, 0, 0)),
            (f"{dependency} < 1.2.0", lambda v: v < (1, 2, 0)),
            (f"{dependency} <= 1.2.0, > 0.9.0", lambda v: v <= (1, 2, 0) and v > (0, 9, 0)),
            (f"{dependency} == 1.10.0", lambda v: v == (1, 10, 0)),
        ]

        for constraint, predicate in cases:
            eligible = [
                c for c in candidates
                if c["dependency"] == dependency
                and predicate(c["version"])
                and c["actual_hash"] == c["expected_hash"]
            ]
            expected = max(eligible, key=lambda c: c["version"])["path"]

            result = subprocess.run(
                ["python3", script, constraint],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Resolver failed for {constraint!r}: stdout={result.stdout!r}, "
                f"stderr={result.stderr!r}"
            )
            assert os.path.isfile(output_path), "Resolver did not create link_target.txt"
            with open(output_path, "r") as f:
                actual = f.read()
            assert actual == expected, (
                f"For {constraint!r}, expected exactly {expected!r}, got {actual!r}"
            )
    finally:
        with open(index_path, "wb") as f:
            f.write(original_index)
        for path in created_files:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        if output_existed:
            with open(output_path, "wb") as f:
                f.write(original_output)
        else:
            try:
                os.remove(output_path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
