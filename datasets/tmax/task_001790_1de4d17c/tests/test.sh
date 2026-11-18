#!/bin/bash
set -u
mkdir -p /logs/verifier

REAL_BUILDER=$(mktemp /tmp/img_builder.real.XXXXXX)
BUILDER_LOG=$(mktemp /tmp/img_builder.calls.XXXXXX)
mv /app/img_builder "$REAL_BUILDER"

cat > /app/img_builder <<'WRAPPER_EOF'
#!/bin/bash
valid=0
if [ "$#" -eq 2 ] && \
   [ "${TZ-}" = "UTC" ] && \
   [ "${LC_ALL-}" = "C" ] && \
   [ -f "$1/etc/ssh/sshd_config" ] && \
   grep -Eq '^[[:space:]]*PubkeyAuthentication[[:space:]]+yes([[:space:]]*(#.*)?)?$' "$1/etc/ssh/sshd_config" && \
   ! grep -Eq '^[[:space:]]*PubkeyAuthentication[[:space:]]+no([[:space:]]*(#.*)?)?$' "$1/etc/ssh/sshd_config"; then
    valid=1
fi
printf 'START\t%s\t%s\t%s\t%s\t%s\n' "${1-}" "${2-}" "${TZ-}" "${LC_ALL-}" "$valid" >> "$VERIFIER_BUILDER_LOG"
"$VERIFIER_REAL_BUILDER" "$@"
rc=$?
printf 'DONE\t%s\t%s\t%s\n' "${1-}" "${2-}" "$rc" >> "$VERIFIER_BUILDER_LOG"
exit "$rc"
WRAPPER_EOF
chmod 0755 /app/img_builder
export VERIFIER_REAL_BUILDER="$REAL_BUILDER"
export VERIFIER_BUILDER_LOG="$BUILDER_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
from collections import Counter
from pathlib import Path


def test_provision_script_execution_and_output():
    script_path = Path("/home/user/provision.go")
    assert script_path.exists(), f"Go script missing at {script_path}"
    assert script_path.is_file(), f"Go script is not a regular file: {script_path}"

    backups_dir = Path("/home/user/backups")
    images_dir = Path("/home/user/images")
    images_dir.mkdir(parents=True, exist_ok=True)

    # Restore the supplied flawed inputs so this execution must perform the patch.
    for i in range(1, 11):
        config = backups_dir / f"node_{i}" / "etc/ssh/sshd_config"
        assert config.is_file(), f"Missing input SSH configuration {config}"
        config.write_text("Port 22\nPubkeyAuthentication no\n")

    for f in images_dir.glob("node_*.qcow2"):
        f.unlink()

    log_path = Path(os.environ["VERIFIER_BUILDER_LOG"])
    log_path.write_text("")

    start_time = time.time()
    proc = subprocess.run(
        ["go", "run", str(script_path)],
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    elapsed = time.time() - start_time

    assert proc.returncode == 0, (
        f"Go script failed with exit code {proc.returncode}. Stderr: {proc.stderr}"
    )

    # Keep the original output assertions.
    for i in range(1, 11):
        out_file = images_dir / f"node_{i}.qcow2"
        assert out_file.exists(), f"Missing output file {out_file}"
        assert out_file.is_file(), f"Output is not a regular file: {out_file}"
        content = out_file.read_text().strip()
        assert content == "QCOW2_MAGIC_VALID_REPRODUCIBLE", (
            f"Invalid content in {out_file}: '{content}'. "
            "This indicates the sshd_config was not patched correctly "
            "or the required environment variables (TZ=UTC, LC_ALL=C) were not set."
        )

    # Confirm that all source configurations were actually changed to yes.
    for i in range(1, 11):
        config = backups_dir / f"node_{i}" / "etc/ssh/sshd_config"
        lines = [line.split("#", 1)[0].strip().split() for line in config.read_text().splitlines()]
        directives = [parts[1].lower() for parts in lines if len(parts) >= 2 and parts[0].lower() == "pubkeyauthentication"]
        assert directives and all(value == "yes" for value in directives), (
            f"{config} was not patched to PubkeyAuthentication yes"
        )

    # The instrumented proprietary builder must have been called exactly once for
    # every required input/output pair, with the required environment and a
    # patched configuration, and every invocation must have completed.
    records = [line.split("\t") for line in log_path.read_text().splitlines() if line]
    starts = Counter(tuple(row) for row in records if row[0] == "START")
    dones = Counter(tuple(row) for row in records if row[0] == "DONE")
    expected_starts = Counter()
    expected_dones = Counter()
    for i in range(1, 11):
        source = f"/home/user/backups/node_{i}"
        output = f"/home/user/images/node_{i}.qcow2"
        expected_starts[("START", source, output, "UTC", "C", "1")] = 1
        expected_dones[("DONE", source, output, "0")] = 1

    assert starts == expected_starts, (
        "The program did not invoke /app/img_builder exactly once per node with "
        f"the required paths, patched SSH configuration, TZ=UTC, and LC_ALL=C. Records: {records}"
    )
    assert dones == expected_dones, (
        "Not all required /app/img_builder invocations completed successfully before the program exited. "
        f"Records: {records}"
    )
    assert len(records) == 20, f"Unexpected extra builder invocations: {records}"

    # Keep the original metric threshold.
    assert elapsed <= 3.0, (
        f"Execution took {elapsed:.2f}s, which exceeds the 3.0s threshold. "
        "Ensure concurrency is implemented correctly."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
else
    reward=0
fi

rm -f /app/img_builder
mv "$REAL_BUILDER" /app/img_builder
rm -f "$BUILDER_LOG" /tmp/test_final_state.py
echo "$reward" > /logs/verifier/reward.txt
