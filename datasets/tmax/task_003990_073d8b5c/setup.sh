#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential espeak
    pip3 install pytest

    mkdir -p /app/audio /app/corpus/clean /app/corpus/evil

    espeak -w /app/audio/template_dictation.wav "Attention localization team. All dynamic template variables must be strictly enclosed in double curly braces, such as curly curly user underscore name curly curly. Any other bracket types are invalid."

    python3 -c "
import os

clean_template = 'id_{i},en,\"Line 1\nLine 2 with {o}{o}var_{i}{c}{c}\"\n'
evil_template_1 = 'id_{i},en,\"Line 1\nLine 2 with [[var_{i}]]\"\n'
evil_template_2 = 'id_{i},en,\"Line 1\nLine 2 with <var_{i}>\"\n'
evil_template_3 = 'id_{i},en,\"Line 1\nLine 2 with {o}{o}var_{i}{c}{c}\n'

for i in range(20):
    with open(f'/app/corpus/clean/clean_{i}.csv', 'w') as f:
        f.write('string_id,language_code,translation_text\n')
        f.write(clean_template.format(i=i, o='{', c='}'))

    with open(f'/app/corpus/evil/evil_{i}.csv', 'w') as f:
        f.write('string_id,language_code,translation_text\n')
        if i % 3 == 0:
            f.write(evil_template_1.format(i=i))
        elif i % 3 == 1:
            f.write(evil_template_2.format(i=i))
        else:
            f.write(evil_template_3.format(i=i, o='{', c='}'))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
