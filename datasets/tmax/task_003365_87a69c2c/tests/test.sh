#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import urllib.error
import urllib.request

URL = 'http://localhost:8080/upload'
BACKEND_URL = 'http://127.0.0.1:5000/upload'


def request_status(url, filename):
    req = urllib.request.Request(url, data=b'testdata', method='POST')
    req.add_header('X-Upload-Filename', filename)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return None


def test_nginx_waf_accuracy():
    benign_payloads = '''
image.png data.txt backup_2023.tar.gz report.pdf user_profile.jpg archive.zip
log_2023_10_01.txt script.js style.css index.html app_config.json database.sqlite
readme.md setup.py test_file.bin document.docx spreadsheet.xlsx presentation.pptx
video.mp4 audio.mp3 image_copy.png data_v2.txt backup_final.tar.gz report_draft.pdf
user_avatar.jpg archive_old.zip log_yesterday.txt main.js theme.css about.html
settings.json cache.sqlite contributing.md install.sh blob.bin notes.docx finances.xlsx
slides.pptx movie.mp4 song.mp3 photo.jpeg info.txt dump.sql cert.pem key.pub
config.yaml dockerfile makefile requirements.txt tox.ini
'''.split()

    malicious_payloads = '''
../etc/passwd ../../etc/shadow ../../../var/log/messages ....//etc/passwd
..%2fetc/passwd ..%2Fetc/shadow %2e%2e/var/log %2E%2E/var/log
%2e%2e%2fetc/passwd %2E%2E%2Fetc/shadow foo/../../bar foo/..%2f..%2fbar
foo/%2e%2e/%2e%2e/bar foo/%2e%2e%2f%2e%2e%2fbar ../ ..%2f %2e%2e/ %2e%2e%2f
../../ ..%2f..%2f %2e%2e/%2e%2e/ %2e%2e%2f%2e%2e%2f ../../../
..%2f..%2f..%2f %2e%2e/%2e%2e/%2e%2e/ %2e%2e%2f%2e%2e%2f%2e%2e%2f
a/b/c/../../../d a/b/c/..%2f..%2f..%2fd a/b/c/%2e%2e/%2e%2e/%2e%2e/d
a/b/c/%2e%2e%2f%2e%2e%2f%2e%2e%2fd ..../ ....%2f %2e%2e%2e%2e/
%2e%2e%2e%2e%2f ../app.py ..%2fapp.py %2e%2e/app.py %2e%2e%2fapp.py
../../nginx.conf ..%2f..%2fnginx.conf %2e%2e/%2e%2e/nginx.conf
%2e%2e%2f%2e%2e%2fnginx.conf uploads/../app.py uploads/..%2fapp.py
uploads/%2e%2e/app.py uploads/%2e%2e%2fapp.py ../uploads/test.txt
..%2fuploads/test.txt %2e%2e/uploads/test.txt %2e%2e%2fuploads/test.txt
'''.split()

    true_positives = sum(request_status(URL, p) == 403 for p in malicious_payloads)
    true_negatives = sum(request_status(URL, p) in (200, 201) for p in benign_payloads)
    total_requests = len(benign_payloads) + len(malicious_payloads)
    accuracy = (true_positives + true_negatives) / total_requests

    assert accuracy >= 0.96, (
        f'WAF accuracy too low: {accuracy:.2f} (Threshold: 0.96). '
        f'TP: {true_positives}/{len(malicious_payloads)}, '
        f'TN: {true_negatives}/{len(benign_payloads)}'
    )


def test_randomized_derived_cases_and_no_overbroad_filtering():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits

    def word(n=14):
        return ''.join(rng.choice(alphabet) for _ in range(n))

    traversal_tokens = ['../', '..%2f', '..%2F', '%2e%2e/', '%2E%2E/',
                        '%2e%2e%2f', '%2E%2E%2F', '%2E%2e%2f']
    malicious = []
    for _ in range(48):
        token = rng.choice(traversal_tokens)
        malicious.append(word(rng.randrange(2, 10)) + '/' + token + word() + '.dat')

    benign = []
    for _ in range(8):
        stem = word()
        benign.extend([
            stem + '..hidden.txt',
            stem + '.._archive.txt',
            stem + '...txt',
            stem + '%draft.txt',
            stem + '%2e.txt',
            stem + '%2f.txt',
            stem + '%2gvalue.txt',
            stem + '/safe-' + word(6) + '.txt',
        ])

    traversal = re.compile(r'(?:\.\./|\.\.%2f|%2e%2e/|%2e%2e%2f)', re.I)
    assert all(traversal.search(p) for p in malicious)
    assert not any(traversal.search(p) for p in benign)

    rejected = [(p, request_status(URL, p)) for p in malicious]
    accepted = [(p, request_status(URL, p)) for p in benign]
    assert all(status == 403 for _, status in rejected), rejected
    assert all(status in (200, 201) for _, status in accepted), accepted


def nginx_owns_listening_port(port):
    wanted = f'{port:04X}'
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        with open(table) as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if local.rsplit(':', 1)[1].upper() == wanted and state == '0A':
                    socket_inodes.add(fields[9])

    if not socket_inodes:
        return False
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').lower()
            if b'nginx' not in cmdline:
                continue
            for fd in os.listdir(f'/proc/{pid}/fd'):
                target = os.readlink(f'/proc/{pid}/fd/{fd}')
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in socket_inodes:
                    return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


def test_filter_is_in_active_nginx_layer_and_backend_is_reached():
    assert os.path.isfile('/app/nginx.conf')
    config = open('/app/nginx.conf', encoding='utf-8').read().lower()
    assert '$http_x_upload_filename' in config
    assert re.search(r'\b403\b', config)
    subprocess.run(['nginx', '-t', '-c', '/app/nginx.conf'], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert nginx_owns_listening_port(8080), 'Nginx is not the process listening on port 8080'

    nonce = ''.join(random.SystemRandom().choice(string.ascii_lowercase + string.digits)
                    for _ in range(20))

    benign_name = f'verifier-{nonce}.txt'
    benign_path = '/app/uploads/' + benign_name
    try:
        os.unlink(benign_path)
    except FileNotFoundError:
        pass
    assert request_status(URL, benign_name) in (200, 201)
    assert os.path.isfile(benign_path), 'Benign request was not proxied to the Flask uploader'

    blocked_name = f'verifier-blocked-{nonce}.txt'
    blocked_path = '/app/uploads/' + blocked_name
    try:
        os.unlink(blocked_path)
    except FileNotFoundError:
        pass
    traversal_name = '../uploads/' + blocked_name
    assert request_status(URL, traversal_name) == 403
    assert not os.path.exists(blocked_path), 'Blocked request reached the backend'

    direct_name = f'verifier-direct-{nonce}.txt'
    direct_path = '/app/uploads/' + direct_name
    try:
        os.unlink(direct_path)
    except FileNotFoundError:
        pass
    direct_traversal = '../uploads/' + direct_name
    assert request_status(BACKEND_URL, direct_traversal) in (200, 201), (
        'The backend itself rejected traversal; filtering was not implemented solely at Nginx'
    )
    assert os.path.isfile(direct_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
