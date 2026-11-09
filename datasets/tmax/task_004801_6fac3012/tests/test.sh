#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path
from zoneinfo import ZoneInfo

HOME = Path('/home/user')
RAW = HOME / 'raw_fs.txt'
SOURCE = HOME / 'agent.cpp'
DEPLOY = HOME / 'deploy.sh'
LOG = HOME / 'observability.log'
BLUE = HOME / 'deploy_blue' / 'agent_bin'
GREEN = HOME / 'deploy_green' / 'agent_bin'
EXPECTED_RAW = '1672531200 /var/log 5048392'
EXPECTED_LINES = [
    'Connectivity OK',
    '[2023/01/01 09:00:00] Mount: /var/log | Free: 5048392 bytes | Env: tuning_stage',
]


def run(cmd, **kwargs):
    kwargs.setdefault('timeout', 30)
    kwargs.setdefault('check', True)
    return subprocess.run(cmd, **kwargs)


def assert_original_state():
    assert RAW.exists(), f'File {RAW} does not exist.'
    assert RAW.read_text().strip() == EXPECTED_RAW, f'Content of {RAW} is incorrect.'

    for binary in (BLUE, GREEN):
        assert binary.exists(), f'Binary {binary} does not exist.'
        assert os.access(binary, os.X_OK), f'Binary {binary} is not executable.'

    assert LOG.exists(), f'Log file {LOG} does not exist.'
    lines = [line.strip() for line in LOG.read_text().strip().splitlines()]
    assert len(lines) == 2, f'Expected 2 lines in {LOG}, found {len(lines)}.'
    assert lines[0] == EXPECTED_LINES[0], f'First line of {LOG} is incorrect.'
    assert lines[1] == EXPECTED_LINES[1], f'Second line of {LOG} is incorrect.'


def expected_metric(timestamp, mount, byte_count, env_value, timezone):
    formatted = datetime.datetime.fromtimestamp(
        timestamp, ZoneInfo(timezone)
    ).strftime('%Y/%m/%d %H:%M:%S')
    return f'[{formatted}] Mount: {mount} | Free: {byte_count} bytes | Env: {env_value}'


def exercise_binary(binary, timezone):
    token = secrets.token_hex(8)
    timestamp = 1000000000 + secrets.randbelow(700000000)
    mount = f'/mnt/fs_{token}'
    byte_count = 1000 + secrets.randbelow(900000000)
    env_value = f'env_{token}'
    RAW.write_text(f'{timestamp} {mount} {byte_count}\n')
    LOG.write_text('existing-entry\n')

    env = os.environ.copy()
    env.update({'TZ': timezone, 'LC_ALL': 'C', 'METRICS_ENV': env_value})
    run([str(binary)], env=env, cwd=str(HOME))

    expected = expected_metric(timestamp, mount, byte_count, env_value, timezone)
    assert LOG.read_text().splitlines() == ['existing-entry', expected], (
        f'{binary} did not read the supplied metrics/environment, respect TZ, '
        'or append exactly one correctly formatted line.'
    )


def remove_deployment_outputs():
    shutil.rmtree(HOME / 'deploy_blue', ignore_errors=True)
    shutil.rmtree(HOME / 'deploy_green', ignore_errors=True)
    for path in (HOME / 'agent_bin', LOG):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def validate_ping_args(args):
    assert args.count('127.0.0.1') == 1, f'ping did not target 127.0.0.1: {args}'
    count = None
    for i, arg in enumerate(args):
        if arg == '-c' and i + 1 < len(args):
            count = args[i + 1]
        elif arg.startswith('-c') and len(arg) > 2:
            count = arg[2:]
    assert count == '1', f'ping was not configured for exactly one packet: {args}'


