#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/corpus.txt
Hello world! This is a test.
Data science is fun, but data processing is hard.
Tokens are the building blocks of language models.
Numerical accuracy is crucial.
We are researchers organizing datasets.
Let's tokenize this properly.
End of the first ten lines? No, this is line 7.
Line eight is here.
Almost done with the dataset.
This is the tenth and final line for the test.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
