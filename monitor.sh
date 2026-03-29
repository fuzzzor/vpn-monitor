#!/bin/bash

#############################################
# Script de monitoring Gluetun + qBittorrent
# Vérifie l'état du VPN et relance qBittorrent si nécessaire
#############################################

# Configuration
GLUETUN_CONTAINER="Gluetun"
QBITTORRENT_CONTAINER="qBittorrent"
LOG_FILE="/var/log/monitor_vpn.log"
CHECK_INTERVAL=30  # Intervalle en secondes entre chaque vérification
MAX_LOG_SIZE=10485760  # Taille max du fichier de logs en octets (10 MB)
LOG_LINES_TO_KEEP=1000  # Nombre de lignes à conserver lors de la purge

# Fonction de logging
log_message() {
    local level="$1"
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Fonction de purge automatique des logs
purge_logs_if_needed() {
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)
        
        if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
            log_message "INFO" "Purge des logs (taille actuelle: $((log_size / 1024 / 1024)) MB)"
            
            # Garder seulement les dernières lignes
            local temp_file="${LOG_FILE}.tmp"
            tail -n "$LOG_LINES_TO_KEEP" "$LOG_FILE" > "$temp_file"
            mv "$temp_file" "$LOG_FILE"
            
            log_message "INFO" "Logs purgés. Conservées: $LOG_LINES_TO_KEEP dernières lignes"
        fi
    fi
}

