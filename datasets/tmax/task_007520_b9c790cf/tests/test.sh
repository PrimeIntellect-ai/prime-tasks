#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

run_tests() {
cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_verified_files_moved():
    expected_files = [
        "/home/user/repo/x86_64/bin/app_main.bin",
        "/home/user/repo/aarch64/modules/network.ko"
    ]
    for filepath in expected_files:
        assert os.path.exists(filepath), f"Expected verified file was not moved to correct target path: {filepath}"

def test_unverified_files_not_moved():
    unexpected_file = "/home/user/repo/armv7/lib/helper.so"
    assert not os.path.exists(unexpected_file), f"Corrupted file should not have been moved to {unexpected_file}"

def test_summary_file_content():
    summary_path = "/home/user/curator_summary.txt"
    assert os.path.exists(summary_path), f"Summary file is missing at {summary_path}"

    with open(summary_path, "r") as f:
        content = f.read().strip()

    expected_content = "Successfully curated: 2 artifacts"
    assert content == expected_content, f"Summary file content is incorrect. Expected '{expected_content}', got '{content}'"

def test_original_verified_files_removed():
    unexpected_incoming_files = [
        "/home/user/incoming/raw_001.dat",
        "/home/user/incoming/raw_003.dat"
    ]
    for filepath in unexpected_incoming_files:
        assert not os.path.exists(filepath), f"Verified file {filepath} was copied instead of moved (or not moved at all)."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

cat << 'DYNAMIC_EOF' > /tmp/test_curator_dynamic.py
import os
import shutil
import stat
import subprocess
import time
import uuid
from pathlib import Path

HOME = Path('/home/user')
INCOMING = HOME / 'incoming'
REPO = HOME / 'repo'
SOURCE = HOME / 'curator.c'
BINARY = HOME / 'curator'
SUMMARY = HOME / 'curator_summary.txt'
FRESH_BINARY = Path('/tmp/curator_fresh_build')

assert SOURCE.is_file(), 'Missing /home/user/curator.c'
assert BINARY.is_file(), 'Missing compiled binary /home/user/curator'
mode = BINARY.stat().st_mode
assert stat.S_ISREG(mode) and os.access(BINARY, os.X_OK), '/home/user/curator is not an executable regular file'
with BINARY.open('rb') as f:
    assert f.read(4) == b'\x7fELF', '/home/user/curator is not an ELF binary'

compile_result = subprocess.run(
    ['gcc', str(SOURCE), '-o', str(FRESH_BINARY)],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=20,
)
assert compile_result.returncode == 0, 'curator.c does not compile:\n' + compile_result.stderr
assert os.access(FRESH_BINARY, os.X_OK), 'Freshly compiled curator is not executable'


def has_active_inotify_watch(pid):
    fd_root = Path(f'/proc/{pid}/fd')
    try:
        for fd in fd_root.iterdir():
            try:
                if os.readlink(fd) != 'anon_inode:inotify':
                    continue
                info = Path(f'/proc/{pid}/fdinfo/{fd.name}').read_text(errors='replace')
                if 'inotify wd:' in info:
                    return True
            except (FileNotFoundError, PermissionError, OSError):
                continue
    except FileNotFoundError:
        return False
    return False


def run_case(executable):
    token = uuid.uuid4().hex[:12]
    shutil.rmtree(INCOMING, ignore_errors=True)
    shutil.rmtree(REPO, ignore_errors=True)
    INCOMING.mkdir(parents=True)
    REPO.mkdir(parents=True)
    try:
        SUMMARY.unlink()
    except FileNotFoundError:
        pass

    records = [
        (f'raw_{token}_a.dat', f'x86_{token}', f'bin/deep/app_{token}.bin', 'verified', b'first verified payload\x00' + token.encode()),
        (f'raw_{token}_b.dat', f'arm_{token}', f'lib/helper_{token}.so', 'corrupted', b'corrupted payload ' + token.encode()),
        (f'raw_{token}_c.dat', f'aarch_{token}', f'modules/net/driver_{token}.ko', 'verified', b'second verified payload ' + token.encode()),
        (f'raw_{token}_d.dat', f'mips_{token}', f'objects/rejected_{token}.o', 'rejected', b'rejected payload ' + token.encode()),
    ]

    manifest_parts = []
    for filename, arch, target, status, payload in records:
        (INCOMING / filename).write_bytes(payload)
        manifest_parts.append(
            '[Artifact]\n'
            f'File: {filename}\n'
            f'Arch: {arch}\n'
            f'Target: {target}\n'
            f'Status: {status}\n'
        )
    (INCOMING / 'manifest.log').write_text('\n'.join(manifest_parts))
    (INCOMING / 'process.trigger').touch()
    (INCOMING / 'unrelated.tmp').touch()

    proc = subprocess.Popen(
        [str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate()
                raise AssertionError(f'Curator exited before the trigger was deleted. stdout={out!r}, stderr={err!r}')
            if has_active_inotify_watch(proc.pid):
                break
            time.sleep(0.05)
        else:
            raise AssertionError('Curator did not establish an active inotify watch on startup')

        (INCOMING / 'unrelated.tmp').unlink()
        time.sleep(0.35)
        assert proc.poll() is None, 'Curator reacted to deletion of a file other than process.trigger'
        assert not SUMMARY.exists(), 'Curator processed the manifest before process.trigger was deleted'
        for filename, arch, target, status, payload in records:
            assert (INCOMING / filename).is_file(), 'An artifact was processed before process.trigger was deleted'
            assert not (REPO / arch / target).exists(), 'A target appeared before process.trigger was deleted'

        (INCOMING / 'process.trigger').unlink()
        try:
            out, err = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, err = proc.communicate()
            raise AssertionError(f'Curator did not exit after trigger deletion. stdout={out!r}, stderr={err!r}')

        assert proc.returncode == 0, f'Curator exited with {proc.returncode}. stdout={out!r}, stderr={err!r}'

        verified_count = 0
        for filename, arch, target, status, payload in records:
            source = INCOMING / filename
            destination = REPO / arch / target
            if status == 'verified':
                verified_count += 1
                assert destination.is_file(), f'Verified artifact was not moved to {destination}'
                assert destination.read_bytes() == payload, f'Artifact content changed at {destination}'
                assert not source.exists(), f'Verified source was not removed: {source}'
            else:
                assert source.is_file(), f'Unverified source should remain: {source}'
                assert source.read_bytes() == payload, f'Unverified source content changed: {source}'
                assert not destination.exists(), f'Unverified artifact was moved to {destination}'

        assert SUMMARY.is_file(), 'Curator summary was not created'
        expected = f'Successfully curated: {verified_count} artifacts'
        assert SUMMARY.read_text().strip() == expected, f'Expected summary {expected!r}'
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=3)


# Exercise both the submitted executable and a fresh build of the submitted C source.
run_case(BINARY)
run_case(FRESH_BINARY)
DYNAMIC_EOF

python3 /tmp/test_curator_dynamic.py || return 1
return 0
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
