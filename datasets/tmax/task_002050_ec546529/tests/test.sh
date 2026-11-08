#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile


def read_tree(root):
    result = {}
    for current, dirs, files in os.walk(root):
        dirs.sort()
        for filename in sorted(files):
            path = os.path.join(current, filename)
            rel = os.path.relpath(path, root)
            with open(path, "rb") as f:
                result[rel] = f.read()
    return result


def archive_files():
    result = {}
    with tarfile.open("/home/user/configs.tar.gz", "r:gz") as archive:
        for member in archive.getmembers():
            if member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None
                result[member.name.lstrip("./")] = extracted.read()
    return result


def test_endpoints_log_content():
    log_file = "/home/user/endpoints.log"
    assert os.path.isfile(log_file), f"Expected log file {log_file} does not exist."

    expected_lines = [
        "app1.conf | CACHE | 10.0.0.6:6379",
        "app1.conf | DB | 10.0.0.5:5432",
        "app2.conf | DB | 192.168.1.100:3306",
        "app3.conf | CACHE | 172.16.0.4:11211",
        "app4.conf | DB | db.internal.net:27017"
    ]

    with open(log_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The content of endpoints.log does not match the expected output."


def test_remote_backup_sync():
    sync_dir = "/home/user/remote_backup/configs_sync"
    assert os.path.isdir(sync_dir), f"Expected backup directory {sync_dir} does not exist."

    expected_files = {"app1.conf", "app2.conf", "app3.conf", "app4.conf"}
    actual_files = set(os.listdir(sync_dir))

    assert expected_files.issubset(actual_files), f"Expected files {expected_files} are not all present in {sync_dir}."


def test_tracker_script_exists():
    script_file = "/home/user/tracker.py"
    assert os.path.isfile(script_file), f"Expected script {script_file} does not exist."
    assert os.access(script_file, os.R_OK), f"Script {script_file} is not readable."


def test_extracted_and_backup_contents_match_archive():
    expected_archive = archive_files()
    expected_extracted = {
        name: content for name, content in expected_archive.items()
        if name == "configs" or name.startswith("configs/")
    }
    assert expected_extracted, "The source archive contains no configs files."

    extracted_root = "/home/user/extracted"
    assert os.path.isdir(os.path.join(extracted_root, "configs")), "The archive was not extracted under /home/user/extracted/configs."
    assert read_tree(extracted_root) == expected_extracted, "Extracted files do not exactly match the source archive."

    expected_sync = {
        name[len("configs/"):]: content
        for name, content in expected_extracted.items()
        if name.startswith("configs/")
    }
    sync_root = "/home/user/remote_backup/configs_sync"
    assert read_tree(sync_root) == expected_sync, "Backup files do not exactly match the extracted archive contents."


def test_tracker_uses_regex_and_processes_unseen_configs():
    script_file = "/home/user/tracker.py"
    with open(script_file, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=script_file)

    module_aliases = set()
    function_aliases = set()
    regex_functions = {"compile", "search", "match", "fullmatch", "findall", "finditer"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "re":
                    module_aliases.add(alias.asname or "re")
        elif isinstance(node, ast.ImportFrom) and node.module == "re":
            for alias in node.names:
                if alias.name in regex_functions:
                    function_aliases.add(alias.asname or alias.name)

    uses_regex = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            uses_regex = True
        elif (isinstance(node.func, ast.Attribute)
              and node.func.attr in regex_functions
              and isinstance(node.func.value, ast.Name)
              and node.func.value.id in module_aliases):
            uses_regex = True
    assert uses_regex, "tracker.py must use Python regular expressions to process endpoint lines."

    token = secrets.token_hex(6)
    port1 = 20000 + int(token[:3], 16) % 10000
    port2 = 30000 + int(token[3:6], 16) % 10000
    first_name = f"alpha_{token}.conf"
    second_name = f"zeta_{token}.conf"
    db_host = f"db-{token}.internal"
    cache_host = f"cache-{token}.example"
    ip_host = f"10.{int(token[0:2], 16)}.{int(token[2:4], 16)}.{int(token[4:6], 16)}"

    expected_lines = sorted([
        f"{first_name} | CACHE | {cache_host}:{port2}",
        f"{first_name} | DB | {db_host}:{port1}",
        f"{second_name} | CACHE | {ip_host}:6379",
        f"{second_name} | DB | {db_host}:27017",
    ], key=lambda line: (line.split(" | ")[0], line.split(" | ")[1]))

    extracted = "/home/user/extracted"
    log_file = "/home/user/endpoints.log"
    holding = tempfile.mkdtemp(prefix="tracker-verifier-")
    saved_extracted = os.path.join(holding, "extracted")
    saved_log = os.path.join(holding, "endpoints.log")
    had_extracted = os.path.exists(extracted)
    had_log = os.path.exists(log_file)

    try:
        if had_extracted:
            os.rename(extracted, saved_extracted)
        if had_log:
            os.rename(log_file, saved_log)

        config_dir = os.path.join(extracted, "configs")
        os.makedirs(config_dir)
        with open(os.path.join(config_dir, first_name), "w", encoding="utf-8") as f:
            f.write(f"# generated test input\nDB_URL=postgres://user:password@{db_host}:{port1}/main\n")
            f.write(f"CACHE_URL=redis://{cache_host}:{port2}/0\n")
        with open(os.path.join(config_dir, second_name), "w", encoding="utf-8") as f:
            f.write(f"CACHE_URL=redis://{ip_host}:6379/2\n")
            f.write(f"DB_URL=mongodb://{db_host}:27017/generated\n")
        with open(os.path.join(config_dir, "ignored.txt"), "w", encoding="utf-8") as f:
            f.write("DB_URL=postgres://wrong.example:9999/not_a_conf\n")

        completed = subprocess.run(
            ["python3", script_file], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
        assert completed.returncode == 0, f"tracker.py failed when executed: {completed.stderr}"
        assert os.path.isfile(log_file), "tracker.py did not create /home/user/endpoints.log."
        with open(log_file, "r", encoding="utf-8") as f:
            actual_lines = [line.strip() for line in f if line.strip()]
        assert actual_lines == expected_lines, "tracker.py did not correctly process and sort unseen .conf inputs."
    finally:
        if os.path.isdir(extracted):
            shutil.rmtree(extracted)
        elif os.path.exists(extracted):
            os.unlink(extracted)
        if os.path.exists(log_file):
            os.unlink(log_file)
        if had_extracted:
            os.rename(saved_extracted, extracted)
        if had_log:
            os.rename(saved_log, log_file)
        shutil.rmtree(holding, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
