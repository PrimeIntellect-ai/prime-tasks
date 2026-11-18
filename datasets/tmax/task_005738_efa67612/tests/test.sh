#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
import pytest

EXPORTER_C_PATH = "/home/user/exporter.c"
EXPORTER_BIN_PATH = "/home/user/exporter"
SCRIPT_PATH = "/home/user/collect_and_rotate.sh"
DB_PATH = "/home/user/app_data/db.sqlite"
METRICS_LOG_PATH = "/home/user/metrics.log"
BACKUP_LOG_PATH = "/home/user/backups/metrics_backup.log"


def get_expected_iface():
    with open("/proc/net/route", "r") as f:
        lines = f.readlines()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) > 1 and parts[1] == "00000000":
            return parts[0]
    return None


def expected_line():
    iface = get_expected_iface()
    assert iface is not None, "Could not determine default interface from /proc/net/route"
    return f'{{"default_iface": "{iface}", "db_size": {os.path.getsize(DB_PATH)}}}'


def assert_exact_exporter_output(executable):
    result = subprocess.run([executable], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running {executable} failed: {result.stderr}"
    assert result.stdout == expected_line() + "\n", (
        f"{executable} did not print exactly the required single JSON line; "
        f"got {result.stdout!r}"
    )
    assert result.stderr == "", f"{executable} unexpectedly wrote to stderr: {result.stderr!r}"


def exercise_varying_db_sizes(executable):
    with open(DB_PATH, "rb") as f:
        original = f.read()
    try:
        for size in (123457, 76543):
            with open(DB_PATH, "r+b") as f:
                f.truncate(size)
            assert_exact_exporter_output(executable)
    finally:
        with open(DB_PATH, "wb") as f:
            f.write(original)


def test_exporter_c_exists():
    assert os.path.isfile(EXPORTER_C_PATH), f"Source file {EXPORTER_C_PATH} is missing."


def test_exporter_bin_exists_and_executable():
    assert os.path.isfile(EXPORTER_BIN_PATH), f"Executable {EXPORTER_BIN_PATH} is missing."
    st = os.stat(EXPORTER_BIN_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{EXPORTER_BIN_PATH} is not executable."


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT_PATH} is not executable."


def test_exporter_output():
    expected_iface = get_expected_iface()
    assert expected_iface is not None, "Could not determine default interface from /proc/net/route"
    expected_size = os.path.getsize(DB_PATH)

    result = subprocess.run([EXPORTER_BIN_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {EXPORTER_BIN_PATH} failed."

    output = result.stdout.strip()
    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        pytest.fail(f"Output of {EXPORTER_BIN_PATH} is not valid JSON: {output}")

    assert "default_iface" in data, "Output JSON missing 'default_iface' key."
    assert "db_size" in data, "Output JSON missing 'db_size' key."
    assert data["default_iface"] == expected_iface, f"Expected default_iface '{expected_iface}', got '{data['default_iface']}'"
    assert data["db_size"] == expected_size, f"Expected db_size {expected_size}, got {data['db_size']}"


def test_backup_log_contains_metrics():
    assert os.path.isfile(BACKUP_LOG_PATH), f"Backup log {BACKUP_LOG_PATH} is missing."

    expected_iface = get_expected_iface()
    expected_size = os.path.getsize(DB_PATH)

    with open(BACKUP_LOG_PATH, "r") as f:
        content = f.read()

    found = False
    for line in content.strip().split('\n'):
        if not line:
            continue
        try:
            data = json.loads(line)
            if data.get("default_iface") == expected_iface and data.get("db_size") == expected_size:
                found = True
                break
        except json.JSONDecodeError:
            pass

    assert found, f"Backup log {BACKUP_LOG_PATH} does not contain the expected JSON metrics."


def test_metrics_log_is_truncated():
    assert os.path.isfile(METRICS_LOG_PATH), f"Metrics log {METRICS_LOG_PATH} is missing."
    size = os.path.getsize(METRICS_LOG_PATH)
    assert size == 0, f"Metrics log {METRICS_LOG_PATH} should be 0 bytes (truncated), but is {size} bytes."


def test_installed_exporter_is_native_and_dynamic():
    with open(EXPORTER_BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXPORTER_BIN_PATH} is not a compiled native executable"
    exercise_varying_db_sizes(EXPORTER_BIN_PATH)


def test_c_source_compiles_and_implements_exporter():
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "exporter_from_source")
        result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", EXPORTER_C_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"exporter.c did not compile successfully: {result.stderr}"
        exercise_varying_db_sizes(rebuilt)


def test_initial_backup_is_exactly_one_collection():
    with open(BACKUP_LOG_PATH, "r") as f:
        content = f.read()
    assert content == expected_line() + "\n", (
        "The backup must contain exactly the one collection produced by running "
        "the pipeline once from the initially empty log"
    )


def test_collection_script_is_bash_and_executes_full_pipeline():
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, (
        f"{SCRIPT_PATH} must be a bash script with a bash shebang"
    )

    saved_exporter = "/tmp/verifier_saved_exporter"
    if os.path.lexists(saved_exporter):
        os.unlink(saved_exporter)

    marker = "preexisting-log-entry\n"
    probe_line = "__VERIFIER_EXPORTER_WAS_EXECUTED__"
    os.replace(EXPORTER_BIN_PATH, saved_exporter)
    try:
        with open(EXPORTER_BIN_PATH, "w") as f:
            f.write("#!/bin/bash\nprintf '%s\\n' '__VERIFIER_EXPORTER_WAS_EXECUTED__'\n")
        os.chmod(EXPORTER_BIN_PATH, 0o755)

        with open(METRICS_LOG_PATH, "w") as f:
            f.write(marker)
        if os.path.exists(BACKUP_LOG_PATH):
            os.unlink(BACKUP_LOG_PATH)

        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Collection script failed: {result.stderr}"
        assert os.path.isfile(BACKUP_LOG_PATH), "Collection script did not create the backup"
        with open(BACKUP_LOG_PATH, "r") as f:
            backup = f.read()
        assert backup == marker + probe_line + "\n", (
            "Collection script must append exactly one exporter invocation to metrics.log "
            "and then copy the complete log to metrics_backup.log"
        )
        assert os.path.isfile(METRICS_LOG_PATH), "Collection script removed metrics.log"
        assert os.path.getsize(METRICS_LOG_PATH) == 0, "Collection script did not truncate metrics.log"
    finally:
        if os.path.lexists(EXPORTER_BIN_PATH):
            os.unlink(EXPORTER_BIN_PATH)
        os.replace(saved_exporter, EXPORTER_BIN_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
