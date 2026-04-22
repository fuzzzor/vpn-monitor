# Intégration Dockhand pour le VPN Monitor

## Vue d'ensemble

Le script de monitoring peut maintenant redéployer automatiquement le stack via l'API Dockhand si le container qBittorrent n'existe pas.

## ⚠️ Architecture importante

**Le container vpn-monitor DOIT être dans un stack séparé** du stack qbittorrent !

Sinon, quand le script redéploie le stack qbittorrent, vpn-monitor sera également redéployé, ce qui :
- Interrompt le script en plein milieu
- Réinitialise tous les états et compteurs
- Peut créer une boucle infinie de redéploiements

### Architecture recommandée

```
Stack 1: vpn-monitor (séparé)
  └── vpn-monitor container

Stack 2: qbittorrent (surveillé)
  ├── Gluetun
  └── qBittorrent
```

## Configuration

### Variables d'environnement

Ajoutez ces variables à votre `docker-compose.yml` :

```yaml
monitor:
  image: fuzzzor/vpn-monitor:latest
  container_name: vpn-monitor
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - /volume1/docker/monitor_vpn/logs:/var/log
  environment:
    - GLUETUN_CONTAINER=Gluetun
    - QBITTORRENT_CONTAINER=qBittorrent
    - QBITTORRENT_PORT=8880
    - CHECK_INTERVAL=300
    - HEARTBEAT_INTERVAL=2
    - TZ=Europe/Paris
    
    # Configuration Dockhand (optionnel)
    - REDEPLOY_ON_MISSING_CONTAINER=true
    - DOCKHAND_API_URL=http://192.168.0.242:9900
    - DOCKHAND_API_TOKEN=votre_token_dockhand
    - DOCKHAND_STACK_NAME=qbittorrent
  restart: unless-stopped
```

### Paramètres de configuration

| Variable | Description | Défaut | Requis |
|----------|-------------|--------|--------|
| `GLUETUN_CONTAINER` | Nom du container Gluetun | `Gluetun` | Non |
| `QBITTORRENT_CONTAINER` | Nom du container qBittorrent | `qBittorrent` | Non |
| `QBITTORRENT_PORT` | Port de l'interface Web qBittorrent | `8880` | Non |
| `CHECK_INTERVAL` | Intervalle entre chaque vérification (secondes) | `30` | Non |
| `HEARTBEAT_INTERVAL` | Nombre d'itérations entre chaque log heartbeat | `2` | Non |

### Paramètres Dockhand

| Variable | Description | Défaut | Requis |
|----------|-------------|--------|--------|
| `REDEPLOY_ON_MISSING_CONTAINER` | Active le redéploiement automatique | `false` | Non |
| `DOCKHAND_API_URL` | URL de l'API Dockhand | - | Oui si activé |
| `DOCKHAND_API_TOKEN` | Token d'authentification Dockhand | - | Oui si activé |
| `DOCKHAND_STACK_NAME` | Nom du stack à redéployer | `qbittorrent` | Non |

### Calcul du Heartbeat

Le heartbeat affiche un log périodique "Monitoring actif" pour confirmer que le script fonctionne.

**Formule** : `HEARTBEAT_INTERVAL × CHECK_INTERVAL = secondes entre chaque heartbeat`

**Exemples** :
- `HEARTBEAT_INTERVAL=2` et `CHECK_INTERVAL=300` → Log toutes les **10 minutes**
- `HEARTBEAT_INTERVAL=3` et `CHECK_INTERVAL=300` → Log toutes les **15 minutes**
- `HEARTBEAT_INTERVAL=1` et `CHECK_INTERVAL=60` → Log toutes les **1 minute** (verbose)

## Fonctionnement

### Sans Dockhand (comportement par défaut)

Si `REDEPLOY_ON_MISSING_CONTAINER=false` ou non défini :
1. Le script détecte que qBittorrent n'existe pas
2. Log une erreur
3. Retente à chaque cycle (toutes les 5 minutes)

### Avec Dockhand activé

Si `REDEPLOY_ON_MISSING_CONTAINER=true` :
1. Le script détecte que qBittorrent n'existe pas
2. Appelle l'API Dockhand pour redéployer le stack complet
3. Attend 30 secondes que le stack se redéploie
4. Vérifie que qBittorrent a été recréé
5. Démarre qBittorrent normalement

## Exemples de logs

### Container manquant sans Dockhand
```
[2026-04-22 14:05:31] [ERROR] Le container qBittorrent n'existe pas !
[2026-04-22 14:05:31] [WARNING] Redéploiement automatique désactivé (REDEPLOY_ON_MISSING_CONTAINER=false)
[2026-04-22 14:05:31] [WARNING] Le redémarrage a échoué, nouvelle tentative au prochain cycle...
```

### Container manquant avec Dockhand activé
```
[2026-04-22 14:05:31] [ERROR] Le container qBittorrent n'existe pas !
[2026-04-22 14:05:31] [INFO] Tentative de redéploiement du stack pour recréer qBittorrent...
[2026-04-22 14:05:31] [INFO] Tentative de redéploiement du stack 'qbittorrent' via Dockhand...
[2026-04-22 14:05:32] [SUCCESS] Redéploiement du stack 'qbittorrent' lancé via Dockhand
[2026-04-22 14:05:32] [INFO] Attente de 30 secondes pour que le stack se redéploie...
[2026-04-22 14:06:02] [SUCCESS] Le container qBittorrent a été recréé via le redéploiement du stack
[2026-04-22 14:06:02] [INFO] Démarrage de qBittorrent...
[2026-04-22 14:06:07] [SUCCESS] qBittorrent démarré avec succès
```

## Endpoint API utilisé

Le script utilise l'endpoint Dockhand suivant pour redéployer le stack :
```
POST /api/stacks/{nom}/deploy?env=1
```

Vous pouvez tester manuellement avec :
```bash
curl -X POST "http://192.168.0.242:9900/api/stacks/qbittorrent/deploy?env=1" -H "Authorization: Bearer VOTRE_TOKEN" -H "Content-Type: application/json" -d '{}'
```

## Obtenir un token Dockhand

1. Connectez-vous à l'interface Dockhand (http://192.168.0.242:9900)
2. Allez dans **Settings** → **API Tokens**
3. Créez un nouveau token avec un nom descriptif (ex: "VPN Monitor - Auto Redeploy")
4. Copiez le token généré (il commence par `dh_`)

## Sécurité

⚠️ **Important** : Le token Dockhand donne accès à votre infrastructure Docker. 

Recommandations :
- Créez un token dédié avec permissions minimales
- Stockez le token dans un secret Docker si possible
- Limitez l'accès au container monitor

## Dépannage

### L'API Dockhand ne répond pas
```bash
# Tester manuellement l'API
curl -H "Authorization: Bearer VOTRE_TOKEN" \
  http://192.168.0.242:5000/api/stacks

# Vérifier que Dockhand est accessible depuis le container
docker exec vpn-monitor curl -I http://192.168.0.242:5000
```

### Le redéploiement échoue
Vérifiez les logs du container monitor :
```bash
docker logs vpn-monitor | grep -i dockhand
```

Vérifiez les logs de Dockhand pour voir les erreurs API.
