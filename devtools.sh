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
section() { echo -e "\n${BLUE}${BOLD}━━━ $1 ━━━${NC}"; }

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

[ "$EUID" -ne 0 ] && error "Ejecuta como root: sudo bash install_devtools.sh"

echo -e "\n${BOLD}${CYAN}"
echo "  ██████╗ ███████╗██╗   ██╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗"
echo "  ██╔══██╗██╔════╝██║   ██║    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝"
echo "  ██║  ██║█████╗  ██║   ██║       ██║   ██║   ██║██║   ██║██║     ███████╗"
echo "  ██║  ██║██╔══╝  ╚██╗ ██╔╝       ██║   ██║   ██║██║   ██║██║     ╚════██║"
echo "  ██████╔╝███████╗ ╚████╔╝        ██║   ╚██████╔╝╚██████╔╝███████╗███████║"
echo "  ╚═════╝ ╚══════╝  ╚═══╝         ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝"
echo -e "${NC}"
echo -e "  ${BOLD}Entorno de Desarrollo Completo - Ubuntu 24.04${NC}"
echo -e "  Usuario: ${CYAN}${REAL_USER}${NC} | Home: ${CYAN}${REAL_HOME}${NC}\n"
echo -e "  Instalando: Python · Homebrew · Node.js · npm · Rust · Build Tools · Docker\n"

# ─── RESUMEN PREVIO ───────────────────────────────────────────
section "Verificación del sistema"
OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
ARCH=$(uname -m)
RAM=$(free -h | awk '/^Mem:/ {print $2}')
DISK=$(df -h / | awk 'NR==2 {print $4}')
info "Sistema  : $OS"
info "Arquitectura: $ARCH"
info "RAM      : $RAM"
info "Disco libre : $DISK"

# ─── 1. PAQUETES BASE Y BUILD TOOLS ───────────────────────────
section "1/7 · Paquetes base y herramientas de compilación"
info "Actualizando sistema..."
apt-get update -qq && apt-get upgrade -y -qq
info "Instalando build-essential y dependencias..."
apt-get install -y -qq \
    build-essential \
    gcc g++ make cmake \
    libssl-dev libffi-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev \
    libncursesw5-dev libgdbm-dev libnss3-dev \
    liblzma-dev tk-dev uuid-dev \
    curl wget git unzip zip \
    jq htop tree vim nano \
    ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https \
    pkg-config autoconf automake libtool \
    libxml2-dev libxslt1-dev \
    net-tools iputils-ping dnsutils \
    > /dev/null 2>&1
log "Build tools y paquetes base instalados"

# ─── 2. PYTHON ────────────────────────────────────────────────
section "2/7 · Python"
info "Instalando Python 3 y herramientas..."
apt-get install -y -qq \
    python3 python3-pip python3-venv \
    python3-dev python3-setuptools python3-wheel \
    python3-full \
    > /dev/null 2>&1

# pip actualizado
sudo -u "$REAL_USER" pip3 install --upgrade pip --break-system-packages > /dev/null 2>&1 || true

# pipx para herramientas globales
apt-get install -y -qq pipx > /dev/null 2>&1 || true
sudo -u "$REAL_USER" pipx ensurepath > /dev/null 2>&1 || true

# pyenv para manejar múltiples versiones de Python
info "Instalando pyenv..."
if [ ! -d "$REAL_HOME/.pyenv" ]; then
    sudo -u "$REAL_USER" git clone https://github.com/pyenv/pyenv.git "$REAL_HOME/.pyenv" --quiet
    # Agregar pyenv al bashrc/zshrc del usuario
    for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
        if [ -f "$RC" ]; then
            grep -q 'pyenv' "$RC" || cat >> "$RC" << 'PYENV_EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
PYENV_EOF
        fi
    done
    log "pyenv instalado"
else
    warn "pyenv ya existe, omitiendo"
fi

PYTHON_VER=$(python3 --version 2>&1)
log "Python instalado: $PYTHON_VER"

