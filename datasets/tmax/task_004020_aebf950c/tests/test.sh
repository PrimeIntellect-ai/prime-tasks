#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /tmp/program_status /tmp/rename_audit.log

cat > /tmp/rename_audit.c <<'C_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void make_abs(int dirfd, const char *path, char *out, size_t n) {
    char base[PATH_MAX] = {0};
    if (path && path[0] == '/') {
        snprintf(out, n, "%s", path);
        return;
    }
    if (dirfd == AT_FDCWD) {
        if (!getcwd(base, sizeof(base))) snprintf(base, sizeof(base), ".");
    } else {
        char proc[64];
        snprintf(proc, sizeof(proc), "/proc/self/fd/%d", dirfd);
        ssize_t got = readlink(proc, base, sizeof(base) - 1);
        if (got < 0) snprintf(base, sizeof(base), ".");
        else base[got] = '\0';
    }
    snprintf(out, n, "%s/%s", base, path ? path : "");
}

static void record_rename(int olddirfd, const char *oldpath, int newdirfd,
                          const char *newpath, const struct stat *st) {
    char oldabs[PATH_MAX * 2], newabs[PATH_MAX * 2];
    make_abs(olddirfd, oldpath, oldabs, sizeof(oldabs));
    make_abs(newdirfd, newpath, newabs, sizeof(newabs));
    int fd = open("/tmp/rename_audit.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        dprintf(fd, "%s\t%s\t%lld\t%o\n", oldabs, newabs,
                (long long)st->st_size, (unsigned int)st->st_mode);
        close(fd);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    struct stat st;
    int have = lstat(oldpath, &st) == 0;
    int rc = real_fn(oldpath, newpath);
    if (rc == 0 && have) record_rename(AT_FDCWD, oldpath, AT_FDCWD, newpath, &st);
    return rc;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    struct stat st;
    int have = fstatat(olddirfd, oldpath, &st, AT_SYMLINK_NOFOLLOW) == 0;
    int rc = real_fn(olddirfd, oldpath, newdirfd, newpath);
    if (rc == 0 && have) record_rename(olddirfd, oldpath, newdirfd, newpath, &st);
    return rc;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd,
              const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    if (!real_fn) return -1;
    struct stat st;
    int have = fstatat(olddirfd, oldpath, &st, AT_SYMLINK_NOFOLLOW) == 0;
    int rc = real_fn(olddirfd, oldpath, newdirfd, newpath, flags);
    if (rc == 0 && have) record_rename(olddirfd, oldpath, newdirfd, newpath, &st);
    return rc;
}
C_EOF

gcc -shared -fPIC -o /tmp/librename_audit.so /tmp/rename_audit.c -ldl
compile_audit_rc=$?

rm -rf /home/user/incoming/extracted /home/user/repo
rm -f /home/user/repo_curated.tar.gz /tmp/rename_audit.log

if [ "$compile_audit_rc" -ne 0 ] || [ ! -f /home/user/curator/src/main.rs ]; then
    echo 1 > /tmp/program_status
elif [ -f /home/user/curator/Cargo.toml ]; then
    timeout 180 env LD_PRELOAD=/tmp/librename_audit.so cargo run --quiet --manifest-path /home/user/curator/Cargo.toml
    echo $? > /tmp/program_status
else
    rustc /home/user/curator/src/main.rs -o /tmp/curator_program
    build_rc=$?
    if [ "$build_rc" -eq 0 ]; then
        timeout 180 env LD_PRELOAD=/tmp/librename_audit.so /tmp/curator_program
        echo $? > /tmp/program_status
    else
        echo "$build_rc" > /tmp/program_status
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import re
import stat
import tarfile


def test_x86_64_binaries_exist():
    """Check that x86_64 binaries exist."""
    path_1_0_5 = '/home/user/repo/x86_64/server_bin-1.0.5.elf'
    path_1_2_0 = '/home/user/repo/x86_64/server_bin-1.2.0.elf'
    assert os.path.isfile(path_1_0_5), f"Expected file {path_1_0_5} does not exist."
    assert os.path.isfile(path_1_2_0), f"Expected file {path_1_2_0} does not exist."


def test_aarch64_binaries_exist():
    """Check that aarch64 binaries exist."""
    path_client = '/home/user/repo/aarch64/client_bin-2.1.0.elf'
    path_proxy = '/home/user/repo/aarch64/proxy_bin-3.0.0.elf'
    assert os.path.isfile(path_client), f"Expected file {path_client} does not exist."
    assert os.path.isfile(path_proxy), f"Expected file {path_proxy} does not exist."


