# LightScope Container Edition

🐳 **Easy containerized deployment of LightScope Network Security Monitor**

LightScope Container Edition provides the same powerful network monitoring capabilities as the standard LightScope installation, but packaged in a Docker container for easy deployment, automatic restarts, and memory management.

## 🚀 Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/thelightscope/lightscope/main/install-lightscope-container.sh | bash
```

### Manual Installation

1. **Download the installer:**
   ```bash
   wget https://raw.githubusercontent.com/thelightscope/lightscope/main/install-lightscope-container.sh
   chmod +x install-lightscope-container.sh
   ```

2. **Run the installer:**
   ```bash
   ./install-lightscope-container.sh
   ```

3. **Check status:**
   ```bash
   lightscope-ctl status
   ```

## 📋 Prerequisites

- **Operating System:** Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+, RHEL 8+)
- **Memory:** Minimum 2GB RAM (4GB recommended)
- **Disk Space:** 5GB free space
- **Network:** Internet connectivity for updates and reporting
- **Privileges:** User account with sudo access

## 🔧 Management Commands

After installation, use the `lightscope-ctl` command to manage your LightScope container:

```bash
# Check service status
lightscope-ctl status

# View live logs
lightscope-ctl logs

# Restart the service
lightscope-ctl restart

# Stop the service
lightscope-ctl stop

# Start the service
lightscope-ctl start

# Update to latest version
lightscope-ctl update

# Uninstall (keeps data)
lightscope-ctl uninstall
```

## 📊 Viewing Your Data

After installation, your unique database identifier will be displayed. Use it to view your network security reports:

```
🌐 View your LightScope reports at:
   https://thelightscope.com/light_table/YOUR_DATABASE_ID
```

## 🛠️ Configuration

### Default Configuration

LightScope Container Edition comes with optimized defaults:

- **Memory Limit:** 512MB with automatic restart on approach
- **Auto-Updates:** Enabled for security patches
- **Honeypot Ports:** 10 dynamic ports rotated every 4 hours
- **Monitoring:** All network interfaces automatically detected

### Custom Configuration

Edit the configuration file:

```bash
sudo nano /opt/lightscope-container/config/config.ini
```

Key settings for containers:

```ini
[Container]
# Memory management
memory_limit_mb = 512
memory_warning_threshold = 85

# Honeypot settings
enable_honeypot_rotation = yes
honeypot_rotation_hours = 4
honeypot_port_count = 10

# Performance tuning
worker_processes = 0  # Auto-detect
packet_batch_size = 280
```

After editing, restart the service:

```bash
lightscope-ctl restart
```

## 🔒 Security Features

### Container Security

- **Non-root execution:** Runs as dedicated `lightscope` user
- **Minimal privileges:** Only network capabilities required for packet capture
- **Read-only filesystem:** Application files are protected
- **Resource limits:** Memory and CPU limits prevent resource exhaustion

### Network Security

- **Encrypted communication:** All data transmission uses HTTPS/TLS
- **IP anonymization:** Internal IPs are randomized before transmission
- **Signature verification:** Updates are cryptographically signed
- **Rate limiting:** Protection against connection flooding

## 📈 Resource Usage

### Memory Management

LightScope Container Edition includes intelligent memory management:

- **Automatic monitoring:** Checks memory usage every 30 seconds
- **Graceful restart:** Restarts before hitting memory limits
- **No data loss:** Processes pending packets before restart
- **Configurable limits:** Adjust memory limits based on your system

### CPU Usage

- **Efficient processing:** Optimized packet processing pipeline
- **Multi-core support:** Automatically uses available CPU cores
- **Adaptive batching:** Adjusts processing batch sizes based on load

### Network Usage

- **Minimal bandwidth:** Only metadata is transmitted, not packet contents
- **Batch uploads:** Efficient batching reduces network overhead
- **Compression:** Data is compressed before transmission

## 🐛 Troubleshooting

### Common Issues

#### Container Won't Start

```bash
# Check Docker status
sudo systemctl status docker

# Check container logs
docker logs lightscope-monitor

# Check system resources
free -h
df -h
```

#### No Network Traffic Detected

```bash
# Check network interfaces
ip link show