# ─── 3. HOMEBREW ──────────────────────────────────────────────
section "3/7 · Homebrew"
if command -v brew &>/dev/null; then
    warn "Homebrew ya está instalado, actualizando..."
    sudo -u "$REAL_USER" brew update > /dev/null 2>&1 || true
else
    info "Instalando Homebrew (puede tardar unos minutos)..."
    sudo -u "$REAL_USER" bash -c \
        'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
        > /dev/null 2>&1

    # Agregar brew al PATH
    BREW_PREFIX=""
    if [ -d "/home/linuxbrew/.linuxbrew" ]; then
        BREW_PREFIX="/home/linuxbrew/.linuxbrew"
    elif [ -d "$REAL_HOME/.linuxbrew" ]; then
        BREW_PREFIX="$REAL_HOME/.linuxbrew"
    fi

    if [ -n "$BREW_PREFIX" ]; then
        for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc" "$REAL_HOME/.profile"; do
            if [ -f "$RC" ]; then
                grep -q 'linuxbrew\|homebrew' "$RC" || cat >> "$RC" << BREW_EOF

# Homebrew
eval "\$($BREW_PREFIX/bin/brew shellenv)"
BREW_EOF
            fi
        done
        eval "$($BREW_PREFIX/bin/brew shellenv)" 2>/dev/null || true
        log "Homebrew instalado en: $BREW_PREFIX"
    fi
fi
brew --version 2>/dev/null && log "Homebrew listo" || warn "Homebrew instalado pero reinicia sesión para usarlo"

# ─── 4. NODE.JS Y NPM ─────────────────────────────────────────
section "4/7 · Node.js y npm"
info "Instalando NVM (Node Version Manager)..."
NVM_DIR="$REAL_HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    sudo -u "$REAL_USER" bash -c \
        'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash' \
        > /dev/null 2>&1
    log "NVM instalado"
else
    warn "NVM ya existe"
fi

# Cargar nvm y instalar Node LTS
info "Instalando Node.js LTS..."
sudo -u "$REAL_USER" bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts > /dev/null 2>&1
    nvm use --lts > /dev/null 2>&1
    nvm alias default "lts/*" > /dev/null 2>&1
' 2>/dev/null

