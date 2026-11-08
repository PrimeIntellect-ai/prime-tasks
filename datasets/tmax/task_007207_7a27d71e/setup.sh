#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang nodejs
    pip3 install pytest

    mkdir -p /home/user/project/packages/libalpha
    mkdir -p /home/user/project/packages/libbeta
    mkdir -p /home/user/project/packages/libgamma
    mkdir -p /home/user/project/packages/libdelta

    cat << 'EOF' > /home/user/project/legacy_semver.js
// Legacy version evaluation logic
function compareVersions(v1, v2) {
    const p1 = v1.split('.').map(Number);
    const p2 = v2.split('.').map(Number);
    for (let i = 0; i < 3; i++) {
        if (p1[i] > p2[i]) return 1;
        if (p1[i] < p2[i]) return -1;
    }
    return 0;
}

function evaluateCondition(actualVer, operator, targetVer) {
    const cmp = compareVersions(actualVer, targetVer);
    if (operator === '==') return cmp === 0;
    if (operator === '>=') return cmp >= 0;
    if (operator === '<=') return cmp <= 0;
    return false;
}

function evaluateExpression(actualVer, expr) {
    // expr example: ">= 1.0.0 && <= 2.0.0" or "== 3.0.0"
    const parts = expr.split('&&').map(p => p.trim());
    for (const part of parts) {
        const tokens = part.split(' ');
        const op = tokens[0];
        const target = tokens[1];
        if (!evaluateCondition(actualVer, op, target)) {
            return false;
        }
    }
    return true;
}
EOF

    cat << 'EOF' > /home/user/project/manifest.txt
libalpha >= 1.2.0 && <= 2.0.0
libbeta == 3.1.4
libgamma >= 2.0.0 && <= 2.9.9
libdelta >= 1.0.0
libepsilon == 1.0.0
EOF

    echo -n "1.5.0" > /home/user/project/packages/libalpha/version.txt
    cat << 'EOF' > /home/user/project/packages/libalpha/build.sh
#!/bin/bash
echo "alpha compiled" > /home/user/project/packages/libalpha/out.artifact
EOF
    chmod +x /home/user/project/packages/libalpha/build.sh

    echo -n "3.1.4" > /home/user/project/packages/libbeta/version.txt
    cat << 'EOF' > /home/user/project/packages/libbeta/build.sh
#!/bin/bash
echo "beta compiled" > /home/user/project/packages/libbeta/out.artifact
EOF
    chmod +x /home/user/project/packages/libbeta/build.sh

    echo -n "1.9.9" > /home/user/project/packages/libgamma/version.txt
    cat << 'EOF' > /home/user/project/packages/libgamma/build.sh
#!/bin/bash
echo "gamma compiled" > /home/user/project/packages/libgamma/out.artifact
EOF
    chmod +x /home/user/project/packages/libgamma/build.sh

    echo -n "1.0.5" > /home/user/project/packages/libdelta/version.txt
    cat << 'EOF' > /home/user/project/packages/libdelta/build.sh
#!/bin/bash
echo "delta compiled" > /home/user/project/packages/libdelta/out.artifact
EOF
    chmod +x /home/user/project/packages/libdelta/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
