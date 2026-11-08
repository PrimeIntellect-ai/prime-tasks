#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

RESTORE_SH_PATH = "/home/user/restore.sh"
GENERATE_PY_PATH = "/home/user/generate_restore.py"
DB_PATH = "/home/user/backups.db"


def test_generate_script_exists():
    assert os.path.exists(GENERATE_PY_PATH), f"The script {GENERATE_PY_PATH} was not found."
    assert os.path.isfile(GENERATE_PY_PATH), f"{GENERATE_PY_PATH} is not a file."


def test_restore_sh_exists_and_executable():
    assert os.path.exists(RESTORE_SH_PATH), f"The generated script {RESTORE_SH_PATH} was not found. Did you run your python script?"
    assert os.path.isfile(RESTORE_SH_PATH), f"{RESTORE_SH_PATH} is not a file."

    st = os.stat(RESTORE_SH_PATH)
    is_executable = bool(st.st_mode & stat.S_IXUSR)
    assert is_executable, f"The file {RESTORE_SH_PATH} is not executable. Please use chmod +x."


def test_restore_sh_content():
    expected_content = (
        "#!/bin/bash\n"
        "restore_cmd --db db_prod --id b1 --type full\n"
        "restore_cmd --db db_prod --id b2 --type incremental\n"
        "restore_cmd --db db_prod --id b3 --type incremental\n"
    )

    with open(RESTORE_SH_PATH, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), (
        f"The content of {RESTORE_SH_PATH} does not match the expected output.\n"
        f"Expected:\n{expected_content.strip()}\n"
        f"Got:\n{content.strip()}"
    )


def _derive_expected(db_name, target_ts):
    with sqlite3.connect(DB_PATH) as conn:
        row = conn.execute(
            "SELECT id, backup_type, parent_id FROM backups "
            "WHERE db_name = ? AND ts <= ? ORDER BY ts DESC LIMIT 1",
            (db_name, target_ts),
        ).fetchone()
        assert row is not None

        chain = []
        seen = set()
        while row is not None:
            backup_id, backup_type, parent_id = row
            assert backup_id not in seen, "Test metadata unexpectedly contains a cycle"
            seen.add(backup_id)
            chain.append((backup_id, backup_type))
            if backup_type == "full":
                break
            assert parent_id, "Incremental test backup has no parent"
            row = conn.execute(
                "SELECT id, backup_type, parent_id FROM backups "
                "WHERE db_name = ? AND id = ?",
                (db_name, parent_id),
            ).fetchone()
            assert row is not None, "Test metadata unexpectedly has a missing parent"

    chain.reverse()
    lines = ["#!/bin/bash"]
    lines.extend(
        f"restore_cmd --db {db_name} --id {backup_id} --type {backup_type}"
        for backup_id, backup_type in chain
    )
    return "\n".join(lines)


def test_generator_executes_and_handles_unseen_metadata():
    token = uuid.uuid4().hex[:12]
    db_a = f"prod_{token}"
    db_b = f"dev_{token}"
    base = 2000000000 + int(token[:5], 16)

    a1, a2, a3, a4, a5 = [f"a{i}_{token}" for i in range(1, 6)]
    b1, b2 = [f"b{i}_{token}" for i in range(1, 3)]
    records = [
        (a1, db_a, "full", "", base),
        (a2, db_a, "incremental", a1, base + 7),
        (a3, db_a, "incremental", a2, base + 19),
        (a4, db_a, "full", "", base + 33),
        (a5, db_a, "incremental", a4, base + 47),
        (b1, db_b, "full", "", base + 2),
        (b2, db_b, "incremental", b1, base + 29),
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        saved_db = os.path.join(tmpdir, "backups.db")
        shutil.copy2(DB_PATH, saved_db)

        restore_existed = os.path.isfile(RESTORE_SH_PATH)
        saved_restore = os.path.join(tmpdir, "restore.sh")
        if restore_existed:
            shutil.copy2(RESTORE_SH_PATH, saved_restore)

        try:
            for suffix in ("", "-wal", "-shm"):
                path = DB_PATH + suffix
                if os.path.lexists(path):
                    os.remove(path)

            with sqlite3.connect(DB_PATH) as conn:
                conn.execute(
                    "CREATE TABLE backups (id TEXT, db_name TEXT, backup_type TEXT, "
                    "parent_id TEXT, ts INTEGER)"
                )
                conn.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", records)
                conn.commit()

            cases = [
                (db_a, base + 19),
                (db_a, base + 40),
                (db_a, base + 47),
                (db_b, base + 29),
            ]

            for db_name, target_ts in cases:
                expected = _derive_expected(db_name, target_ts)
                if os.path.lexists(RESTORE_SH_PATH):
                    os.remove(RESTORE_SH_PATH)

                result = subprocess.run(
                    ["python3", GENERATE_PY_PATH, db_name, str(target_ts)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert result.returncode == 0, (
                    f"Generator failed for {db_name} at {target_ts}.\n"
                    f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
                )
                assert os.path.isfile(RESTORE_SH_PATH), "Generator did not create restore.sh"
                assert os.stat(RESTORE_SH_PATH).st_mode & stat.S_IXUSR, (
                    "Generated restore.sh is not executable"
                )
                with open(RESTORE_SH_PATH, "r") as f:
                    actual = f.read()
                assert actual.strip() == expected.strip(), (
                    f"Incorrect generated restore chain for {db_name} at {target_ts}.\n"
                    f"Expected:\n{expected}\nGot:\n{actual}"
                )
        finally:
            for suffix in ("", "-wal", "-shm"):
                path = DB_PATH + suffix
                if os.path.lexists(path):
                    os.remove(path)
            shutil.copy2(saved_db, DB_PATH)

            if os.path.lexists(RESTORE_SH_PATH):
                os.remove(RESTORE_SH_PATH)
            if restore_existed:
                shutil.copy2(saved_restore, RESTORE_SH_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
