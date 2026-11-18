#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils curl
    pip3 install pytest pandas flask requests

    mkdir -p /app
    cat << 'EOF' > /app/extractor.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    if (strstr(argv[1], "app_v1.bin")) {
        printf("key,en_US,es_ES,fr_FR,ja_JP\n");
        printf("GREETING,Hello,Hola,Bonjour,Konnichiwa\n");
        printf("FAREWELL,Goodbye,,Au revoir,Sayonara\n");
        printf("MULTI_LINE,Line1\nLine2,Linea1\nLinea2,Ligne1\nLigne2,Rain1\nRain2\n");
        printf("LOGIN,Login,Iniciar,Connexion,Rogun\n");
    } else if (strstr(argv[1], "app_v2.bin")) {
        printf("key,en_US,es_ES,fr_FR,ja_JP\n");
        printf("YES,Yes,Si,Oui,Hai\n");
        printf("NO,No,No,Non,Iie\n");
        printf("CANCEL,Cancel,Cancelar,Annuler,Kyanseru\n");
    } else if (strstr(argv[1], "app_v3.bin")) {
        printf("key,en_US,es_ES,fr_FR,ja_JP\n");
        printf("SAVE,Save,Guardar,,Hozon\n");
        printf("ERROR_MSG,Error\nOccurred,Error\nOcurrido,Erreur\nSurvenue,Era\n\n");
        printf("SUCCESS,Success,Exito,Succes,Seiko\n");
    }
    return 0;
}
EOF

    gcc /app/extractor.c -o /app/legacy_extractor
    strip /app/legacy_extractor
    rm /app/extractor.c

    mkdir -p /home/user/data/resources
    mkdir -p /home/user/data/processed

    echo "dummy binary data v1" > /home/user/data/resources/app_v1.bin
    echo "dummy binary data v2" > /home/user/data/resources/app_v2.bin
    echo "dummy binary data v3" > /home/user/data/resources/app_v3.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
