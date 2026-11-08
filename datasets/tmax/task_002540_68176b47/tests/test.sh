#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import mmap
import os
import shutil
import subprocess
import tarfile
import tempfile
import time

TARGET_FRAMES = {142, 455, 891, 1024, 1560}
ROGUE = b"[ROGUE_OVERRIDE_ENABLED=TRUE]"
SECURE = b"[SECURE_DEFAULT_LOCKED]"
VALID = b"[VALID_CONFIG_DATA]\n"


def test_restored_configs_archive():
    archive_path = "/home/user/restored_configs.tar.gz"
    assert os.path.exists(archive_path), f"{archive_path} does not exist"
    assert os.path.isfile(archive_path), f"{archive_path} is not a regular file"

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        found_conf = False
        found = {}
        for root, dirs, files in os.walk(tmpdir):
            for file in files:
                if not file.endswith(".conf"):
                    continue

                found_conf = True
                assert file not in found, f"Duplicate configuration filename in archive: {file}"
                file_path = os.path.join(root, file)
                found[file] = file_path

                with open(file_path, "rb") as f:
                    content = f.read()
                assert ROGUE not in content, f"Rogue string found in {file}"
                if file in ["config_batch_142.conf", "config_batch_455.conf",
                            "config_batch_891.conf", "config_batch_1024.conf",
                            "config_batch_1560.conf"]:
                    assert SECURE in content, f"Secure string not found in patched file {file}"

        assert found_conf, "No .conf files found in the restored archive"

        expected_names = {f"config_batch_{i}.conf" for i in range(1801)}
        assert set(found) == expected_names, (
            f"Archive must contain exactly all 1,801 source .conf files; "
            f"missing={sorted(expected_names - set(found))[:10]}, "
            f"unexpected={sorted(set(found) - expected_names)[:10]}"
        )

        for i in range(1801):
            name = f"config_batch_{i}.conf"
            path = found[name]
            rel_parts = os.path.relpath(path, tmpdir).split(os.sep)
            assert len(rel_parts) >= 3 and rel_parts[-3:] == [
                "backups_raw", f"batch_{i // 100}", name
            ], f"Incorrect archive location for {name}: {os.path.relpath(path, tmpdir)}"

            with open(path, "rb") as f:
                content = f.read()
            expected = VALID
            if i in TARGET_FRAMES:
                expected += (SECURE + b"\n") * 1000
            assert content == expected, f"Incorrect or incomplete contents in {name}"


def test_fast_patch_speedup():
    patcher_script = "/home/user/fast_patch.py"
    assert os.path.exists(patcher_script), f"{patcher_script} does not exist"
    assert os.path.isfile(patcher_script), f"{patcher_script} is not a regular file"

    with tempfile.TemporaryDirectory() as tmpdir:
        naive_dir = os.path.join(tmpdir, "naive")
        agent_dir = os.path.join(tmpdir, "agent")
        naive_nested = os.path.join(naive_dir, "level1", "level2")
        agent_nested = os.path.join(agent_dir, "level1", "level2")
        os.makedirs(naive_nested)
        os.makedirs(agent_nested)

        filename = "large_config_7f3a9c.conf"
        naive_file = os.path.join(naive_nested, filename)
        agent_file = os.path.join(agent_nested, filename)

        chunk = (b"Some filler config data line 1\n"
                 b"Some filler config data line 2\n"
                 b"[ROGUE_OVERRIDE_ENABLED=TRUE]\n") * 1000
        patched_chunk = chunk.replace(ROGUE, SECURE)
        expected_hash = hashlib.sha256()
        expected_size = 0

        with open(naive_file, "wb") as f:
            for _ in range(5000):
                f.write(chunk)
                expected_hash.update(patched_chunk)
                expected_size += len(patched_chunk)

        shutil.copy2(naive_file, agent_file)

        start_time = time.time()
        with open(naive_file, "rb") as f:
            content = f.read()
        content = content.replace(ROGUE, SECURE)
        with open(naive_file, "wb") as f:
            f.write(content)
        t_ref = time.time() - start_time

        start_time = time.time()
        subprocess.run(["python3", patcher_script, agent_dir], check=True)
        t_agent = time.time() - start_time

        assert os.path.getsize(agent_file) == expected_size, "Patched file has an incorrect size"

        actual_hash = hashlib.sha256()
        with open(agent_file, "rb") as f:
            while True:
                block = f.read(8 * 1024 * 1024)
                if not block:
                    break
                actual_hash.update(block)
        assert actual_hash.digest() == expected_hash.digest(), (
            "Agent script did not correctly patch the complete benchmark file"
        )

        with open(agent_file, "rb") as f:
            with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as mapped:
                assert mapped.find(ROGUE) == -1, "Agent script did not replace every rogue string"
                assert mapped.find(SECURE) != -1, "Agent script did not insert the secure string"

        speedup = t_ref / max(t_agent, 0.0001)
        assert speedup >= 2.5, (
            f"Patcher speedup was {speedup:.2f}x, which is below the 2.5x threshold. "
            f"T_ref={t_ref:.2f}s, T_agent={t_agent:.2f}s"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
