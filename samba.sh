#!/bin/bash
# ============================================================================
#  SAMBA FILE SHARING - INSTALADOR INTERACTIVO
#  Para Ubuntu 24.04 Server
#  Autor: Jhon Supelano | serviciosconiabyjhonsu.com
# ============================================================================

set -e

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Variables globales ---
SAMBA_CONF="/etc/samba/smb.conf"
SAMBA_CONF_BAK="/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
LOG_FILE="/var/log/samba-setup.log"
SHARES_DIR="/srv/samba"

# --- Funciones de utilidad ---
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          SAMBA FILE SHARING - INSTALADOR INTERACTIVO       ║"
    echo "║                    Ubuntu 24.04 Server                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

info()    { echo -e "${BLUE}[INFO]${NC} $1"; log_msg "INFO: $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1";   log_msg "OK: $1"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; log_msg "AVISO: $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1";  log_msg "ERROR: $1"; }

separator() {
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
}

confirm() {
    local prompt="$1"
    local default="${2:-s}"
    local response
    if [[ "$default" == "s" ]]; then
        read -rp "$(echo -e "${YELLOW}$prompt [S/n]: ${NC}")" response
        response="${response:-s}"
    else
        read -rp "$(echo -e "${YELLOW}$prompt [s/N]: ${NC}")" response
        response="${response:-n}"
    fi
    [[ "${response,,}" == "s" || "${response,,}" == "y" ]]
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse como root."
        echo -e "Ejecuta: ${BOLD}sudo bash $0${NC}"
        exit 1
    fi
}

get_local_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1 || \
    ip -4 addr show | grep -oP '(?<=inet\s)10\.\d+\.\d+\.\d+' | head -1 || \
    hostname -I | awk '{print $1}'
}

# ============================================================================
#  PASO 1: INSTALACIÓN DE SAMBA
# ============================================================================
install_samba() {
    print_banner
    echo -e "${BOLD}PASO 1: Instalación de Samba${NC}"
    separator

    if dpkg -l | grep -q "^ii.*samba "; then
        success "Samba ya está instalado."
        SAMBA_VERSION=$(smbd --version 2>/dev/null || echo "desconocida")
        info "Versión: $SAMBA_VERSION"
    else
        info "Instalando Samba y dependencias..."
        apt-get update -qq
        apt-get install -y samba samba-common-bin samba-client cifs-utils
        success "Samba instalado correctamente."
    fi

    # Respaldar configuración original
    if [[ -f "$SAMBA_CONF" ]]; then
        cp "$SAMBA_CONF" "$SAMBA_CONF_BAK"
        success "Backup de smb.conf creado: $SAMBA_CONF_BAK"
    fi

    echo ""
}

# ============================================================================
#  PASO 2: CONFIGURACIÓN DE RED (WORKGROUP)
# ============================================================================
configure_network() {
    print_banner
    echo -e "${BOLD}PASO 2: Configuración de Red${NC}"
    separator

    LOCAL_IP=$(get_local_ip)
    info "IP local detectada: ${BOLD}$LOCAL_IP${NC}"
    SUBNET=$(echo "$LOCAL_IP" | sed 's/\.[0-9]*$/.0\/24/')
    info "Subred: ${BOLD}$SUBNET${NC}"

    echo ""
    read -rp "$(echo -e "${YELLOW}Nombre del grupo de trabajo [WORKGROUP]: ${NC}")" WORKGROUP
    WORKGROUP="${WORKGROUP:-WORKGROUP}"
    WORKGROUP="${WORKGROUP^^}"

    read -rp "$(echo -e "${YELLOW}Descripción del servidor [Servidor Samba - $(hostname)]: ${NC}")" SERVER_DESC
    SERVER_DESC="${SERVER_DESC:-Servidor Samba - $(hostname)}"

    success "Workgroup: $WORKGROUP"
    success "Descripción: $SERVER_DESC"
    echo ""
}

