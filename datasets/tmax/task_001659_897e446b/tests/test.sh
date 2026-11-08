#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import time
import uuid
import random
import shutil
import subprocess


def test_complete_solution():
    # Preserve the original fstab assertion.
    fstab_path = "/app/fstab_entry.txt"
    assert os.path.exists(fstab_path), f"{fstab_path} is missing"
    with open(fstab_path, "r") as f:
        content = f.read().strip()
    expected_entry = "tmpfs /app/run tmpfs rw,nosuid,nodev,size=50m 0 0"
    assert expected_entry in content, (
        f"Incorrect fstab entry. Expected to find '{expected_entry}' in {fstab_path}"
    )

    # Verify that the exporter source was fixed and a real executable was built.
    source_path = "/app/exporter.c"
    exporter_path = "/app/exporter"
    assert os.path.isfile(source_path), f"{source_path} is missing"
    source = open(source_path, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r'#\s*define\s+SOCKET_PATH\s+"/app/run/metrics\.sock"', source), (
        "SOCKET_PATH in exporter.c was not updated to /app/run/metrics.sock"
    )
    assert "/tmp/wrong_upstream.sock" not in source, "The wrong upstream socket remains in exporter.c"
    assert os.path.isfile(exporter_path), f"{exporter_path} is missing"
    assert os.access(exporter_path, os.X_OK), f"{exporter_path} is not executable"
    with open(exporter_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/exporter is not a compiled ELF executable"

    # Exercise the exporter on an unpredictable number of records and derive the answer.
    export_count = random.SystemRandom().randint(173, 397)
    export_input = b"".join(
        (f"record-{uuid.uuid4().hex}-{i}\n").encode() for i in range(export_count)
    )
    exporter_result = subprocess.run(
        [exporter_path], input=export_input, capture_output=True, timeout=2
    )
    assert exporter_result.returncode == 0, (
        f"exporter failed with return code {exporter_result.returncode}: "
        f"{exporter_result.stderr.decode(errors='replace')}"
    )
    exporter_stdout = exporter_result.stdout.decode(errors="replace")
    assert re.search(rf"Processed\s+{export_count}\s+requests", exporter_stdout), (
        f"exporter reported an incorrect processed count: {exporter_stdout!r}"
    )

    pipeline_path = "/app/pipeline.sh"
    assert os.path.exists(pipeline_path), f"{pipeline_path} is missing"
    assert os.access(pipeline_path, os.X_OK), f"{pipeline_path} is not executable"
    pipeline_source = open(pipeline_path, "r", encoding="utf-8", errors="replace").read()
    code_without_comments = "\n".join(
        line for line in pipeline_source.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert "/app/access.log" in code_without_comments, "pipeline.sh does not read /app/access.log"
    assert re.search(r"\b(?:grep|awk|sed)\b", code_without_comments), (
        "pipeline.sh does not use grep, awk, or sed to filter the logs"
    )
    assert re.search(r"\|\s*/app/exporter\b", code_without_comments), (
        "pipeline.sh must pipe the filtered logs directly into /app/exporter"
    )

    # Replace the input with unpredictable records and instrument /app/exporter.
    # This proves that pipeline.sh reads access.log, removes every 404 record, and
    # actually sends the remaining records to the required exporter path.
    token = uuid.uuid4().hex
    access_path = "/app/access.log"
    temp_dir = f"/tmp/pipeline_verify_{token}"
    os.mkdir(temp_dir)
    access_backup = os.path.join(temp_dir, "access.log.backup")
    exporter_backup = os.path.join(temp_dir, "exporter.backup")
    capture_path = os.path.join(temp_dir, "captured.stdin")
    shutil.copy2(access_path, access_backup)
    shutil.copy2(exporter_path, exporter_backup)

    rng = random.SystemRandom()
    statuses = [rng.choice(["200", "201", "302", "404", "500"]) for _ in range(83)]
    statuses.extend(["404", "200"])
    rng.shuffle(statuses)
    records = [
        f'192.0.2.{i % 251 + 1} - - [11/Sep/2026:12:00:00 +0000] "GET /{token}/{i} HTTP/1.1" {status} {1000+i}\n'
        for i, status in enumerate(statuses)
    ]
    expected = "".join(line for line in records if " 404 " not in line).encode()

    try:
        with open(access_path, "wb") as f:
            f.write("".join(records).encode())
        with open(exporter_path, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"cat > '{capture_path}'\n")
            f.write(f"printf 'Processed %s requests\\n' \"$(wc -l < '{capture_path}')\"\n")
        os.chmod(exporter_path, 0o755)

        result = subprocess.run(["bash", pipeline_path], capture_output=True, text=True, timeout=2)
        assert result.returncode == 0, (
            f"pipeline.sh failed during filtering test with return code {result.returncode}. "
            f"stderr: {result.stderr}"
        )
        assert os.path.exists(capture_path), "pipeline.sh did not invoke /app/exporter"
        with open(capture_path, "rb") as f:
            captured = f.read()
        assert captured == expected, (
            "pipeline.sh did not pipe exactly the non-404 access.log records into /app/exporter"
        )
    finally:
        shutil.copy2(access_backup, access_path)
        shutil.copy2(exporter_backup, exporter_path)
        os.chmod(exporter_path, stat.S_IMODE(os.stat(exporter_backup).st_mode))

    # Run the real pipeline over the original 500,000-line workload, check its
    # derived result, and preserve the original 0.5-second performance assertion.
    expected_count = 0
    total_count = 0
    with open(access_path, "rb") as f:
        for line in f:
            total_count += 1
            if b" 404 " not in line:
                expected_count += 1
    assert total_count == 500000, "/app/access.log no longer contains the supplied 500,000-line workload"

    start_time = time.time()
    result = subprocess.run(["bash", pipeline_path], capture_output=True, text=True, timeout=2)
    runtime = time.time() - start_time

    assert result.returncode == 0, (
        f"pipeline.sh failed with return code {result.returncode}. stderr: {result.stderr}"
    )
    assert re.search(rf"Processed\s+{expected_count}\s+requests", result.stdout), (
        f"pipeline/exporter reported the wrong count; expected {expected_count}, got {result.stdout!r}"
    )
    threshold = 0.5
    assert runtime <= threshold, (
        f"Execution time {runtime:.4f}s exceeds the {threshold}s threshold. "
        "The exporter bottleneck might not be fully removed."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
