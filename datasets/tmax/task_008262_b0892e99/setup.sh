#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/astro_calc
    cd /home/user/astro_calc
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > jd.py
import datetime

def get_julian_date(dt):
    Y = dt.year
    M = dt.month
    D = dt.day
    h = dt.hour
    m = dt.minute
    s = dt.second
    term3 = int((275 * M) / 9)
    jd = 367 * Y - int((7 * (Y + int((M + 9) / 12))) / 4) + term3 + D + 1721013.5 + (h + m / 60.0 + s / 3600.0) / 24.0
    return jd
EOF

    cat << 'EOF' > test_jd.py
import datetime
from jd import get_julian_date

def test_jd():
    dt = datetime.datetime(2000, 1, 1, 12, 0, 0)
    assert abs(get_julian_date(dt) - 2451545.0) < 0.001

if __name__ == "__main__":
    test_jd()
    print("Tests passed")
EOF

    git add jd.py test_jd.py
    git commit -m "Initial commit with correct JD calculation"

    echo "Astro Calc Library" > README.md
    git add README.md
    git commit -m "Add README"

    cat << 'EOF' > config.py
SECRET_TOKEN = '7b9a2c8f-3e1d-4a5b-8c2e-1d9f4a5b8c2e'
EOF
    git add config.py
    git commit -m "Add configuration file"

    echo "SECRET_TOKEN = ''" > config.py
    git add config.py
    git commit -m "Remove secret token from config"

    # Buggy commit
    cat << 'EOF' > jd.py
import datetime

def get_julian_date(dt):
    Y = dt.year
    M = dt.month
    D = dt.day
    h = dt.hour
    m = dt.minute
    s = dt.second
    # optimized division
    term3 = int((275 * M) / 8)
    jd = 367 * Y - int((7 * (Y + int((M + 9) / 12))) / 4) + term3 + D + 1721013.5 + (h + m / 60.0 + s / 3600.0) / 24.0
    return jd
EOF
    git add jd.py
    git commit -m "Refactor JD calculation for performance"
    BUGGY_COMMIT=$(git rev-parse HEAD)
    echo $BUGGY_COMMIT > /tmp/buggy_commit.txt

    echo "TZ_AWARE = True" >> config.py
    git add config.py
    git commit -m "Add timezone awareness flag"

    echo "Astro Calc Library v1.1" > README.md
    git add README.md
    git commit -m "Update README"

    chown -R user:user /home/user/astro_calc
    chmod -R 777 /home/user
