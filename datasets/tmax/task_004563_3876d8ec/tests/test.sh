#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests

DB_PATH = Path("/home/user/app.db")
CLIB = Path("/home/user/clib")
RUST_DIR = Path("/home/user/rust_svc")
RUST_BIN = RUST_DIR / "target/release/rust_svc"
CONFIG_IMAGE = Path("/app/server_config.png")
URL = "http://127.0.0.1:7331/compute"
GOOD_HEADERS = {
    "X-API-Key": "tesseract_secret_99",
    "Content-Type": "application/json",
}


def schema_columns(path):
    conn = sqlite3.connect(path)
    try:
        return [row[1] for row in conn.execute("PRAGMA table_info(users);").fetchall()]
    finally:
        conn.close()


def test_configuration_image_is_ocr_readable():
    assert CONFIG_IMAGE.is_file(), f"Configuration image {CONFIG_IMAGE} is missing."
    result = subprocess.run(
        ["tesseract", str(CONFIG_IMAGE), "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    text = re.sub(r"\s+", "", result.stdout)
    assert "PORT=7331" in text, result.stdout
    assert "API_KEY=tesseract_secret_99" in text, result.stdout
    assert "MIGRATION_TARGET=v3" in text, result.stdout


def test_database_schema():
    db_path = "/home/user/app.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(users);")
    columns = cursor.fetchall()

    assert len(columns) > 0, "Table 'users' does not exist or has no columns."
    column_names = [col[1] for col in columns]
    assert "id" in column_names, "Column 'id' is missing from 'users' table."
    assert "name" in column_names, "Column 'name' is missing from 'users' table."
    assert "email" in column_names, "Column 'email' is missing from 'users' table."
    conn.close()


def test_migration_script_rebuilds_database_from_sql_diffs():
    candidates = []
    for path in Path("/home/user").rglob("*.py"):
        if path == Path("/home/user/server.py") or "target" in path.parts:
            continue
        try:
            source = path.read_text(errors="ignore")
        except OSError:
            continue
        lowered = source.lower()
        if "sqlite" in lowered and ".sql" in lowered and (
            "open(" in lowered or "read_text" in lowered or "glob" in lowered
        ):
            candidates.append(path)

    assert candidates, "No Python schema migration script was found."
    original_db = DB_PATH.read_bytes()
    failures = []
    succeeded = False

    try:
        for candidate in candidates:
            for suffix in ("", "-wal", "-shm"):
                try:
                    Path(str(DB_PATH) + suffix).unlink()
                except FileNotFoundError:
                    pass

            try:
                run = subprocess.run(
                    ["python3", str(candidate)],
                    cwd=str(candidate.parent),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                )
            except Exception as exc:
                failures.append(f"{candidate}: {exc}")
                continue

            if run.returncode != 0:
                failures.append(f"{candidate}: {run.stderr}")
                continue
            if not DB_PATH.is_file():
                failures.append(f"{candidate}: did not create {DB_PATH}")
                continue

            try:
                columns = schema_columns(str(DB_PATH))
            except sqlite3.Error as exc:
                failures.append(f"{candidate}: invalid database: {exc}")
                continue

            if columns == ["id", "name", "email"]:
                succeeded = True
                break
            failures.append(f"{candidate}: produced columns {columns!r}")
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                Path(str(DB_PATH) + suffix).unlink()
            except FileNotFoundError:
                pass
        DB_PATH.write_bytes(original_db)

    assert succeeded, "No migration script rebuilt v1 through v3 in order: " + "; ".join(failures)


def test_c_library_and_rust_release_binary():
    subprocess.run(
        ["make", "-B", "libmathops.a"],
        cwd=str(CLIB),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    archive = CLIB / "libmathops.a"
    assert archive.is_file(), "The static library libmathops.a was not built."
    members = subprocess.check_output(["ar", "t", str(archive)], text=True)
    assert "math_ops.o" in members
    symbols = subprocess.check_output(["nm", "-g", str(archive)], text=True)
    assert re.search(r"\badd$", symbols, re.MULTILINE), "libmathops.a does not export add."

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        harness = td / "check.c"
        executable = td / "check"
        harness.write_text(
            '#include <stdio.h>\n#include <stdlib.h>\n'
            'extern int add(int, int);\n'
            'int main(int c, char **v) { if (c != 3) return 2; '
            'printf("%d\\n", add(atoi(v[1]), atoi(v[2]))); return 0; }\n'
        )
        subprocess.run(
            ["gcc", str(harness), str(archive), "-o", str(executable)],
            check=True,
            timeout=30,
        )
        for _ in range(4):
            a = secrets.randbelow(200001) - 100000
            b = secrets.randbelow(200001) - 100000
            output = subprocess.check_output([str(executable), str(a), str(b)], text=True).strip()
            assert output == str(a + b), f"C add({a}, {b}) returned {output}."

    subprocess.run(["cargo", "clean"], cwd=str(RUST_DIR), check=True, timeout=30)
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=str(RUST_DIR),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert RUST_BIN.is_file(), "cargo build --release did not produce rust_svc."
    assert os.access(RUST_BIN, os.X_OK), "rust_svc is not executable."
    assert RUST_BIN.read_bytes()[:4] == b"\x7fELF", "rust_svc is not an ELF release binary."

    for _ in range(6):
        a = secrets.randbelow(200001) - 100000
        b = secrets.randbelow(200001) - 100000
        output = subprocess.check_output([str(RUST_BIN), str(a), str(b)], text=True).strip()
        assert output == str(a + b), f"Rust binary returned {output} for {a} + {b}."

    # Relink against a temporary altered implementation to prove the Rust CLI
    # actually calls the C FFI rather than independently computing the sum.
    original_archive = archive.read_bytes()
    marker = secrets.randbelow(10000) + 1000
    try:
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            probe_c = td / "math_ops.c"
            probe_o = td / "math_ops.o"
            probe_c.write_text(f"int add(int a, int b) {{ return a + b + {marker}; }}\n")
            subprocess.run(["gcc", "-c", str(probe_c), "-o", str(probe_o)], check=True)
            subprocess.run(["ar", "rcs", str(archive), str(probe_o)], check=True)
            subprocess.run(["cargo", "clean"], cwd=str(RUST_DIR), check=True, timeout=30)
            subprocess.run(
                ["cargo", "build", "--release"],
                cwd=str(RUST_DIR),
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=120,
            )
            a = secrets.randbelow(1000) - 500
            b = secrets.randbelow(1000) - 500
            output = subprocess.check_output([str(RUST_BIN), str(a), str(b)], text=True).strip()
            assert output == str(a + b + marker), "Rust binary did not use the linked C add function."
    finally:
        archive.write_bytes(original_archive)
        subprocess.run(["cargo", "clean"], cwd=str(RUST_DIR), check=True, timeout=30)
        subprocess.run(
            ["cargo", "build", "--release"],
            cwd=str(RUST_DIR),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )


def post_compute(a, b, headers=GOOD_HEADERS):
    try:
        return requests.post(URL, headers=headers, json={"a": a, "b": b}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the Python server or request failed: {exc}")


def test_python_server_compute_endpoint():
    assert Path("/home/user/server.py").is_file(), "Python server file is missing."

    # Preserve the original fixed assertion.
    response = post_compute(42, 58)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "result" in data, f"Expected 'result' in response JSON, got: {data}"
    assert data["result"] == 100, f"Expected result to be 100, got {data['result']}"

    # Exercise unpredictable inputs whose answers are derived by the verifier.
    for _ in range(6):
        a = secrets.randbelow(200001) - 100000
        b = secrets.randbelow(200001) - 100000
        response = post_compute(a, b)
        assert response.status_code == 200, response.text
        assert response.json() == {"result": a + b}


def test_server_invokes_release_rust_binary():
    assert RUST_BIN.is_file()
    backup = RUST_BIN.with_name(f"rust_svc.verifier-backup-{os.getpid()}")
    log = Path(f"/tmp/rust_svc_probe_{os.getpid()}.log")
    sentinel = secrets.randbelow(1000000000) + 1000000000
    a = secrets.randbelow(100000) - 50000
    b = secrets.randbelow(100000) - 50000

    os.replace(RUST_BIN, backup)
    try:
        RUST_BIN.write_text(
            "#!/bin/sh\n"
            f"printf '%s %s\\n' \"$1\" \"$2\" >> '{log}'\n"
            f"printf '%s\\n' '{sentinel}'\n"
        )
        RUST_BIN.chmod(RUST_BIN.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        response = post_compute(a, b)
        assert response.status_code == 200, response.text
        assert response.json() == {"result": sentinel}, (
            "The API response was not based on the release Rust binary's output."
        )
        assert log.is_file(), "The server did not execute the release Rust binary."
        assert log.read_text().strip() == f"{a} {b}"
    finally:
        try:
            RUST_BIN.unlink()
        except FileNotFoundError:
            pass
        os.replace(backup, RUST_BIN)
        try:
            log.unlink()
        except FileNotFoundError:
            pass


def test_python_server_unauthorized():
    headers = {
        "X-API-Key": "wrong_key",
        "Content-Type": "application/json",
    }
    response = post_compute(10, 15, headers=headers)
    assert response.status_code in (401, 403), (
        f"Expected status code 401 or 403 for unauthorized request, got {response.status_code}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
