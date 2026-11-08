#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/math_concepts.csv
ID,Description
1,A triangle with all three sides of equal length.
2,A closed plane curve consisting of all points at a given distance from a fixed point.
3,A quadrilateral with four equal sides and four right angles.
4,A polyhedron with six square faces.
5,A straight one-dimensional figure having no thickness and extending infinitely in both directions.
EOF

    chmod -R 777 /home/user
