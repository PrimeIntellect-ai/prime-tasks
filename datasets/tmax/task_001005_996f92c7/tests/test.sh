#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import hashlib
import subprocess
import tempfile
import shutil
import secrets


def get_expected_results():
    submissions_dir = "/home/user/ci_system/submissions"
    src_dir = "/home/user/ci_system/src"

    meta_files = sorted(glob.glob(os.path.join(submissions_dir, "*.meta")))

    user_timestamps = {}
    expected_results = []

    for meta_file in meta_files:
        base_name = os.path.basename(meta_file)
        sub_id = base_name.replace(".meta", "")
        patch_file = os.path.join(submissions_dir, f"{sub_id}.patch")

        with open(meta_file, "r") as f:
            lines = f.read().splitlines()

        meta_data = {}
        for line in lines:
            if "=" in line:
                k, v = line.split("=", 1)
                meta_data[k.strip()] = v.strip()

        user = meta_data.get("USER")
        timestamp = int(meta_data.get("TIMESTAMP", 0))
        expected_checksum = meta_data.get("CHECKSUM")

        # 1. Rate Limiting
        last_ts = user_timestamps.get(user)
        if last_ts is not None and (timestamp - last_ts) < 60:
            expected_results.append(f"{sub_id} RATE_LIMITED")
            continue

        # Update timestamp for non-rate-limited
        user_timestamps[user] = timestamp

        # 2. Checksum Validation
        with open(patch_file, "rb") as f:
            actual_checksum = hashlib.sha256(f.read()).hexdigest()

        if actual_checksum != expected_checksum:
            expected_results.append(f"{sub_id} CHECKSUM_FAILED")
            continue

        # 3. Patch Processing
        with tempfile.TemporaryDirectory() as tmpdir:
            for item in os.listdir(src_dir):
                s = os.path.join(src_dir, item)
                d = os.path.join(tmpdir, item)
                if os.path.isdir(s):
                    shutil.copytree(s, d)
                else:
                    shutil.copy2(s, d)

            with open(patch_file, "r") as f:
                patch_proc = subprocess.run(
                    ["patch", "-p1"],
                    stdin=f,
                    cwd=tmpdir,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )

            if patch_proc.returncode != 0:
                expected_results.append(f"{sub_id} PATCH_FAILED")
                continue

            # 4. Testing
            test_proc = subprocess.run(
                ["./math_utils.sh", "test"],
                cwd=tmpdir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            if test_proc.returncode != 0:
                expected_results.append(f"{sub_id} TEST_FAILED")
                continue

            # 5. Success
            expected_results.append(f"{sub_id} ACCEPTED")

    return expected_results


def test_results_log():
    results_file = "/home/user/ci_system/results.log"
    assert os.path.isfile(results_file), f"Results file missing: {results_file}"

    with open(results_file, "r") as f:
        actual_lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    expected_lines = get_expected_results()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in results.log, found {len(actual_lines)}"

    for idx, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {idx + 1}: expected '{expected}', got '{actual}'"


def test_script_exists_and_executable():
    script_path = "/home/user/ci_system/process_queue.sh"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script not executable: {script_path}"


def test_script_processes_fresh_runtime_queue():
    base = "/home/user/ci_system"
    script_path = os.path.join(base, "process_queue.sh")
    src_dir = os.path.join(base, "src")
    submissions_dir = os.path.join(base, "submissions")
    results_file = os.path.join(base, "results.log")

    token = secrets.token_hex(6)
    user_a = "runtime_a_" + token
    user_b = "runtime_b_" + token

    baseline = '''#!/bin/bash
if [ "$1" == "test" ]; then
    res=$(./math_utils.sh add 2 3)
    if [ "$res" != "5" ]; then exit 1; fi
    exit 0
fi

if [ "$1" == "add" ]; then
    echo $(($2 + $3))
fi
'''

    valid_patch = '''--- a/math_utils.sh
+++ b/math_utils.sh
@@ -6,6 +6,9 @@
     exit 0
 fi

+if [ "$1" == "sub" ]; then
+    echo $(($2 - $3))
+fi
 if [ "$1" == "add" ]; then
     echo $(($2 + $3))
 fi
'''

    patch_fail = '''--- a/math_utils.sh
+++ b/math_utils.sh
@@ -100,1 +100,1 @@
-this-context-does-not-exist
+replacement
'''

    test_fail = '''--- a/math_utils.sh
+++ b/math_utils.sh
@@ -7,5 +7,5 @@
 fi

 if [ "$1" == "add" ]; then
-    echo $(($2 + $3))
+    echo $(($2 * $3))
 fi
'''

    with tempfile.TemporaryDirectory(prefix="queue-verifier-backup-") as backup:
        backup_src = os.path.join(backup, "src")
        backup_submissions = os.path.join(backup, "submissions")
        backup_results = os.path.join(backup, "results.log")
        had_results = os.path.exists(results_file)

        shutil.move(src_dir, backup_src)
        shutil.move(submissions_dir, backup_submissions)
        if had_results:
            shutil.move(results_file, backup_results)

        try:
            os.makedirs(src_dir)
            os.makedirs(submissions_dir)
            math_file = os.path.join(src_dir, "math_utils.sh")
            with open(math_file, "w") as f:
                f.write(baseline)
            os.chmod(math_file, 0o755)

            def add_submission(number, user, timestamp, patch_text, checksum_ok=True):
                sub_id = f"{number:02d}_{token}"
                patch_path = os.path.join(submissions_dir, sub_id + ".patch")
                with open(patch_path, "w") as f:
                    f.write(patch_text)
                digest = hashlib.sha256(patch_text.encode()).hexdigest()
                if not checksum_ok:
                    digest = ("0" if digest[0] != "0" else "1") + digest[1:]
                with open(os.path.join(submissions_dir, sub_id + ".meta"), "w") as f:
                    f.write(f"USER={user}\nTIMESTAMP={timestamp}\nCHECKSUM={digest}\n")
                return sub_id

            ids = []
            ids.append(add_submission(10, user_a, 1000, valid_patch))
            ids.append(add_submission(15, user_b, 2000, valid_patch, checksum_ok=False))
            ids.append(add_submission(20, user_a, 1030, valid_patch, checksum_ok=False))
            ids.append(add_submission(25, user_b, 2030, valid_patch))
            ids.append(add_submission(30, user_a, 1065, valid_patch))
            ids.append(add_submission(40, "runtime_c_" + token, 3000, patch_fail))
            ids.append(add_submission(50, "runtime_d_" + token, 4000, test_fail))

            expected = get_expected_results()
            assert expected == [
                f"{ids[0]} ACCEPTED",
                f"{ids[1]} CHECKSUM_FAILED",
                f"{ids[2]} RATE_LIMITED",
                f"{ids[3]} RATE_LIMITED",
                f"{ids[4]} ACCEPTED",
                f"{ids[5]} PATCH_FAILED",
                f"{ids[6]} TEST_FAILED",
            ]

            with open(results_file, "w") as f:
                f.write("STALE CONTENT MUST BE REMOVED\n")

            proc = subprocess.run(
                [script_path],
                cwd=base,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=20,
            )
            assert proc.returncode == 0, f"process_queue.sh exited with {proc.returncode}"
            assert os.path.isfile(results_file), "Script did not create results.log"

            with open(results_file, "r") as f:
                actual = f.read().splitlines()
            assert actual == expected, f"Runtime queue results mismatch: expected {expected}, got {actual}"

            with open(math_file, "r") as f:
                assert f.read() == baseline, "The baseline source tree was modified"
            assert sorted(os.listdir(src_dir)) == ["math_utils.sh"], "The baseline source tree gained unexpected files"
        finally:
            if os.path.isdir(src_dir):
                shutil.rmtree(src_dir)
            if os.path.isdir(submissions_dir):
                shutil.rmtree(submissions_dir)
            if os.path.exists(results_file):
                os.remove(results_file)
            shutil.move(backup_src, src_dir)
            shutil.move(backup_submissions, submissions_dir)
            if had_results:
                shutil.move(backup_results, results_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
