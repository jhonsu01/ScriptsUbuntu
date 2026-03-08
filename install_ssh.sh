#!/bin/bash
# ============================================================
# Script: install_devtools.sh
# Descripción: Instala entorno de desarrollo completo
#              Ubuntu 24.04 - Python, Brew, Node, Rust, Docker
# Uso: sudo bash install_devtools.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✘]${NC} $1"; exit 1; }
info()    { echo -e "${CYAN}[→]${NC} $1"; }
skip()    { echo -e "${YELLOW}[~]${NC} $1 (omitido, continúa...)"; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $1 ━━━${NC}"; }

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

[ "$EUID" -ne 0 ] && error "Ejecuta como root: sudo bash install_devtools.sh"

echo -e "\n${BOLD}${CYAN}  Dev Tools Installer - Ubuntu 24.04${NC}"
echo -e "  Usuario: ${CYAN}${REAL_USER}${NC} | Home: ${CYAN}${REAL_HOME}${NC}\n"
echo -e "  Instalando: Python · Homebrew · Node.js · npm · Rust · Build Tools · Docker\n"

# ─── RESUMEN PREVIO ────────────────────────────────────────────
section "Verificación del sistema"
OS=$(lsb_release -ds 2>/dev/null || echo "Ubuntu")
ARCH=$(uname -m)
RAM=$(free -h | awk '/^Mem:/ {print $2}')
DISK=$(df -h / | awk 'NR==2 {print $4}')
info "Sistema      : $OS"
info "Arquitectura : $ARCH"
info "RAM          : $RAM"
info "Disco libre  : $DISK"

# ─── 1. PAQUETES BASE Y BUILD TOOLS ───────────────────────────
section "1/7 · Paquetes base y herramientas de compilación"
info "Actualizando sistema..."
apt-get update -qq && apt-get upgrade -y -qq
info "Instalando build-essential y dependencias..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    build-essential gcc g++ make cmake \
    libssl-dev libffi-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev \
    libncursesw5-dev libgdbm-dev libnss3-dev \
    liblzma-dev tk-dev uuid-dev \
    curl wget git unzip zip \
    jq htop tree vim nano \
    ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https \
    pkg-config autoconf automake libtool \
    net-tools iputils-ping dnsutils \
    > /dev/null 2>&1
log "Build tools y paquetes base instalados"

# ─── 2. PYTHON ────────────────────────────────────────────────
section "2/7 · Python"
info "Instalando Python 3 y herramientas..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3 python3-pip python3-venv \
    python3-dev python3-setuptools python3-wheel \
    python3-full pipx \
    > /dev/null 2>&1

sudo -u "$REAL_USER" pip3 install --upgrade pip --break-system-packages > /dev/null 2>&1 || true
sudo -u "$REAL_USER" pipx ensurepath > /dev/null 2>&1 || true

# pyenv
info "Instalando pyenv..."
if [ ! -d "$REAL_HOME/.pyenv" ]; then
    sudo -u "$REAL_USER" git clone --quiet https://github.com/pyenv/pyenv.git "$REAL_HOME/.pyenv" 2>/dev/null
    for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
        [ -f "$RC" ] || continue
        grep -q 'pyenv' "$RC" && continue
        cat >> "$RC" << 'PYENV_EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
PYENV_EOF
    done
    log "pyenv instalado"
else
    warn "pyenv ya existe, omitiendo"
fi

log "Python: $(python3 --version 2>/dev/null)"

# ─── 3. HOMEBREW ──────────────────────────────────────────────
section "3/7 · Homebrew"
BREW_OK=false
BREW_PREFIX=""

# Detectar si Homebrew ya está instalado en alguna ubicación conocida
detect_brew() {
    for loc in \
        "/home/linuxbrew/.linuxbrew/bin/brew" \
        "$REAL_HOME/.linuxbrew/bin/brew" \
        "/usr/local/bin/brew" \
        "/opt/homebrew/bin/brew"; do
        [ -x "$loc" ] && echo "$loc" && return 0
    done
    command -v brew 2>/dev/null && command -v brew && return 0
    return 1
}

configure_brew_path() {
    local prefix="$1"
    info "Configurando PATH para Homebrew en: $prefix"
    local line="eval \"\$(${prefix}/bin/brew shellenv)\""

    # Agregar a todos los RC files del usuario
    for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc" "$REAL_HOME/.profile"; do
        # Crear .bashrc si no existe
        [ "$RC" = "$REAL_HOME/.bashrc" ] && touch "$RC"
        [ -f "$RC" ] || continue
        if ! grep -q 'linuxbrew\|homebrew\|brew shellenv' "$RC" 2>/dev/null; then
            printf '\n# Homebrew\n%s\n' "$line" >> "$RC"
            chown "$REAL_USER:$REAL_USER" "$RC"
            log "PATH agregado a $(basename $RC)"
        else
            warn "PATH de Homebrew ya existe en $(basename $RC)"
        fi
    done

    # Activar en la sesión actual del script
    eval "$($prefix/bin/brew shellenv)" 2>/dev/null || true
    export PATH="$prefix/bin:$prefix/sbin:$PATH"
    BREW_OK=true
}

BREW_BIN=$(detect_brew || true)

if [ -n "$BREW_BIN" ]; then
    # Homebrew ya instalado — solo asegurar PATH
    BREW_PREFIX=$(dirname "$(dirname "$BREW_BIN")")
    warn "Homebrew ya instalado en: $BREW_PREFIX"
    configure_brew_path "$BREW_PREFIX"
else
    info "Instalando Homebrew con timeout de 4 minutos..."
    BREW_EXIT=0
    timeout 240 sudo -u "$REAL_USER" bash -c \
        'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
        > /tmp/brew_install.log 2>&1 || BREW_EXIT=$?

    if [ "$BREW_EXIT" -eq 124 ]; then
        skip "Homebrew timeout — instalar manualmente luego"
    elif [ "$BREW_EXIT" -ne 0 ]; then
        skip "Homebrew falló (código $BREW_EXIT) — revisa /tmp/brew_install.log"
    else
        log "Homebrew instalado correctamente"
        # Buscar dónde quedó instalado
        BREW_BIN=$(detect_brew || true)
        if [ -n "$BREW_BIN" ]; then
            BREW_PREFIX=$(dirname "$(dirname "$BREW_BIN")")
            configure_brew_path "$BREW_PREFIX"
        else
            warn "Homebrew instalado pero no se encontró el binario"
        fi
    fi
fi

if $BREW_OK; then
    log "Homebrew: $($BREW_PREFIX/bin/brew --version 2>/dev/null | head -1)"
    log "Ejecuta 'brew' después de: source ~/.bashrc"
else
    warn "Homebrew no disponible — instalar manualmente: https://brew.sh"
    warn "Luego agrega al PATH con: eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\""
fi

# ─── 4. NODE.JS Y NPM ─────────────────────────────────────────
section "4/7 · Node.js y npm (via NVM)"
NVM_DIR="$REAL_HOME/.nvm"

if [ ! -d "$NVM_DIR" ]; then
    info "Instalando NVM..."
    sudo -u "$REAL_USER" bash -c \
        'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash' \
        > /dev/null 2>&1
    log "NVM instalado"
else
    warn "NVM ya existe"
fi

info "Instalando Node.js LTS..."
sudo -u "$REAL_USER" bash << 'NVM_EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts > /dev/null 2>&1
nvm use --lts > /dev/null 2>&1
nvm alias default "lts/*" > /dev/null 2>&1
npm install -g pm2 typescript ts-node nodemon yarn pnpm > /dev/null 2>&1
NVM_EOF

NODE_VER=$(sudo -u "$REAL_USER" bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    node --version 2>/dev/null || echo "(reinicia sesión)"
')
log "Node.js: $NODE_VER"
log "npm globals: pm2, typescript, ts-node, nodemon, yarn, pnpm"

# ─── 5. RUST ──────────────────────────────────────────────────
section "5/7 · Rust (via rustup)"
if [ -f "$REAL_HOME/.cargo/bin/rustc" ]; then
    warn "Rust ya instalado, actualizando..."
    sudo -u "$REAL_USER" "$REAL_HOME/.cargo/bin/rustup" update stable > /dev/null 2>&1 || true
else
    info "Instalando Rust..."
    sudo -u "$REAL_USER" bash -c \
        'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet' \
        > /dev/null 2>&1

    for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc" "$REAL_HOME/.profile"; do
        [ -f "$RC" ] || continue
        grep -q 'cargo' "$RC" && continue
        echo 'source "$HOME/.cargo/env"' >> "$RC"
    done
fi

RUST_VER=$(sudo -u "$REAL_USER" "$REAL_HOME/.cargo/bin/rustc" --version 2>/dev/null || echo "instalado")
log "Rust: $RUST_VER"

# ─── 6. DOCKER ────────────────────────────────────────────────
section "6/7 · Docker y Docker Compose"
if command -v docker &>/dev/null; then
    warn "Docker ya está instalado: $(docker --version)"
else
    info "Agregando repositorio oficial de Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    info "Instalando Docker Engine..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        > /dev/null 2>&1

    systemctl enable docker > /dev/null 2>&1
    systemctl start docker
    usermod -aG docker "$REAL_USER"
    log "Usuario '${REAL_USER}' agregado al grupo docker (sin sudo)"
fi

log "Docker: $(docker --version 2>/dev/null)"
log "Compose: $(docker compose version 2>/dev/null)"

# ─── 7. HERRAMIENTAS EXTRA ────────────────────────────────────
section "7/7 · Herramientas adicionales"
info "Instalando herramientas extra..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git-lfs tmux bat ripgrep fd-find neofetch \
    > /dev/null 2>&1 || true

sudo -u "$REAL_USER" git lfs install > /dev/null 2>&1 || true
log "git-lfs, tmux, bat, ripgrep, fd, neofetch instalados"

# ─── RESUMEN FINAL ─────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║      ✔  INSTALACIÓN COMPLETADA EXITOSAMENTE         ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
printf "  ${BOLD}%-22s${NC} %s\n" "Python"         "$(python3 --version 2>/dev/null)"
printf "  ${BOLD}%-22s${NC} %s\n" "pip"            "$(pip3 --version 2>/dev/null | awk '{print $1,$2}')"
printf "  ${BOLD}%-22s${NC} %s\n" "pyenv"          "instalado en ~/.pyenv"
printf "  ${BOLD}%-22s${NC} %s\n" "Homebrew"       "$( $BREW_OK && brew --version 2>/dev/null | head -1 || echo 'no instalado')"
printf "  ${BOLD}%-22s${NC} %s\n" "Node.js"        "$NODE_VER (NVM)"
printf "  ${BOLD}%-22s${NC} %s\n" "Rust"           "$RUST_VER"
printf "  ${BOLD}%-22s${NC} %s\n" "Docker"         "$(docker --version 2>/dev/null)"
printf "  ${BOLD}%-22s${NC} %s\n" "Docker Compose" "$(docker compose version 2>/dev/null)"
printf "  ${BOLD}%-22s${NC} %s\n" "gcc"            "$(gcc --version 2>/dev/null | head -1 | awk '{print $NF}')"
printf "  ${BOLD}%-22s${NC} %s\n" "cmake"          "$(cmake --version 2>/dev/null | head -1 | awk '{print $3}')"

echo ""
echo -e "${YELLOW}${BOLD}  ⚠  Cierra y abre sesión SSH para activar:${NC}"
echo -e "     • Docker sin sudo  ${CYAN}→ grupo docker aplicado${NC}"
echo -e "     • Node.js / NVM    ${CYAN}→ source ~/.bashrc${NC}"
echo -e "     • Rust / Cargo     ${CYAN}→ source ~/.bashrc${NC}"
echo -e "     • pyenv            ${CYAN}→ source ~/.bashrc${NC}"
echo ""
echo -e "  Atajo: ${CYAN}exec bash${NC}  o  ${CYAN}source ~/.bashrc${NC}"
echo ""