# ============================================================================
#  PASO 3: GESTIÓN DE USUARIOS
# ============================================================================
manage_users() {
    print_banner
    echo -e "${BOLD}PASO 3: Gestión de Usuarios Samba${NC}"
    separator

    SAMBA_USERS=()

    while true; do
        echo ""
        echo -e "${CYAN}Opciones de usuario:${NC}"
        echo "  1) Crear nuevo usuario Samba"
        echo "  2) Usar usuario existente del sistema"
        echo "  3) Terminar (continuar al siguiente paso)"
        echo ""
        read -rp "$(echo -e "${YELLOW}Selecciona una opción [1-3]: ${NC}")" user_opt

        case $user_opt in
            1)
                echo ""
                read -rp "$(echo -e "${YELLOW}Nombre de usuario nuevo: ${NC}")" NEW_USER
                if [[ -z "$NEW_USER" ]]; then
                    warn "El nombre no puede estar vacío."
                    continue
                fi

                # Validar nombre
                if ! [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                    warn "Nombre inválido. Usa solo letras minúsculas, números, guiones y guion bajo."
                    continue
                fi

                # Crear usuario del sistema si no existe
                if ! id "$NEW_USER" &>/dev/null; then
                    useradd -M -s /usr/sbin/nologin "$NEW_USER"
                    success "Usuario del sistema '$NEW_USER' creado (sin shell de login)."
                else
                    warn "El usuario '$NEW_USER' ya existe en el sistema."
                fi

                # Establecer contraseña Samba
                echo -e "${YELLOW}Establece la contraseña de Samba para '$NEW_USER':${NC}"
                smbpasswd -a "$NEW_USER"
                smbpasswd -e "$NEW_USER"
                SAMBA_USERS+=("$NEW_USER")
                success "Usuario Samba '$NEW_USER' configurado."
                ;;
            2)
                echo ""
                info "Usuarios disponibles en el sistema:"
                awk -F: '$3 >= 1000 && $3 < 65534 {print "  - " $1}' /etc/passwd
                echo ""
                read -rp "$(echo -e "${YELLOW}Nombre de usuario existente: ${NC}")" EXIST_USER

                if ! id "$EXIST_USER" &>/dev/null; then
                    error "El usuario '$EXIST_USER' no existe."
                    continue
                fi

                echo -e "${YELLOW}Establece la contraseña de Samba para '$EXIST_USER':${NC}"
                smbpasswd -a "$EXIST_USER"
                smbpasswd -e "$EXIST_USER"
                SAMBA_USERS+=("$EXIST_USER")
                success "Usuario Samba '$EXIST_USER' configurado."
                ;;
            3)
                if [[ ${#SAMBA_USERS[@]} -eq 0 ]]; then
                    warn "No has configurado ningún usuario Samba."
                    if ! confirm "¿Continuar sin usuarios (solo carpetas públicas)?"; then
                        continue
                    fi
                fi
                break
                ;;
            *)
                warn "Opción inválida."
                ;;
        esac
    done

    echo ""
    if [[ ${#SAMBA_USERS[@]} -gt 0 ]]; then
        success "Usuarios Samba configurados: ${SAMBA_USERS[*]}"
    fi
}

# ============================================================================
#  PASO 4: CONFIGURACIÓN DE CARPETAS COMPARTIDAS
# ============================================================================
configure_shares() {
    print_banner
    echo -e "${BOLD}PASO 4: Configuración de Carpetas Compartidas${NC}"
    separator

    SHARES_CONFIG=""
    SHARE_COUNT=0

    # Crear directorio base
    mkdir -p "$SHARES_DIR"

    while true; do
        echo ""
        echo -e "${CYAN}Opciones:${NC}"
        echo "  1) Crear carpeta compartida nueva"
        echo "  2) Compartir carpeta existente del sistema"
        echo "  3) Crear carpeta pública (sin contraseña)"
        echo "  4) Terminar (continuar al siguiente paso)"
        echo ""
        read -rp "$(echo -e "${YELLOW}Selecciona una opción [1-4]: ${NC}")" share_opt

        case $share_opt in
            1|2)
                echo ""
                read -rp "$(echo -e "${YELLOW}Nombre visible en la red (ej: Documentos): ${NC}")" SHARE_NAME
                if [[ -z "$SHARE_NAME" ]]; then
                    warn "El nombre no puede estar vacío."
                    continue
                fi

                if [[ "$share_opt" == "1" ]]; then
                    SHARE_PATH="$SHARES_DIR/${SHARE_NAME// /_}"
                    mkdir -p "$SHARE_PATH"
                    success "Directorio creado: $SHARE_PATH"
                else
                    read -rp "$(echo -e "${YELLOW}Ruta completa de la carpeta (ej: /home/jaiver/docs): ${NC}")" SHARE_PATH
                    if [[ ! -d "$SHARE_PATH" ]]; then
                        if confirm "La carpeta no existe. ¿Crearla?"; then
                            mkdir -p "$SHARE_PATH"
                        else
                            continue
                        fi
                    fi
                fi

                read -rp "$(echo -e "${YELLOW}Comentario/descripción [Carpeta compartida]: ${NC}")" SHARE_COMMENT
                SHARE_COMMENT="${SHARE_COMMENT:-Carpeta compartida}"

                # Permisos
                echo ""
                echo -e "${CYAN}Tipo de acceso:${NC}"
                echo "  1) Lectura y escritura (read/write)"
                echo "  2) Solo lectura (read only)"
                read -rp "$(echo -e "${YELLOW}Selecciona [1-2, default: 1]: ${NC}")" ACCESS_TYPE
                ACCESS_TYPE="${ACCESS_TYPE:-1}"

                if [[ "$ACCESS_TYPE" == "2" ]]; then
                    WRITABLE="no"
                    READONLY="yes"
                else
                    WRITABLE="yes"
                    READONLY="no"
                fi

                # Usuarios válidos
                echo ""
                echo -e "${CYAN}Acceso de usuarios:${NC}"
                echo "  1) Todos los usuarios Samba configurados"
                echo "  2) Usuarios específicos"
                read -rp "$(echo -e "${YELLOW}Selecciona [1-2, default: 1]: ${NC}")" USER_ACCESS
                USER_ACCESS="${USER_ACCESS:-1}"

                VALID_USERS_LINE=""
                WRITE_LIST_LINE=""

                if [[ "$USER_ACCESS" == "2" ]]; then
                    echo ""
                    info "Usuarios Samba disponibles: ${SAMBA_USERS[*]}"
                    read -rp "$(echo -e "${YELLOW}Usuarios con acceso (separados por espacio): ${NC}")" SELECTED_USERS
                    VALID_USERS_LINE="   valid users = $SELECTED_USERS"

                    if [[ "$WRITABLE" == "yes" ]]; then
                        echo ""
                        read -rp "$(echo -e "${YELLOW}Usuarios con permiso de escritura (separados por espacio, Enter = todos los seleccionados): ${NC}")" WRITE_USERS
                        if [[ -n "$WRITE_USERS" ]]; then
                            WRITE_LIST_LINE="   write list = $WRITE_USERS"
                        fi
                    fi
                fi

                # Visibilidad
                if confirm "¿Mostrar esta carpeta al explorar la red?" "s"; then
                    BROWSEABLE="yes"
                else
                    BROWSEABLE="no"
                fi

                # Permisos de archivos
                echo ""
                echo -e "${CYAN}Permisos de archivos nuevos:${NC}"
                echo "  1) Estándar (0664 archivos, 0775 directorios)"
                echo "  2) Restringido (0644 archivos, 0755 directorios)"
                echo "  3) Abierto (0666 archivos, 0777 directorios)"
                echo "  4) Personalizado"
                read -rp "$(echo -e "${YELLOW}Selecciona [1-4, default: 1]: ${NC}")" PERM_OPT
                PERM_OPT="${PERM_OPT:-1}"

                case $PERM_OPT in
                    2) FILE_MASK="0644"; DIR_MASK="0755" ;;
                    3) FILE_MASK="0666"; DIR_MASK="0777" ;;
                    4)
                        read -rp "$(echo -e "${YELLOW}Máscara de archivos (ej: 0664): ${NC}")" FILE_MASK
                        read -rp "$(echo -e "${YELLOW}Máscara de directorios (ej: 0775): ${NC}")" DIR_MASK
                        ;;
                    *) FILE_MASK="0664"; DIR_MASK="0775" ;;
                esac

                # Aplicar permisos al directorio
                chmod "$DIR_MASK" "$SHARE_PATH"
                if [[ ${#SAMBA_USERS[@]} -gt 0 ]]; then
                    chown "${SAMBA_USERS[0]}:sambashare" "$SHARE_PATH" 2>/dev/null || \
                    chown "${SAMBA_USERS[0]}:${SAMBA_USERS[0]}" "$SHARE_PATH" 2>/dev/null || true
                fi

                # Construir bloque de configuración
                SHARE_BLOCK="
[$SHARE_NAME]
   comment = $SHARE_COMMENT
   path = $SHARE_PATH
   browseable = $BROWSEABLE
   read only = $READONLY
   writable = $WRITABLE
   guest ok = no
   create mask = $FILE_MASK
   directory mask = $DIR_MASK
   force create mode = $FILE_MASK
   force directory mode = $DIR_MASK"

                [[ -n "$VALID_USERS_LINE" ]] && SHARE_BLOCK+="
$VALID_USERS_LINE"
                [[ -n "$WRITE_LIST_LINE" ]] && SHARE_BLOCK+="
$WRITE_LIST_LINE"

                SHARES_CONFIG+="$SHARE_BLOCK
"
                SHARE_COUNT=$((SHARE_COUNT + 1))
                success "Carpeta '$SHARE_NAME' configurada -> $SHARE_PATH"
                ;;

            3)
                echo ""
                read -rp "$(echo -e "${YELLOW}Nombre de la carpeta pública (ej: Publico): ${NC}")" PUB_NAME
                if [[ -z "$PUB_NAME" ]]; then
                    warn "El nombre no puede estar vacío."
                    continue
                fi

                PUB_PATH="$SHARES_DIR/${PUB_NAME// /_}"
                mkdir -p "$PUB_PATH"
                chmod 0777 "$PUB_PATH"

                read -rp "$(echo -e "${YELLOW}Comentario [Carpeta pública]: ${NC}")" PUB_COMMENT
                PUB_COMMENT="${PUB_COMMENT:-Carpeta pública}"

                echo ""
                echo -e "${CYAN}Permisos para la carpeta pública:${NC}"
                echo "  1) Solo lectura"
                echo "  2) Lectura y escritura"
                read -rp "$(echo -e "${YELLOW}Selecciona [1-2, default: 2]: ${NC}")" PUB_ACCESS
                PUB_ACCESS="${PUB_ACCESS:-2}"

                if [[ "$PUB_ACCESS" == "1" ]]; then
                    PUB_WRITABLE="no"
                    PUB_READONLY="yes"
                else
                    PUB_WRITABLE="yes"
                    PUB_READONLY="no"
                fi

                SHARES_CONFIG+="
[$PUB_NAME]
   comment = $PUB_COMMENT
   path = $PUB_PATH
   browseable = yes
   read only = $PUB_READONLY
   writable = $PUB_WRITABLE
   guest ok = yes
   guest only = yes
   create mask = 0666
   directory mask = 0777
   force user = nobody
   force group = nogroup
"
                SHARE_COUNT=$((SHARE_COUNT + 1))
                success "Carpeta pública '$PUB_NAME' configurada -> $PUB_PATH"
                ;;

            4)
                if [[ $SHARE_COUNT -eq 0 ]]; then
                    warn "No has configurado ninguna carpeta compartida."
                    if ! confirm "¿Continuar sin carpetas?"; then
                        continue
                    fi
                fi
                break
                ;;
            *)
                warn "Opción inválida."
                ;;
        esac
    done
}

