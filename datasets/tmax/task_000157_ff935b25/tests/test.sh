#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pathlib
import secrets
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

SRC = pathlib.Path('/home/user/workspace/src')
BIN = pathlib.Path('/home/user/workspace/bin/fm_tool')
DETECTOR = pathlib.Path('/home/user/detector.sh')


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def post(data):
    req = urllib.request.Request('http://localhost:8080/validate', data=data, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def test_libraries_compile_link_and_tool_runs():
    result = run(['make', '-B'], cwd=SRC)
    assert result.returncode == 0, result.stdout + result.stderr

    ecc = SRC / 'libecc.so'
    frame = SRC / 'libframemeta.so'
    assert ecc.is_file(), 'libecc.so was not built'
    assert frame.is_file(), 'libframemeta.so was not built'
    assert BIN.is_file() and os.access(BIN, os.X_OK), 'fm_tool was not built as an executable'

    for artifact in (ecc, frame, BIN):
        info = run(['file', str(artifact)])
        assert info.returncode == 0 and 'ELF' in info.stdout, f'{artifact} is not an ELF artifact: {info.stdout}'

    dynamic = run(['readelf', '-d', str(frame)])
    assert dynamic.returncode == 0, dynamic.stderr
    assert 'libecc.so' in dynamic.stdout, 'libframemeta.so is not dynamically linked against libecc.so'

    tool_dynamic = run(['readelf', '-d', str(BIN)])
    assert tool_dynamic.returncode == 0, tool_dynamic.stderr
    assert 'libframemeta.so' in tool_dynamic.stdout, 'fm_tool is not dynamically linked against libframemeta.so'

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(SRC) + ':' + env.get('LD_LIBRARY_PATH', '')
    probe = run([str(BIN), '/home/user/corpora/clean/file_1.bin'], env=env)
    assert probe.returncode >= 0, 'fm_tool could not be executed'
    assert 'error while loading shared libraries' not in probe.stderr.lower(), probe.stderr


def test_extractor_memory_safety_with_maximum_header():
    harness = pathlib.Path('/tmp/extractor_harness.c')
    harness.write_text(r'''#include <string.h>
struct Data { char header[256]; };
void extract(struct Data *input);
int main(void) {
    struct Data d;
    memset(d.header, 'A', sizeof(d.header));
    d.header[sizeof(d.header)-1] = '\0';
    extract(&d);
    memset(d.header, 'B', 127);
    d.header[127] = '\0';
    extract(&d);
    return 0;
}
''')
    exe = '/tmp/extractor_asan'
    build = run([
        'gcc', '-g', '-O1', '-fno-omit-frame-pointer', '-fsanitize=address',
        str(SRC / 'extractor.c'), str(SRC / 'ecc.c'), str(harness), '-o', exe
    ])
    assert build.returncode == 0, build.stdout + build.stderr
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
    checked = run([exe], env=env)
    assert checked.returncode == 0, checked.stdout + checked.stderr
    assert 'AddressSanitizer' not in checked.stderr, checked.stderr


def test_frame42_checksum():
    checksum_file = '/home/user/frame42_checksum.txt'
    assert os.path.isfile(checksum_file), f'Checksum file {checksum_file} is missing.'
    with open(checksum_file, 'r') as f:
        content = f.read().strip()
    assert '0x4F8A2B9C' in content, f"Expected checksum '0x4F8A2B9C' not found in {checksum_file}. Content: {content}"


def test_extraction_script_executes_ffmpeg_and_fm_tool_for_frame_42():
    script = pathlib.Path('/home/user/extract_reference.sh')
    checksum = pathlib.Path('/home/user/frame42_checksum.txt')
    assert script.is_file() and os.access(script, os.X_OK), 'extract_reference.sh is missing or not executable'

    original_checksum = checksum.read_bytes() if checksum.exists() else None
    original_mode = stat.S_IMODE(BIN.stat().st_mode)
    real_tool = BIN.with_name('fm_tool.verifier-real')
    token = '0x' + secrets.token_hex(4).upper()
    os.replace(BIN, real_tool)
    BIN.write_text(f'''#!/bin/bash
printf '%s\\n' '{token}'
''')
    os.chmod(BIN, 0o755)
    try:
        if checksum.exists():
            checksum.unlink()
        result = run(['bash', '-x', str(script)], timeout=30)
        trace = result.stdout + result.stderr
        assert result.returncode == 0, trace
        assert checksum.is_file(), 'extract_reference.sh did not create frame42_checksum.txt'
        assert token in checksum.read_text(), 'the checksum output did not come from the invoked fm_tool'
        assert '/app/reference_video.mp4' in trace, 'the extraction did not use the required reference video'
        ffmpeg_lines = [line for line in trace.splitlines() if 'ffmpeg' in line]
        assert ffmpeg_lines, 'extract_reference.sh did not execute ffmpeg'
        invocation = ' '.join(ffmpeg_lines)
        assert ('select' in invocation and ('41' in invocation or '42' in invocation)), \
            f'ffmpeg invocation does not select frame 42: {invocation}'
        assert ('-frames:v 1' in invocation or '-vframes 1' in invocation or '-frames 1' in invocation), \
            f'ffmpeg invocation does not limit extraction to exactly one frame: {invocation}'
        assert 'fm_tool' in trace, 'extract_reference.sh did not execute fm_tool'
    finally:
        if BIN.exists():
            BIN.unlink()
        os.replace(real_tool, BIN)
        os.chmod(BIN, original_mode)
        if original_checksum is None:
            checksum.unlink(missing_ok=True)
        else:
            checksum.write_bytes(original_checksum)


def test_detector_clean_corpus():
    detector_script = '/home/user/detector.sh'
    assert os.path.isfile(detector_script), f'Detector script {detector_script} is missing.'
    assert os.access(detector_script, os.X_OK), f'Detector script {detector_script} is not executable.'
    clean_files = glob.glob('/home/user/corpora/clean/*')
    assert len(clean_files) > 0, 'Clean corpus is empty.'
    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([detector_script, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))
    assert len(failed_files) == 0, f'{len(failed_files)} of {len(clean_files)} clean modified/rejected by detector.sh. Offending files: {failed_files}'


def test_detector_evil_corpus():
    detector_script = '/home/user/detector.sh'
    assert os.path.isfile(detector_script), f'Detector script {detector_script} is missing.'
    assert os.access(detector_script, os.X_OK), f'Detector script {detector_script} is not executable.'
    evil_files = glob.glob('/home/user/corpora/evil/*')
    assert len(evil_files) > 0, 'Evil corpus is empty.'
    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([detector_script, filepath], capture_output=True)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(filepath))
    assert len(bypassed_files) == 0, f'{len(bypassed_files)} of {len(evil_files)} evil bypassed detector.sh. Offending files: {bypassed_files}'


