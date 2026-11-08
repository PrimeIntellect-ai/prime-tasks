#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import os
import tarfile
import zipfile


def archive_records():
    archive = "/home/user/dataset_archives/master_dataset.tar.gz"
    records = {}
    with tarfile.open(archive, "r:gz") as tf:
        for member in tf.getmembers():
            if not member.isfile() or not member.name.lower().endswith(".zip"):
                continue
            extracted = tf.extractfile(member)
            assert extracted is not None
            with zipfile.ZipFile(io.BytesIO(extracted.read())) as zf:
                for name in zf.namelist():
                    if name.lower().endswith(".dat") and not name.endswith("/"):
                        data = zf.read(name)
                        lines = data.decode("utf-8").splitlines()
                        assert lines[0].startswith("SENSOR_ID: ")
                        assert lines[1].startswith("TIMESTAMP: ")
                        sensor = lines[0].split(":", 1)[1].strip()
                        timestamp = lines[1].split(":", 1)[1].strip()
                        records[os.path.basename(name)] = (
                            f"sensor_{sensor}_{timestamp}.dat", data
                        )
    return records


def test_processed_dataset_directory():
    dir_path = "/home/user/processed_dataset"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."


def test_processed_files_exist():
    dir_path = "/home/user/processed_dataset"
    for i in range(1, 11):
        filename = f"sensor_X{i}_17000000{i:02d}.dat"
        file_path = os.path.join(dir_path, filename)
        assert os.path.isfile(file_path), f"Expected processed file {file_path} does not exist."


def test_processed_file_contents_match_archive():
    for original, (renamed, expected_data) in archive_records().items():
        path = os.path.join("/home/user/processed_dataset", renamed)
        assert os.path.isfile(path), f"Missing processed file for {original}: {path}"
        with open(path, "rb") as f:
            assert f.read() == expected_data, f"Processed contents differ for {path}"


def test_rename_log_exists_and_format():
    log_path = "/home/user/processed_dataset/rename_log.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 10, f"Expected exactly 10 lines in {log_path}, found {len(lines)}."

    expected_mappings = []
    for i in range(1, 11):
        orig = f"file_{i:02d}.dat"
        new = f"sensor_X{i}_17000000{i:02d}.dat"
        expected_mappings.append(f"{orig} -> {new}")
    for mapping in expected_mappings:
        assert mapping in lines, f"Expected mapping '{mapping}' not found in {log_path}."

    derived = {
        f"{original} -> {renamed}"
        for original, (renamed, _) in archive_records().items()
    }
    assert set(lines) == derived, "Log mappings do not match the files in the nested archive."


def test_process_data_script():
    script_path = "/home/user/process_data.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    with open(script_path, "r") as f:
        content = f.read()
    assert "filelock" in content.lower(), f"Script {script_path} must use the filelock package."
    has_concurrent = "concurrent" in content or "multiprocessing" in content
    assert has_concurrent, f"Script {script_path} must use concurrent.futures or multiprocessing."


def test_required_apis_are_actually_constructed():
    path = "/home/user/process_data.py"
    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    lock_names = {"FileLock"}
    concurrency_names = {
        "ThreadPoolExecutor", "ProcessPoolExecutor", "Pool", "Process"
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            module = node.module or ""
            for alias in node.names:
                local = alias.asname or alias.name
                if module == "filelock" and alias.name == "FileLock":
                    lock_names.add(local)
                if (module.startswith("concurrent.futures") or
                        module.startswith("multiprocessing")) and alias.name in concurrency_names:
                    concurrency_names.add(local)

    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                calls.append(node.func.attr)

    assert any(name in lock_names for name in calls), "process_data.py never constructs a FileLock."
    assert any(name in concurrency_names for name in calls), (
        "process_data.py never constructs a concurrent executor or multiprocessing worker/pool."
    )


def test_filelock_installed():
    try:
        import filelock  # noqa: F401
    except ImportError:
        assert False, "The 'filelock' package is not installed."
TEST_EOF

cat <<'BEHAVIOR_EOF' > /tmp/test_behavior.py
import ast
import io
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

SCRIPT = "/home/user/process_data.py"
PROCESSED = "/home/user/processed_dataset"
MASTER = "/home/user/dataset_archives/master_dataset.tar.gz"
token = uuid.uuid4().hex[:12]
work = tempfile.mkdtemp(prefix="verifier_behavior_")
processed_backup = os.path.join(work, "processed_backup")
master_backup = os.path.join(work, "master_backup.tar.gz")
created_probes = []

def safe_candidate(path):
    path = os.path.abspath(path)
    if path in ("/", "/home", "/tmp"):
        return False
    blocked = (PROCESSED, "/home/user/dataset_archives", "/logs", "/tests", work)
    return path.startswith(("/home/user/", "/tmp/")) and not any(
        path == b or path.startswith(b + os.sep) for b in blocked
    )


def make_group(directory, group, count=12):
    os.makedirs(directory, exist_ok=True)
    expected = []
    for i in range(count):
        original = f"probe_{token}_{group}_{i:02d}.dat"
        sensor = f"V{token}{group}Z{i}"
        timestamp = str(1800000000 + group * 100 + i)
        renamed = f"sensor_{sensor}_{timestamp}.dat"
        data = (
            f"SENSOR_ID: {sensor}\n"
            f"TIMESTAMP: {timestamp}\n"
            f"random verifier payload {token} {group} {i}\n"
        ).encode()
        path = os.path.join(directory, original)
        with open(path, "wb") as f:
            f.write(data)
        created_probes.append(path)
        expected.append((original, renamed, data))
    return expected


def make_dynamic_master(path, group=900):
    expected = []
    zip_blobs = []
    for batch in range(2):
        blob = io.BytesIO()
        with zipfile.ZipFile(blob, "w", zipfile.ZIP_DEFLATED) as zf:
            for j in range(6):
                i = batch * 6 + j
                original = f"archive_probe_{token}_{i:02d}.dat"
                sensor = f"A{token}Z{i}"
                timestamp = str(1900000000 + i)
                renamed = f"sensor_{sensor}_{timestamp}.dat"
                data = (
                    f"SENSOR_ID: {sensor}\n"
                    f"TIMESTAMP: {timestamp}\n"
                    f"archive verifier payload {token} {i}\n"
                ).encode()
                zf.writestr(original, data)
                expected.append((original, renamed, data))
        zip_blobs.append((f"batch_{batch}.zip", blob.getvalue()))
    with tarfile.open(path, "w:gz") as tf:
        for name, data in zip_blobs:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))
    return expected


