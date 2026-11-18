#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_GXX=/usr/bin/g++.verifier-real
ORIG_GXX=/usr/bin/g++

cleanup() {
    if [ -e "$REAL_GXX" ] || [ -L "$REAL_GXX" ]; then
        rm -f "$ORIG_GXX"
        mv "$REAL_GXX" "$ORIG_GXX"
    fi
}
trap cleanup EXIT

mv "$ORIG_GXX" "$REAL_GXX"
cat > "$ORIG_GXX" <<'GXX_EOF'
#!/bin/bash
real_gxx=/usr/bin/g++.verifier-real
printf 'PWD=%s ARGS=' "$PWD" >> /tmp/verifier-gxx.log
printf '%q ' "$@" >> /tmp/verifier-gxx.log
printf '\n' >> /tmp/verifier-gxx.log

out=''
need_out=0
for arg in "$@"; do
    if [ "$need_out" -eq 1 ]; then
        out="$arg"
        need_out=0
        continue
    fi
    case "$arg" in
        -o) need_out=1 ;;
        -o*) out="${arg#-o}" ;;
    esac
done

"$real_gxx" "$@"
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

if [ -n "$out" ]; then
    abs_out=$(readlink -m "$out")
    if [ "$abs_out" = /home/user/quota_analyzer ]; then
        real_out="${abs_out}.verifier-real"
        mv -f "$abs_out" "$real_out"
        {
            echo '#!/bin/bash'
            echo 'echo invoked >> /tmp/verifier-analyzer-invoked'
            printf 'tee /tmp/verifier-analyzer-stdin | %q\n' "$real_out"
            echo 'rc=${PIPESTATUS[1]}'
            echo 'exit "$rc"'
        } > "$abs_out"
        chmod +x "$abs_out"
    fi
fi
GXX_EOF
chmod +x "$ORIG_GXX"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

CPP = Path('/home/user/quota_analyzer.cpp')
SCRIPT = Path('/home/user/deploy_check.sh')
REPORT = Path('/home/user/quota_report.txt')
DIRS = Path('/home/user/update_dirs.txt')
LOG = Path('/home/user/deployment_status.log')
EXE = Path('/home/user/quota_analyzer')


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_source_files_exist():
    cpp_file = '/home/user/quota_analyzer.cpp'
    sh_file = '/home/user/deploy_check.sh'

    assert os.path.isfile(cpp_file), f'Missing C++ source file: {cpp_file}'
    assert os.path.isfile(sh_file), f'Missing Bash script file: {sh_file}'


def test_deployment_status_log_content():
    log_file = '/home/user/deployment_status.log'
    assert os.path.isfile(log_file), f'Log file not found at {log_file}. Did the script run successfully?'

    lines = read_nonempty_lines(log_file)
    expected_lines = [
        '[EXCEEDS] /opt/app/backend requires 150 MB more quota',
        '[EXCEEDS] /opt/app/cache requires 200 MB more quota',
        '[OK] /opt/app/frontend requires 0 MB more quota',
        '[EXCEEDS] /opt/app/logs requires 50 MB more quota',
    ]

    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in log, but got {len(lines)}.'
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: '{expected}'\nActual:   '{actual}'"


def test_executable_exists():
    exe_file = '/home/user/quota_analyzer'
    assert os.path.isfile(exe_file), f'Compiled executable not found at {exe_file}. Ensure the bash script compiles the C++ program.'
    assert os.access(exe_file, os.X_OK), f'The file at {exe_file} is not executable.'


def expected_lines(records, targets):
    result = []
    for directory in sorted(targets):
        used, quota = records[directory]
        shortfall = max(0, used + 350 - quota)
        status = 'EXCEEDS' if shortfall else 'OK'
        result.append(f'[{status}] {directory} requires {shortfall} MB more quota')
    return result


def run_dynamic_case(case_number):
    token = secrets.token_hex(6)
    targets = [
        f'/srv/{token}/zeta',
        f'/srv/{token}/alpha',
        f'/srv/{token}/middle',
        f'/srv/{token}/equal',
    ]
    base = 700 + case_number * 137
    records = {
        targets[0]: (base + 50, base + 300),
        targets[1]: (base + 900, base + 1600),
        targets[2]: (base + 2400, base + 2501),
        targets[3]: (base + 100, base + 450),
    }
    decoy = f'/srv/{token}/not-updated'

    report_lines = [
        'RANDOM STORAGE REPORT',
        'this line must be ignored',
        f'DIR {targets[2]} USAGE {records[targets[2]][0]} QUOTA {records[targets[2]][1]}',
        f'DIR {decoy} USAGE 99999 QUOTA 1',
        f'DIR {targets[0]} USAGE {records[targets[0]][0]} QUOTA {records[targets[0]][1]}',
        '----------------',
        f'DIR {targets[3]} USAGE {records[targets[3]][0]} QUOTA {records[targets[3]][1]}',
        f'DIR {targets[1]} USAGE {records[targets[1]][0]} QUOTA {records[targets[1]][1]}',
    ]
    REPORT.write_text('\n'.join(report_lines) + '\n')
    DIRS.write_text('\n'.join(reversed(targets)) + '\n')

    for path in (LOG, EXE, Path('/home/user/quota_analyzer.verifier-real'),
                 Path('/tmp/verifier-gxx.log'), Path('/tmp/verifier-analyzer-invoked'),
                 Path('/tmp/verifier-analyzer-stdin')):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    proc = subprocess.run(
        ['/bin/bash', str(SCRIPT)], text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f'deploy_check.sh failed:\nstdout={proc.stdout}\nstderr={proc.stderr}'
    assert LOG.is_file(), 'The script did not generate deployment_status.log'
    assert read_nonempty_lines(LOG) == expected_lines(records, targets)

    compile_log = Path('/tmp/verifier-gxx.log')
    assert compile_log.is_file(), 'deploy_check.sh did not invoke g++'
    invocation = compile_log.read_text()
    assert 'quota_analyzer.cpp' in invocation, 'g++ was not invoked on quota_analyzer.cpp'
    assert re.search(r'(^|[ /])-o(?: |[^ ]*)', invocation), 'g++ invocation did not specify an output executable'
    assert 'quota_analyzer' in invocation, 'g++ did not produce the required quota_analyzer output'

    assert Path('/tmp/verifier-analyzer-invoked').is_file(), 'The compiled analyzer was not executed by deploy_check.sh'
    assert Path('/tmp/verifier-analyzer-stdin').stat().st_size > 0, 'The analyzer received no piped input'
    real_binary = Path('/home/user/quota_analyzer.verifier-real')
    assert real_binary.is_file() and os.access(real_binary, os.X_OK), 'Compilation did not produce an executable binary'


def test_script_compiles_filters_pipes_and_handles_errors():
    script_text = SCRIPT.read_text()
    assert re.search(r'\b(grep|awk|sed)\b', script_text), 'The Bash script does not use the required text-processing tools'

    original_cpp = CPP.read_bytes()
    try:
        run_dynamic_case(1)
        run_dynamic_case(2)

        CPP.write_text('this is deliberately invalid C++\n')
        for path in (EXE, Path('/home/user/quota_analyzer.verifier-real')):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        failed = subprocess.run(
            ['/bin/bash', str(SCRIPT)], text=True, capture_output=True, timeout=30
        )
        assert failed.returncode != 0, 'deploy_check.sh reported success even though C++ compilation failed'
    finally:
        CPP.write_bytes(original_cpp)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    result=1
else
    result=0
fi

cleanup
trap - EXIT
echo "$result" > /logs/verifier/reward.txt