def test_failed_binary_not_in_repo():
    """Check that worker_bin is not in the repo."""
    for root, dirs, files in os.walk('/home/user/repo'):
        for file in files:
            assert 'worker_bin' not in file, f"Failed binary worker_bin found in repo: {os.path.join(root, file)}"


def test_symlink_latest():
    """Check that server_bin-latest.elf is a symlink to server_bin-1.2.0.elf."""
    symlink_path = '/home/user/repo/x86_64/server_bin-latest.elf'
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert 'server_bin-1.2.0.elf' in target, f"Symlink {symlink_path} does not point to server_bin-1.2.0.elf, points to {target}"


def test_hardlink_all_binaries():
    """Check that files in all_binaries are hardlinks to the arch folders."""
    arch_file = '/home/user/repo/x86_64/server_bin-1.2.0.elf'
    all_bin_file = '/home/user/repo/all_binaries/server_bin-1.2.0.elf'
    assert os.path.isfile(arch_file), f"Missing {arch_file}"
    assert os.path.isfile(all_bin_file), f"Missing {all_bin_file}"
    stat_arch = os.stat(arch_file)
    stat_all = os.stat(all_bin_file)
    assert stat_arch.st_ino == stat_all.st_ino, f"{all_bin_file} is not a hardlink to {arch_file} (inodes differ)"


def test_final_archive_exists():
    """Check that the final tarball exists and is a valid tar file."""
    archive_path = '/home/user/repo_curated.tar.gz'
    assert os.path.isfile(archive_path), f"Final archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."


def semver_key(version):
    main, sep, pre = version.partition('-')
    nums = tuple(int(x) for x in main.split('.'))
    nums = nums + (0,) * (3 - len(nums))
    if not sep:
        return nums, (1,)
    parts = []
    for item in pre.split('.'):
        parts.append((0, int(item)) if item.isdigit() else (1, item))
    return nums, (0, tuple(parts))


def load_oracle_from_inputs():
    artifacts = {}
    with tarfile.open('/home/user/incoming/artifacts.tar.gz', 'r:gz') as tf:
        for member in tf.getmembers():
            if member.isfile():
                name = posixpath.basename(member.name)
                artifacts[name] = tf.extractfile(member).read()

    text = open('/home/user/incoming/build.log', encoding='utf-8').read()
    records = []
    for block in text.split('--- BUILD RECORD ---')[1:]:
        fields = dict(re.findall(r'^(Artifact|Target|Version|Status):\s*(.*?)\s*$', block, re.M))
        if fields:
            records.append(fields)

    expected = {}
    successful = []
    for record in records:
        if record['Status'] != 'SUCCESS' or record['Artifact'] not in artifacts:
            continue
        data = artifacts[record['Artifact']]
        assert data[:4] == b'\x7fELF' and len(data) >= 20
        endian = 'little' if data[5] == 1 else 'big'
        machine = int.from_bytes(data[18:20], endian)
        arch = {62: 'x86_64', 183: 'aarch64'}[machine]
        filename = f"{record['Artifact']}-{record['Version']}.elf"
        expected[(arch, filename)] = data
        successful.append((arch, record['Artifact'], record['Version'], filename))
    return artifacts, expected, successful


def normalized_disk_target(link_path):
    target = os.readlink(link_path)
    if os.path.isabs(target):
        return os.path.normpath(target)
    return os.path.normpath(os.path.join(os.path.dirname(link_path), target))


def clean_tar_name(name):
    assert not name.startswith('/'), f"Absolute archive member: {name}"
    raw_parts = [p for p in name.split('/') if p not in ('', '.')]
    assert '..' not in raw_parts, f"Unsafe archive member: {name}"
    return posixpath.normpath('/'.join(raw_parts))


def test_program_executed_successfully():
    assert os.path.isfile('/home/user/curator/src/main.rs')
    assert not os.path.islink('/home/user/curator/src/main.rs')
    assert open('/tmp/program_status').read().strip() == '0'


