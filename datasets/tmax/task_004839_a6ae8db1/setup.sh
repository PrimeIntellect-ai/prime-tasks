#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
with open("/home/user/telemetry.csv", "wb") as f:
    # 1. fr-FR, ISO-8859-1
    f.write(b"2023-10-12T08:15:32Z,fr-FR,ISO-8859-1,100,D\xe9faillance\n")
    # 2. es-ES, UTF-8
    f.write(b"2023-10-12T08:15:45Z,es-ES,UTF-8,150,Error de red\n")
    # 3. fr-FR, UTF-8
    f.write("2023-10-12T08:16:05Z,fr-FR,UTF-8,200,Succès\n".encode("utf-8"))
    # 4. fr-FR, ISO-8859-1
    f.write(b"2023-10-12T08:16:55Z,fr-FR,ISO-8859-1,250,Arr\xeat\n")
    # 5. es-ES, ISO-8859-1
    f.write(b"2023-10-12T08:17:10Z,es-ES,ISO-8859-1,100,M\xe1s tarde\n")
    # 6. fr-FR, UTF-8
    f.write(b"2023-10-12T08:18:00Z,fr-FR,UTF-8,300,Fini\n")
'

    chmod -R 777 /home/user
