#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import re
import subprocess
import tarfile
import tempfile
import uuid


def test_backup_out_exists_and_contains_added_files():
    out_path = "/home/user/backup.out"
    assert os.path.isfile(out_path), f"Standard output file {out_path} does not exist."

    with open(out_path, "r") as f:
        content = f.read()

    assert "Added access.log" in content, "backup.out is missing 'Added access.log'"
    assert "Added app.log" in content, "backup.out is missing 'Added app.log'"
    assert "Added dump.sql" in content, "backup.out is missing 'Added dump.sql'"


def test_backup_err_exists_and_is_consistent_with_skips():
    err_path = "/home/user/backup.err"
    assert os.path.isfile(err_path), f"Standard error file {err_path} does not exist."
    with open(err_path, "r", errors="replace") as f:
        err_content = f.read()
    assert "Traceback (most recent call last)" not in err_content, "backup.err contains a Python traceback"

    archive_path = "/home/user/backups/sanitized_backup.tar.gz"
    if os.path.isfile(archive_path):
        with tarfile.open(archive_path, "r:gz") as tar:
            if "ignore.txt" not in tar.getnames():
                assert "ignore.txt" in err_content, "Skipped ignore.txt was not reported on standard error"


def test_archive_exists_and_is_valid_tar_gz():
    archive_path = "/home/user/backups/sanitized_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."


def test_archive_contents_and_sanitization():
    archive_path = "/home/user/backups/sanitized_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()

        # Check files are at root level
        for member in members:
            assert "/" not in member, f"File {member} is not at the root level of the archive."

        assert "access.log" in members, "access.log is missing from the archive."
        assert "app.log" in members, "app.log is missing from the archive."
        assert "dump.sql" in members, "dump.sql is missing from the archive."

        # Check access.log
        access_log_f = tar.extractfile("access.log")
        assert access_log_f is not None, "Could not extract access.log"
        access_log_content = access_log_f.read().decode("utf-8")
        assert "XXX.XXX.XXX.XXX GET /index.html 200" in access_log_content, "access.log not properly sanitized"
        assert "XXX.XXX.XXX.XXX POST /api/data 500" in access_log_content, "access.log not properly sanitized"
        assert "XXX.XXX.XXX.XXX GET /health 200" in access_log_content, "access.log not properly sanitized"
        assert "192.168.1.100" not in access_log_content, "Original IP found in access.log"
        assert "10.0.0.5" not in access_log_content, "Original IP found in access.log"
        assert access_log_content == (
            "XXX.XXX.XXX.XXX GET /index.html 200\n"
            "XXX.XXX.XXX.XXX POST /api/data 500\n"
            "XXX.XXX.XXX.XXX GET /health 200\n"
        ), "access.log does not exactly match the sanitized source"

        # Check app.log
        app_log_f = tar.extractfile("app.log")
        assert app_log_f is not None, "Could not extract app.log"
        app_log_content = app_log_f.read().decode("utf-8")
        assert "[INFO] Server started at XXX.XXX.XXX.XXX" in app_log_content, "app.log not properly sanitized"
        assert "[ERROR] Database connection failed from XXX.XXX.XXX.XXX" in app_log_content, "app.log not properly sanitized"
        assert "172.16.0.2" not in app_log_content, "Original IP found in app.log"
        assert "127.0.0.1" not in app_log_content, "Original IP found in app.log"
        assert app_log_content == (
            "[INFO] Server started at XXX.XXX.XXX.XXX\n"
            "[ERROR] Database connection failed from XXX.XXX.XXX.XXX\n"
        ), "app.log does not exactly match the sanitized source"

        # Check dump.sql (should be unmodified)
        dump_sql_f = tar.extractfile("dump.sql")
        assert dump_sql_f is not None, "Could not extract dump.sql"
        dump_sql_content = dump_sql_f.read().decode("utf-8")
        assert "INSERT INTO users (id, name) VALUES (1, 'admin');" in dump_sql_content, "dump.sql was modified"
        assert "INSERT INTO logs (ip) VALUES ('192.168.1.1');" in dump_sql_content, "dump.sql was modified (IPs should not be sanitized in .sql files)"
        assert dump_sql_content == (
            "INSERT INTO users (id, name) VALUES (1, 'admin');\n"
            "INSERT INTO logs (ip) VALUES ('192.168.1.1');\n"
        ), "dump.sql does not exactly match the source"


