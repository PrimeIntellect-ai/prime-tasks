#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import textwrap
import pytest

REPO_PATH = "/home/user/audio_service.git"
CURRENT_SYMLINK = "/home/user/releases/current"
AGENT_EXECUTABLE = os.path.join(CURRENT_SYMLINK, "target", "release", "audio_service")
ORACLE_PATH = "/tests/audio_service_oracle"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 180)
    return subprocess.run(cmd, **kwargs)


def test_deployment_state():
    assert os.path.isdir(REPO_PATH), f"Bare repository not found at {REPO_PATH}"

    bare_check = run(["git", "--git-dir", REPO_PATH, "rev-parse", "--is-bare-repository"], text=True)
    assert bare_check.returncode == 0 and bare_check.stdout.strip() == "true", \
        f"Repository at {REPO_PATH} is not a bare Git repository"

    hook_path = os.path.join(REPO_PATH, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"post-receive hook is not executable"

    assert os.path.islink(CURRENT_SYMLINK), f"Symlink not found at {CURRENT_SYMLINK}"
    current_target = os.path.realpath(CURRENT_SYMLINK)
    assert os.path.isdir(current_target), f"Current symlink target is not a directory: {current_target}"

    assert os.path.isfile(AGENT_EXECUTABLE), f"Agent executable not found at {AGENT_EXECUTABLE}"
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable is not executable"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle is not executable at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_EXECUTABLE), f"Agent executable not found at {AGENT_EXECUTABLE}"

    random.seed(42)
    for i in range(1000):
        length = random.randint(0, 65536)
        input_data = random.randbytes(length)

        oracle_proc = run([ORACLE_PATH], input=input_data)
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"

        agent_proc = run([AGENT_EXECUTABLE], input=input_data)
        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent executable failed with return code {agent_proc.returncode} "
                f"on iteration {i} with input length {length}"
            )
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Output mismatch on iteration {i} with input length {length}. "
                f"Expected {len(oracle_proc.stdout)} bytes, got {len(agent_proc.stdout)} bytes."
            )


def test_post_receive_hook_behavior():
    hook_path = os.path.join(REPO_PATH, "hooks", "post-receive")
    marker = secrets.token_hex(24)

    with tempfile.TemporaryDirectory(prefix="verify-audio-hook-") as work:
        subprocess.run(["git", "init", work], check=True, capture_output=True)
        subprocess.run(["git", "-C", work, "config", "user.name", "Verifier"], check=True)
        subprocess.run(["git", "-C", work, "config", "user.email", "verifier@example.invalid"], check=True)

        os.makedirs(os.path.join(work, "src"))
        with open(os.path.join(work, "Cargo.toml"), "w") as f:
            f.write(textwrap.dedent("""\
                [package]
                name = "audio_service"
                version = "0.1.0"
                edition = "2021"
            """))
        with open(os.path.join(work, "src", "main.rs"), "w") as f:
            f.write(textwrap.dedent(f"""\
                use std::io::{{self, Read, Write}};
                fn main() {{
                    let mut data = Vec::new();
                    io::stdin().read_to_end(&mut data).unwrap();
                    for byte in &mut data {{
                        *byte = byte.rotate_right(3) ^ 0x8C;
                    }}
                    io::stdout().write_all(&data).unwrap();
                    eprintln!("{marker}");
                }}
            """))
        with open(os.path.join(work, "deployment_marker"), "w") as f:
            f.write(marker + "\n")

        subprocess.run(["git", "-C", work, "add", "."], check=True)
        subprocess.run(["git", "-C", work, "commit", "-m", "verifier valid deployment"], check=True, capture_output=True)
        valid_hash = subprocess.check_output(["git", "-C", work, "rev-parse", "HEAD"], text=True).strip()

        push = run([
            "git", "-c", f"safe.directory={REPO_PATH}", "-C", work,
            "push", REPO_PATH, "HEAD:refs/heads/verifier-hook-test"
        ], text=True, timeout=300)
        assert push.returncode == 0, f"Valid push failed: {push.stdout}\n{push.stderr}"

        valid_release = f"/home/user/releases/release_{valid_hash}"
        assert os.path.isdir(valid_release), f"Hook did not create {valid_release}"
        assert os.path.realpath(CURRENT_SYMLINK) == os.path.realpath(valid_release), \
            "Hook did not update current to the release for the pushed commit"

        marker_file = os.path.join(valid_release, "deployment_marker")
        assert os.path.isfile(marker_file), "Hook did not extract the pushed commit into its release"
        with open(marker_file) as f:
            assert f.read().strip() == marker

        built_binary = os.path.join(valid_release, "target", "release", "audio_service")
        assert os.path.isfile(built_binary) and os.access(built_binary, os.X_OK), \
            "Hook did not produce an executable release build"
        probe = secrets.token_bytes(4096)
        expected = bytes(((b >> 3) | ((b << 5) & 0xff)) ^ 0x8C for b in probe)
        built = run([built_binary], input=probe)
        assert built.returncode == 0 and built.stdout == expected, "Built release has incorrect behavior"
        assert built.stderr.decode(errors="replace").strip() == marker, \
            "Deployed binary was not built from the pushed source"

        with open(os.path.join(work, "src", "main.rs"), "w") as f:
            f.write("fn main() { std::process::exit(7); }\n")
        subprocess.run(["git", "-C", work, "add", "src/main.rs"], check=True)
        subprocess.run(["git", "-C", work, "commit", "-m", "verifier failing health check"], check=True, capture_output=True)
        invalid_hash = subprocess.check_output(["git", "-C", work, "rev-parse", "HEAD"], text=True).strip()

        run([
            "git", "-c", f"safe.directory={REPO_PATH}", "-C", work,
            "push", REPO_PATH, "HEAD:refs/heads/verifier-hook-test"
        ], text=True, timeout=300)
        assert os.path.realpath(CURRENT_SYMLINK) == os.path.realpath(valid_release), \
            "Hook activated a release whose binary fails the health check"

        hook_input = f"{valid_hash} {invalid_hash} refs/heads/verifier-hook-test\n"
        failed_hook = run([hook_path], input=hook_input, text=True, cwd=REPO_PATH, timeout=300)
        assert failed_hook.returncode != 0, "Hook did not exit non-zero after a failed health check"
        assert os.path.realpath(CURRENT_SYMLINK) == os.path.realpath(valid_release), \
            "Failed health check changed the current deployment"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