def test_extraction_and_complete_repository_contents():
    artifacts, expected, successful = load_oracle_from_inputs()

    extracted = '/home/user/incoming/extracted'
    assert os.path.isdir(extracted)
    assert set(os.listdir(extracted)) == set(artifacts)
    for name, data in artifacts.items():
        path = os.path.join(extracted, name)
        assert os.path.isfile(path) and not os.path.islink(path)
        assert open(path, 'rb').read() == data

    expected_dirs = {'x86_64', 'aarch64', 'all_binaries'}
    assert set(os.listdir('/home/user/repo')) == expected_dirs

    expected_by_dir = {'x86_64': set(), 'aarch64': set(), 'all_binaries': set()}
    latest = {}
    for arch, artifact, version, filename in successful:
        expected_by_dir[arch].add(filename)
        expected_by_dir['all_binaries'].add(filename)
        key = (arch, artifact)
        if key not in latest or semver_key(version) > semver_key(latest[key][0]):
            latest[key] = (version, filename)
    for (arch, artifact), (_, filename) in latest.items():
        expected_by_dir[arch].add(f'{artifact}-latest.elf')

    for directory, names in expected_by_dir.items():
        path = os.path.join('/home/user/repo', directory)
        assert os.path.isdir(path) and not os.path.islink(path)
        assert set(os.listdir(path)) == names

    for (arch, filename), data in expected.items():
        arch_path = os.path.join('/home/user/repo', arch, filename)
        all_path = os.path.join('/home/user/repo/all_binaries', filename)
        for path in (arch_path, all_path):
            assert os.path.isfile(path) and not os.path.islink(path)
            assert open(path, 'rb').read() == data
        a, b = os.stat(arch_path), os.stat(all_path)
        assert a.st_dev == b.st_dev and a.st_ino == b.st_ino

    for (arch, artifact), (_, filename) in latest.items():
        link = os.path.join('/home/user/repo', arch, f'{artifact}-latest.elf')
        destination = os.path.join('/home/user/repo', arch, filename)
        assert os.path.islink(link)
        assert normalized_disk_target(link) == destination


def test_each_final_file_was_atomically_renamed_from_same_directory():
    _, expected, _ = load_oracle_from_inputs()
    events = []
    if os.path.exists('/tmp/rename_audit.log'):
        for line in open('/tmp/rename_audit.log', encoding='utf-8'):
            parts = line.rstrip('\n').split('\t')
            if len(parts) == 4:
                src, dst, size, mode = parts
                events.append((os.path.normpath(src), os.path.normpath(dst), int(size), int(mode, 8)))

    for (arch, filename), data in expected.items():
        final = os.path.normpath(os.path.join('/home/user/repo', arch, filename))
        matches = [e for e in events if e[1] == final]
        assert matches, f'No successful atomic rename into {final}'
        assert any(
            os.path.dirname(src) == os.path.dirname(final)
            and src != final
            and size == len(data)
            and stat.S_ISREG(mode)
            for src, _, size, mode in matches
        ), f'{final} was not renamed from a regular temporary file in its target directory'


def test_archive_contents_bytes_symlinks_and_hardlinks():
    _, expected, successful = load_oracle_from_inputs()
    latest = {}
    for arch, artifact, version, filename in successful:
        key = (arch, artifact)
        if key not in latest or semver_key(version) > semver_key(latest[key][0]):
            latest[key] = (version, filename)

    expected_files = set()
    expected_links = set()
    expected_dirs = {'repo', 'repo/x86_64', 'repo/aarch64', 'repo/all_binaries'}
    for arch, filename in expected:
        expected_files.add(f'repo/{arch}/{filename}')
        expected_files.add(f'repo/all_binaries/{filename}')
    for arch, artifact in latest:
        expected_links.add(f'repo/{arch}/{artifact}-latest.elf')

    with tarfile.open('/home/user/repo_curated.tar.gz', 'r:gz') as tf:
        members = {}
        for member in tf.getmembers():
            name = clean_tar_name(member.name)
            assert name not in members, f'Duplicate archive member {name}'
            members[name] = member

        assert set(members) == expected_dirs | expected_files | expected_links
        assert all(members[d].isdir() for d in expected_dirs)

        for (arch, filename), data in expected.items():
            arch_name = f'repo/{arch}/{filename}'
            all_name = f'repo/all_binaries/{filename}'
            first, second = members[arch_name], members[all_name]
            assert not first.issym() and not second.issym()
            assert int(first.islnk()) + int(second.islnk()) == 1, \
                f'Archive did not preserve hard link between {arch_name} and {all_name}'
            linked, regular = (first, second) if first.islnk() else (second, first)
            assert regular.isfile()
            assert clean_tar_name(linked.linkname) == clean_tar_name(regular.name)
            assert tf.extractfile(regular).read() == data
            assert tf.extractfile(linked).read() == data

        for (arch, artifact), (_, filename) in latest.items():
            link_name = f'repo/{arch}/{artifact}-latest.elf'
            member = members[link_name]
            assert member.issym()
            if posixpath.isabs(member.linkname):
                resolved = clean_tar_name(member.linkname.lstrip('/'))
            else:
                resolved = clean_tar_name(posixpath.join(posixpath.dirname(link_name), member.linkname))
            assert resolved == f'repo/{arch}/{filename}'
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
result=$?
if [ "$result" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