# Fonction pour vérifier si un container est en cours d'exécution
is_container_running() {
    local container_name="$1"
    local status=$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)
    
    if [ "$status" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# Fonction pour vérifier l'interface VPN dans gluetun
check_vpn_interface() {
    local container_name="$1"
    
    # Détecter l'interface VPN (tun0 pour OpenVPN ou wg0/wgX pour WireGuard)
    local vpn_interface=$(docker exec "$container_name" ip link show 2>/dev/null | grep -oE '(tun[0-9]+|wg[0-9]+):' | sed 's/:$//' | head -n1)
    
    if [ -n "$vpn_interface" ]; then
        # Vérifier si l'interface détectée est UP (chercher le flag UP dans les chevrons)
        local interface_check=$(docker exec "$container_name" ip link show "$vpn_interface" 2>/dev/null)
        
        if echo "$interface_check" | grep -qE '<.*UP.*>'; then
            echo "$vpn_interface"  # Retourner le nom de l'interface
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Fonction pour vérifier la connectivité VPN
check_vpn_connectivity() {
    local container_name="$1"
    
    # Vérifier l'IP publique via le container gluetun
    local ip_check=$(docker exec "$container_name" wget -qO- https://api.ipify.org 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$ip_check" ]; then
        echo "$ip_check"  # Retourner l'IP
        return 0
    else
        return 1
    fi
}

# Fonction pour redémarrer qBittorrent
restart_qbittorrent() {
    log_message "INFO" "Redémarrage de $QBITTORRENT_CONTAINER..."
    
    docker restart "$QBITTORRENT_CONTAINER" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "$QBITTORRENT_CONTAINER redémarré avec succès"
        
        # Attendre que le container soit vraiment démarré
        sleep 5
        
        if is_container_running "$QBITTORRENT_CONTAINER"; then
            log_message "SUCCESS" "$QBITTORRENT_CONTAINER est maintenant en cours d'exécution"
            return 0
        else
            log_message "ERROR" "$QBITTORRENT_CONTAINER n'a pas démarré correctement"
            return 1
        fi
    else
        log_message "ERROR" "Échec du redémarrage de $QBITTORRENT_CONTAINER"
        return 1
    fi
}

# Fonction pour vérifier l'état de qBittorrent
check_qbittorrent_status() {
    if is_container_running "$QBITTORRENT_CONTAINER"; then
        return 0
    else
        return 1
    fi
}

# Variables pour suivre l'état précédent
previous_gluetun_state=""
previous_vpn_state=""
previous_qbittorrent_state=""
previous_vpn_ip=""
qbittorrent_restart_needed=false
heartbeat_counter=0
HEARTBEAT_INTERVAL=20  # Logger un heartbeat toutes les 20 itérations (10 minutes si CHECK_INTERVAL=30s)

# Fonction principale de monitoring
main_loop() {
    log_message "INFO" "=== Démarrage du monitoring Gluetun + qBittorrent ==="
    log_message "INFO" "Intervalle de vérification: ${CHECK_INTERVAL}s"
    
    while true; do
        # Purger les logs si nécessaire (une fois par cycle)
        purge_logs_if_needed
        
        # Heartbeat périodique pour montrer que le monitoring est actif
        heartbeat_counter=$((heartbeat_counter + 1))
        if [ $heartbeat_counter -ge $HEARTBEAT_INTERVAL ]; then
            log_message "INFO" "Monitoring actif - Gluetun: $previous_gluetun_state, VPN: $previous_vpn_state, qBittorrent: $previous_qbittorrent_state"
            heartbeat_counter=0
        fi
        
        # 1. Vérifier si Gluetun est en cours d'exécution
        if is_container_running "$GLUETUN_CONTAINER"; then
            current_gluetun_state="running"
            
            # Logger uniquement si changement d'état
            if [ "$previous_gluetun_state" != "running" ]; then
                log_message "INFO" "$GLUETUN_CONTAINER est maintenant en cours d'exécution"
                qbittorrent_restart_needed=true
            fi
            
            # 2. Vérifier l'interface VPN
            vpn_interface=$(check_vpn_interface "$GLUETUN_CONTAINER")
            if [ $? -eq 0 ]; then
                current_vpn_state="up"
                
                # Logger uniquement si changement d'état
                if [ "$previous_vpn_state" != "up" ]; then
                    log_message "INFO" "Interface VPN ($vpn_interface) est maintenant UP"
                    qbittorrent_restart_needed=true
                fi
                
                # 3. Vérifier la connectivité VPN
                current_vpn_ip=$(check_vpn_connectivity "$GLUETUN_CONTAINER")
                if [ $? -eq 0 ]; then
                    # Logger uniquement si l'IP a changé
                    if [ "$previous_vpn_ip" != "$current_vpn_ip" ]; then
                        log_message "INFO" "VPN connecté. IP publique: $current_vpn_ip"
                        previous_vpn_ip="$current_vpn_ip"
                    fi
                fi
                
            else
                current_vpn_state="down"
                # Logger uniquement si changement d'état
                if [ "$previous_vpn_state" != "down" ]; then
                    log_message "WARNING" "Interface VPN non disponible dans $GLUETUN_CONTAINER"
                fi
            fi
            
        else
            current_gluetun_state="stopped"
            current_vpn_state="down"
            # Logger uniquement si changement d'état
            if [ "$previous_gluetun_state" != "stopped" ]; then
                log_message "WARNING" "$GLUETUN_CONTAINER n'est pas en cours d'exécution"
            fi
        fi
        
        # 4. Vérifier l'état de qBittorrent
        if check_qbittorrent_status; then
            current_qbittorrent_state="running"
            # Logger uniquement si changement d'état
            if [ "$previous_qbittorrent_state" != "running" ]; then
                log_message "INFO" "$QBITTORRENT_CONTAINER est maintenant en cours d'exécution"
            fi
        else
            current_qbittorrent_state="stopped"
            # Logger uniquement si changement d'état
            if [ "$previous_qbittorrent_state" != "stopped" ]; then
                log_message "WARNING" "$QBITTORRENT_CONTAINER n'est pas en cours d'exécution"
            fi
        fi
        
        # 5. Redémarrer qBittorrent si nécessaire
        if [ "$qbittorrent_restart_needed" = true ] && [ "$current_gluetun_state" = "running" ] && [ "$current_vpn_state" = "up" ]; then
            log_message "INFO" "Redémarrage de qBittorrent nécessaire (VPN restauré)"
            restart_qbittorrent
            qbittorrent_restart_needed=false
            current_qbittorrent_state="running"
        fi
        
        # Sauvegarder l'état actuel pour le prochain cycle
        previous_gluetun_state="$current_gluetun_state"
        previous_vpn_state="$current_vpn_state"
        previous_qbittorrent_state="$current_qbittorrent_state"
        
        sleep "$CHECK_INTERVAL"
    done
}

# Créer le répertoire de logs si nécessaire
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Démarrer le monitoring
main_loop
