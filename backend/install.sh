#!/bin/sh
# ============================================================================
#  WhatsApp Sticker Backend - Installer per OpenWrt (aarch64)
#  Target: Xiaomi AX3600 / IPQ8071A / OpenWrt 24.10.0
# ============================================================================

set -e

APP_NAME="go-whatsapp-web-multidevice"
INSTALL_DIR="/opt/whatsapp-backend"
SERVICE_NAME="whatsapp-api"
GITHUB_REPO="aldinokemal/go-whatsapp-web-multidevice"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  WhatsApp Sticker API - OpenWrt Installer     ║"
echo "║  Target: aarch64 (Xiaomi AX3600)              ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# ── Pre-flight checks ──
info "Verifica architettura..."
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    warn "Architettura rilevata: $ARCH (atteso: aarch64)"
    echo "Continuare comunque? (y/N)"
    read -r ans
    [ "$ans" != "y" ] && exit 1
fi

info "Verifica spazio su disco..."
FREE_KB=$(df /opt 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
if [ "$FREE_KB" -lt 50000 ] 2>/dev/null; then
    warn "Spazio libero: ${FREE_KB}KB. Consigliati almeno 50MB."
    echo "Il backend + dipendenze richiedono ~30-50MB."
    echo "Continuare? (y/N)"
    read -r ans
    [ "$ans" != "y" ] && exit 1
fi

# ── Installazione dipendenze ──
info "Aggiornamento lista pacchetti..."
opkg update || warn "opkg update fallito, continuo..."

info "Installazione dipendenze necessarie..."
for pkg in ca-certificates ca-bundle curl wget; do
    opkg list-installed | grep -q "^$pkg " || {
        log "Installazione $pkg..."
        opkg install "$pkg" || warn "$pkg non installato"
    }
done

# ── Creazione directory ──
info "Creazione directory di installazione..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data"
cd "$INSTALL_DIR"

# ── Download del binary ──
info "Ricerca ultima release su GitHub..."

# Determina l'URL del binary
LATEST_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DOWNLOAD_URL=""

if command -v curl >/dev/null 2>&1; then
    RELEASE_JSON=$(curl -sL "$LATEST_URL")
elif command -v wget >/dev/null 2>&1; then
    RELEASE_JSON=$(wget -qO- "$LATEST_URL")
else
    err "Né curl né wget trovati. Installa almeno uno dei due."
fi

# Cerca binary linux-arm64
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url"[^"]*linux[^"]*arm64[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    # Prova con aarch64
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url"[^"]*linux[^"]*aarch64[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    warn "Binary pre-compilato per arm64 non trovato nell'ultima release."
    echo ""
    echo "Opzioni disponibili:"
    echo "  1) Cross-compilare da un altro PC (vedi README)"
    echo "  2) Scaricare e compilare manualmente"
    echo ""
    info "Per cross-compilare da un PC con Go installato:"
    echo "  GOOS=linux GOARCH=arm64 go build -o whatsapp-api ./src"
    echo "  scp whatsapp-api root@<router-ip>:${INSTALL_DIR}/"
    echo ""

    echo "Hai già il binary compilato in ${INSTALL_DIR}/whatsapp-api? (y/N)"
    read -r ans
    if [ "$ans" != "y" ]; then
        info "Creazione script di cross-compilazione..."
        cat > "${INSTALL_DIR}/cross-compile.sh" << 'CROSSEOF'
#!/bin/bash
# Esegui questo su un PC con Go >= 1.21
set -e
echo "Clonazione repository..."
git clone https://github.com/aldinokemal/go-whatsapp-web-multidevice.git /tmp/wa-build
cd /tmp/wa-build
echo "Cross-compilazione per linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o whatsapp-api ./src
echo "Binary pronto: /tmp/wa-build/whatsapp-api"
echo "Copia sul router con: scp /tmp/wa-build/whatsapp-api root@<ROUTER_IP>:/opt/whatsapp-backend/"
CROSSEOF
        chmod +x "${INSTALL_DIR}/cross-compile.sh"
        log "Script cross-compile.sh creato in ${INSTALL_DIR}/"
        echo ""
        info "Dopo aver copiato il binary, riesegui questo script."
        exit 0
    fi
else
    info "Download binary: $DOWNLOAD_URL"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "${INSTALL_DIR}/whatsapp-api" "$DOWNLOAD_URL"
    else
        wget -O "${INSTALL_DIR}/whatsapp-api" "$DOWNLOAD_URL"
    fi
fi

# ── Verifica e permessi binary ──
if [ ! -f "${INSTALL_DIR}/whatsapp-api" ]; then
    err "Binary non trovato in ${INSTALL_DIR}/whatsapp-api"
fi

chmod +x "${INSTALL_DIR}/whatsapp-api"
log "Binary installato: ${INSTALL_DIR}/whatsapp-api"

# ── File di configurazione ──
info "Creazione configurazione..."
if [ ! -f "${INSTALL_DIR}/.env" ]; then
    cat > "${INSTALL_DIR}/.env" << 'ENVEOF'
# WhatsApp API Configuration
# Porta del server API
APP_PORT=3000

# Indirizzo di ascolto (0.0.0.0 = tutte le interfacce)
APP_HOST=0.0.0.0

# Debug mode
APP_DEBUG=false

# Percorso database SQLite per sessioni
APP_DB_PATH=/opt/whatsapp-backend/data/whatsapp.db

# Auto-reply (opzionale)
APP_AUTOREPLY=

# Webhook URL (opzionale)
APP_WEBHOOK_URL=

# Dimensione massima upload (MB)
APP_MAX_FILE_SIZE=50

# Basic auth (opzionale, consigliato se esposto su internet)
APP_BASIC_AUTH_USER=
APP_BASIC_AUTH_PASS=
ENVEOF
    log "File .env creato"
else
    warn "File .env già esistente, non sovrascritto"
fi

# ── Init.d service ──
info "Installazione servizio OpenWrt..."
cat > "/etc/init.d/${SERVICE_NAME}" << INITEOF
#!/bin/sh /etc/rc.common
# WhatsApp Sticker API Service

START=99
STOP=10
USE_PROCD=1

PROG="${INSTALL_DIR}/whatsapp-api"
PIDFILE="/var/run/${SERVICE_NAME}.pid"

start_service() {
    logger -t "${SERVICE_NAME}" "Avvio WhatsApp API..."

    # Carica variabili ambiente
    if [ -f "${INSTALL_DIR}/.env" ]; then
        . "${INSTALL_DIR}/.env" 2>/dev/null || true
        export \$(grep -v '^#' "${INSTALL_DIR}/.env" | grep '=' | cut -d= -f1)
    fi

    procd_open_instance
    procd_set_param command \$PROG
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile \$PIDFILE
    procd_set_param env HOME="${INSTALL_DIR}" APP_PORT="\${APP_PORT:-3000}"
    procd_close_instance

    logger -t "${SERVICE_NAME}" "WhatsApp API avviato sulla porta \${APP_PORT:-3000}"
}

stop_service() {
    logger -t "${SERVICE_NAME}" "Arresto WhatsApp API..."
}

reload_service() {
    stop
    start
}
INITEOF

chmod +x "/etc/init.d/${SERVICE_NAME}"
log "Servizio init.d installato"

# ── Firewall ──
info "Configurazione firewall (porta 3000)..."
FIREWALL_RULE_EXISTS=$(uci show firewall 2>/dev/null | grep "whatsapp_api" || true)
if [ -z "$FIREWALL_RULE_EXISTS" ]; then
    uci add firewall rule >/dev/null
    uci set firewall.@rule[-1].name='WhatsApp-API'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest_port='3000'
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].target='ACCEPT'
    uci commit firewall
    /etc/init.d/firewall reload 2>/dev/null || true
    log "Regola firewall aggiunta (LAN → porta 3000)"
