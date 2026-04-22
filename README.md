# VPN Monitor pour Gluetun + qBittorrent

Surveillance automatique de Gluetun et qBittorrent avec redémarrage intelligent et intégration Dockhand optionnelle.

## Fonctionnalités

- ✅ Surveillance de l'état de Gluetun (container en cours d'exécution)
- ✅ Vérification de l'interface VPN (tun0/wg0)
- ✅ Test de connectivité VPN (IP publique)
- ✅ Surveillance de qBittorrent (container + WebUI)
- ✅ Redémarrage automatique de qBittorrent si le VPN se reconnecte
- ✅ Détection correcte des erreurs Docker
- ✅ Logs uniquement sur changements d'état (évite le spam)
- ✅ Heartbeat périodique pour confirmer que le monitoring est actif
- ✅ **Redéploiement automatique du stack via Dockhand** si qBittorrent n'existe pas

## Architecture recommandée

**Important** : Le container vpn-monitor doit être dans un **stack séparé** pour éviter qu'il se redéploie lui-même.

```
Stack 1: vpn-monitor (ce repository)
  └── vpn-monitor container

Stack 2: qbittorrent (stack surveillé)
  ├── Gluetun
  └── qBittorrent
```

## Déploiement

### Option 1 : Docker Compose (Recommandé)

```bash
# 1. Cloner ce repository
git clone https://github.com/VOTRE_USERNAME/vpn-monitor.git
cd vpn-monitor

# 2. Modifier docker-compose.monitor.yml avec votre configuration
nano docker-compose.monitor.yml

# 3. Déployer le stack
docker compose -f docker-compose.monitor.yml -p vpn-monitor up -d
```

### Option 2 : Docker Run

```bash
docker run -d \
  --name vpn-monitor \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /volume1/docker/monitor_vpn/logs:/var/log \
  -e GLUETUN_CONTAINER=Gluetun \
  -e QBITTORRENT_CONTAINER=qBittorrent \
  -e QBITTORRENT_PORT=8880 \
  -e CHECK_INTERVAL=300 \
  -e HEARTBEAT_INTERVAL=2 \
  -e TZ=Europe/Paris \
  fuzzzor/vpn-monitor:latest
```

### Option 3 : Via Dockhand

1. Uploadez le fichier [`docker-compose.monitor.yml`](docker-compose.monitor.yml) dans Dockhand
2. Créez un nouveau stack nommé "vpn-monitor"
3. Configurez les variables d'environnement
4. Déployez

## Configuration

Voir [`DOCKHAND_INTEGRATION.md`](DOCKHAND_INTEGRATION.md) pour la documentation complète.

### Variables d'environnement essentielles

| Variable | Description | Défaut |
|----------|-------------|--------|
| `GLUETUN_CONTAINER` | Nom du container Gluetun | `Gluetun` |
| `QBITTORRENT_CONTAINER` | Nom du container qBittorrent | `qBittorrent` |
| `QBITTORRENT_PORT` | Port WebUI qBittorrent | `8880` |
| `CHECK_INTERVAL` | Intervalle de vérification (secondes) | `30` |
| `HEARTBEAT_INTERVAL` | Nombre d'itérations entre heartbeats | `2` |

### Variables pour l'intégration Dockhand (optionnel)

| Variable | Description | Requis |
|----------|-------------|--------|
| `REDEPLOY_ON_MISSING_CONTAINER` | Active le redéploiement auto | Non |
| `DOCKHAND_API_URL` | URL de l'API Dockhand | Oui si activé |
| `DOCKHAND_API_TOKEN` | Token API Dockhand | Oui si activé |
| `DOCKHAND_STACK_NAME` | Stack à redéployer | Non |

## Logs

### Voir les logs en temps réel
```bash
docker logs -f vpn-monitor
```

### Voir les logs persistants
```bash
tail -f /volume1/docker/monitor_vpn/logs/monitor_vpn.log
```

### Exemples de logs

```
[2026-04-22 15:01:11] [INFO] === Démarrage du monitoring Gluetun + qBittorrent ===
[2026-04-22 15:01:11] [INFO] Intervalle de vérification: 300s
[2026-04-22 15:01:11] [INFO] Gluetun est maintenant en cours d'exécution
[2026-04-22 15:01:11] [INFO] Interface VPN (tun0) est maintenant UP
[2026-04-22 15:01:11] [INFO] VPN connecté. IP publique: 91.148.244.84
[2026-04-22 15:11:20] [INFO] Monitoring actif - Gluetun: running, VPN: up, qBittorrent: running
```

## Build local

```bash
# Build l'image
docker build -t vpn-monitor:local -f Dockerfile.monitor .

# Run en local
docker run -d --name vpn-monitor-test vpn-monitor:local
```

## Contribuer

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.

## License

MIT
