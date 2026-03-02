# 🎨 WhatsApp Sticker Sender PWA

PWA per convertire e inviare sticker su WhatsApp, con backend self-hosted su router OpenWrt.

![Architettura](https://img.shields.io/badge/Frontend-PWA_GitHub_Pages-blue) ![Backend](https://img.shields.io/badge/Backend-OpenWrt_aarch64-green) ![Proxy](https://img.shields.io/badge/Proxy-Cloudflare_Worker-orange)

## Architettura

```
┌─────────────────────┐     ┌──────────────────────┐     ┌────────────────────────┐
│   PWA (Browser)     │────▶│  CF Worker (Proxy)   │────▶│  Router OpenWrt        │
│   GitHub Pages      │     │  CORS + forwarding   │     │  go-whatsapp-web-multi │
│                     │     │                      │     │  device API            │
│  • Image upload     │     │  (opzionale, serve   │     │                        │
│  • Paste/URL        │     │   solo se PWA HTTPS  │     │  • WhatsApp WebSocket  │
│  • Resize 512×512   │     │   e backend HTTP)    │     │  • Send sticker API    │
│  • WebP conversion  │     │                      │     │  • QR login            │
│  • GIF animate      │     └──────────────────────┘     │  • Contacts/Groups     │
└─────────────────────┘                                  └────────────────────────┘
```

## Funzionalità

- **Invio sticker** — Carica immagine → resize automatico 512×512 → conversione WebP → invio su WhatsApp
- **Formati supportati** — JPG, JPEG, PNG, WebP, GIF (anche animate)
- **Input flessibile** — Drag & drop, incolla da clipboard (Ctrl+V), upload file, URL remoto
- **Trasparenza PNG** — Preservata nella conversione
- **GIF animate** — Inviate al backend per conversione ad animated WebP
- **QR Code pairing** — Associa il dispositivo WhatsApp direttamente dalla PWA
- **Contatti e gruppi** — Seleziona destinatario dalla lista
- **PWA completa** — Installabile come app, funziona offline (UI)
- **Dati persistenti** — Configurazione salvata in IndexedDB

## Quick Start

### 1. Deploy della PWA su GitHub Pages

```bash
# Clona il repository
git clone https://github.com/<tuo-username>/whatsapp-sticker-pwa.git
cd whatsapp-sticker-pwa

# La PWA è nella cartella /docs
# Vai su Settings → Pages → Source: Deploy from branch
# Branch: main, folder: /docs
```

La PWA sarà disponibile su `https://<tuo-username>.github.io/whatsapp-sticker-pwa/`

### 2. Setup del Backend sul Router OpenWrt

#### Requisiti Hardware
| Spec | Minimo | Xiaomi AX3600 |
|------|--------|---------------|
| CPU | ARMv8 / aarch64 | ✅ Qualcomm IPQ8071A |
| RAM | 256MB | ✅ 512MB |
| Storage | 50MB liberi | ✅ 256MB flash |
| OpenWrt | 21.02+ | ✅ 24.10.0 |

#### Opzione A: Installazione automatica (sul router)

```bash
# Connettiti al router via SSH
ssh root@192.168.1.1

# Scarica ed esegui lo script di installazione
wget -O /tmp/install.sh https://raw.githubusercontent.com/<tuo-username>/whatsapp-sticker-pwa/main/backend/install.sh
chmod +x /tmp/install.sh
sh /tmp/install.sh
```

Lo script:
1. Verifica architettura aarch64
2. Installa dipendenze (`ca-certificates`, `curl`)
3. Scarica il binary pre-compilato arm64 dalla release GitHub
4. Crea configurazione `.env`
5. Installa servizio init.d con procd
6. Configura firewall (porta 3000 LAN)
7. Avvia il servizio

#### Opzione B: Cross-compilazione manuale

Se il binary pre-compilato non è disponibile, compilalo da un PC con Go:

```bash
# Sul tuo PC (Linux/Mac/Windows con Go >= 1.21)
git clone https://github.com/aldinokemal/go-whatsapp-web-multidevice.git
cd go-whatsapp-web-multidevice

# Cross-compilazione per aarch64
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o whatsapp-api ./src

# Copia sul router
scp whatsapp-api root@192.168.1.1:/opt/whatsapp-backend/
```

Poi sul router:
```bash
chmod +x /opt/whatsapp-backend/whatsapp-api

# Installa il servizio (lo script lo fa automaticamente)
sh /tmp/install.sh
```

### 3. Cloudflare Worker Proxy (opzionale)

Necessario solo se la PWA è su HTTPS (GitHub Pages) e il backend su HTTP (router LAN). Il browser blocca le richieste mixed-content.

**Se accedi alla PWA dalla LAN** puoi skipppare questo passaggio e usare direttamente `http://192.168.1.1:3000`.

#### Deploy del Worker

```bash
# Installa Wrangler CLI
npm install -g wrangler

# Login
wrangler login

# Crea il worker
cd backend
wrangler init whatsapp-proxy
# Copia il contenuto di cf-worker-proxy.js nel file src/index.js

wrangler deploy
```

Oppure tramite la dashboard Cloudflare:
1. Vai su [dash.cloudflare.com](https://dash.cloudflare.com) → Workers & Pages
2. Crea un nuovo Worker
3. Incolla il contenuto di `backend/cf-worker-proxy.js`
4. Deploy

### 4. Configurazione PWA

1. Apri la PWA nel browser
2. Vai al tab **Config**
3. Inserisci:
   - **URL Backend**: `http://192.168.1.1:3000` (o l'IP del tuo router)
   - **CF Worker Proxy**: `https://tuo-worker.workers.dev/?url=` (se necessario)
4. Salva
5. Vai al tab **Pair** → Genera QR Code → Scansiona con WhatsApp

## Gestione del Servizio

```bash
# Comandi sul router via SSH
/etc/init.d/whatsapp-api start      # Avvia
/etc/init.d/whatsapp-api stop       # Ferma
/etc/init.d/whatsapp-api restart    # Riavvia
/etc/init.d/whatsapp-api enable     # Autostart al boot
/etc/init.d/whatsapp-api disable    # Disabilita autostart

# Logs
logread -e whatsapp-api              # Vedi log
logread -f -e whatsapp-api           # Log in tempo reale

# Verifica che sia in esecuzione
ps | grep whatsapp-api
netstat -tlnp | grep 3000
```

## Configurazione Backend

Modifica `/opt/whatsapp-backend/.env`:

```env
# Porta API (default: 3000)
APP_PORT=3000

# Ascolto su tutte le interfacce
APP_HOST=0.0.0.0

# Basic auth (consigliato se esponi via CF Worker)
APP_BASIC_AUTH_USER=admin
APP_BASIC_AUTH_PASS=una-password-sicura

# Upload max (MB)
APP_MAX_FILE_SIZE=50
```

Dopo le modifiche: `/etc/init.d/whatsapp-api restart`

## Sicurezza

### Accesso LAN-only (consigliato)
Il firewall è configurato per accettare connessioni solo dalla LAN. Il backend non è esposto a internet.

### Con CF Worker Proxy
Se usi il proxy Cloudflare:
1. **Abilita Basic Auth** nel `.env` del backend
2. **Limita le origini** nel worker (`ALLOW_ALL_ORIGINS = false`)
3. Aggiungi il tuo dominio GitHub Pages in `ALLOWED_ORIGINS`

### Modifica il CF Worker per sicurezza extra

```javascript
// In cf-worker-proxy.js
const ALLOW_ALL_ORIGINS = false;
const ALLOWED_ORIGINS = [
  'https://tuo-username.github.io',
];
```

## Specifiche Sticker WhatsApp

| Proprietà | Requisito |
|-----------|-----------|
| Formato | WebP |
| Dimensioni | 512×512 pixel |
| File size | < 100KB (statici), < 500KB (animati) |
| Trasparenza | Supportata |
| Animazione | Max 10 secondi |

La PWA gestisce automaticamente il resize e la conversione per immagini statiche. Le GIF animate vengono inviate al backend per la conversione server-side.

## Struttura del Progetto

```
whatsapp-sticker-pwa/
├── docs/                    # PWA (GitHub Pages)
│   ├── index.html           # App completa (single file)
│   ├── manifest.json        # PWA manifest
│   └── sw.js                # Service Worker
├── backend/
│   ├── install.sh           # Script installazione OpenWrt
│   ├── cf-worker-proxy.js   # Cloudflare Worker CORS proxy
│   └── cross-compile.sh     # Script cross-compilazione (generato)
└── README.md
```

## Troubleshooting

### "CORS Error" nel browser
→ Usa il CF Worker proxy, oppure accedi alla PWA via HTTP (non HTTPS) dalla LAN

### Il QR code non appare
→ Verifica che il backend sia raggiungibile: `curl http://192.168.1.1:3000/app/login`

### "Binary not found" durante installazione
→ Il binary pre-compilato potrebbe non essere disponibile. Usa la cross-compilazione (Opzione B)

### Il router è lento / va in OOM
→ Il backend Go usa ~30-50MB di RAM. Con 512MB sull'AX3600 dovrebbe andare bene, ma monitora con `free -m`

### L'invio sticker fallisce
→ Verifica che il dispositivo sia ancora associato (tab Pair → Verifica stato)
→ Controlla i log: `logread -e whatsapp-api`
→ Il formato immagine potrebbe non essere supportato dal backend

### GIF animate non funzionano
→ Le GIF animate vengono inviate raw al backend che le converte. Verifica che il backend supporti la conversione (potrebbe richiedere `ffmpeg` installato sul router: `opkg install ffmpeg`)

## API Endpoints Utilizzati

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/app/login` | Genera QR code per pairing |
| POST | `/app/logout` | Disconnetti dispositivo |
| GET | `/user/info` | Info connessione |
| GET | `/user/my/contacts` | Lista contatti |
| GET | `/user/my/groups` | Lista gruppi |
| POST | `/send/image/sticker` | Invia sticker (primario) |
| POST | `/send/image` | Invia immagine/sticker (fallback) |
| POST | `/send/sticker` | Invia sticker (fallback 2) |

## License

MIT
