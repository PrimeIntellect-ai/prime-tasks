#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import subprocess
import tempfile
import uuid

import pytest


def test_dedup_c_exists():
    path = "/home/user/dedup.c"
    assert os.path.isfile(path), f"The C source file {path} does not exist."


def test_dedup_executable_exists():
    path = "/home/user/dedup"
    assert os.path.isfile(path), f"The executable {path} does not exist."
    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f"The file {path} is not executable."


def test_pipeline_sh_exists_and_executable():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"The bash script {path} does not exist."
    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f"The script {path} is not executable."


def test_sampled_csv_content():
    path = "/home/user/sampled.csv"
    assert os.path.isfile(path), f"The output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "u1,admin,10",
        "u2,user,5",
        "u3,guest,2",
        "u4,user,8",
        "u5,admin,20",
        "u6,guest,1"
    ]

    # Preserve the original verifier's accepted comparison.
    assert sorted(lines) == sorted(expected_lines), f"The content of {path} does not match the expected output. Got: {lines}"


def _run_dedup(path, rows):
    proc = subprocess.run(
        [path], input="".join(rows), text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, proc.stderr
    return proc.stdout


def _assert_search_symbols(binary):
    proc = subprocess.run(["nm", "-D", binary], text=True, capture_output=True, timeout=10)
    assert proc.returncode == 0, proc.stderr
    symbols = proc.stdout
    assert re.search(r"\bU\s+hcreate(?:@|$)", symbols), "deduplicator does not use POSIX hcreate"
    assert re.search(r"\bU\s+hsearch(?:@|$)", symbols), "deduplicator does not use POSIX hsearch"


def test_deduplicator_behavior_and_search_h_usage():
    source = "/home/user/dedup.c"
    binary = "/home/user/dedup"

    with open(source, "r", encoding="utf-8", errors="replace") as f:
        source_text = f.read()
    assert re.search(r"^\s*#\s*include\s*[<\"]search\.h[>\"]", source_text, re.MULTILINE), \
        "dedup.c must include <search.h>"

    assert open(binary, "rb").read(4) == b"\x7fELF", "dedup must be a compiled native executable"

    suffix = uuid.uuid4().hex
    rows = [
        f"idA_{suffix},admin,10\n",
        f"idB_{suffix},user,5\n",
        f"idA_{suffix},guest,999\n",
        f"idC_{suffix},guest,2\n",
        f"idB_{suffix},admin,777\n",
        f"idD_{suffix},user,8\n",
    ]
    expected = "".join([rows[0], rows[1], rows[3], rows[5]])

    assert _run_dedup(binary, rows) == expected
    _assert_search_symbols(binary)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "dedup-rebuilt")
        proc = subprocess.run(
            ["gcc", source, "-o", rebuilt], text=True, capture_output=True, timeout=30
        )
        assert proc.returncode == 0, f"dedup.c does not compile with gcc: {proc.stderr}"
        assert _run_dedup(rebuilt, rows) == expected
        _assert_search_symbols(rebuilt)


def _derive_expected(files):
    seen = set()
    role_counts = {}
    result = []
    for rows in files:
        for line in rows:
            user_id, role, _score = line.rstrip("\n").split(",", 2)
            if user_id in seen:
                continue
            seen.add(user_id)
            if role_counts.get(role, 0) < 2:
                result.append(line)
                role_counts[role] = role_counts.get(role, 0) + 1
    return "".join(result)


def test_pipeline_executes_dedup_and_samples_dynamic_data():
    pipeline = "/home/user/pipeline.sh"
    dedup = "/home/user/dedup"
    sampled = "/home/user/sampled.csv"
    raw_paths = [f"/home/user/raw_data/data_{i}.csv" for i in (1, 2, 3)]

    with open(pipeline, "r", encoding="utf-8", errors="replace") as f:
        script_text = f.read()
    assert re.search(r"\bawk\b", script_text), "pipeline.sh must use awk for stratified sampling"

    suffix = uuid.uuid4().hex
    files = [
        [
            f"a_{suffix},admin,10\n",
            f"b_{suffix},user,5\n",
            f"a_{suffix},guest,999\n",
            f"c_{suffix},guest,2\n",
            f"d_{suffix},admin,20\n",
        ],
        [
            f"e_{suffix},user,8\n",
            f"f_{suffix},admin,30\n",
            f"b_{suffix},guest,777\n",
            f"g_{suffix},guest,4\n",
        ],
        [
            f"h_{suffix},guest,1\n",
            f"i_{suffix},user,3\n",
            f"j_{suffix},admin,5\n",
        ],
    ]
    expected = _derive_expected(files)

    with tempfile.TemporaryDirectory() as td:
        raw_backups = []
        for index, path in enumerate(raw_paths):
            backup = os.path.join(td, f"raw-{index}")
            shutil.copy2(path, backup)
            raw_backups.append(backup)

        dedup_backup = os.path.join(td, "real-dedup")
        shutil.copy2(dedup, dedup_backup)
        sampled_existed = os.path.exists(sampled)
        sampled_backup = os.path.join(td, "sampled-backup")
        if sampled_existed:
            shutil.copy2(sampled, sampled_backup)

        marker = os.path.join(td, "dedup-was-called")
        try:
            for path, rows in zip(raw_paths, files):
                with open(path, "w", encoding="utf-8", newline="") as f:
                    f.write("".join(rows))

            with open(dedup, "w", encoding="utf-8") as f:
                f.write("#!/bin/sh\n")
                f.write(f": > {marker!r}\n")
                f.write(f"exec {dedup_backup!r} \"$@\"\n")
            os.chmod(dedup, 0o755)

            proc = subprocess.run(
                [pipeline], cwd="/home/user", text=True, capture_output=True, timeout=20
            )
            assert proc.returncode == 0, f"pipeline.sh failed: {proc.stderr}"
            assert os.path.isfile(marker), "pipeline.sh did not invoke /home/user/dedup"
            assert os.path.isfile(sampled), "pipeline.sh did not generate /home/user/sampled.csv"
            with open(sampled, "r", encoding="utf-8", newline="") as f:
                actual = f.read()
            assert actual == expected, f"pipeline output was incorrect. Expected {expected!r}, got {actual!r}"
        finally:
            shutil.copy2(dedup_backup, dedup)
            for backup, path in zip(raw_backups, raw_paths):
                shutil.copy2(backup, path)
            if sampled_existed:
                shutil.copy2(sampled_backup, sampled)
            elif os.path.exists(sampled):
                os.remove(sampled)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