# ============================================================================
#  PASO 5: GENERAR smb.conf
# ============================================================================
generate_config() {
    print_banner
    echo -e "${BOLD}PASO 5: Generando Configuración${NC}"
    separator

    # Determinar si hay carpetas públicas
    GUEST_MAP="never"
    if echo "$SHARES_CONFIG" | grep -q "guest ok = yes"; then
        GUEST_MAP="bad user"
    fi

    cat > "$SAMBA_CONF" << SMBEOF
# ============================================================================
# Samba Configuration - Generado automáticamente
# Fecha: $(date '+%Y-%m-%d %H:%M:%S')
# Servidor: $(hostname) ($LOCAL_IP)
# ============================================================================

[global]
   workgroup = $WORKGROUP
   server string = $SERVER_DESC
   server role = standalone server

   # --- Seguridad ---
   security = user
   map to guest = $GUEST_MAP
   encrypt passwords = yes
   passdb backend = tdbsam

   # --- Red ---
   interfaces = lo $(ip -o link show | awk -F': ' '/state UP/{print $2}' | grep -v lo | head -1)
   bind interfaces only = yes
   hosts allow = 127.0.0.1 $(echo "$SUBNET" | sed 's/\/24/\/24/')
   hosts deny = 0.0.0.0/0

   # --- Rendimiento ---
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   use sendfile = yes
   aio read size = 16384
   aio write size = 16384

   # --- Protocolo ---
   server min protocol = SMB2
   server max protocol = SMB3
   client min protocol = SMB2

   # --- Logging ---
   log file = /var/log/samba/log.%m
   max log size = 1000
   log level = 1

   # --- Opciones adicionales ---
   unix charset = UTF-8
   dos charset = CP850
   mangled names = no
   fruit:metadata = stream
   fruit:model = MacSamba
   vfs objects = fruit streams_xattr

   # --- Impresoras (deshabilitadas) ---
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
$SHARES_CONFIG
SMBEOF

    success "Archivo $SAMBA_CONF generado correctamente."
    echo ""

    # Validar configuración
    info "Validando configuración..."
    if testparm -s "$SAMBA_CONF" > /dev/null 2>&1; then
        success "Configuración válida."
    else
        warn "Posibles advertencias en la configuración:"
        testparm -s "$SAMBA_CONF" 2>&1 | tail -5
    fi
}

# ============================================================================
#  PASO 6: FIREWALL Y SERVICIOS
# ============================================================================
setup_firewall_and_services() {
    print_banner
    echo -e "${BOLD}PASO 6: Firewall y Servicios${NC}"
    separator

    # Grupo sambashare
    if ! getent group sambashare > /dev/null 2>&1; then
        groupadd sambashare
        success "Grupo 'sambashare' creado."
    fi

    # Añadir usuarios al grupo
    for user in "${SAMBA_USERS[@]}"; do
        usermod -aG sambashare "$user" 2>/dev/null || true
    done

    # Firewall
    if command -v ufw &>/dev/null; then
        info "Configurando UFW..."
        ufw allow from "$SUBNET" to any app Samba 2>/dev/null || \
        ufw allow from "$SUBNET" to any port 137,138,139,445 proto tcp 2>/dev/null || true
        ufw allow from "$SUBNET" to any port 137,138 proto udp 2>/dev/null || true
        success "Reglas de firewall añadidas para subred $SUBNET"
    else
        warn "UFW no detectado. Asegúrate de abrir los puertos 137-139, 445 manualmente."
    fi

    # Reiniciar servicios
    info "Reiniciando servicios Samba..."
    systemctl enable smbd nmbd 2>/dev/null
    systemctl restart smbd nmbd

    if systemctl is-active --quiet smbd; then
        success "smbd está activo y corriendo."
    else
        error "smbd no pudo iniciar. Revisa: journalctl -xeu smbd"
    fi

    if systemctl is-active --quiet nmbd; then
        success "nmbd está activo y corriendo."
    else
        warn "nmbd no está activo (opcional para descubrimiento NetBIOS)."
    fi

    echo ""
}

# ============================================================================
#  RESUMEN FINAL
# ============================================================================
show_summary() {
    print_banner
    echo -e "${BOLD}CONFIGURACIÓN COMPLETADA${NC}"
    separator

    echo ""
    echo -e "${GREEN}${BOLD}Servidor Samba configurado exitosamente.${NC}"
    echo ""
    echo -e "  ${BOLD}Hostname:${NC}       $(hostname)"
    echo -e "  ${BOLD}IP Local:${NC}       $LOCAL_IP"
    echo -e "  ${BOLD}Workgroup:${NC}      $WORKGROUP"
    echo -e "  ${BOLD}Subred:${NC}         $SUBNET"
    echo -e "  ${BOLD}Usuarios:${NC}       ${SAMBA_USERS[*]:-ninguno (solo público)}"
    echo -e "  ${BOLD}Carpetas:${NC}       $SHARE_COUNT compartida(s)"

    separator
    echo ""
    echo -e "${BOLD}Cómo conectarte desde otros equipos:${NC}"
    echo ""
    echo -e "  ${CYAN}Windows:${NC}"
    echo -e "    Explorador de archivos → ${BOLD}\\\\\\\\$LOCAL_IP${NC}"
    echo -e "    O: Win+R → ${BOLD}\\\\\\\\$LOCAL_IP${NC}"
    echo ""
    echo -e "  ${CYAN}Linux:${NC}"
    echo -e "    Nautilus/Nemo → ${BOLD}smb://$LOCAL_IP${NC}"
    echo -e "    Terminal: ${BOLD}smbclient -L //$LOCAL_IP -U <usuario>${NC}"
    echo ""
    echo -e "  ${CYAN}Mac:${NC}"
    echo -e "    Finder → Ir → Conectar al servidor → ${BOLD}smb://$LOCAL_IP${NC}"
    echo ""
    echo -e "  ${CYAN}Android:${NC}"
    echo -e "    Usa una app como ${BOLD}Cx File Explorer${NC} o ${BOLD}Solid Explorer${NC}"
    echo -e "    Agrega red SMB → ${BOLD}$LOCAL_IP${NC}"

    separator
    echo ""
    echo -e "${BOLD}Comandos útiles:${NC}"
    echo ""
    echo -e "  Ver carpetas compartidas:  ${CYAN}smbclient -L //$LOCAL_IP -U <usuario>${NC}"
    echo -e "  Estado del servicio:       ${CYAN}sudo systemctl status smbd${NC}"
    echo -e "  Reiniciar Samba:           ${CYAN}sudo systemctl restart smbd nmbd${NC}"
    echo -e "  Agregar usuario Samba:     ${CYAN}sudo smbpasswd -a <usuario>${NC}"
    echo -e "  Eliminar usuario Samba:    ${CYAN}sudo smbpasswd -x <usuario>${NC}"
    echo -e "  Ver conexiones activas:    ${CYAN}sudo smbstatus${NC}"
    echo -e "  Validar configuración:     ${CYAN}testparm${NC}"
    echo -e "  Ver logs:                  ${CYAN}tail -f /var/log/samba/log.*${NC}"
    echo -e "  Editar configuración:      ${CYAN}sudo nano $SAMBA_CONF${NC}"
    echo ""
    echo -e "  ${BOLD}Backup de config anterior:${NC} $SAMBA_CONF_BAK"
    echo -e "  ${BOLD}Log de instalación:${NC}        $LOG_FILE"

    separator
    echo ""

    if confirm "¿Deseas ver la configuración generada?"; then
        echo ""
        echo -e "${CYAN}--- $SAMBA_CONF ---${NC}"
        cat "$SAMBA_CONF"
        echo -e "${CYAN}--- fin ---${NC}"
    fi

    echo ""
    success "¡Listo! Tu servidor Samba está funcionando."
    echo ""
}

# ============================================================================
#  MENÚ DE ADMINISTRACIÓN (post-instalación)
# ============================================================================
admin_menu() {
    while true; do
        echo ""
        separator
        echo -e "${BOLD}MENÚ DE ADMINISTRACIÓN${NC}"
        separator
        echo "  1) Agregar nuevo usuario Samba"
        echo "  2) Eliminar usuario Samba"
        echo "  3) Agregar nueva carpeta compartida"
        echo "  4) Listar carpetas compartidas actuales"
        echo "  5) Ver conexiones activas"
        echo "  6) Reiniciar servicios Samba"
        echo "  7) Ver/editar smb.conf"
        echo "  8) Desinstalar Samba completamente"
        echo "  9) Gestionar permisos de carpeta compartida"
        echo " 10) Quitar carpeta compartida"
        echo "  0) Salir"
        echo ""
        read -rp "$(echo -e "${YELLOW}Opción: ${NC}")" admin_opt

        case $admin_opt in
            1)
                read -rp "Nombre de usuario: " au
                if ! id "$au" &>/dev/null; then
                    useradd -M -s /usr/sbin/nologin "$au"
                fi
                smbpasswd -a "$au"
                smbpasswd -e "$au"
                usermod -aG sambashare "$au" 2>/dev/null || true
                success "Usuario '$au' añadido."
                ;;
            2)
                read -rp "Nombre de usuario a eliminar: " du
                smbpasswd -x "$du" 2>/dev/null && success "Usuario '$du' eliminado de Samba." || error "No se pudo eliminar."
                ;;
            3)
                read -rp "Nombre del recurso compartido: " sn
                read -rp "Ruta del directorio: " sp
                mkdir -p "$sp"
                chmod 0775 "$sp"
                cat >> "$SAMBA_CONF" << ADDEOF