# Verify container has network access
docker exec lightscope-monitor ip link show

# Check capabilities
docker exec lightscope-monitor capsh --print
```

#### Memory Issues

```bash
# Check current memory usage
docker stats lightscope-monitor --no-stream

# Adjust memory limit
sudo nano /opt/lightscope-container/docker-compose.yml
# Edit: memory: 1G  # Increase from 512M
lightscope-ctl restart
```

### Log Analysis

View detailed logs:

```bash
# Container logs
lightscope-ctl logs

# System service logs
sudo journalctl -u lightscope-container.service -f

# Docker daemon logs
sudo journalctl -u docker.service -f
```

### Performance Tuning

For high-traffic networks:

```bash
# Edit configuration
sudo nano /opt/lightscope-container/config/config.ini

# Increase memory limit
memory_limit_mb = 1024

# Increase batch size
packet_batch_size = 500

# Restart service
lightscope-ctl restart
```

## 🔄 Updates

### Automatic Updates

LightScope Container Edition automatically checks for updates every hour and applies them seamlessly:

- **Zero downtime:** Updates are applied with automatic restart
- **Rollback capability:** Previous versions are backed up
- **Security patches:** Critical security updates are prioritized

### Manual Updates

Force an immediate update:

```bash
lightscope-ctl update
```

### Update Notifications

Monitor update activity:

```bash
# Watch for updates in logs
lightscope-ctl logs | grep -i update

# Check current version
docker exec lightscope-monitor python3 -c "
import sys
sys.path.append('/opt/lightscope/bin')
import lightscope_core
print(f'Version: {lightscope_core.ls_version}')
"
```

## 🏗️ Advanced Deployment

### Docker Compose

For advanced users, you can customize the Docker Compose configuration:

```yaml
# /opt/lightscope-container/docker-compose.yml
version: '3.8'
services:
  lightscope:
    image: thelightscope/lightscope:latest
    container_name: lightscope-monitor
    restart: unless-stopped
    network_mode: host
    cap_add: [NET_RAW, NET_ADMIN, NET_BIND_SERVICE]
    
    # Custom resource limits
    deploy:
      resources:
        limits:
          memory: 1G      # Increased memory
          cpus: '2.0'     # More CPU
    
    # Custom environment
    environment:
      - CONTAINER_MEMORY_LIMIT_MB=1024
      - PYTHONUNBUFFERED=1
    
    volumes:
      - lightscope-config:/opt/lightscope/config
      - lightscope-logs:/opt/lightscope/logs
      - lightscope-updates:/opt/lightscope/updates
```

### Kubernetes Deployment

Deploy on Kubernetes:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: lightscope
spec:
  selector:
    matchLabels:
      app: lightscope
  template:
    metadata:
      labels:
        app: lightscope
    spec:
      hostNetwork: true
      containers:
      - name: lightscope
        image: thelightscope/lightscope:latest
        securityContext:
          capabilities:
            add: [NET_RAW, NET_ADMIN, NET_BIND_SERVICE]
        resources:
          limits:
            memory: "512Mi"
            cpu: "1000m"
          requests:
            memory: "256Mi"
            cpu: "500m"
        env:
        - name: CONTAINER_MEMORY_LIMIT_MB
          value: "512"
```

### Multi-Node Deployment

Deploy across multiple servers:

```bash
# On each server
curl -fsSL https://raw.githubusercontent.com/thelightscope/lightscope/main/install-lightscope-container.sh | bash

# Each installation gets a unique database ID
# View consolidated data at https://thelightscope.com/
```

## 📞 Support

### Getting Help

- **Documentation:** [https://thelightscope.com/docs](https://thelightscope.com/docs)
- **Issues:** [GitHub Issues](https://github.com/thelightscope/lightscope/issues)
- **Email:** support@thelightscope.com

### Reporting Issues

When reporting issues, include:

```bash
# System information
uname -a
docker --version
docker compose version

# LightScope status
lightscope-ctl status

# Recent logs
lightscope-ctl logs | tail -50

# Resource usage
docker stats lightscope-monitor --no-stream
```

## 📄 License

LightScope is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

---

**LightScope Container Edition** - Secure, scalable network monitoring made simple. 🛡️
