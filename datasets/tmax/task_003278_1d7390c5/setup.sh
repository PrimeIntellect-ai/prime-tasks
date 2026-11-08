#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create crash.dump
    dd if=/dev/urandom of=/home/user/crash.dump bs=1K count=10
    echo -n "LAST_REQ: lat1=40.7128,lon1=-74.0060,lat2=51.5074,lon2=-0.1278" >> /home/user/crash.dump
    dd if=/dev/urandom bs=1K count=10 >> /home/user/crash.dump

    # Create haversine.c
    cat << 'EOF' > /home/user/haversine.c
#include <math.h>

#define EARTH_RADIUS_KM 6371.0
#define TO_RAD(deg) ((deg) * 3.14159265358979323846 / 180.0)

double calculate_distance(double lat1, double lon1, double lat2, double lon2) {
    double dLat = TO_RAD(lat2 - lat1);
    double dLon = TO_RAD(lon2 - lon1);

    // BUG: The formula requires lat1 and lat2 to be in radians when passed to cos().
    // The buggy version passes them in as degrees.
    double a = sin(dLat / 2.0) * sin(dLat / 2.0) +
               cos(lat1) * cos(lat2) * 
               sin(dLon / 2.0) * sin(dLon / 2.0);

    double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
    return EARTH_RADIUS_KM * c;
}
EOF

    chmod -R 777 /home/user
