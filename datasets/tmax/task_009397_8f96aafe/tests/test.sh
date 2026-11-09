#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import secrets
import stat
import subprocess


def get_dir_size(path):
    total_size = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size


def test_script_exists_and_executable():
    script_path = "/home/user/enforce_quota.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_bob_untouched():
    bob_dir = "/home/user/ci_builds/bob"
    assert os.path.isdir(bob_dir), "Bob's directory is missing."

    build_log = os.path.join(bob_dir, "build.log")
    app_jar = os.path.join(bob_dir, "app.jar")

    assert os.path.isfile(build_log), "Bob's build.log was incorrectly deleted."
    assert os.path.isfile(app_jar), "Bob's app.jar was incorrectly deleted."


def test_alice_quota_and_files():
    alice_dir = "/home/user/ci_builds/alice"
    assert os.path.isdir(alice_dir), "Alice's directory is missing."

    size = get_dir_size(alice_dir)
    assert size <= 40000000, f"Alice's directory size {size} exceeds quota 40000000."

    old_build = os.path.join(alice_dir, "old_build.o")
    cache = os.path.join(alice_dir, "cache.pyc")
    main_bin = os.path.join(alice_dir, "main.bin")

    assert not os.path.exists(old_build), "Alice's old_build.o should have been deleted."
    assert not os.path.exists(cache), "Alice's cache.pyc should have been deleted."
    assert os.path.isfile(main_bin), "Alice's main.bin should have been kept."


def test_charlie_quota_and_files():
    charlie_dir = "/home/user/ci_builds/charlie"
    assert os.path.isdir(charlie_dir), "Charlie's directory is missing."

    size = get_dir_size(charlie_dir)
    assert size <= 40000000, f"Charlie's directory size {size} exceeds quota 40000000."

    lib1 = os.path.join(charlie_dir, "lib1.so")
    lib2 = os.path.join(charlie_dir, "lib2.so")

    assert not os.path.exists(lib1), "Charlie's lib1.so should have been deleted."
    assert os.path.isfile(lib2), "Charlie's lib2.so should have been kept."


def test_log_file_contents():
    log_file = "/home/user/quota_cleanup.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read()

    expected_lines = [
        "[CLEANUP] Deleted /home/user/ci_builds/alice/old_build.o recovered 15728640 bytes from alice",
        "[CLEANUP] Deleted /home/user/ci_builds/alice/cache.pyc recovered 15728640 bytes from alice",
        "[CLEANUP] Deleted /home/user/ci_builds/charlie/lib1.so recovered 26214400 bytes from charlie"
    ]

    for line in expected_lines:
        assert line in content, f"Expected log line not found: '{line}'"


def write_file(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    block = b"\0" * (1024 * 1024)
    remaining = size
    with open(path, "wb") as f:
        while remaining:
            chunk = block if remaining >= len(block) else block[:remaining]
            f.write(chunk)
            remaining -= len(chunk)


def chown_tree(path):
    account = pwd.getpwnam("user")
    os.chown(path, account.pw_uid, account.pw_gid)
    if os.path.isdir(path):
        for dirpath, dirnames, filenames in os.walk(path):
            os.chown(dirpath, account.pw_uid, account.pw_gid)
            for name in dirnames + filenames:
                os.chown(os.path.join(dirpath, name), account.pw_uid, account.pw_gid)


def test_script_on_randomized_directory_trees():
    rng = random.SystemRandom()
    suffix = secrets.token_hex(6)
    root = "/home/user/ci_builds"
    log_path = "/home/user/quota_cleanup.log"
    script = "/home/user/enforce_quota.sh"

    users = [f"quota_{suffix}_one", f"quota_{suffix}_two"]
    fixtures = {}

    for user_index, username in enumerate(users):
        user_dir = os.path.join(root, username)
        paths = [
            os.path.join(user_dir, "objects", "old.o"),
            os.path.join(user_dir, "cache.bin"),
            os.path.join(user_dir, "nested", "library.a"),
            os.path.join(user_dir, "newest.jar"),
        ]
        sizes = [
            rng.randint(8_000_000, 9_000_000),
            rng.randint(8_000_000, 9_000_000),
            rng.randint(13_000_000, 14_000_000),
            rng.randint(21_000_000, 22_000_000),
        ]
        for index, (path, size) in enumerate(zip(paths, sizes)):
            write_file(path, size)
            timestamp = 1_600_000_000 + user_index * 100 + index * 10
            os.utime(path, (timestamp, timestamp))
        chown_tree(user_dir)

        assert sum(sizes) > 40_000_000
        assert sum(sizes[1:]) > 40_000_000
        assert sum(sizes[2:]) < 40_000_000
        fixtures[username] = (user_dir, paths, sizes)

    under_user = f"under_{suffix}"
    under_dir = os.path.join(root, under_user)
    under_path = os.path.join(under_dir, "keep.dat")
    under_size = rng.randint(30_000_000, 34_000_000)
    write_file(under_path, under_size)
    os.utime(under_path, (1_500_000_000, 1_500_000_000))
    chown_tree(under_dir)

    nondirectory = os.path.join(root, f"not_a_directory_{suffix}")
    marker = secrets.token_bytes(128)
    with open(nondirectory, "wb") as f:
        f.write(marker)
    chown_tree(nondirectory)

    with open(log_path, "rb") as f:
        old_log = f.read()

    result = subprocess.run(
        [script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"Submitted script failed on randomized fixtures with exit code "
        f"{result.returncode}. stderr: {result.stderr}"
    )

    with open(log_path, "rb") as f:
        new_log = f.read()
    assert new_log.startswith(old_log), "The cleanup log was overwritten instead of appended to."
    appended_lines = new_log[len(old_log):].decode("utf-8").splitlines()

    for username, (user_dir, paths, sizes) in fixtures.items():
        assert os.path.isdir(user_dir), f"User directory {user_dir} was deleted."
        assert get_dir_size(user_dir) <= 40_000_000, f"{username} remains over quota."
        assert not os.path.exists(paths[0]), f"Oldest file for {username} was not deleted."
        assert not os.path.exists(paths[1]), f"Second-oldest file for {username} was not deleted."
        assert os.path.isfile(paths[2]), f"Script deleted too many files for {username}."
        assert os.path.isfile(paths[3]), f"Newest file for {username} was incorrectly deleted."

        expected = [
            f"[CLEANUP] Deleted {paths[0]} recovered {sizes[0]} bytes from {username}",
            f"[CLEANUP] Deleted {paths[1]} recovered {sizes[1]} bytes from {username}",
        ]
        actual = [line for line in appended_lines if line.endswith(f" bytes from {username}")]
        assert actual == expected, (
            f"Incorrect cleanup log entries or deletion order for {username}: {actual}"
        )

    assert os.path.isfile(under_path), "A file in a randomized under-quota directory was deleted."
    assert os.path.getsize(under_path) == under_size
    with open(nondirectory, "rb") as f:
        assert f.read() == marker, "A non-directory directly under ci_builds was modified."

    assert os.path.isfile("/home/user/ci_builds/bob/build.log")
    assert os.path.isfile("/home/user/ci_builds/bob/app.jar")
    assert os.path.isfile("/home/user/ci_builds/alice/main.bin")
    assert os.path.isfile("/home/user/ci_builds/charlie/lib2.so")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
