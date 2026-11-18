#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path
from zoneinfo import ZoneInfo

BASE = Path('/home/user/log_processor')
FIXED = BASE / 'process_logs_fixed.sh'
TEST_SH = BASE / 'test.sh'
VERIFICATION = BASE / 'verification.log'
LOGS = BASE / 'logs'
OUT = BASE / 'out'


def run(cmd, timeout=120):
    return subprocess.run(cmd, capture_output=True, timeout=timeout)


def assert_success(result, description):
    assert result.returncode == 0, (
        f'{description} failed with return code {result.returncode}.\n'
        f'Stdout: {result.stdout.decode(errors="replace")}\n'
        f'Stderr: {result.stderr.decode(errors="replace")}'
    )


def reset_dir(path):
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def main():
    backup_root = Path(tempfile.mkdtemp(prefix='log-verifier-backup-'))
    logs_backup = backup_root / 'logs'
    out_backup = backup_root / 'out'
    if LOGS.exists():
        shutil.copytree(LOGS, logs_backup)
    if OUT.exists():
        shutil.copytree(OUT, out_backup)

    fixed_data = FIXED.read_bytes() if FIXED.is_file() else None
    fixed_mode = stat.S_IMODE(FIXED.stat().st_mode) if FIXED.is_file() else None
    verification_data = VERIFICATION.read_bytes() if VERIFICATION.is_file() else None
    verification_mode = stat.S_IMODE(VERIFICATION.stat().st_mode) if VERIFICATION.is_file() else None
    hidden_original = BASE / '.verifier_original_process_logs_fixed.sh'

    try:
        # Preserve the original verification.log assertions.
        assert VERIFICATION.is_file(), f'File {VERIFICATION} is missing.'
        expected_lines = [
            '1696161000 Message 1 from Asia',
            '1696161300 Message 1 from EU',
            '1696161600 Message 1 from US',
            '1696161720 Message 2 from EU',
            '1696161900 Message 2 from US',
            '1696162200 Message 2 from Asia',
        ]
        content = VERIFICATION.read_bytes()
        assert b'\x00' not in content, 'Null bytes were not stripped from the final log.'
        lines = content.decode('utf-8').strip().split('\n')
        assert len(lines) == len(expected_lines), (
            f'Expected {len(expected_lines)} lines, but got {len(lines)}.'
        )
        for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
            assert actual.strip() == expected, (
                f"Line {i + 1} mismatch. Expected: '{expected}', Got: '{actual.strip()}'"
            )

        # Preserve the original artifact and regression-test assertions.
        assert FIXED.is_file(), f'File {FIXED} is missing.'
        assert os.access(FIXED, os.X_OK), f'File {FIXED} is not executable.'
        assert TEST_SH.is_file(), f'File {TEST_SH} is missing.'
        st = TEST_SH.stat()
        assert bool(st.st_mode & stat.S_IXUSR), f'File {TEST_SH} is not executable.'

        normal_test = run([str(TEST_SH)])
        assert_success(normal_test, 'test.sh')

        # Restore the submitted processor in case the regression test changed it.
        FIXED.write_bytes(fixed_data)
        os.chmod(FIXED, fixed_mode)

        # Run test.sh again through an instrumented wrapper. This confirms that it
        # actually creates substantial concurrent fixtures covering every timezone
        # and null-byte corruption, and that it invokes the submitted fixed script.
        reset_dir(LOGS)
        reset_dir(OUT)
        marker = Path('/tmp') / ('regression-called-' + secrets.token_hex(12))
        inspector = Path('/tmp') / ('inspect-regression-' + secrets.token_hex(12) + '.py')
        inspector.write_text(r'''from pathlib import Path
root = Path('/home/user/log_processor/logs')
files = list(root.glob('*.log'))
regions = {p.name.split('_', 1)[0] for p in files}
data = [p.read_bytes() for p in files]
line_count = sum(len(x.splitlines()) for x in data)
assert {'us-east', 'eu-west', 'asia'} <= regions, 'missing timezone fixtures'
assert any(b'\x00' in x for x in data), 'missing null-byte fixture'
assert len(files) >= 3, 'insufficient files for concurrent processing'
assert line_count >= 200, 'insufficient volume for race regression test'
''')
        if hidden_original.exists():
            hidden_original.unlink()
        FIXED.rename(hidden_original)
        wrapper = f'''#!/bin/bash
python3 {str(inspector)!r} || exit 97
touch {str(marker)!r}
mv {str(hidden_original)!r} {str(FIXED)!r}
chmod {fixed_mode:o} {str(FIXED)!r}
exec {str(FIXED)!r} "$@"
'''
        FIXED.write_text(wrapper)
        os.chmod(FIXED, 0o755)
        covered_test = run([str(TEST_SH)])
        assert_success(covered_test, 'instrumented test.sh')
        assert marker.is_file(), 'test.sh did not invoke process_logs_fixed.sh.'
        assert FIXED.is_file(), 'test.sh did not complete the instrumented processor invocation.'
        FIXED.write_bytes(fixed_data)
        os.chmod(FIXED, fixed_mode)
        inspector.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)

        # Ensure test.sh detects a processor that produces no output rather than
        # being an unconditional executable that exits successfully.
        reset_dir(LOGS)
        reset_dir(OUT)
        VERIFICATION.unlink(missing_ok=True)
        FIXED.write_text('#!/bin/bash\nexit 0\n')
        os.chmod(FIXED, 0o755)
        broken_test = run([str(TEST_SH)])
        assert broken_test.returncode != 0, (
            'test.sh still succeeds when process_logs_fixed.sh produces no final.log.'
        )
        FIXED.write_bytes(fixed_data)
        os.chmod(FIXED, fixed_mode)

        # Independently exercise the submitted processor on unpredictable,
        # high-volume inputs. Expected epochs are derived by Python's zoneinfo.
        reset_dir(LOGS)
        reset_dir(OUT)
        zones = {
            'us-east': ZoneInfo('America/New_York'),
            'eu-west': ZoneInfo('Europe/London'),
            'asia': ZoneInfo('Asia/Tokyo'),
        }
        prefixes = list(zones)
        file_data = {(p, n): bytearray() for p in prefixes for n in range(4)}
        expected = []
        nonce = secrets.token_hex(8)
        total = 1440
        winter = datetime.datetime(2024, 1, 15, 0, 0, tzinfo=datetime.timezone.utc)
        summer = datetime.datetime(2024, 7, 15, 0, 0, tzinfo=datetime.timezone.utc)

        for i in range(total):
            prefix = prefixes[i % len(prefixes)]
            file_number = (i // len(prefixes)) % 4
            half_index = i if i < total // 2 else i - total // 2
            utc_dt = (winter if i < total // 2 else summer) + datetime.timedelta(seconds=half_index * 67)
            local_text = utc_dt.astimezone(zones[prefix]).strftime('%Y-%m-%d %H:%M:%S')
            message = f'{nonce}-{prefix}-entry-{i:04d}'
            raw = f'{local_text} {message}\n'.encode()
            if i % 5 == 0:
                raw = raw.replace(b' entry-not-present', b' entry-not-present')
                split = raw.find(b' ') + 1
                raw = raw[:split] + b'\x00' + raw[split:]
            elif i % 5 == 1:
                pos = raw.find(message.encode()) + len(message) // 2
                raw = raw[:pos] + b'\x00' + raw[pos:]
            elif i % 5 == 2:
                raw = b'\x00' + raw
            file_data[(prefix, file_number)].extend(raw)
            expected.append(f'{int(utc_dt.timestamp())} {message}')

        for (prefix, number), data in file_data.items():
            (LOGS / f'{prefix}_{number}_{nonce}.log').write_bytes(bytes(data))

        result = run([str(FIXED)], timeout=180)
        assert_success(result, 'process_logs_fixed.sh on generated logs')
        final_log = OUT / 'final.log'
        assert final_log.is_file(), 'process_logs_fixed.sh did not create out/final.log.'
        final_content = final_log.read_bytes()
        assert b'\x00' not in final_content, 'Generated output still contains null bytes.'
        actual = final_content.decode('utf-8').splitlines()
        expected.sort(key=lambda line: int(line.split(' ', 1)[0]))
        assert len(actual) == total, f'Expected {total} generated lines, got {len(actual)}.'
        assert actual == expected, 'Generated output has incorrect epochs, ordering, messages, or data loss.'
        epochs = [int(line.split(' ', 1)[0]) for line in actual]
        assert epochs == sorted(epochs), 'Generated final.log is not numerically sorted by epoch.'

    finally:
        if hidden_original.exists():
            hidden_original.unlink()
        if fixed_data is not None:
            FIXED.write_bytes(fixed_data)
            os.chmod(FIXED, fixed_mode)
        if verification_data is not None:
            VERIFICATION.write_bytes(verification_data)
            os.chmod(VERIFICATION, verification_mode)
        elif VERIFICATION.exists():
            VERIFICATION.unlink()
        if LOGS.exists():
            shutil.rmtree(LOGS)
        if logs_backup.exists():
            shutil.copytree(logs_backup, LOGS)
        else:
            LOGS.mkdir(parents=True)
        if OUT.exists():
            shutil.rmtree(OUT)
        if out_backup.exists():
            shutil.copytree(out_backup, OUT)
        else:
            OUT.mkdir(parents=True)
        shutil.rmtree(backup_root, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