def main():
    assert SOURCE.is_file(), f'{SOURCE} is missing or is not a regular file.'
    assert DEPLOY.is_file(), f'{DEPLOY} is missing or is not a regular file.'
    assert os.access(DEPLOY, os.X_OK), f'{DEPLOY} is not executable.'

    # Preserve all assertions made by the original verifier.
    assert_original_state()

    # Exercise both submitted staged artifacts on verifier-generated inputs.
    exercise_binary(BLUE, 'UTC')
    exercise_binary(GREEN, 'America/Los_Angeles')

    # Independently compile and exercise the submitted C++ source.
    compiled = Path('/tmp/verifier_agent_from_source')
    run(['/usr/bin/g++', str(SOURCE), '-o', str(compiled)])
    assert compiled.read_bytes().startswith(b'\x7fELF'), 'agent.cpp did not produce a native executable.'
    exercise_binary(compiled, 'Asia/Tokyo')

    original_source = SOURCE.read_bytes()
    ping_path = Path(shutil.which('ping') or '/usr/bin/ping')
    ping_real = ping_path.with_name(ping_path.name + '.verifier-real')
    ping_trace = Path('/tmp/verifier_ping_trace')
    probe_trace = Path('/tmp/verifier_deploy_probe_' + secrets.token_hex(8))
    ping_replaced = False

    try:
        # Replace agent.cpp temporarily with an unpredictable probe. A correct
        # deployment must compile this source, stage it, and execute the green copy.
        probe_literal = json.dumps(str(probe_trace))
        SOURCE.write_text(f'''#include <cstdlib>\n#include <fstream>\nint main(int argc, char** argv) {{\n  std::ofstream out({probe_literal}, std::ios::app);\n  const char* tz = std::getenv("TZ");\n  const char* lc = std::getenv("LC_ALL");\n  const char* me = std::getenv("METRICS_ENV");\n  out << (argc ? argv[0] : "") << "|" << (tz ? tz : "") << "|"\n      << (lc ? lc : "") << "|" << (me ? me : "") << "\\n";\n  return out ? 0 : 2;\n}}\n''')

        # Instrument the real ping pathname while still invoking the real tool.
        ping_trace.unlink(missing_ok=True)
        if ping_real.exists():
            ping_real.unlink()
        ping_path.rename(ping_real)
        ping_path.write_text(
            '#!/bin/bash\n'
            f'printf "%s\\0" "$@" >> {json.dumps(str(ping_trace))}\n'
            f'exec {json.dumps(str(ping_real))} "$@"\n'
        )
        ping_path.chmod(0o755)
        ping_replaced = True

        RAW.write_text(EXPECTED_RAW + '\n')
        remove_deployment_outputs()
        run([str(DEPLOY)], cwd=str(HOME), env=os.environ.copy())

        assert probe_trace.exists(), 'The binary built from agent.cpp was not executed.'
        probe_lines = probe_trace.read_text().splitlines()
        assert probe_lines == [
            '/home/user/deploy_green/agent_bin|Asia/Tokyo|C|tuning_stage'
        ], 'deploy.sh did not execute the green binary exactly once with the required environment.'

        assert ping_trace.exists(), 'deploy.sh did not execute ping.'
        ping_items = ping_trace.read_bytes().split(b'\0')
        ping_args = [item.decode() for item in ping_items if item]
        validate_ping_args(ping_args)

        assert LOG.read_text().splitlines() == ['Connectivity OK'], (
            'deploy.sh did not append Connectivity OK after the successful diagnostic.'
        )
        assert BLUE.is_file() and GREEN.is_file(), 'deploy.sh did not create both staged binaries.'
        assert os.access(BLUE, os.X_OK) and os.access(GREEN, os.X_OK), 'A staged binary is not executable.'
        assert BLUE.read_bytes() == GREEN.read_bytes(), 'Blue and green are not copies of the same build.'
    finally:
        SOURCE.write_bytes(original_source)
        if ping_replaced:
            try:
                ping_path.unlink()
            finally:
                ping_real.rename(ping_path)

    # Run the submitted deployment normally and re-check its required final state.
    RAW.write_text(EXPECTED_RAW + '\n')
    remove_deployment_outputs()
    run([str(DEPLOY)], cwd=str(HOME), env=os.environ.copy())
    assert_original_state()

    for binary in (BLUE, GREEN):
        assert binary.is_file(), f'{binary} is not a regular file.'
        assert binary.read_bytes().startswith(b'\x7fELF'), f'{binary} is not a compiled native executable.'
    assert BLUE.read_bytes() == GREEN.read_bytes(), 'The final blue and green binaries differ.'


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