else
    warn "Regola firewall già presente"
fi

# ── CORS config note ──
info "Nota CORS: il backend deve accettare richieste cross-origin."
info "Se usi il Cloudflare Worker come proxy, i CORS sono gestiti lì."

# ── Abilitazione e avvio ──
echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  Installazione completata!                    ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
log "Directory: ${INSTALL_DIR}"
log "Servizio: /etc/init.d/${SERVICE_NAME}"
log "Config: ${INSTALL_DIR}/.env"
echo ""

echo "Comandi utili:"
echo "  Avvio:     /etc/init.d/${SERVICE_NAME} start"
echo "  Stop:      /etc/init.d/${SERVICE_NAME} stop"
echo "  Restart:   /etc/init.d/${SERVICE_NAME} restart"
echo "  Auto-boot: /etc/init.d/${SERVICE_NAME} enable"
echo "  Log:       logread -e ${SERVICE_NAME}"
echo ""

echo "Avviare il servizio e abilitare l'autostart ora? (Y/n)"
read -r ans
if [ "$ans" != "n" ]; then
    /etc/init.d/${SERVICE_NAME} enable
    /etc/init.d/${SERVICE_NAME} start
    log "Servizio avviato e abilitato!"
    echo ""
    info "API disponibile su: http://$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1'):3000"
    info "Configura questo URL nella PWA (tab Config)"
else
    info "Puoi avviarlo manualmente con: /etc/init.d/${SERVICE_NAME} start"
fi

echo ""
log "Setup completato. Buon divertimento! 🎉"