# Verificar versión de Node instalada
NODE_VER=$(sudo -u "$REAL_USER" bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    node --version 2>/dev/null || echo "instalado"
')
NPM_VER=$(sudo -u "$REAL_USER" bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    npm --version 2>/dev/null || echo "instalado"
')

log "Node.js instalado: $NODE_VER"
log "npm instalado: v$NPM_VER"

# Paquetes npm globales útiles
info "Instalando paquetes npm globales..."
sudo -u "$REAL_USER" bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    npm install -g pm2 typescript ts-node nodemon yarn pnpm > /dev/null 2>&1
' 2>/dev/null
log "npm globals: pm2, typescript, ts-node, nodemon, yarn, pnpm"

# ─── 5. RUST ──────────────────────────────────────────────────
section "5/7 · Rust"
if command -v rustc &>/dev/null || [ -f "$REAL_HOME/.cargo/bin/rustc" ]; then
    warn "Rust ya está instalado, actualizando..."
    sudo -u "$REAL_USER" "$REAL_HOME/.cargo/bin/rustup" update > /dev/null 2>&1 || true
else
    info "Instalando Rust vía rustup..."
    sudo -u "$REAL_USER" bash -c \
        'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet' \
        > /dev/null 2>&1

    for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc" "$REAL_HOME/.profile"; do
        if [ -f "$RC" ]; then
            grep -q 'cargo' "$RC" || echo 'source "$HOME/.cargo/env"' >> "$RC"
        fi
    done
fi

RUST_VER=$(sudo -u "$REAL_USER" "$REAL_HOME/.cargo/bin/rustc" --version 2>/dev/null || echo "instalado")
log "Rust instalado: $RUST_VER"
log "Cargo disponible en: $REAL_HOME/.cargo/bin/"

# ─── 6. DOCKER ────────────────────────────────────────────────
section "6/7 · Docker y Docker Compose"
if command -v docker &>/dev/null; then
    warn "Docker ya está instalado"
    docker --version
else
    info "Agregando repositorio oficial de Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    info "Instalando Docker Engine..."
    apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        > /dev/null 2>&1

    systemctl enable docker > /dev/null 2>&1
    systemctl start docker

    # Agregar usuario al grupo docker (sin sudo)
    usermod -aG docker "$REAL_USER"
    log "Usuario '${REAL_USER}' agregado al grupo docker"
fi

DOCKER_VER=$(docker --version 2>/dev/null)
COMPOSE_VER=$(docker compose version 2>/dev/null)
log "Docker listo: $DOCKER_VER"
log "Compose listo: $COMPOSE_VER"

# ─── 7. HERRAMIENTAS EXTRA ────────────────────────────────────
section "7/7 · Herramientas adicionales de desarrollo"
info "Instalando herramientas extra..."
apt-get install -y -qq \
    git-lfs \
    tmux \
    neofetch \
    bat \
    ripgrep \
    fd-find \
    > /dev/null 2>&1 || true

# git-lfs
sudo -u "$REAL_USER" git lfs install > /dev/null 2>&1 || true
log "git-lfs, tmux, neofetch, bat, ripgrep, fd instalados"

# Configuración git básica (si no existe)
GIT_EMAIL=$(sudo -u "$REAL_USER" git config --global user.email 2>/dev/null || echo "")
if [ -z "$GIT_EMAIL" ]; then
    warn "Configura git después con:"
    echo -e "  ${CYAN}git config --global user.name 'Tu Nombre'${NC}"
    echo -e "  ${CYAN}git config --global user.email 'tu@email.com'${NC}"
fi

# ─── RESUMEN FINAL ────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║      ✔  INSTALACIÓN COMPLETADA EXITOSAMENTE         ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}  Herramientas instaladas:${NC}"
printf "  %-20s %s\n" "Python 3"      "$(python3 --version 2>/dev/null)"
printf "  %-20s %s\n" "pip"           "$(pip3 --version 2>/dev/null | awk '{print $1,$2}')"
printf "  %-20s %s\n" "pyenv"         "$(sudo -u $REAL_USER $REAL_HOME/.pyenv/bin/pyenv --version 2>/dev/null || echo 'instalado')"
printf "  %-20s %s\n" "Homebrew"      "$(brew --version 2>/dev/null | head -1 || echo 'instalado (reinicia sesión)')"
printf "  %-20s %s\n" "Node.js"       "$NODE_VER (via NVM)"
printf "  %-20s %s\n" "npm"           "v$NPM_VER"
printf "  %-20s %s\n" "Rust"          "$RUST_VER"
printf "  %-20s %s\n" "Docker"        "$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
printf "  %-20s %s\n" "Docker Compose" "$(docker compose version 2>/dev/null | awk '{print $4}')"
printf "  %-20s %s\n" "gcc/g++"       "$(gcc --version 2>/dev/null | head -1 | awk '{print $NF}')"
printf "  %-20s %s\n" "cmake"         "$(cmake --version 2>/dev/null | head -1 | awk '{print $3}')"

echo ""
echo -e "${YELLOW}${BOLD}  ⚠  IMPORTANTE: Cierra y abre sesión SSH para activar:${NC}"
echo -e "     • Docker sin sudo   ${CYAN}(grupo docker aplicado)${NC}"
echo -e "     • Node.js / NVM     ${CYAN}(PATH actualizado)${NC}"
echo -e "     • Homebrew          ${CYAN}(shellenv cargado)${NC}"
echo -e "     • Rust / Cargo      ${CYAN}(cargo env cargado)${NC}"
echo -e "     • pyenv             ${CYAN}(init cargado)${NC}"
echo ""
echo -e "  O ejecuta: ${CYAN}source ~/.bashrc${NC}"
echo ""
