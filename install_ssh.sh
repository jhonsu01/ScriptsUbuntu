#!/bin/bash
# ============================================================
# Script: install_ssh.sh
# Descripción: Instala y configura SSH Server en Ubuntu 24.04
#              con autenticación por contraseña en red local
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error(){ echo -e "${RED}[✘]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

[ "$EUID" -ne 0 ] && error "Ejecuta como root: sudo bash install_ssh.sh"

echo -e "\n${CYAN}================================================${NC}"
echo -e "${CYAN}   Instalación de SSH Server - Ubuntu 24.04    ${NC}"
echo -e "${CYAN}================================================${NC}\n"

info "Actualizando repositorios..."
apt-get update -qq

info "Instalando openssh-server y ufw..."
apt-get install -y openssh-server ufw > /dev/null 2>&1
log "openssh-server instalado"

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
log "Backup creado en /etc/ssh/sshd_config.bak"

LOCAL_IP=$(hostname -I | awk '{print $1}')
NETWORK=$(echo "$LOCAL_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')
info "Red local detectada: ${NETWORK} (IP del servidor: ${LOCAL_IP})"

info "Configurando SSH..."
cat > /etc/ssh/sshd_config << EOF
# SSH Server Config - Ubuntu 24.04 - Red Local

Port 22
AddressFamily inet
ListenAddress 0.0.0.0

# Autenticación
PermitRootLogin no
MaxAuthTries 5
MaxSessions 5

PasswordAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication yes

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

Banner /etc/ssh/banner
ClientAliveInterval 60
ClientAliveCountMax 3
LoginGraceTime 30
EOF

cat > /etc/ssh/banner << 'BANNER'

  ╔══════════════════════════════════════╗
  ║     Servidor SSH - Red Local         ║
  ║     Acceso autorizado únicamente     ║
  ╚══════════════════════════════════════╝

BANNER

info "Configurando firewall UFW..."
ufw --force enable > /dev/null 2>&1
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow from "$NETWORK" to any port 22 proto tcp > /dev/null 2>&1
log "Regla creada: SSH permitido solo desde ${NETWORK}"

info "Habilitando y reiniciando SSH..."
systemctl enable ssh > /dev/null 2>&1
systemctl restart ssh

systemctl is-active --quiet ssh && log "Servicio SSH activo y corriendo" || error "SSH no pudo iniciarse. Revisa: journalctl -xe"

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}   ✔ Instalación completada exitosamente       ${NC}"
echo -e "${GREEN}================================================${NC}\n"
info "IP del servidor    : ${LOCAL_IP}"
info "Puerto SSH         : 22"
info "Red permitida      : ${NETWORK}"
info "Auth por contraseña: HABILITADA"
info "Auth por llave     : HABILITADA"
info "Login root         : DESHABILITADO"
echo -e "\n${YELLOW}Conéctate desde otro equipo en tu red:${NC}"
echo -e "  ${CYAN}ssh usuario@${LOCAL_IP}${NC}\n"
