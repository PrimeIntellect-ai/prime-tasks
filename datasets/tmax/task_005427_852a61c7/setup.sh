#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
pip3 install pytest

mkdir -p /app/audio
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Generate audio file
espeak -w /app/audio/lecture.wav "In linear algebra, an eigenvector or characteristic vector of a linear transformation is a non-zero vector that changes at most by a scalar factor when that linear transformation is applied to it. The corresponding eigenvalue, often denoted by lambda, is the factor by which the eigenvector is scaled."

# Create clean corpus
cat << 'EOF' > /app/corpus/clean/doc1.txt
Matrix multiplication is a fundamental operation in linear algebra. It involves taking the rows of the first matrix and the columns of the second matrix to compute the dot product.
EOF

cat << 'EOF' > /app/corpus/clean/doc2.txt
The determinant of a square matrix is a scalar value that can be computed from the elements of the matrix. It provides important properties about the matrix, such as whether it is invertible.
EOF

cat << 'EOF' > /app/corpus/clean/doc3.txt
Basis vectors are a set of linearly independent vectors that span a vector space. Any vector in the space can be represented as a linear combination of the basis vectors.
EOF

cat << 'EOF' > /app/corpus/clean/doc4.txt
Eigenspaces are the set of all eigenvectors corresponding to a specific eigenvalue, along with the zero vector. They form a subspace of the vector space.
EOF

# Create evil corpus
cat << 'EOF' > /app/corpus/evil/bad1.txt
Cellular mitosis is the process by which a single cell divides into two identical daughter cells. It consists of several phases, including prophase, metaphase, anaphase, and telophase.
EOF

cat << 'EOF' > /app/corpus/evil/bad2.txt
During the medieval period, Europe experienced significant social and political changes. The feudal system was the dominant social structure, with lords granting land to vassals in exchange for military service.
EOF

cat << 'EOF' > /app/corpus/evil/bad3.txt
To make the perfect chocolate chip cookies, you need butter, sugar, eggs, flour, baking soda, and of course, chocolate chips. Cream the butter and sugar together, then add the eggs and dry ingredients.
EOF

cat << 'EOF' > /app/corpus/evil/bad4.txt
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
