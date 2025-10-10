# LightScope Container - Quick Start Guide

## 🚀 Install in 30 Seconds

### Option 1: One-Line Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/thelightscope/lightscope/main/install-lightscope-container.sh | bash
```

### Option 2: Manual Install
```bash
# Download installer
wget https://github.com/thelightscope/lightscope/releases/latest/download/install-lightscope-container.sh

# Make executable and run
chmod +x install-lightscope-container.sh
./install-lightscope-container.sh
```

## ✅ Verify Installation

```bash
# Check status
lightscope-ctl status

# View logs
lightscope-ctl logs
```

## 🌐 View Your Data

After installation, you'll see your unique URL:
```
🌐 View your LightScope reports at:
   https://thelightscope.com/light_table/YOUR_DATABASE_ID
```

## 🛠️ Basic Management

```bash
lightscope-ctl start     # Start monitoring
lightscope-ctl stop      # Stop monitoring  
lightscope-ctl restart   # Restart service
lightscope-ctl status    # Check status
lightscope-ctl logs      # View logs
lightscope-ctl update    # Update to latest
```

## 🔧 Memory Management

LightScope automatically restarts when approaching memory limits:

- **Default limit:** 512MB
- **Restart trigger:** 85% of limit (435MB)
- **Graceful restart:** No data loss
- **Automatic recovery:** Continues monitoring

### Adjust Memory Limit

```bash
# Edit docker-compose.yml
sudo nano /opt/lightscope-container/docker-compose.yml

# Change memory limit
deploy:
  resources:
    limits:
      memory: 1G  # Increase to 1GB

# Restart
lightscope-ctl restart
```

## 📊 What You'll See

LightScope monitors and reports:

- **Unwanted TCP connections** to your network
- **Source IP geolocation** and network information  
- **Port scanning attempts** and attack patterns
- **Honeypot interactions** from automated tools
- **Network traffic statistics** and trends

## 🔒 Security Features

- ✅ **No root privileges** - runs as dedicated user
- ✅ **Encrypted transmission** - all data uses HTTPS
- ✅ **IP anonymization** - your internal IPs are randomized
- ✅ **Automatic updates** - security patches applied automatically
- ✅ **Memory protection** - automatic restart prevents crashes

## 🚨 Troubleshooting

### Container Won't Start
```bash
# Check Docker
sudo systemctl status docker

# Check logs
docker logs lightscope-monitor
```

### No Traffic Detected
```bash
# Verify network interfaces
docker exec lightscope-monitor ip link show

# Check capabilities
docker exec lightscope-monitor capsh --print
```

### High Memory Usage
```bash
# Monitor memory
docker stats lightscope-monitor --no-stream

# Increase limit if needed (see above)
```

## 📞 Need Help?

- **Documentation:** [Full Container Guide](README-CONTAINER.md)
- **Website:** https://thelightscope.com
- **Issues:** https://github.com/thelightscope/lightscope/issues
- **Email:** support@thelightscope.com

---

**That's it!** LightScope is now monitoring your network and will automatically restart if it runs out of memory. 🛡️
