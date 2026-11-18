#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > loc_exports.tsv
1620000000	1	es-ES	Inicio
1620000000	2	es-ES	Configuración
1620000000	3	es-ES	Usuario
1620000000	5	es-ES	Contraseña
1620000000	6	es-ES	Correo electrónico
1620000000	7	es-ES	Guardar
1620000000	8	es-ES	Cancelar
1620000000	9	es-ES	Eliminar
1620000000	10	es-ES	Añadir
1620000000	1	ja-JP	ホーム
1620000000	2	ja-JP	設定
1620000000	11	es-ES	Perfil
1620000000	12	es-ES	Ayuda (Old)
1620000100	12	es-ES	Ayuda
1620000000	13	es-ES	Acerca de
1620000000	14	es-ES	Cerrar sesión
1620000000	16	es-ES	Notificaciones
1620000000	17	es-ES	Privacidad
1620000000	18	es-ES	Seguridad
1620000000	19	es-ES	Idioma
1620000000	20	es-ES	Tema
1620000000	21	es-ES	Avanzado
1620000000	23	es-ES	Sistema
1620000000	24	es-ES	Red
1620000000	25	es-ES	Almacenamiento
1620000000	26	es-ES	Batería
1620000000	27	es-ES	Pantalla
1620000000	28	es-ES	Sonido
1620000000	29	es-ES	Aplicaciones
1620000000	30	es-ES	Permisos (v1)
1620000050	30	es-ES	Permisos (v2)
1620000200	30	es-ES	Permisos
1620000000	31	es-ES	Cuentas
1620000000	32	es-ES	Sincronización
1620000000	33	es-ES	Copia de seguridad
1620000000	34	es-ES	Restablecer
1620000000	35	es-ES	Fecha y hora
1620000000	36	es-ES	Accesibilidad
1620000000	37	es-ES	Impresión
1620000000	38	es-ES	Desarrollador
1620000000	39	es-ES	Estado
1620000000	40	es-ES	Legal
1620000000	41	es-ES	Licencias
1620000000	42	es-ES	Términos
1620000000	43	es-ES	Condiciones
1620000000	44	es-ES	Política
1620000000	45	es-ES	Cookies
1620000000	46	es-ES	Contacto
1620000000	47	es-ES	Soporte
1620000000	48	es-ES	Foro
1620000000	50	es-ES	Versión
EOF

useradd -m -s /bin/bash user || true
chown user:user /home/user/loc_exports.tsv
chmod -R 777 /home/user