[$sn]
   comment = Agregado manualmente
   path = $sp
   browseable = yes
   read only = no
   writable = yes
   guest ok = no
   create mask = 0664
   directory mask = 0775
ADDEOF
                systemctl restart smbd nmbd
                success "Carpeta '$sn' añadida y servicios reiniciados."
                ;;
            4)
                echo ""
                info "Carpetas compartidas activas:"
                echo ""
                testparm -s 2>/dev/null | grep -E '^\[' | grep -v '\[global\]'
                ;;
            5)
                smbstatus 2>/dev/null || warn "No hay conexiones activas."
                ;;
            6)
                systemctl restart smbd nmbd
                success "Servicios reiniciados."
                ;;
            7)
                if command -v nano &>/dev/null; then
                    nano "$SAMBA_CONF"
                    testparm -s "$SAMBA_CONF" > /dev/null 2>&1 && success "Config válida." || warn "Revisa la configuración."
                    if confirm "¿Reiniciar servicios Samba?"; then
                        systemctl restart smbd nmbd
                    fi
                else
                    cat "$SAMBA_CONF"
                fi
                ;;
            8)
                if confirm "¿Seguro que deseas DESINSTALAR Samba completamente?" "n"; then
                    systemctl stop smbd nmbd 2>/dev/null
                    apt-get purge -y samba samba-common-bin
                    success "Samba desinstalado. Los datos en $SHARES_DIR permanecen."
                    exit 0
                fi
                ;;
            9)
                echo ""
                separator
                echo -e "${BOLD}GESTIÓN DE PERMISOS DE CARPETAS COMPARTIDAS${NC}"
                separator

                # ---------------------------------------------------------------
                # Función robusta: extrae un parámetro de un bloque [share]
                # Usa python3 para parsear smb.conf de forma confiable
                # ---------------------------------------------------------------
                _get_param() {
                    local share_name="$1" param_name="$2"
                    python3 - "$SAMBA_CONF" "$share_name" "$param_name" << 'PYEOF'
import sys, re
conf_file, target_section, target_param = sys.argv[1], sys.argv[2], sys.argv[3]
in_section = False
with open(conf_file, 'r') as f:
    for line in f:
        stripped = line.strip()
        m = re.match(r'^\[(.+)\]$', stripped)
        if m:
            in_section = (m.group(1) == target_section)
            continue
        if in_section and '=' in stripped:
            key, _, val = stripped.partition('=')
            if key.strip().lower() == target_param.lower():
                print(val.strip())
                sys.exit(0)
print("")
PYEOF
                }

                # Función: establecer parámetro en bloque [share]
                _set_share_param() {
                    local share="$1" param="$2" value="$3"
                    python3 - "$SAMBA_CONF" "$share" "$param" "$value" << 'PYEOF'
import sys, re
conf_file, target, param, value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(conf_file, 'r') as f:
    lines = f.readlines()
in_section = False
param_set = False
insert_after = -1
result = []
for i, line in enumerate(lines):
    stripped = line.strip()
    m = re.match(r'^\[(.+)\]$', stripped)
    if m:
        # If we were in the target section and didn't find the param, insert it
        if in_section and not param_set:
            result.append(f'   {param} = {value}\n')
            param_set = True
        in_section = (m.group(1) == target)
        result.append(line)
        continue
    if in_section and '=' in stripped:
        key = stripped.split('=', 1)[0].strip().lower()
        if key == param.lower():
            result.append(f'   {param} = {value}\n')
            param_set = True
            continue
        if key == 'path':
            insert_after = len(result)
    result.append(line)
# If still in section at EOF and param not set
if in_section and not param_set:
    result.append(f'   {param} = {value}\n')
with open(conf_file, 'w') as f:
    f.writelines(result)
PYEOF
                }

                # Función: eliminar parámetro de bloque [share]
                _del_share_param() {
                    local share="$1" param="$2"
                    python3 - "$SAMBA_CONF" "$share" "$param" << 'PYEOF'
import sys, re
conf_file, target, param = sys.argv[1], sys.argv[2], sys.argv[3]
with open(conf_file, 'r') as f:
    lines = f.readlines()
in_section = False
result = []
for line in lines:
    stripped = line.strip()
    m = re.match(r'^\[(.+)\]$', stripped)
    if m:
        in_section = (m.group(1) == target)
        result.append(line)
        continue
    if in_section and '=' in stripped:
        key = stripped.split('=', 1)[0].strip().lower()
        if key == param.lower():
            continue  # skip / delete this line
    result.append(line)
with open(conf_file, 'w') as f:
    f.writelines(result)
PYEOF
                }

                # ---------------------------------------------------------------
                # Diagnóstico de ruta: detecta problemas de acceso en filesystem
                # ---------------------------------------------------------------
                _diagnose_path() {
                    local share_path="$1" share_name="$2"
                    local issues=0

                    if [[ ! -d "$share_path" ]]; then
                        error "  La ruta '$share_path' NO EXISTE."
                        if confirm "  ¿Crear el directorio?"; then
                            mkdir -p "$share_path"
                            chmod 0775 "$share_path"
                            success "  Directorio creado: $share_path"
                        fi
                        return 1
                    fi

                    # Verificar permisos de lectura/ejecución para 'others' en toda la cadena
                    local check_path="$share_path"
                    local blocked_paths=()
                    while [[ "$check_path" != "/" ]]; do
                        local perms
                        perms=$(stat -c '%a' "$check_path" 2>/dev/null)
                        local other_perm=${perms: -1}
                        if [[ $other_perm -lt 5 ]]; then
                            blocked_paths+=("$check_path (permisos: $perms)")
                        fi
                        check_path=$(dirname "$check_path")
                    done

                    if [[ ${#blocked_paths[@]} -gt 0 ]]; then
                        warn "  Directorios BLOQUEANDO el acceso por Samba:"
                        for bp in "${blocked_paths[@]}"; do
                            echo -e "    ${RED}✗${NC} $bp"
                        done
                        issues=1
                    fi

                    # Verificar propietario vs usuario samba
                    local owner group
                    owner=$(stat -c '%U' "$share_path")
                    group=$(stat -c '%G' "$share_path")
                    local dir_perms
                    dir_perms=$(stat -c '%a' "$share_path")
                    echo -e "  ${CYAN}Propietario:${NC} $owner:$group  ${CYAN}Permisos:${NC} $dir_perms"

                    # Detectar rutas sensibles
                    case "$share_path" in
                        /root|/root/*)
                            warn "  Esta es una ruta de ROOT (/root). Por defecto tiene permisos 700."
                            warn "  Samba NO puede acceder a /root a menos que se relajen los permisos."
                            issues=1
                            ;;
                        /home/*/|/home/*)
                            local home_user
                            home_user=$(echo "$share_path" | cut -d/ -f3)
                            local home_dir="/home/$home_user"
                            local home_perms
                            home_perms=$(stat -c '%a' "$home_dir" 2>/dev/null)
                            if [[ "${home_perms: -1}" -lt 5 ]]; then
                                warn "  El home de '$home_user' ($home_dir) tiene permisos $home_perms."
                                warn "  Samba necesita al menos 'o+rx' en $home_dir para entrar."
                                issues=1
                            fi
                            ;;
                        /|/bin*|/sbin*|/usr*|/etc*|/var*|/proc*|/sys*|/dev*)
                            error "  ADVERTENCIA: Compartir rutas del sistema ($share_path) es peligroso."
                            issues=1
                            ;;
                    esac

                    return $issues
                }

                # Función: corregir permisos automáticamente
                _fix_permissions() {
                    local share_path="$1" share_name="$2" samba_user="$3"

                    echo ""
                    echo -e "${CYAN}Opciones de corrección para [$share_name] → $share_path:${NC}"
                    echo ""
                    echo "  1) Corrección segura  — chmod o+rx en la cadena + 0775 en la carpeta"
                    echo "  2) Corrección amplia  — chmod o+rx en la cadena + 0777 en la carpeta"
                    echo "  3) Reubicar carpeta   — mover a /srv/samba/ (recomendado para /root)"
                    echo "  4) No corregir"
                    echo ""
                    read -rp "$(echo -e "${YELLOW}Selecciona [1-4]: ${NC}")" fix_opt

                    case $fix_opt in
                        1)
                            # Dar o+rx a cada directorio padre
                            local fix_path="$share_path"
                            while [[ "$fix_path" != "/" ]]; do
                                chmod o+rx "$fix_path" 2>/dev/null
                                fix_path=$(dirname "$fix_path")
                            done
                            chmod 0775 "$share_path"
                            # Si hay usuario samba, darle propiedad de grupo
                            if [[ -n "$samba_user" ]]; then
                                chown -R "$samba_user:sambashare" "$share_path" 2>/dev/null || true
                            fi
                            success "Permisos corregidos (modo seguro)."
                            ;;
                        2)
                            local fix_path="$share_path"
                            while [[ "$fix_path" != "/" ]]; do
                                chmod o+rx "$fix_path" 2>/dev/null
                                fix_path=$(dirname "$fix_path")
                            done
                            chmod -R 0777 "$share_path"
                            success "Permisos corregidos (modo amplio 0777)."
                            ;;
                        3)
                            local new_path="/srv/samba/${share_name// /_}"
                            if [[ -d "$new_path" ]]; then
                                warn "$new_path ya existe."
                                read -rp "$(echo -e "${YELLOW}Nombre alternativo [${share_name}_moved]: ${NC}")" alt_name
                                alt_name="${alt_name:-${share_name}_moved}"
                                new_path="/srv/samba/${alt_name// /_}"
                            fi

                            mkdir -p "$new_path"

                            if confirm "¿Copiar el contenido de $share_path a $new_path?"; then
                                rsync -a "$share_path/" "$new_path/" 2>/dev/null || cp -a "$share_path/." "$new_path/" 2>/dev/null
                                success "Contenido copiado."
                            fi

                            chmod 0775 "$new_path"
                            if [[ -n "$samba_user" ]]; then
                                chown -R "$samba_user:sambashare" "$new_path" 2>/dev/null || true
                            fi

                            # Actualizar path en smb.conf
                            _set_share_param "$share_name" "path" "$new_path"
                            success "Carpeta reubicada: $share_path → $new_path"
                            success "smb.conf actualizado con la nueva ruta."
                            ;;
                        4)
                            info "Sin cambios."
                            ;;
                        *)
                            warn "Opción inválida."
                            ;;
                    esac
                }

                # ---------------------------------------------------------------
                # Listar carpetas compartidas con datos reales
                # ---------------------------------------------------------------
                mapfile -t SHARE_NAMES < <(grep -oP '(?<=^\[)[^\]]+' "$SAMBA_CONF" | grep -v '^global$')

                if [[ ${#SHARE_NAMES[@]} -eq 0 ]]; then
                    warn "No hay carpetas compartidas configuradas."
                    continue
                fi

                echo ""
                echo -e "${CYAN}Carpetas compartidas disponibles:${NC}"
                echo ""

                declare -a SHARE_PATHS=()
                for i in "${!SHARE_NAMES[@]}"; do
                    SN="${SHARE_NAMES[$i]}"
                    SP=$(_get_param "$SN" "path")
                    RO=$(_get_param "$SN" "read only")
                    WR=$(_get_param "$SN" "writable")
                    GO=$(_get_param "$SN" "guest ok")
                    VU=$(_get_param "$SN" "valid users")
                    WL=$(_get_param "$SN" "write list")
                    CM=$(_get_param "$SN" "create mask")
                    DM=$(_get_param "$SN" "directory mask")
                    SHARE_PATHS+=("$SP")

                    # Estado de permisos
                    if [[ "$WR" == "yes" ]]; then
                        PERM_LABEL="${GREEN}Lectura/Escritura${NC}"
                    elif [[ "$RO" == "yes" ]]; then
                        PERM_LABEL="${YELLOW}Solo Lectura${NC}"
                    else
                        PERM_LABEL="${BLUE}Predeterminado (R/W)${NC}"
                    fi

                    # Estado de acceso
                    if [[ "$GO" == "yes" ]]; then
                        ACCESS_LABEL="${CYAN}Público${NC}"
                    else
                        ACCESS_LABEL="${RED}Privado${NC}"
                    fi

                    # Estado del filesystem
                    FS_STATUS=""
                    if [[ -z "$SP" ]]; then
                        FS_STATUS="${RED}✗ SIN RUTA CONFIGURADA${NC}"
                    elif [[ ! -d "$SP" ]]; then
                        FS_STATUS="${RED}✗ DIRECTORIO NO EXISTE${NC}"
                    else
                        FS_PERMS=$(stat -c '%a' "$SP" 2>/dev/null || echo "???")
                        FS_OWNER=$(stat -c '%U:%G' "$SP" 2>/dev/null || echo "???")
                        # Verificar acceso transversal
                        local check="$SP" blocked=false
                        while [[ "$check" != "/" ]]; do
                            local op=${check##*/}
                            local p=$(stat -c '%a' "$check" 2>/dev/null)
                            if [[ -n "$p" && "${p: -1}" -lt 5 ]]; then
                                blocked=true
                                break
                            fi
                            check=$(dirname "$check")
                        done
                        if $blocked; then
                            FS_STATUS="${RED}✗ BLOQUEADO${NC} ($FS_OWNER $FS_PERMS)"
                        else
                            FS_STATUS="${GREEN}✓ OK${NC} ($FS_OWNER $FS_PERMS)"
                        fi
                    fi

                    echo -e "  ${BOLD}$((i+1)))${NC} [$SN]"
                    echo -e "     Ruta:       ${BOLD}${SP:-<no definida>}${NC}"
                    echo -e "     Samba:      $PERM_LABEL | $ACCESS_LABEL"
                    echo -e "     Filesystem: $FS_STATUS"
                    echo -e "     Máscaras:   archivos=${CM:-defecto} directorios=${DM:-defecto}"
                    [[ -n "$VU" ]] && echo -e "     Usuarios:   $VU"
                    [[ -n "$WL" ]] && echo -e "     Escritura:  $WL"
                    echo ""
                done

                echo ""
                echo -e "  ${BOLD}d)${NC} Diagnosticar y reparar TODAS las carpetas"
                echo -e "  ${BOLD}0)${NC} Volver"
                echo ""
                read -rp "$(echo -e "${YELLOW}Selecciona carpeta [1-${#SHARE_NAMES[@]}], 'd' para diagnosticar todo, 0=volver: ${NC}")" SHARE_SEL

                if [[ "$SHARE_SEL" == "0" || -z "$SHARE_SEL" ]]; then
                    continue
                fi

                # Diagnóstico masivo
                if [[ "${SHARE_SEL,,}" == "d" ]]; then
                    echo ""
                    separator
                    echo -e "${BOLD}DIAGNÓSTICO COMPLETO DE CARPETAS${NC}"
                    separator
                    SAMBA_FIRST_USER=$(pdbedit -L 2>/dev/null | head -1 | cut -d: -f1)
                    for i in "${!SHARE_NAMES[@]}"; do
                        SN="${SHARE_NAMES[$i]}"
                        SP="${SHARE_PATHS[$i]}"
                        echo ""
                        echo -e "${BOLD}[$SN] → $SP${NC}"
                        if _diagnose_path "$SP" "$SN"; then
                            success "  Sin problemas detectados."
                        else
                            if confirm "  ¿Corregir permisos de [$SN]?"; then
                                _fix_permissions "$SP" "$SN" "$SAMBA_FIRST_USER"
                            fi
                        fi
                    done
                    echo ""
                    if confirm "¿Reiniciar servicios Samba?"; then
                        systemctl restart smbd nmbd
                        success "Servicios reiniciados."
                    fi
                    continue
                fi

                # Selección individual
                SHARE_IDX=$((SHARE_SEL - 1))
                if [[ $SHARE_IDX -lt 0 || $SHARE_IDX -ge ${#SHARE_NAMES[@]} ]]; then
                    warn "Selección fuera de rango."
                    continue
                fi

                TARGET_SHARE="${SHARE_NAMES[$SHARE_IDX]}"
                TARGET_PATH="${SHARE_PATHS[$SHARE_IDX]}"

                echo ""
                separator
                echo -e "${BOLD}Modificando: [$TARGET_SHARE] → $TARGET_PATH${NC}"
                separator

                # Diagnóstico automático al seleccionar
                echo ""
                echo -e "${CYAN}Diagnóstico del filesystem:${NC}"
                if ! _diagnose_path "$TARGET_PATH" "$TARGET_SHARE"; then
                    SAMBA_FIRST_USER=$(pdbedit -L 2>/dev/null | head -1 | cut -d: -f1)
                    if confirm "¿Corregir permisos antes de continuar?"; then
                        _fix_permissions "$TARGET_PATH" "$TARGET_SHARE" "$SAMBA_FIRST_USER"
                        # Re-read path in case it was relocated
                        TARGET_PATH=$(_get_param "$TARGET_SHARE" "path")
                    fi
                else
                    success "Filesystem OK."
                fi

                echo ""
                echo -e "${CYAN}¿Qué deseas cambiar?${NC}"
                echo ""
                echo "  a) Modo de acceso (lectura/escritura/ambos/total)"
                echo "  b) Tipo de autenticación (público o privado)"
                echo "  c) Usuarios válidos / lista de escritura"
                echo "  d) Máscaras de permisos (archivos y directorios)"
                echo "  e) Aplicar perfil completo predefinido"
                echo "  f) Volver"
                echo ""
                read -rp "$(echo -e "${YELLOW}Opción [a-f]: ${NC}")" perm_action

                case $perm_action in
                    a|A)
                        echo ""
                        echo -e "${CYAN}Modo de acceso para [$TARGET_SHARE]:${NC}"
                        echo ""
                        echo "  1) Solo lectura        — nadie puede modificar archivos"
                        echo "  2) Solo escritura       — pueden crear/modificar, lectura por write list"
                        echo "  3) Lectura y escritura  — acceso normal, crear y leer archivos"
                        echo "  4) Acceso total         — lectura, escritura, eliminar, sin restricciones"
                        echo ""
                        read -rp "$(echo -e "${YELLOW}Selecciona [1-4]: ${NC}")" access_mode

                        case $access_mode in
                            1)
                                _set_share_param "$TARGET_SHARE" "read only" "yes"
                                _set_share_param "$TARGET_SHARE" "writable" "no"
                                _del_share_param "$TARGET_SHARE" "write list"
                                success "[$TARGET_SHARE] → Solo Lectura"
                                ;;
                            2)
                                _set_share_param "$TARGET_SHARE" "read only" "yes"
                                _set_share_param "$TARGET_SHARE" "writable" "no"
                                SAMBA_ALL=$(pdbedit -L 2>/dev/null | cut -d: -f1 | tr '\n' ' ')
                                _set_share_param "$TARGET_SHARE" "write list" "${SAMBA_ALL% }"
                                success "[$TARGET_SHARE] → Solo Escritura (write list: $SAMBA_ALL)"
                                ;;
                            3)
                                _set_share_param "$TARGET_SHARE" "read only" "no"
                                _set_share_param "$TARGET_SHARE" "writable" "yes"
                                _del_share_param "$TARGET_SHARE" "write list"
                                success "[$TARGET_SHARE] → Lectura y Escritura"
                                ;;
                            4)
                                _set_share_param "$TARGET_SHARE" "read only" "no"
                                _set_share_param "$TARGET_SHARE" "writable" "yes"
                                _set_share_param "$TARGET_SHARE" "create mask" "0777"
                                _set_share_param "$TARGET_SHARE" "directory mask" "0777"
                                _set_share_param "$TARGET_SHARE" "force create mode" "0777"
                                _set_share_param "$TARGET_SHARE" "force directory mode" "0777"
                                _del_share_param "$TARGET_SHARE" "write list"
                                _del_share_param "$TARGET_SHARE" "valid users"
                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0777 "$TARGET_PATH"
                                fi
                                success "[$TARGET_SHARE] → Acceso Total (0777, sin restricciones)"
                                ;;
                            *) warn "Opción inválida."; continue ;;
                        esac
                        ;;

                    b|B)
                        echo ""
                        echo -e "${CYAN}Tipo de autenticación para [$TARGET_SHARE]:${NC}"
                        echo ""
                        echo "  1) Privado — requiere usuario y contraseña Samba"
                        echo "  2) Público — acceso libre sin credenciales (guest)"
                        echo ""
                        read -rp "$(echo -e "${YELLOW}Selecciona [1-2]: ${NC}")" auth_mode

                        case $auth_mode in
                            1)
                                _set_share_param "$TARGET_SHARE" "guest ok" "no"
                                _del_share_param "$TARGET_SHARE" "guest only"
                                _del_share_param "$TARGET_SHARE" "force user"
                                _del_share_param "$TARGET_SHARE" "force group"
                                success "[$TARGET_SHARE] → Privado (requiere credenciales)"
                                ;;
                            2)
                                _set_share_param "$TARGET_SHARE" "guest ok" "yes"
                                _set_share_param "$TARGET_SHARE" "guest only" "yes"
                                _set_share_param "$TARGET_SHARE" "force user" "nobody"
                                _set_share_param "$TARGET_SHARE" "force group" "nogroup"
                                sed -i 's/map to guest = never/map to guest = bad user/' "$SAMBA_CONF"
                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0777 "$TARGET_PATH"
                                    chown -R nobody:nogroup "$TARGET_PATH"
                                fi
                                success "[$TARGET_SHARE] → Público (acceso sin contraseña)"
                                ;;
                            *) warn "Opción inválida."; continue ;;
                        esac
                        ;;

                    c|C)
                        echo ""
                        echo -e "${CYAN}Gestión de usuarios para [$TARGET_SHARE]:${NC}"
                        echo ""
                        info "Usuarios Samba registrados:"
                        pdbedit -L 2>/dev/null | awk -F: '{print "  - " $1}' || warn "No se pudieron listar."
                        echo ""
                        echo "  1) Restringir acceso a usuarios específicos (valid users)"
                        echo "  2) Restringir escritura a usuarios específicos (write list)"
                        echo "  3) Quitar restricciones (todos los usuarios Samba tienen acceso)"
                        echo ""
                        read -rp "$(echo -e "${YELLOW}Selecciona [1-3]: ${NC}")" user_mode

                        case $user_mode in
                            1)
                                read -rp "$(echo -e "${YELLOW}Usuarios con acceso (separados por espacio): ${NC}")" vu_list
                                if [[ -n "$vu_list" ]]; then
                                    _set_share_param "$TARGET_SHARE" "valid users" "$vu_list"
                                    success "[$TARGET_SHARE] → valid users = $vu_list"
                                else
                                    warn "Lista vacía, no se modificó."
                                fi
                                ;;
                            2)
                                read -rp "$(echo -e "${YELLOW}Usuarios con permiso de escritura (separados por espacio): ${NC}")" wl_list
                                if [[ -n "$wl_list" ]]; then
                                    _set_share_param "$TARGET_SHARE" "write list" "$wl_list"
                                    _set_share_param "$TARGET_SHARE" "read only" "yes"
                                    _set_share_param "$TARGET_SHARE" "writable" "no"
                                    success "[$TARGET_SHARE] → Solo lectura + write list = $wl_list"
                                else
                                    warn "Lista vacía, no se modificó."
                                fi
                                ;;
                            3)
                                _del_share_param "$TARGET_SHARE" "valid users"
                                _del_share_param "$TARGET_SHARE" "write list"
                                success "[$TARGET_SHARE] → Sin restricciones de usuario."
                                ;;
                            *) warn "Opción inválida."; continue ;;
                        esac
                        ;;

                    d|D)
                        echo ""
                        echo -e "${CYAN}Máscaras de permisos para [$TARGET_SHARE]:${NC}"
                        echo ""
                        echo "  1) Estándar     — archivos 0664, directorios 0775"
                        echo "  2) Restringido  — archivos 0644, directorios 0755 (dueño escribe)"
                        echo "  3) Abierto      — archivos 0666, directorios 0777"
                        echo "  4) Máximo       — archivos 0777, directorios 0777 (todo permitido)"
                        echo "  5) Personalizado"
                        echo ""
                        read -rp "$(echo -e "${YELLOW}Selecciona [1-5]: ${NC}")" mask_mode

                        case $mask_mode in
                            1) FM="0664"; DM="0775" ;;
                            2) FM="0644"; DM="0755" ;;
                            3) FM="0666"; DM="0777" ;;
                            4) FM="0777"; DM="0777" ;;
                            5)
                                read -rp "$(echo -e "${YELLOW}Máscara de archivos (ej: 0664): ${NC}")" FM
                                read -rp "$(echo -e "${YELLOW}Máscara de directorios (ej: 0775): ${NC}")" DM
                                ;;
                            *) warn "Opción inválida."; continue ;;
                        esac

                        _set_share_param "$TARGET_SHARE" "create mask" "$FM"
                        _set_share_param "$TARGET_SHARE" "force create mode" "$FM"
                        _set_share_param "$TARGET_SHARE" "directory mask" "$DM"
                        _set_share_param "$TARGET_SHARE" "force directory mode" "$DM"

                        if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]] && confirm "¿Aplicar permisos recursivamente a $TARGET_PATH?"; then
                            find "$TARGET_PATH" -type d -exec chmod "$DM" {} \;
                            find "$TARGET_PATH" -type f -exec chmod "$FM" {} \;
                            success "Permisos del filesystem actualizados."
                        fi

                        success "[$TARGET_SHARE] → create mask=$FM, directory mask=$DM"
                        ;;

                    e|E)
                        echo ""
                        echo -e "${CYAN}Perfiles predefinidos para [$TARGET_SHARE]:${NC}"
                        echo ""
                        echo -e "  1) ${GREEN}Acceso Total${NC}        — público, R/W, 0777, sin restricciones"
                        echo -e "  2) ${YELLOW}Solo Lectura Público${NC} — público, solo lectura, 0755"
                        echo -e "  3) ${BLUE}Privado Estándar${NC}    — requiere login, R/W, 0664/0775"
                        echo -e "  4) ${RED}Privado Restringido${NC} — requiere login, solo lectura, 0644/0755"
                        echo -e "  5) ${CYAN}Privado por Usuario${NC} — login, escritura por usuario específico"
                        echo ""
                        read -rp "$(echo -e "${YELLOW}Selecciona perfil [1-5]: ${NC}")" profile

                        # Helper para aplicar perfil base
                        _apply_profile_base() {
                            local ro="$1" wr="$2" go="$3" fm="$4" dm="$5"
                            _set_share_param "$TARGET_SHARE" "read only" "$ro"
                            _set_share_param "$TARGET_SHARE" "writable" "$wr"
                            _set_share_param "$TARGET_SHARE" "guest ok" "$go"
                            _set_share_param "$TARGET_SHARE" "create mask" "$fm"
                            _set_share_param "$TARGET_SHARE" "directory mask" "$dm"
                            _set_share_param "$TARGET_SHARE" "force create mode" "$fm"
                            _set_share_param "$TARGET_SHARE" "force directory mode" "$dm"
                        }

                        case $profile in
                            1)
                                _apply_profile_base "no" "yes" "yes" "0777" "0777"
                                _set_share_param "$TARGET_SHARE" "guest only" "yes"
                                _set_share_param "$TARGET_SHARE" "force user" "nobody"
                                _set_share_param "$TARGET_SHARE" "force group" "nogroup"
                                _del_share_param "$TARGET_SHARE" "valid users"
                                _del_share_param "$TARGET_SHARE" "write list"
                                sed -i 's/map to guest = never/map to guest = bad user/' "$SAMBA_CONF"
                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0777 "$TARGET_PATH"
                                    chown -R nobody:nogroup "$TARGET_PATH"
                                    # Asegurar traversal de directorios padre
                                    local tp="$TARGET_PATH"
                                    while [[ "$tp" != "/" ]]; do
                                        chmod o+rx "$tp" 2>/dev/null
                                        tp=$(dirname "$tp")
                                    done
                                fi
                                success "[$TARGET_SHARE] → Perfil: Acceso Total"
                                ;;
                            2)
                                _apply_profile_base "yes" "no" "yes" "0644" "0755"
                                _set_share_param "$TARGET_SHARE" "guest only" "yes"
                                _set_share_param "$TARGET_SHARE" "force user" "nobody"
                                _set_share_param "$TARGET_SHARE" "force group" "nogroup"
                                _del_share_param "$TARGET_SHARE" "valid users"
                                _del_share_param "$TARGET_SHARE" "write list"
                                sed -i 's/map to guest = never/map to guest = bad user/' "$SAMBA_CONF"
                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0755 "$TARGET_PATH"
                                    chown -R nobody:nogroup "$TARGET_PATH"
                                    local tp="$TARGET_PATH"
                                    while [[ "$tp" != "/" ]]; do
                                        chmod o+rx "$tp" 2>/dev/null
                                        tp=$(dirname "$tp")
                                    done
                                fi
                                success "[$TARGET_SHARE] → Perfil: Solo Lectura Público"
                                ;;
                            3)
                                _apply_profile_base "no" "yes" "no" "0664" "0775"
                                _del_share_param "$TARGET_SHARE" "guest only"
                                _del_share_param "$TARGET_SHARE" "force user"
                                _del_share_param "$TARGET_SHARE" "force group"
                                _del_share_param "$TARGET_SHARE" "valid users"
                                _del_share_param "$TARGET_SHARE" "write list"
                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0775 "$TARGET_PATH"
                                    local tp="$TARGET_PATH"
                                    while [[ "$tp" != "/" ]]; do
                                        chmod o+rx "$tp" 2>/dev/null
                                        tp=$(dirname "$tp")
                                    done
                                fi
                                success "[$TARGET_SHARE] → Perfil: Privado Estándar"
                                ;;
                            4)
                                _apply_profile_base "yes" "no" "no" "0644" "0755"
                                _del_share_param "$TARGET_SHARE" "guest only"
                                _del_share_param "$TARGET_SHARE" "force user"
                                _del_share_param "$TARGET_SHARE" "force group"
                                _del_share_param "$TARGET_SHARE" "valid users"
                                _del_share_param "$TARGET_SHARE" "write list"
                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0755 "$TARGET_PATH"
                                    local tp="$TARGET_PATH"
                                    while [[ "$tp" != "/" ]]; do
                                        chmod o+rx "$tp" 2>/dev/null
                                        tp=$(dirname "$tp")
                                    done
                                fi
                                success "[$TARGET_SHARE] → Perfil: Privado Restringido"
                                ;;
                            5)
                                info "Usuarios Samba registrados:"
                                pdbedit -L 2>/dev/null | awk -F: '{print "  - " $1}'
                                echo ""
                                read -rp "$(echo -e "${YELLOW}Usuarios con acceso (separados por espacio): ${NC}")" vu
                                read -rp "$(echo -e "${YELLOW}De esos, ¿quiénes pueden escribir? (Enter=ninguno): ${NC}")" wl

                                _apply_profile_base "yes" "no" "no" "0664" "0775"
                                _del_share_param "$TARGET_SHARE" "guest only"
                                _del_share_param "$TARGET_SHARE" "force user"
                                _del_share_param "$TARGET_SHARE" "force group"

                                [[ -n "$vu" ]] && _set_share_param "$TARGET_SHARE" "valid users" "$vu" || _del_share_param "$TARGET_SHARE" "valid users"
                                [[ -n "$wl" ]] && _set_share_param "$TARGET_SHARE" "write list" "$wl" || _del_share_param "$TARGET_SHARE" "write list"

                                if [[ -n "$TARGET_PATH" && -d "$TARGET_PATH" ]]; then
                                    chmod -R 0775 "$TARGET_PATH"
                                    local tp="$TARGET_PATH"
                                    while [[ "$tp" != "/" ]]; do
                                        chmod o+rx "$tp" 2>/dev/null
                                        tp=$(dirname "$tp")
                                    done
                                fi
                                success "[$TARGET_SHARE] → Perfil: Privado por Usuario (valid=$vu, write=$wl)"
                                ;;
                            *) warn "Opción inválida."; continue ;;
                        esac
                        ;;

                    f|F)
                        continue
                        ;;
                    *)
                        warn "Opción inválida."
                        continue
                        ;;
                esac

                # Validar y reiniciar
                echo ""
                info "Validando configuración..."
                if testparm -s "$SAMBA_CONF" > /dev/null 2>&1; then
                    success "Configuración válida."
                else
                    warn "Posibles advertencias:"
                    testparm -s "$SAMBA_CONF" 2>&1 | tail -5
                fi

                if confirm "¿Reiniciar servicios Samba para aplicar cambios?"; then
                    systemctl restart smbd nmbd
                    success "Servicios reiniciados. Cambios aplicados."
                else
                    warn "Recuerda reiniciar Samba manualmente para aplicar los cambios."
                fi
                ;;
            10)
                echo ""
                separator
                echo -e "${BOLD}QUITAR CARPETA COMPARTIDA${NC}"
                separator

                # Listar shares usando python3 para parseo confiable
                mapfile -t RM_SHARES < <(grep -oP '(?<=^\[)[^\]]+' "$SAMBA_CONF" | grep -v '^global$')

                if [[ ${#RM_SHARES[@]} -eq 0 ]]; then
                    warn "No hay carpetas compartidas configuradas."
                    continue
                fi

                echo ""
                echo -e "${CYAN}Carpetas compartidas activas:${NC}"
                echo ""
                for i in "${!RM_SHARES[@]}"; do
                    SN="${RM_SHARES[$i]}"
                    SP=$(python3 -c "
import sys, re
in_s = False
with open('$SAMBA_CONF') as f:
    for l in f:
        s = l.strip()
        m = re.match(r'^\[(.+)\]$', s)
        if m:
            in_s = (m.group(1) == '$SN')
            continue
        if in_s and '=' in s:
            k, _, v = s.partition('=')
            if k.strip().lower() == 'path':
                print(v.strip())
                sys.exit(0)
print('<sin ruta>')
" 2>/dev/null)
                    echo -e "  ${BOLD}$((i+1)))${NC} [$SN] → $SP"
                done

                echo ""
                echo -e "  ${BOLD}a)${NC} Quitar TODAS las carpetas compartidas"
                echo -e "  ${BOLD}0)${NC} Volver"
                echo ""
                read -rp "$(echo -e "${YELLOW}Selecciona la carpeta a quitar [1-${#RM_SHARES[@]}], 'a'=todas, 0=volver: ${NC}")" RM_SEL

                if [[ "$RM_SEL" == "0" || -z "$RM_SEL" ]]; then
                    continue
                fi

                # Quitar todas
                if [[ "${RM_SEL,,}" == "a" ]]; then
                    echo ""
                    warn "Esto eliminará TODAS las carpetas compartidas de smb.conf."
                    warn "Los archivos en disco NO se borran, solo dejan de compartirse."
                    echo ""
                    if confirm "¿Estás seguro?" "n"; then
                        for SN in "${RM_SHARES[@]}"; do
                            # Eliminar bloque completo [share] del smb.conf
                            python3 - "$SAMBA_CONF" "$SN" << 'PYEOF'
import sys, re
conf_file, target = sys.argv[1], sys.argv[2]
with open(conf_file, 'r') as f:
    lines = f.readlines()
result = []
in_target = False
for line in lines:
    stripped = line.strip()
    m = re.match(r'^\[(.+)\]$', stripped)
    if m:
        if m.group(1) == target:
            in_target = True
            continue
        else:
            in_target = False
    if not in_target:
        result.append(line)
# Remove trailing blank lines left by removed block
while result and result[-1].strip() == '':
    result.pop()
result.append('\n')
with open(conf_file, 'w') as f:
    f.writelines(result)
PYEOF
                            success "[$SN] eliminada de smb.conf."
                        done

                        systemctl restart smbd nmbd
                        success "Servicios reiniciados. Ninguna carpeta se comparte ahora."
                    fi
                    continue
                fi

                # Quitar una específica
                RM_IDX=$((RM_SEL - 1))
                if [[ $RM_IDX -lt 0 || $RM_IDX -ge ${#RM_SHARES[@]} ]]; then
                    warn "Selección fuera de rango."
                    continue
                fi

                TARGET_RM="${RM_SHARES[$RM_IDX]}"
                TARGET_RM_PATH=$(python3 -c "
import sys, re
in_s = False
with open('$SAMBA_CONF') as f:
    for l in f:
        s = l.strip()
        m = re.match(r'^\[(.+)\]$', s)
        if m:
            in_s = (m.group(1) == '$TARGET_RM')
            continue
        if in_s and '=' in s:
            k, _, v = s.partition('=')
            if k.strip().lower() == 'path':
                print(v.strip())
                sys.exit(0)
print('')
" 2>/dev/null)

                echo ""
                echo -e "${BOLD}Carpeta seleccionada:${NC} [$TARGET_RM] → $TARGET_RM_PATH"
                echo ""
                warn "Esto quitará la carpeta de smb.conf (dejará de compartirse)."
                warn "Los archivos en disco NO se borran."
                echo ""

                echo -e "${CYAN}¿Qué deseas hacer?${NC}"
                echo ""
                echo "  1) Solo dejar de compartir (quitar de smb.conf)"
                echo "  2) Dejar de compartir Y eliminar archivos del disco"
                echo "  3) Cancelar"
                echo ""
                read -rp "$(echo -e "${YELLOW}Selecciona [1-3]: ${NC}")" rm_action

                case $rm_action in
                    1|2)
                        # Eliminar bloque del smb.conf
                        python3 - "$SAMBA_CONF" "$TARGET_RM" << 'PYEOF'
import sys, re
conf_file, target = sys.argv[1], sys.argv[2]
with open(conf_file, 'r') as f:
    lines = f.readlines()
result = []
in_target = False
for line in lines:
    stripped = line.strip()
    m = re.match(r'^\[(.+)\]$', stripped)
    if m:
        if m.group(1) == target:
            in_target = True
            continue
        else:
            in_target = False
    if not in_target:
        result.append(line)
# Clean trailing blanks
while result and result[-1].strip() == '':
    result.pop()
result.append('\n')
with open(conf_file, 'w') as f:
    f.writelines(result)
PYEOF
                        success "[$TARGET_RM] eliminada de smb.conf."

                        if [[ "$rm_action" == "2" ]]; then
                            if [[ -n "$TARGET_RM_PATH" && -d "$TARGET_RM_PATH" ]]; then
                                # Proteger rutas del sistema
                                case "$TARGET_RM_PATH" in
                                    /|/root|/home|/home/*|/etc*|/var*|/usr*|/bin*|/sbin*|/boot*|/proc*|/sys*|/dev*)
                                        error "No se permite eliminar rutas del sistema: $TARGET_RM_PATH"
                                        warn "Solo se quitó la compartición. Los archivos permanecen intactos."
                                        ;;
                                    *)
                                        echo ""
                                        echo -e "${RED}${BOLD}ATENCIÓN: Esto eliminará permanentemente:${NC}"
                                        echo -e "  ${RED}$TARGET_RM_PATH${NC}"
                                        du -sh "$TARGET_RM_PATH" 2>/dev/null | awk '{print "  Tamaño: " $1}'
                                        find "$TARGET_RM_PATH" -type f 2>/dev/null | wc -l | awk '{print "  Archivos: " $1}'
                                        echo ""
                                        read -rp "$(echo -e "${RED}Escribe 'ELIMINAR' para confirmar: ${NC}")" confirm_delete
                                        if [[ "$confirm_delete" == "ELIMINAR" ]]; then
                                            rm -rf "$TARGET_RM_PATH"
                                            success "Directorio $TARGET_RM_PATH eliminado del disco."
                                        else
                                            info "Eliminación de archivos cancelada. Solo se quitó la compartición."
                                        fi
                                        ;;
                                esac
                            else
                                warn "La ruta '$TARGET_RM_PATH' no existe o no es un directorio."
                            fi
                        fi

                        # Validar config
                        info "Validando configuración..."
                        if testparm -s "$SAMBA_CONF" > /dev/null 2>&1; then
                            success "Configuración válida."
                        else
                            warn "Posibles advertencias:"
                            testparm -s "$SAMBA_CONF" 2>&1 | tail -5
                        fi

                        if confirm "¿Reiniciar servicios Samba?"; then
                            systemctl restart smbd nmbd
                            success "Servicios reiniciados."
                        fi
                        ;;
                    3|*)
                        info "Operación cancelada."
                        ;;
                esac
                ;;
            0)
                echo -e "${GREEN}¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                warn "Opción inválida."
                ;;
        esac
    done
}

# ============================================================================
#  MAIN
# ============================================================================
main() {
    check_root

    # Si Samba ya está configurado, ofrecer menú admin
    if dpkg -l | grep -q "^ii.*samba " && [[ -f "$SAMBA_CONF" ]] && grep -q "Generado automáticamente" "$SAMBA_CONF" 2>/dev/null; then
        print_banner
        echo -e "${GREEN}Samba ya está configurado en este servidor.${NC}"
        echo ""
        echo "  1) Reinstalar / Reconfigurar desde cero"
        echo "  2) Abrir menú de administración"
        echo "  0) Salir"
        echo ""
        read -rp "$(echo -e "${YELLOW}Opción: ${NC}")" main_opt
        case $main_opt in
            1) ;;  # continúa con la instalación
            2) admin_menu; exit 0 ;;
            0) exit 0 ;;
            *) admin_menu; exit 0 ;;
        esac
    fi

    install_samba
    configure_network
    manage_users
    configure_shares
    generate_config
    setup_firewall_and_services
    show_summary

    if confirm "¿Deseas abrir el menú de administración?"; then
        admin_menu
    fi
}

main "$@"
