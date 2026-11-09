#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/pr_review
    mkdir -p /app

    # Create event_parser.c
    cat << 'EOF' > /home/user/pr_review/event_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    char *buffer = malloc(10);
    strcpy(buffer, "test");
    free(buffer);
    // Use after free
    printf("%s\n", buffer);
    return 0;
}
EOF

    # Create process_audio.sh
    cat << 'EOF' > /home/user/pr_review/process_audio.sh
#!/bin/bash
cat $1
EOF
    chmod +x /home/user/pr_review/process_audio.sh

    # Create test_sample.wav
    echo "RIFF....WAVEfmt ........" > /app/test_sample.wav

    # Create sample_transcript.txt
    cat << 'EOF' > /home/user/pr_review/sample_transcript.txt
[00:00:01.000] <APPLAUSE> 
[00:00:02.000] <SPEECH> Welcome to the 42nd annual developer conference.
[00:00:05.000] <APPLAUSE> 
[00:00:06.000] <NOISE> (dog barking)
[00:00:10.000] <APPLAUSE> 
EOF

    # Create oracle_processor
    cat << 'EOF' > /app/oracle_processor.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    printf("00:00:00.000 | [MUSIC] | 10\n");
    return 0;
}
EOF
    gcc /app/oracle_processor.c -o /app/oracle_processor
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
