#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

QUOTA_CHECKER_PATH = "/home/user/quota_checker"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
ACL_PATH = "/app/acl.txt"
VIDEO_PATH = "/app/san_monitoring.mp4"
GIT_REPO_URL = "http://localhost:8080/allocations.git"
GIT_REPO_LOCAL = "/home/user/allocations.git"


def run_checker(path, *extra):
    return subprocess.run(
        [QUOTA_CHECKER_PATH, path, *extra],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def derive_peak_offset():
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
            VIDEO_PATH,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ],
        check=True,
        capture_output=True,
    ).stdout
    frame_bytes = width * height * 3
    assert frame_bytes > 0 and len(decoded) % frame_bytes == 0
    counts = []
    for start in range(0, len(decoded), frame_bytes):
        frame = decoded[start:start + frame_bytes]
        count = sum(
            1 for i in range(0, len(frame), 3)
            if frame[i] > 200 and frame[i + 1] < 50 and frame[i + 2] < 50
        )
        counts.append(count)
    assert counts and max(counts) > 0, "Video contains no pure-red peak frame"
    maximum = max(counts)
    assert counts.count(maximum) == 1, "Video peak is not unique"
    return counts.index(maximum) + 1


def write_alloc(path, user, mount, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(f"USER: {user}\nMOUNT: {mount}\nSIZE: {size}\n")


def configure_git(repo):
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)


def test_quota_checker_exists_and_executable():
    assert os.path.isfile(QUOTA_CHECKER_PATH), f"Quota checker binary not found at {QUOTA_CHECKER_PATH}"
    assert os.access(QUOTA_CHECKER_PATH, os.X_OK), f"Quota checker at {QUOTA_CHECKER_PATH} is not executable"
    with open(QUOTA_CHECKER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "quota_checker is not a compiled native executable"
    description = subprocess.run(
        ["file", "-b", QUOTA_CHECKER_PATH], check=True, capture_output=True, text=True
    ).stdout
    assert "ELF" in description and "executable" in description, description


def test_quota_checker_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.alloc"))
    assert len(clean_files) > 0, "No clean corpus files found."
    failed_files = []
    for f in clean_files:
        result = subprocess.run([QUOTA_CHECKER_PATH, f], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files rejected: {', '.join(failed_files)}"


def test_quota_checker_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.alloc"))
    assert len(evil_files) > 0, "No evil corpus files found."
    bypassed_files = []
    for f in evil_files:
        result = subprocess.run([QUOTA_CHECKER_PATH, f], capture_output=True)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(f))
    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed_files)}"