try:
    shutil.copytree(PROCESSED, processed_backup)
    shutil.copy2(MASTER, master_backup)

    with open(SCRIPT, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    candidates = set()
    defaults = [
        "/home/user/extracted_data", "/home/user/extracted_dataset",
        "/home/user/temp_data", "/home/user/tmp",
        "/tmp/extracted_data", "/tmp/extracted_dataset", "/tmp/sensor_data"
    ]
    candidates.update(defaults)

    for base in ("/home/user", "/tmp"):
        for root, dirs, files in os.walk(base):
            rel_depth = os.path.relpath(root, base).count(os.sep)
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            if rel_depth >= 3:
                dirs[:] = []
            if safe_candidate(root) and any(k in root.lower() for k in ("extract", "temp", "tmp", "data")):
                candidates.add(root)

    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            value = node.value
            if value.startswith(("/home/user/", "/tmp/")):
                value = value.split("*")[0]
                if os.path.splitext(value)[1] in (".dat", ".txt", ".zip", ".gz", ".py"):
                    value = os.path.dirname(value)
                if safe_candidate(value):
                    candidates.add(value)
            elif value and not os.path.isabs(value) and any(
                    k in value.lower() for k in ("extract", "temp", "data")):
                value = value.split("*")[0].strip("/.")
                if value:
                    candidates.add(os.path.join("/home/user", value))

    candidates = sorted(p for p in candidates if safe_candidate(p))[:40]
    groups = []
    for group, directory in enumerate(candidates):
        try:
            groups.append(make_group(directory, group))
        except OSError:
            pass

    archive_group = make_dynamic_master(MASTER)
    groups.append(archive_group)

    shutil.rmtree(PROCESSED)
    result = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45
    )
    assert result.returncode == 0, (
        f"process_data.py failed when executed (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isdir(PROCESSED), "Executed script did not create processed_dataset."
    log_path = os.path.join(PROCESSED, "rename_log.txt")
    assert os.path.isfile(log_path), "Executed script did not create rename_log.txt."
    with open(log_path, "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]

    successful_groups = []
    for expected in groups:
        ok = True
        for original, renamed, data in expected:
            output = os.path.join(PROCESSED, renamed)
            mapping = f"{original} -> {renamed}"
            if not os.path.isfile(output) or log_lines.count(mapping) != 1:
                ok = False
                break
            with open(output, "rb") as f:
                if f.read() != data:
                    ok = False
                    break
        if ok:
            successful_groups.append(expected)

    assert successful_groups, (
        "Executing process_data.py did not correctly process any complete set of 12 "
        "fresh, verifier-generated .dat files with preserved contents and exact log entries."
    )
finally:
    for path in created_probes:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    if os.path.exists(master_backup):
        shutil.copy2(master_backup, MASTER)
    if os.path.isdir(PROCESSED):
        shutil.rmtree(PROCESSED)
    if os.path.isdir(processed_backup):
        shutil.copytree(processed_backup, PROCESSED)
    shutil.rmtree(work, ignore_errors=True)
BEHAVIOR_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