def test_original_files_unmodified():
    # access.log
    log_path = "/home/user/data_source/access.log"
    assert os.path.isfile(log_path), f"Original file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    assert "192.168.1.100 GET /index.html 200" in content, "Original access.log was modified."
    assert "10.0.0.5 POST /api/data 500" in content, "Original access.log was modified."
    assert content == (
        "192.168.1.100 GET /index.html 200\n"
        "10.0.0.5 POST /api/data 500\n"
        "255.255.255.255 GET /health 200\n"
    ), "Original access.log contents were modified."

    # app.log
    app_log_path = "/home/user/data_source/app.log"
    assert os.path.isfile(app_log_path), f"Original file {app_log_path} is missing."
    with open(app_log_path, "r") as f:
        content = f.read()
    assert "[INFO] Server started at 172.16.0.2" in content, "Original app.log was modified."
    assert "[ERROR] Database connection failed from 127.0.0.1" in content, "Original app.log was modified."
    assert content == (
        "[INFO] Server started at 172.16.0.2\n"
        "[ERROR] Database connection failed from 127.0.0.1\n"
    ), "Original app.log contents were modified."


def test_tool_executes_against_runtime_yaml_fixture():
    script = "/home/user/backup_tool.py"
    config = "/home/user/backup_config.yaml"
    assert os.path.isfile(script), f"Python script {script} does not exist."
    py_compile.compile(script, doraise=True)

    with open(config, "rb") as f:
        original_config = f.read()

    token = uuid.uuid4().hex
    root = tempfile.mkdtemp(prefix="backup_verify_", dir="/tmp")
    os.chmod(root, 0o755)
    source = os.path.join(root, "runtime_source")
    output = os.path.join(root, "runtime_output")
    os.mkdir(source, 0o755)
    os.mkdir(output, 0o777)

    log_name = f"events_{token}.log"
    sql_name = f"records_{token}.sql"
    ip1 = f"23.45.67.{int(token[:2], 16) % 250 + 1}"
    ip2 = f"101.102.103.{int(token[2:4], 16) % 250 + 1}"
    log_content = f"request from {ip1}\nforwarded by {ip2} token={token}\n"
    sql_content = f"INSERT INTO audit VALUES ('{token}', '{ip1}');\n"

    with open(os.path.join(source, log_name), "w") as f:
        f.write(log_content)
    with open(os.path.join(source, sql_name), "w") as f:
        f.write(sql_content)

    archive = os.path.join(output, f"archive_{token}.tar.gz")
    runtime_yaml = (
        f'archive_name: "{archive}"\n'
        f'source_directory: "{source}"\n'
        "anonymize_logs: true\n"
        "include_db: true\n"
    )

    try:
        with open(config, "w") as f:
            f.write(runtime_yaml)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", script],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"backup_tool.py failed: {result.stderr}"
        assert os.path.isfile(archive), "Tool did not honor archive_name from the runtime YAML"
        assert "Traceback (most recent call last)" not in result.stderr

        output_lines = result.stdout.splitlines()
        assert f"Added {log_name}" in output_lines, "Tool did not print the runtime log filename"
        assert f"Added {sql_name}" in output_lines, "Tool did not print the runtime SQL filename"

        with tarfile.open(archive, "r:gz") as tar:
            members = tar.getmembers()
            assert sorted(m.name for m in members) == sorted([log_name, sql_name]), (
                "Runtime archive does not contain exactly the files from the configured source"
            )
            assert all(m.isfile() and "/" not in m.name for m in members), (
                "Runtime archive entries must be regular files at archive root"
            )
            archived_log = tar.extractfile(log_name).read().decode("utf-8")
            archived_sql = tar.extractfile(sql_name).read().decode("utf-8")

        expected_log = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "XXX.XXX.XXX.XXX", log_content)
        assert archived_log == expected_log, "Runtime log was not completely and exactly sanitized"
        assert archived_sql == sql_content, "Runtime SQL file was not archived unchanged"

        with open(os.path.join(source, log_name), "r") as f:
            assert f.read() == log_content, "Tool modified the runtime source log"
        with open(os.path.join(source, sql_name), "r") as f:
            assert f.read() == sql_content, "Tool modified the runtime source SQL file"
    finally:
        with open(config, "wb") as f:
            f.write(original_config)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
