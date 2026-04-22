# Gluetun + qBittorrent Monitoring Solution

## Description

This solution solves the network connectivity issue between qBittorrent and Gluetun when the VPN container restarts or updates. A monitoring container continuously monitors the VPN status and automatically restarts qBittorrent if necessary.

## Features

### The monitoring container:

1. ✅ **Checks that Gluetun is active** - Continuous monitoring of the container status
2. ✅ **Checks that the VPN is mounted** - Control of the `tun0` interface and its status
3. ✅ **Checks VPN connectivity** - Test of the public IP to confirm the tunnel
4. ✅ **Checks qBittorrent WebUI** - Verifies that the interface is accessible on the configured port
5. ✅ **Automatically restarts qBittorrent** - Intelligent restart if the VPN reconnects or if the WebUI is unreachable
6. ✅ **Logs all interactions** - Complete traceability in `/var/log/monitor_vpn.log`

## File Structure

```
.
├── docker-compose.yml              # Complete Docker Compose configuration
├── Dockerfile.monitor              # Docker image for monitoring
├── monitor.sh                      # Monitoring script
├── README_MONITORING.md            # This file
└── logs/                           # Logs directory (created automatically)
    └── monitor_vpn.log             # Log file
```


### 1. Permissions (Linux/Mac)

Make sure the script is executable:

```bash
chmod +x monitor_gluetun_qbittorrent.sh
```

### 2. Starting the services

Start all containers:

```bash
docker-compose up -d
```

Or to rebuild the monitoring image:

```bash
docker-compose up -d --build
```

## Checking operation

### Consult monitoring logs

```bash
# Real-time logs
docker-compose logs -f monitor

# Or directly the log file
tail -f ./logs/monitor_vpn.log
```

### Check container status

```bash
docker-compose ps
```

All containers should be in `Up` state.

### Test automatic restart

1. Manually restart Gluetun:
   ```bash
   docker restart gluetun
   ```

2. Observe monitoring logs:
   ```bash
   docker-compose logs -f monitor
   ```

3. You should see:
   - Detection that Gluetun has restarted
   - VPN interface verification
   - Automatic restart of qBittorrent

## Advanced Configuration

### Modify check interval

By default, monitoring checks status every 30 seconds. To modify:

```yaml
# In docker-compose.yml
environment:
  - CHECK_INTERVAL=60  # Check every 60 seconds
  - QBITTORRENT_PORT=8880  # WebUI port to check
```

### Customize container names

If your containers have different names:

```yaml
# In docker-compose.yml
environment:
  - GLUETUN_CONTAINER=my_gluetun
  - QBITTORRENT_CONTAINER=my_qbittorrent
```

Also modify the `container_name` in the corresponding services.

## Logs

### Log format

The logs include:
- **Timestamp** - Precise date and time
- **Level** - INFO, WARNING, ERROR, SUCCESS
- **Message** - Description of the action or event

Example:
```
[2026-03-29 14:50:15] [INFO] === Starting Gluetun + qBittorrent monitoring ===
[2026-03-29 14:50:15] [INFO] Check interval: 30s
[2026-03-29 14:50:15] [INFO] --- Start of verification cycle ---
[2026-03-29 14:50:15] [INFO] VPN interface (tun0) is UP in gluetun
[2026-03-29 14:50:16] [INFO] VPN connected. Public IP: 203.0.113.42
[2026-03-29 14:50:16] [INFO] qbittorrent is running
[2026-03-29 14:50:16] [WARNING] qBittorrent WebUI on port 8880 is inaccessible!
[2026-03-29 14:50:16] [INFO] Restarting qBittorrent necessary (VPN restored or WebUI inaccessible)
```

### Log rotation

To avoid the log file becoming too large, you can configure logrotate or simply clean periodically:

```bash
# Clear the logs
> ./logs/monitor_vpn.log

# Or with the running container
docker exec monitor_vpn sh -c "> /var/log/monitor_vpn.log"
```

## 🛠️ Troubleshooting

### The monitoring does not start

Check that the Docker socket is accessible:
```bash
docker-compose logs monitor
```

### qBittorrent is not restarted

1. Check the monitoring logs
2. Make sure Gluetun is properly started and the VPN connected
3. Check the container names in the configuration

### Permission error

On Linux, you may need to adjust permissions:
```bash
sudo chown -R $USER:$USER ./logs
chmod 755 ./logs
```

### The VPN does not connect

Check Gluetun's logs:
```bash
docker-compose logs gluetun
```

Make sure your VPN credentials are correct.

## Update

### Update Gluetun

With Watchtower or manually:

```bash
docker-compose pull gluetun
docker-compose up -d gluetun
```

The monitoring will automatically detect the restart and restart qBittorrent.

### Update the monitoring script

1. Modify [`monitor.sh`](monitor.sh)
2. Rebuild and restart:
   ```bash
   docker-compose up -d --build monitor
   ```

## Important notes

- **Security**: The Docker socket is mounted read-only (`ro`) to limit risks
- **Network**: qBittorrent uses `network_mode: "service:gluetun"` to go through the VPN
- **Restart**: The monitoring only restarts qBittorrent if Gluetun AND the VPN are operational
- **Performance**: The 30-second interval is a good compromise between responsiveness and system load

## How it works

### Verification Cycle

```
┌─────────────────────────────────────────┐
│ 1. Is Gluetun running?                  │
└────────────────┬────────────────────────┘
                 │ Yes
                 ▼
┌─────────────────────────────────────────┐
│ 2. Is the VPN interface (tun0) UP?      │
└────────────────┬────────────────────────┘
                 │ Yes
                 ▼
┌─────────────────────────────────────────┐
│ 3. Does the VPN have connectivity?      │
└────────────────┬────────────────────────┘
                 │ Yes
                 ▼
┌─────────────────────────────────────────┐
│ 4. Is qBittorrent UI accessible?        │
└────────────────┬────────────────────────┘
                 │ No (or VPN just restored)
                 ▼
┌─────────────────────────────────────────┐
│ 5. Restart qBittorrent                  │
└─────────────────────────────────────────┘
                 │
                 ▼
        Wait 30 seconds
                 │
                 └──────┐
                        │
                        ▼
              Restart the cycle
```

## Support

For any questions or issues:
1. Check the logs: `docker-compose logs`
2. Check the [Gluetun documentation](https://github.com/qdm12/gluetun)
3. Check the [qBittorrent documentation](https://github.com/linuxserver/docker-qbittorrent)

## License

This script is provided as is, without warranty. Use it at your own risk.