def test_quota_checker_generated_rules_and_video_threshold():
    peak = derive_peak_offset()
    limit = 100 - peak
    assert limit >= 0
    token = secrets.token_hex(12)
    dynamic_user = "user_" + token
    unknown_user = "unknown_" + secrets.token_hex(12)

    with open(ACL_PATH, "rb") as f:
        original_acl = f.read()
    try:
        with open(ACL_PATH, "ab") as f:
            if original_acl and not original_acl.endswith(b"\n"):
                f.write(b"\n")
            f.write((dynamic_user + "\n").encode())

        with tempfile.TemporaryDirectory(prefix="quota-generated-") as td:
            cases = []

            for index, size in enumerate(sorted(set([0, max(0, limit // 2), limit]))):
                path = os.path.join(td, f"valid-{token}-{index}.alloc")
                write_alloc(path, dynamic_user, f"/mnt/storage/{token}/{index}", size)
                cases.append((path, 0))

            invalid_specs = [
                (unknown_user, f"/mnt/storage/{token}/unknown", min(1, limit), "unknown-user"),
                (dynamic_user, f"/mnt/storage/{token}/../secret", min(1, limit), "traversal"),
                (dynamic_user, f"/mnt/storage/{token}/a/../../secret", min(1, limit), "deep-traversal"),
                (dynamic_user, f"/mnt/storage-{token}/data", min(1, limit), "bad-prefix"),
                (dynamic_user, f"/tmp/{token}", min(1, limit), "wrong-mount"),
                (dynamic_user, f"/mnt/storage/{token}/too-large", limit + 1 + secrets.randbelow(100), "over-limit"),
            ]
            for user, mount, size, label in invalid_specs:
                path = os.path.join(td, f"invalid-{label}-{secrets.token_hex(5)}.alloc")
                write_alloc(path, user, mount, size)
                cases.append((path, 1))

            malformed = [
                f"USER: {dynamic_user}\nMOUNT: /mnt/storage/{token}\n",
                f"USER: {dynamic_user}\nSIZE: 1\n",
                f"MOUNT: /mnt/storage/{token}\nSIZE: 1\n",
                f"USER: {dynamic_user}\nMOUNT: /mnt/storage/{token}\nSIZE: not-a-number\n",
                f"USER: {dynamic_user}\nMOUNT: /mnt/storage/{token}\nSIZE: {limit + 1}junk\n",
            ]
            for index, contents in enumerate(malformed):
                path = os.path.join(td, f"malformed-{token}-{index}.alloc")
                with open(path, "w") as f:
                    f.write(contents)
                cases.append((path, 1))

            for path, expected in cases:
                assert run_checker(path) == expected, f"Unexpected result for generated case {os.path.basename(path)}"

            valid = next(path for path, expected in cases if expected == 0)
            assert subprocess.run([QUOTA_CHECKER_PATH], capture_output=True).returncode == 1
            assert run_checker(valid, "unexpected-extra-argument") == 1
    finally:
        with open(ACL_PATH, "wb") as f:
            f.write(original_acl)


def test_git_repo_exists():
    assert os.path.isdir(GIT_REPO_LOCAL), f"Git repo not found at {GIT_REPO_LOCAL}"
    assert os.path.isfile(os.path.join(GIT_REPO_LOCAL, "config")), "Git repo does not appear to be initialized"
    result = subprocess.run(
        ["git", "--git-dir", GIT_REPO_LOCAL, "rev-parse", "--is-bare-repository"],
        check=True, capture_output=True, text=True,
    )
    assert result.stdout.strip() == "true"


def test_git_pre_receive_hook_exists():
    hook_path = os.path.join(GIT_REPO_LOCAL, "hooks", "pre-receive")
    assert os.path.isfile(hook_path), f"pre-receive hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), "pre-receive hook is not executable"


def test_nginx_configuration_is_active_git_proxy():
    assert subprocess.run(["pgrep", "-x", "nginx"], capture_output=True).returncode == 0, "nginx is not running"
    config = subprocess.run(["nginx", "-T"], check=True, capture_output=True, text=True).stdout
    assert "8080" in config
    assert "git-http-backend" in config
    assert "GIT_HTTP_EXPORT_ALL" in config
    assert "GIT_PROJECT_ROOT" in config
    assert "/home/user" in config


def test_nginx_git_http_push():
    # Attempt to clone, commit, and push over HTTP
    with tempfile.TemporaryDirectory() as tmpdir:
        clone_dir = os.path.join(tmpdir, "allocations")

        # Clone
        res = subprocess.run(["git", "clone", GIT_REPO_URL, clone_dir], capture_output=True)
        assert res.returncode == 0, f"Failed to clone over HTTP: {res.stderr.decode()}"

        # We need a valid user from acl.txt to make a valid alloc
        acl_path = "/app/acl.txt"
        valid_user = "admin"
        if os.path.isfile(acl_path):
            with open(acl_path, "r") as f:
                lines = f.read().splitlines()
                if lines:
                    valid_user = lines[0]

        # Create a valid alloc
        valid_alloc = os.path.join(clone_dir, "test_valid.alloc")
        with open(valid_alloc, "w") as f:
            f.write(f"USER: {valid_user}\nMOUNT: /mnt/storage/test\nSIZE: 10\n")

        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)

        subprocess.run(["git", "add", "test_valid.alloc"], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", "Add valid alloc"], cwd=clone_dir, check=True)

        # Push valid
        res = subprocess.run(["git", "push", "origin", "master"], cwd=clone_dir, capture_output=True)
        assert res.returncode == 0, f"Failed to push valid commit over HTTP: {res.stderr.decode()}"

        # Create an invalid alloc
        invalid_alloc = os.path.join(clone_dir, "test_invalid.alloc")
        with open(invalid_alloc, "w") as f:
            f.write(f"USER: {valid_user}\nMOUNT: /mnt/storage/test\nSIZE: 999\n")

        subprocess.run(["git", "add", "test_invalid.alloc"], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", "Add invalid alloc"], cwd=clone_dir, check=True)

        # Push invalid (should be rejected by pre-receive hook)
        res = subprocess.run(["git", "push", "origin", "master"], cwd=clone_dir, capture_output=True)
        assert res.returncode != 0, "Pushing an invalid alloc file succeeded, but it should have been rejected by the pre-receive hook."


def test_hook_checks_generated_incoming_alloc_files():
    peak = derive_peak_offset()
    limit = 100 - peak
    token = secrets.token_hex(10)
    dynamic_user = "hook_" + token
    unknown_user = "intruder_" + secrets.token_hex(10)
    branch = "verify-" + token

    with open(ACL_PATH, "rb") as f:
        original_acl = f.read()
    try:
        with open(ACL_PATH, "ab") as f:
            if original_acl and not original_acl.endswith(b"\n"):
                f.write(b"\n")
            f.write((dynamic_user + "\n").encode())

        with tempfile.TemporaryDirectory(prefix="hook-generated-") as td:
            repo = os.path.join(td, "repo")
            cloned = subprocess.run(["git", "clone", GIT_REPO_URL, repo], capture_output=True)
            assert cloned.returncode == 0, cloned.stderr.decode()
            configure_git(repo)
            subprocess.run(["git", "checkout", "-b", branch], cwd=repo, check=True, capture_output=True)

            accepted_rel = os.path.join("nested", token, "accepted.alloc")
            accepted_path = os.path.join(repo, accepted_rel)
            write_alloc(accepted_path, dynamic_user, f"/mnt/storage/{token}/accepted", limit)
            subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "generated valid allocation"], cwd=repo, check=True)
            pushed = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=repo, capture_output=True
            )
            assert pushed.returncode == 0, pushed.stderr.decode()
            accepted_commit = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True, text=True
            ).stdout.strip()

            def rejected_push(label, writer):
                subprocess.run(["git", "reset", "--hard", accepted_commit], cwd=repo, check=True, capture_output=True)
                subprocess.run(["git", "clean", "-fd"], cwd=repo, check=True, capture_output=True)
                writer()
                subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
                subprocess.run(["git", "commit", "-m", label], cwd=repo, check=True, capture_output=True)
                result = subprocess.run(
                    ["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=repo, capture_output=True
                )
                assert result.returncode != 0, f"Hook accepted generated invalid case: {label}"

            rejected_push(
                "random unknown ACL user",
                lambda: write_alloc(
                    os.path.join(repo, "requests", secrets.token_hex(6) + ".alloc"),
                    unknown_user, f"/mnt/storage/{token}/unknown", min(1, limit),
                ),
            )
            rejected_push(
                "random traversal",
                lambda: write_alloc(
                    os.path.join(repo, "deep", token, secrets.token_hex(6) + ".alloc"),
                    dynamic_user, f"/mnt/storage/{token}/../escape", min(1, limit),
                ),
            )
            rejected_push(
                "random mount prefix",
                lambda: write_alloc(
                    os.path.join(repo, secrets.token_hex(6) + ".alloc"),
                    dynamic_user, f"/srv/storage/{token}", min(1, limit),
                ),
            )
            rejected_push(
                "random over-limit size",
                lambda: write_alloc(
                    os.path.join(repo, "oversize", secrets.token_hex(6) + ".alloc"),
                    dynamic_user, f"/mnt/storage/{token}/large", limit + 1 + secrets.randbelow(500),
                ),
            )
            rejected_push(
                "modified existing allocation",
                lambda: write_alloc(
                    accepted_path, dynamic_user, f"/mnt/storage/{token}/../../escape", min(1, limit),
                ),
            )

            subprocess.run(["git", "reset", "--hard", accepted_commit], cwd=repo, check=True, capture_output=True)
            write_alloc(accepted_path, dynamic_user, f"/mnt/storage/{token}/updated", max(0, limit - 1))
            subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "second generated valid allocation"], cwd=repo, check=True)
            pushed = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=repo, capture_output=True
            )
            assert pushed.returncode == 0, f"Hook rejected a generated valid update: {pushed.stderr.decode()}"
    finally:
        with open(ACL_PATH, "wb") as f:
            f.write(original_acl)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
