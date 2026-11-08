#!/bin/bash
set -e
mkdir -p /logs/verifier
trap 'echo "0" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import stat
import struct
import subprocess
import tempfile
import time


def run_program(program, path):
    try:
        return subprocess.run(
            [program, path], capture_output=True, timeout=2
        ).returncode
    except subprocess.TimeoutExpired:
        raise AssertionError(f"{program} timed out while validating {path}")


def make_pdat(entries, magic=b"PDAT", target_size=512, declared_count=None):
    data = bytearray(magic)
    data += struct.pack("<I", len(entries) if declared_count is None else declared_count)
    for offset, size, name in entries:
        data += struct.pack("<II", offset, size)
        data += name.encode("utf-16le") + b"\x00\x00"
    if len(data) < target_size:
        data += b"\x00" * (target_size - len(data))
    return bytes(data)


def test_pdat_filter_exists():
    binary_path = "/home/user/pdat_filter"
    assert os.path.isfile(binary_path), f"Expected binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"The file {binary_path} is not executable."
    assert stat.S_ISREG(os.stat(binary_path).st_mode), "pdat_filter must be a regular file."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pdat_filter must be a compiled executable."
    with open(binary_path, "rb") as submitted, open("/app/validator", "rb") as reference:
        assert submitted.read() != reference.read(), "pdat_filter must not be a byte-identical copy of validator."


def test_clean_corpus():
    clean_dir = "/tests/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    assert clean_files, f"No clean files found in {clean_dir}"

    failed = []
    for f in clean_files:
        res = subprocess.run(["/home/user/pdat_filter", f], capture_output=True)
        if res.returncode != 0:
            failed.append(os.path.basename(f))

    assert not failed, f"{len(failed)} of {len(clean_files)} clean files rejected (should exit 0): {failed}"


def test_evil_corpus():
    evil_dir = "/tests/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    assert evil_files, f"No evil files found in {evil_dir}"

    failed = []
    for f in evil_files:
        res = subprocess.run(["/home/user/pdat_filter", f], capture_output=True)
        if res.returncode == 0:
            failed.append(os.path.basename(f))

    assert not failed, f"{len(failed)} of {len(evil_files)} evil files bypassed (should exit 1): {failed}"


