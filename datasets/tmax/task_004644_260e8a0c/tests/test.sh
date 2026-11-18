#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tarfile
import tempfile


def test_incremental_backup_end_to_end():
    script_path = '/home/user/incremental_backup.py'
    file_path = '/home/user/incremental.pak'

    # Preserve the original verifier's assertions.
    assert os.path.exists(file_path), f"The final archive file was not found at {file_path}. Did you run the legacy packer?"
    assert os.path.isfile(file_path), f"The path {file_path} exists but is not a file."
    size = os.path.getsize(file_path)
    threshold = 1500
    assert size <= threshold, (
        f"The file size of {file_path} is {size} bytes, which exceeds the maximum allowed threshold of {threshold} bytes. "
        "This indicates that either old files were not ignored, or non-ERROR/CRITICAL log entries were included in the staging files."
    )

    assert os.path.exists(script_path), f"Required script not found: {script_path}"
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"{script_path} is not a regular file"

    config_path = '/home/user/backup_config.json'
    staging_path = '/home/user/staging'
    packer_path = '/app/legacy_packer'
    work = tempfile.mkdtemp(prefix='verify_incremental_', dir='/home/user')
    saved_staging = os.path.join(work, 'saved_staging')
    saved_archive = os.path.join(work, 'saved_archive')
    real_packer = os.path.join(work, 'legacy_packer.real')
    call_log = os.path.join(work, 'packer_calls_' + secrets.token_hex(8))
    original_config = open(config_path, 'rb').read()
    had_staging = os.path.lexists(staging_path)
    had_archive = os.path.lexists(file_path)

    token1 = secrets.token_hex(12)
    token2 = secrets.token_hex(12)
    token3 = secrets.token_hex(12)
    target1 = os.path.join(work, 'targets', 'one')
    target2 = os.path.join(work, 'targets', 'two')
    nested = os.path.join(target2, 'nested')
    os.makedirs(target1)
    os.makedirs(nested)
    cutoff = 1800000000

    alpha = os.path.join(target1, 'alpha.log')
    alpha_expected = (
        f"[2027-01-15 08:01:00] [ERROR] failure-{token1}\n"
        f"Traceback payload {token2}\n"
        "  continuation line\n"
        f"[2027-01-15 08:02:00] [CRITICAL] critical-{token3}\n"
        "critical continuation\n"
    )
    with open(alpha, 'w') as f:
        f.write(
            "[2027-01-15 08:00:00] [INFO] omit this\n"
            "info continuation must also be omitted\n"
            + alpha_expected
            + "[2027-01-15 08:03:00] [DEBUG] omit debug\n"
            + "debug continuation must be omitted\n"
        )
    os.utime(alpha, (cutoff + 1, cutoff + 1))

    exactly_old = os.path.join(target2, 'exactly-at-cutoff.log')
    with open(exactly_old, 'w') as f:
        f.write(f"[2027-01-15 09:00:00] [ERROR] must-not-appear-{token1}\n")
    os.utime(exactly_old, (cutoff, cutoff))

    gamma = os.path.join(nested, 'gamma.log')
    gamma_expected = (
        f"[2027-01-15 10:01:00] [CRITICAL] nested-{token2}\n"
        "nested detail one\n"
        "nested detail two\n"
    )
    with open(gamma, 'w') as f:
        f.write(
            "[2027-01-15 10:00:00] [WARNING] omit warning\n"
            "warning continuation must be omitted\n"
            + gamma_expected
            + "[2027-01-15 10:02:00] [INFO] omit trailing info\n"
        )
    os.utime(gamma, (cutoff + 2, cutoff + 2))

    with open(os.path.join(target1, 'not-a-log.txt'), 'w') as f:
        f.write(f"[2027-01-15 11:00:00] [ERROR] wrong-extension-{token3}\n")

    try:
        if had_staging:
            os.replace(staging_path, saved_staging)
        if had_archive:
            os.replace(file_path, saved_archive)

        # A stale staged file must not leak into the new archive.
        os.makedirs(staging_path)
        with open(os.path.join(staging_path, 'stale.log'), 'w') as f:
            f.write('stale data must be removed\n')

        with open(config_path, 'w') as f:
            json.dump({
                'target_directories': [target1, target2],
                'last_run_timestamp': cutoff,
            }, f)

        # Interpose a recorder while still delegating to the real legacy packer.
        os.replace(packer_path, real_packer)
        with open(packer_path, 'w') as f:
            f.write(
                '#!/bin/sh\n'
                + "{ echo __CALL__; printf '%s\\n' \"$@\"; } >> " + repr(call_log) + "\n"
                + 'exec ' + repr(real_packer) + ' "$@"\n'
            )
        os.chmod(packer_path, 0o755)

        result = subprocess.run(
            ['python3', script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Script exited with status {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isfile(call_log), 'The script did not invoke /app/legacy_packer'
        with open(call_log) as f:
            calls = f.read().splitlines()
        assert calls == ['__CALL__', '-i', staging_path, '-o', file_path], (
            f"Unexpected legacy packer invocation: {calls!r}"
        )

        assert os.path.isdir(staging_path), 'The staging directory was not created'
        staged_names = sorted(os.listdir(staging_path))
        assert staged_names == ['alpha.log', 'gamma.log'], f"Unexpected staged files: {staged_names!r}"
        with open(os.path.join(staging_path, 'alpha.log')) as f:
            assert f.read() == alpha_expected
        with open(os.path.join(staging_path, 'gamma.log')) as f:
            assert f.read() == gamma_expected

        assert os.path.isfile(file_path), 'The legacy packer did not create the final archive'
        with tarfile.open(file_path, 'r:gz') as archive:
            archived = {}
            for member in archive.getmembers():
                if member.isfile():
                    extracted = archive.extractfile(member)
                    archived[os.path.basename(member.name)] = extracted.read().decode()
        assert archived == {'alpha.log': alpha_expected, 'gamma.log': gamma_expected}, (
            f"Archive contents were incorrect: {archived!r}"
        )
    finally:
        if os.path.lexists(packer_path):
            os.remove(packer_path)
        if os.path.exists(real_packer):
            os.replace(real_packer, packer_path)
        with open(config_path, 'wb') as f:
            f.write(original_config)
        if os.path.lexists(staging_path):
            if os.path.isdir(staging_path) and not os.path.islink(staging_path):
                shutil.rmtree(staging_path)
            else:
                os.remove(staging_path)
        if had_staging and os.path.lexists(saved_staging):
            os.replace(saved_staging, staging_path)
        if os.path.lexists(file_path):
            os.remove(file_path)
        if had_archive and os.path.lexists(saved_archive):
            os.replace(saved_archive, file_path)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