def test_detector_uses_fm_tool_and_handles_unseen_inputs():
    log = pathlib.Path('/tmp/fm_tool_calls')
    log.unlink(missing_ok=True)
    real_tool = BIN.with_name('fm_tool.verifier-real')
    original_mode = stat.S_IMODE(BIN.stat().st_mode)
    os.replace(BIN, real_tool)
    BIN.write_text(f'''#!/bin/bash
printf '%s\\n' "$1" >> {log}
exec {real_tool} "$@"
''')
    os.chmod(BIN, 0o755)
    files = []
    try:
        for kind, expected in [('clean', 0), ('evil', 1)]:
            for _ in range(5):
                fd, path = tempfile.mkstemp(prefix='payload_', suffix='.bin')
                os.close(fd)
                pathlib.Path(path).write_bytes(f'{kind} data {secrets.token_hex(16)}\n'.encode())
                files.append(path)
                result = subprocess.run([str(DETECTOR), path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if expected == 0:
                    assert result.returncode == 0, f'unseen clean payload was rejected: {result.stderr!r}'
                else:
                    assert result.returncode != 0, 'unseen malicious payload was accepted'
        calls = log.read_text().splitlines() if log.exists() else []
        for path in files:
            assert path in calls, f'detector.sh did not pass {path} through fm_tool'
    finally:
        if BIN.exists():
            BIN.unlink()
        os.replace(real_tool, BIN)
        os.chmod(BIN, original_mode)
        for path in files:
            pathlib.Path(path).unlink(missing_ok=True)


def test_proxy_clean_corpus():
    clean_files = glob.glob('/home/user/corpora/clean/*')
    assert len(clean_files) > 0, 'Clean corpus is empty.'
    failed_files = []
    for filepath in clean_files:
        with open(filepath, 'rb') as f:
            data = f.read()
        try:
            status = post(data)
            if status != 200:
                failed_files.append(os.path.basename(filepath))
        except Exception:
            failed_files.append(os.path.basename(filepath))
    assert len(failed_files) == 0, f'{len(failed_files)} of {len(clean_files)} clean modified/rejected by proxy. Offending files: {failed_files}'


def test_proxy_evil_corpus():
    evil_files = glob.glob('/home/user/corpora/evil/*')
    assert len(evil_files) > 0, 'Evil corpus is empty.'
    bypassed_files = []
    for filepath in evil_files:
        with open(filepath, 'rb') as f:
            data = f.read()
        try:
            status = post(data)
            if status != 400:
                bypassed_files.append(os.path.basename(filepath))
        except Exception:
            bypassed_files.append(os.path.basename(filepath))
    assert len(bypassed_files) == 0, f'{len(bypassed_files)} of {len(evil_files)} evil bypassed proxy. Offending files: {bypassed_files}'


def test_nginx_and_bash_server_are_running():
    nginx = run(['pgrep', '-x', 'nginx'])
    assert nginx.returncode == 0, 'Nginx is not running'
    server = run(['pgrep', '-f', '/home/user/server.sh'])
    assert server.returncode == 0, 'the Bash server is not running'


def test_proxy_really_delegates_opaque_payloads_to_detector():
    original = DETECTOR.read_bytes()
    mode = stat.S_IMODE(DETECTOR.stat().st_mode)
    clean_file = pathlib.Path('/tmp/verifier_opaque_clean')
    evil_file = pathlib.Path('/tmp/verifier_opaque_evil')
    log = pathlib.Path('/tmp/verifier_detector_calls')
    log.unlink(missing_ok=True)
    clean_data = secrets.token_bytes(73)
    evil_data = secrets.token_bytes(91)
    clean_file.write_bytes(clean_data)
    evil_file.write_bytes(evil_data)
    replacement = f'''#!/bin/bash
printf '%s\\n' "$1" >> {log}
if cmp -s "$1" {clean_file}; then exit 0; fi
if cmp -s "$1" {evil_file}; then exit 7; fi
exit 9
'''
    try:
        DETECTOR.write_text(replacement)
        os.chmod(DETECTOR, 0o755)
        time.sleep(0.1)
        assert post(clean_data) == 200, 'proxy did not map a detector success to HTTP 200'
        assert post(evil_data) == 400, 'proxy did not map a detector rejection to HTTP 400'
        calls = log.read_text().splitlines() if log.exists() else []
        assert len(calls) >= 2, 'the backend did not invoke detector.sh for both opaque requests'
    finally:
        DETECTOR.write_bytes(original)
        os.chmod(DETECTOR, mode)
        clean_file.unlink(missing_ok=True)
        evil_file.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