def test_unseen_cases_against_oracle_and_source():
    source = "/home/user/pdat_filter.c"
    assert os.path.isfile(source), f"Expected C source {source} does not exist."
    assert stat.S_ISREG(os.stat(source).st_mode), "pdat_filter.c must be a regular file."

    work = tempfile.mkdtemp(prefix="pdat_runtime_")
    rebuilt = os.path.join(work, secrets.token_hex(12))
    compile_result = subprocess.run(
        ["gcc", "-O2", "-std=c11", source, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "pdat_filter.c did not compile successfully:\n" + compile_result.stderr
    )

    rng = random.Random(int.from_bytes(os.urandom(16), "little"))
    cases = [
        b"",
        b"P",
        b"PDAT",
        b"PDAT\x00\x00\x00",
        b"BADT\x00\x00\x00\x00",
        b"PDAT\x01\x00\x00\x00",
        b"PDAT\x01\x00\x00\x00" + struct.pack("<II", 0, 0) + b"A\x00",
        make_pdat([], target_size=8),
        make_pdat([(0, 0, "a")], target_size=64),
        make_pdat([(12, 20, "folder\\name.txt")], target_size=128),
        make_pdat([(20, 10, "single.dot")], target_size=128),
        make_pdat([(20, 10, "dir/file")], target_size=128),
        make_pdat([(20, 10, "name..txt")], target_size=128),
        make_pdat([(0xffffffff, 1, "x")], target_size=128),
        make_pdat([(127, 1, "x")], target_size=128),
        make_pdat([(128, 1, "x")], target_size=128),
        b"PDAT" + struct.pack("<I", 1) + struct.pack("<II", 0, 0) + b"A\x00B\x00",
    ]

    safe_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    for _ in range(35):
        entry_count = rng.randint(0, 4)
        entries = []
        for _ in range(entry_count):
            name = "".join(rng.choice(safe_chars) for _ in range(rng.randint(1, 24)))
            if rng.random() < 0.4:
                name += ".txt"
            offset = rng.randint(0, 511)
            size = rng.randint(0, 512 - offset)
            entries.append((offset, size, name))
        cases.append(make_pdat(entries, target_size=512))

    malicious_names = ["../x", "a/b", "/root", "a..b", "...", "x/y/z"]
    for _ in range(25):
        cases.append(make_pdat([
            (rng.randint(0, 300), rng.randint(0, 100), rng.choice(malicious_names))
        ], target_size=512))

    for _ in range(35):
        base = bytearray(make_pdat([(100, 50, "ordinary.txt")], target_size=256))
        for _ in range(rng.randint(1, 8)):
            operation = rng.randrange(3)
            if operation == 0 and base:
                base[rng.randrange(len(base))] ^= rng.randrange(1, 256)
            elif operation == 1 and base:
                del base[rng.randrange(len(base)) : rng.randrange(len(base)) + rng.randint(1, 12)]
            else:
                pos = rng.randrange(len(base) + 1)
                base[pos:pos] = os.urandom(rng.randint(1, 8))
        cases.append(bytes(base))

    for _ in range(30):
        cases.append(os.urandom(rng.randint(0, 300)))

    rng.shuffle(cases)
    for content in cases:
        path = os.path.join(work, secrets.token_hex(16) + ".pdat")
        with open(path, "wb") as f:
            f.write(content)

        expected = run_program("/app/validator", path)
        assert expected in (0, 1), f"Oracle returned unexpected status {expected}"
        installed_result = run_program("/home/user/pdat_filter", path)
        rebuilt_result = run_program(rebuilt, path)
        assert installed_result == expected, (
            f"Installed pdat_filter returned {installed_result}, oracle returned {expected} "
            f"for an unseen input"
        )
        assert rebuilt_result == expected, (
            f"Freshly compiled pdat_filter.c returned {rebuilt_result}, oracle returned {expected} "
            f"for an unseen input"
        )


def test_watch_script():
    watch_script = "/home/user/watch.sh"
    assert os.path.isfile(watch_script), f"Expected script {watch_script} does not exist."
    assert os.access(watch_script, os.X_OK), f"The script {watch_script} is not executable."

    fixed_clean = "/home/user/incoming/test_clean.pdat"
    fixed_evil = "/home/user/incoming/test_evil.pdat"
    fixed_accepted = "/home/user/accepted/test_clean.pdat"
    fixed_rejected = "/home/user/rejected/test_evil.pdat"
    token = secrets.token_hex(10)
    random_valid_name = f"item_{token}.pdat"
    random_invalid_name = f"item_{secrets.token_hex(10)}.pdat"
    random_valid_dest = os.path.join("/home/user/accepted", random_valid_name)
    random_invalid_dest = os.path.join("/home/user/rejected", random_invalid_name)

    for path in [fixed_clean, fixed_evil, fixed_accepted, fixed_rejected,
                 os.path.join("/home/user/incoming", random_valid_name),
                 os.path.join("/home/user/incoming", random_invalid_name),
                 random_valid_dest, random_invalid_dest]:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    try:
        os.unlink("/home/user/process.log")
    except FileNotFoundError:
        pass

    tempdir = tempfile.mkdtemp(prefix="watch_inputs_")
    valid_source = os.path.join(tempdir, secrets.token_hex(8))
    invalid_source = os.path.join(tempdir, secrets.token_hex(8))
    with open(valid_source, "wb") as f:
        f.write(make_pdat([(40, 20, "normal.txt")], target_size=256))
    with open(invalid_source, "wb") as f:
        f.write(make_pdat([(40, 20, "dir/file.txt")], target_size=256))
    assert run_program("/app/validator", valid_source) == 0
    assert run_program("/app/validator", invalid_source) == 1

    proc = subprocess.Popen([watch_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        time.sleep(1)

        clean_files = glob.glob("/tests/corpora/clean/*")
        if clean_files:
            subprocess.run(["cp", clean_files[0], fixed_clean], check=True)

        evil_files = glob.glob("/tests/corpora/evil/*")
        if evil_files:
            subprocess.run(["cp", evil_files[0], fixed_evil], check=True)

        subprocess.run(["cp", valid_source, os.path.join("/home/user/incoming", random_valid_name)], check=True)
        subprocess.run(["cp", invalid_source, os.path.join("/home/user/incoming", random_invalid_name)], check=True)

        deadline = time.time() + 6
        while time.time() < deadline:
            if all(os.path.exists(p) for p in [fixed_accepted, fixed_rejected,
                                               random_valid_dest, random_invalid_dest]):
                break
            time.sleep(0.1)

        assert os.path.exists(fixed_accepted), "Clean file was not moved to /home/user/accepted/"
        assert os.path.exists(fixed_rejected), "Evil file was not moved to /home/user/rejected/"
        assert os.path.exists(random_valid_dest), "Unseen valid file was not moved to /home/user/accepted/"
        assert os.path.exists(random_invalid_dest), "Unseen invalid file was not moved to /home/user/rejected/"

        log_path = "/home/user/process.log"
        assert os.path.exists(log_path), f"Log file {log_path} was not created."
        with open(log_path, "r") as f:
            log_content = f.read()

        assert "test_clean.pdat: ACCEPTED" in log_content, "Clean file processing was not logged correctly."
        assert "test_evil.pdat: REJECTED" in log_content, "Evil file processing was not logged correctly."
        assert f"{random_valid_name}: ACCEPTED" in log_content, "Unseen valid file was not logged correctly."
        assert f"{random_invalid_name}: REJECTED" in log_content, "Unseen invalid file was not logged correctly."
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
trap - EXIT
