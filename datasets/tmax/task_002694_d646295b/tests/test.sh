#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import gzip
import hashlib
import json
import os
import pwd
import shutil
import subprocess
import tempfile


def test_clean_dataset_exists_and_content():
    expected_content = """record_id,scaled_measurement
102,450.0
103,220.0
105,123.0
108,5.0"""

    file_path = "/home/user/clean_dataset.csv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )


def test_script_exists_and_uses_atomic_write():
    script_path = "/home/user/compile_results.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original static assertions.
    has_rename = any(func in content for func in ["os.rename", "os.replace", "shutil.move"])
    assert has_rename, "Script does not appear to use an atomic rename operation (e.g., os.rename, os.replace, or shutil.move)."

    has_tmp = ".tmp" in content or "temp" in content.lower() or "NamedTemporaryFile" in content
    assert has_tmp, "Script does not appear to use a temporary file for atomic writing."


def _write_gzip_csv(path, rows):
    with gzip.open(path, "wt", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["record_id", "experiment_name", "status", "measurement"])
        writer.writerows(rows)


def test_script_on_varied_dataset_follows_symlinks_avoids_loops_and_renames_temp():
    script_path = "/home/user/compile_results.py"
    dataset = "/home/user/dataset"
    final_path = "/home/user/clean_dataset.csv"
    token = next(tempfile._get_candidate_names())
    backup = f"/home/user/dataset.verifier-backup-{token}"
    external = f"/home/user/verifier-linked-data-{token}"
    atomic_log = f"/tmp/atomic-{token}.jsonl"

    base_rows = [
        [30, "newA", "VALID", "3.5"],
        [2, "newA", "VALID", "1.25"],
        [99, "newA", "ERROR", "1000"],
    ]
    linked_rows = [
        [11, "newB", "VALID", "-0.5"],
        [7, "newB", "VALID", "0.0"],
        [4, "newB", "valid", "8.0"],
        [5, "newB", "VALID ", "9.0"],
    ]
    all_rows = base_rows + linked_rows
    expected = sorted(
        [(int(r[0]), str(float(r[3]) * 100.0)) for r in all_rows if r[2] == "VALID"],
        key=lambda x: x[0],
    )

    os.rename(dataset, backup)
    try:
        os.makedirs(os.path.join(dataset, "ordinary", "nested"))
        os.makedirs(os.path.join(dataset, "cycle"))
        os.makedirs(os.path.join(external, "deep"))
        _write_gzip_csv(os.path.join(dataset, "ordinary", "nested", "base.csv.gz"), base_rows)
        _write_gzip_csv(os.path.join(external, "deep", "linked.csv.gz"), linked_rows)
        with open(os.path.join(dataset, "ordinary", "notes.txt"), "w") as f:
            f.write("not input data\n")

        # The second gzip file is reachable only by following a valid directory symlink.
        os.symlink(external, os.path.join(dataset, "linked_batch"))
        # Both an ancestor loop and a self-referential loop must terminate safely.
        os.symlink(dataset, os.path.join(dataset, "cycle", "back_to_root"))
        os.symlink(os.path.join(dataset, "cycle"), os.path.join(dataset, "cycle", "self"))

        user = pwd.getpwnam("user")
        for root in [dataset, external]:
            for current, dirs, files in os.walk(root, followlinks=False):
                os.chown(current, user.pw_uid, user.pw_gid)
                for name in files:
                    os.chown(os.path.join(current, name), user.pw_uid, user.pw_gid)
                for name in dirs:
                    p = os.path.join(current, name)
                    if not os.path.islink(p):
                        os.chown(p, user.pw_uid, user.pw_gid)
        # Inputs are readable but cannot be used as extraction destinations.
        for root in [dataset, external]:
            for current, dirs, files in os.walk(root, followlinks=False):
                os.chmod(current, 0o555)
                for name in files:
                    os.chmod(os.path.join(current, name), 0o444)

        if os.path.lexists(final_path):
            os.unlink(final_path)
        with open(atomic_log, "w"):
            pass
        os.chown(atomic_log, user.pw_uid, user.pw_gid)
        os.chmod(atomic_log, 0o666)

        wrapper = r'''
import hashlib
import json
import os
import runpy

log_path = os.environ["ATOMIC_LOG"]
original_rename = os.rename
original_replace = os.replace

def tracked(original, operation):
    def call(src, dst, *args, **kwargs):
        src_text = os.fspath(src)
        dst_text = os.fspath(dst)
        src_abs = os.path.abspath(src_text)
        dst_abs = os.path.abspath(dst_text)
        digest = None
        if os.path.isfile(src_abs):
            with open(src_abs, "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
        result = original(src, dst, *args, **kwargs)
        with open(log_path, "a") as f:
            f.write(json.dumps({"operation": operation, "src": src_abs,
                                "dst": dst_abs, "src_hash": digest}) + "\n")
        return result
    return call

os.rename = tracked(original_rename, "rename")
os.replace = tracked(original_replace, "replace")
runpy.run_path("/home/user/compile_results.py", run_name="__main__")
'''

        def demote():
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        env = os.environ.copy()
        env["ATOMIC_LOG"] = atomic_log
        env["HOME"] = "/home/user"
        result = subprocess.run(
            ["python3", "-c", wrapper],
            cwd="/home/user",
            env=env,
            text=True,
            capture_output=True,
            timeout=10,
            preexec_fn=demote,
        )
        assert result.returncode == 0, (
            f"compile_results.py failed on the varied dataset.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(final_path), "Executing the script did not create clean_dataset.csv"

        with open(final_path, newline="") as f:
            output = list(csv.reader(f))
        assert output and output[0] == ["record_id", "scaled_measurement"]
        assert output[1:] == [[str(record_id), scaled] for record_id, scaled in expected], (
            f"Unexpected transformed, filtered, or sorted rows: {output[1:]}"
        )

        with open(final_path, "rb") as f:
            final_hash = hashlib.sha256(f.read()).hexdigest()
        with open(atomic_log) as f:
            events = [json.loads(line) for line in f if line.strip()]
        matching = [
            event for event in events
            if os.path.abspath(event["dst"]) == final_path
            and os.path.abspath(event["src"]) != final_path
            and event.get("src_hash") == final_hash
        ]
        assert matching, (
            "The final output was not installed by renaming/replacing a temporary file "
            "that already contained the completed output"
        )

        # No uncompressed CSV may have been extracted beside the inputs.
        for root in [dataset, external]:
            for current, dirs, files in os.walk(root, followlinks=False):
                assert not any(name.endswith(".csv") for name in files), (
                    "The script extracted a compressed CSV into the dataset"
                )
    finally:
        if os.path.lexists(dataset):
            shutil.rmtree(dataset)
        if os.path.exists(external):
            shutil.rmtree(external)
        if os.path.exists(backup):
            os.rename(backup, dataset)
        if os.path.exists(atomic_log):
            os.unlink(atomic_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
