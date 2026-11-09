#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path

APP = Path("/home/user/app")
SCRIPT = APP / "test_env_setup.sh"


def assert_not_running():
    result = subprocess.run(
        ["pgrep", "-f", "/home/user/app/mock_service.sh"],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 1, "mock_service.sh is still running in the background."


def clean_outputs():
    for path in [
        APP / "test.db",
        APP / "benchmark.log",
        APP / "mock_service.log",
        APP / "processor_observed_mock",
        APP / "fixtures" / "db_fixture.json",
        APP / "mock_service.sh",
    ]:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_setup():
    started = time.monotonic()
    result = subprocess.run(
        [str(SCRIPT)],
        cwd=str(APP),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    elapsed = time.monotonic() - started
    assert result.returncode == 0, f"Setup script failed:\n{result.stdout}"
    return elapsed


def read_benchmark():
    path = APP / "benchmark.log"
    assert path.is_file(), f"Benchmark log file {path} is missing."
    content = path.read_text().strip()
    assert re.match(r"^[0-9]+$", content), (
        f"Benchmark log does not contain a valid integer: '{content}'"
    )
    return int(content)


def assert_original_final_state():
    fixture_path = APP / "fixtures" / "db_fixture.json"
    assert fixture_path.is_file(), f"Fixture file {fixture_path} is missing."
    with fixture_path.open() as f:
        data = json.load(f)
    assert data.get("host") == "127.0.0.1", "JSON 'host' value is incorrect."
    assert data.get("port") == "5432", "JSON 'port' value is incorrect."
    assert data.get("user") == "ci_tester", "JSON 'user' value is incorrect."

    db_path = APP / "test.db"
    assert db_path.is_file(), f"Database file {db_path} is missing."
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute("SELECT name, status FROM users;").fetchall()
    finally:
        conn.close()
    assert len(rows) == 1, "Database does not contain exactly one user."
    assert rows[0] == ("admin", "active"), "Database seed data is incorrect."

    log_path = APP / "mock_service.log"
    assert log_path.is_file(), f"Log file {log_path} is missing."
    assert "MOCK_ALIVE" in log_path.read_text(), (
        "The string 'MOCK_ALIVE' was not found in mock_service.log."
    )

    value = read_benchmark()
    assert 2 <= value <= 10, (
        f"Benchmark value {value} is outside the expected range (2-10 seconds)."
    )
    assert_not_running()


def test_setup_script_behavior():
    assert SCRIPT.is_file(), f"Setup script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Setup script {SCRIPT} is not executable."
    first_line = SCRIPT.read_text(errors="replace").splitlines()[0]
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), (
        "test_env_setup.sh must be a Bash script."
    )

    # Remove all agent-produced state and require the submitted script to recreate it.
    assert_not_running()
    clean_outputs()
    run_setup()
    assert_original_final_state()

    config = APP / "config.ini"
    processor = APP / "processor.sh"
    migrations = APP / "migrations"
    original_config = config.read_bytes()
    original_processor = processor.read_bytes()
    original_processor_mode = processor.stat().st_mode
    backup_dir = Path(tempfile.mkdtemp(prefix="migration-backup-"))
    shutil.copytree(migrations, backup_dir / "migrations")

    try:
        # Exercise the implementation with different inputs so fixed output files
        # or hard-coded copies of the initial state cannot pass.
        config.write_text(
            "[Global]\nmode=verification\n\n"
            "[Database]\n"
            "host=10.77.23.9\n"
            "port=6184\n"
            "user=dynamic_ci_user\n\n"
            "[API]\nendpoint=https://invalid.example/\n"
        )
        shutil.rmtree(migrations)
        migrations.mkdir()
        (migrations / "001_create.sql").write_text(
            "CREATE TABLE events (seq INTEGER PRIMARY KEY, label TEXT);\n"
        )
        (migrations / "002_seed.sql").write_text(
            "INSERT INTO events (seq, label) VALUES (7, 'created');\n"
        )
        (migrations / "003_update.sql").write_text(
            "UPDATE events SET label='migrated' WHERE seq=7;\n"
        )
        processor.write_text(
            "#!/bin/bash\n"
            "before=$(grep -c '^MOCK_ALIVE$' /home/user/app/mock_service.log 2>/dev/null || true)\n"
            "sleep 5\n"
            "after=$(grep -c '^MOCK_ALIVE$' /home/user/app/mock_service.log 2>/dev/null || true)\n"
            "if [ $((after-before)) -ge 4 ]; then\n"
            "  : > /home/user/app/processor_observed_mock\n"
            "fi\n"
        )
        os.chmod(processor, 0o755)

        clean_outputs()
        elapsed = run_setup()

        with (APP / "fixtures" / "db_fixture.json").open() as f:
            dynamic_fixture = json.load(f)
        assert dynamic_fixture == {
            "host": "10.77.23.9",
            "port": "6184",
            "user": "dynamic_ci_user",
        }, "Fixture was not derived from the current [Database] configuration."

        conn = sqlite3.connect(APP / "test.db")
        try:
            rows = conn.execute("SELECT seq, label FROM events").fetchall()
        finally:
            conn.close()
        assert rows == [(7, "migrated")], (
            "The current migration files were not applied in alphabetical order."
        )

        assert (APP / "processor_observed_mock").is_file(), (
            "The mock service did not remain active while processor.sh executed."
        )
        value = read_benchmark()
        assert 4 <= value <= 8, "Benchmark does not reflect the dynamic processor runtime."
        assert abs(value - int(elapsed)) <= 1, (
            "benchmark.log does not match the measured wall-clock setup runtime."
        )
        assert_not_running()

        # Independently exercise the generated mock and require repeated writes.
        mock = APP / "mock_service.sh"
        assert mock.is_file(), "mock_service.sh was not created."
        (APP / "mock_service.log").write_text("")
        proc = subprocess.Popen(["bash", str(mock)])
        try:
            time.sleep(2.7)
        finally:
            proc.terminate()
            proc.wait(timeout=3)
        lines = (APP / "mock_service.log").read_text().splitlines()
        assert len(lines) >= 2 and all(line == "MOCK_ALIVE" for line in lines), (
            "mock_service.sh must repeatedly write MOCK_ALIVE once per second."
        )
        assert_not_running()
    finally:
        config.write_bytes(original_config)
        processor.write_bytes(original_processor)
        os.chmod(processor, original_processor_mode)
        shutil.rmtree(migrations, ignore_errors=True)
        shutil.copytree(backup_dir / "migrations", migrations)
        shutil.rmtree(backup_dir, ignore_errors=True)

    # Restore and verify the requested final state as well.
    clean_outputs()
    run_setup()
    assert_original_final_state()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
