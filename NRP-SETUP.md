# LightScope NRP Setup - Quick Guide

## What Changed

### 1. New Docker Image: `Dockerfile.nrp`
- Pre-generates database name with format: `nrp{YYYYMMDD}_{50_random_chars}`
- Sets `autoupdate = yes` (auto-updates enabled)
- Otherwise identical to standard Dockerfile

### 2. Modified Code: `lightscope_core.py`
- Automatically detects NRP mode (database starts with "nrp")
- Uses static 20-port list instead of dynamic rotation
- No port rotation every 4 hours in NRP mode

## Static Port List for NRP

These 30 ports are hardcoded for NRP deployments (based on real-world attack data):
```
1080, 1433, 2222, 2323, 2375, 3000, 3306, 3389, 4786, 5432,
5555, 5900, 6379, 7547, 8000, 8081, 8291, 8443, 8728, 8888,
9090, 9200, 9999, 11211, 12281, 17001, 23456, 25565, 27017, 33060
```

**Key targets covered:**
- **Databases**: MySQL (3306), PostgreSQL (5432), MS SQL (1433), MongoDB (27017), Redis (6379), Memcached (11211)
- **Remote Access**: VNC (5900), RDP (3389), SSH alt (2222), Telnet alt (2323)
- **Infrastructure**: Cisco Smart Install (4786), MikroTik (8728, 8291), TR-069 routers (7547)
- **Containers/DevOps**: Docker API (2375), Elasticsearch (9200)
- **Web Services**: HTTP/HTTPS alternatives (8000, 8081, 8443, 3000)
- **Other**: SOCKS proxy (1080), Minecraft (25565)

**Port-to-Honeypot Mapping:**

*SSH honeypot (15 ports):* 2222, 3389, 5900, 3306, 5432, 1433, 27017, 33060, 2375, 9200, 8000, 3000, 8443, 9090, 1080
- Used for: Secure protocols, databases, modern DevOps tools

*Telnet honeypot (15 ports):* 2323, 4786, 7547, 8728, 8291, 6379, 11211, 5555, 8081, 8888, 9999, 12281, 17001, 23456, 25565
- Used for: Router/IoT management, text protocols, generic backdoors

**Ports chosen to avoid NRP conflicts:**
- All > 1024 (non-privileged)
- Avoids: 8080 (stashcache uses it)
- Avoids: 3478, 49152-49172 (TURN)
- Avoids: 50000-51000 (Globus)

## What to Give the Admin

**Ask the admin to add these 30 TCP ports to a Calico GlobalNetworkPolicy:**

```
1080, 1433, 2222, 2323, 2375, 3000, 3306, 3389, 4786, 5432,
5555, 5900, 6379, 7547, 8000, 8081, 8291, 8443, 8728, 8888,
9090, 9200, 9999, 11211, 12281, 17001, 23456, 25565, 27017, 33060
```

Example policy name: `lightscope-honeypot`
Order: 16 (to match other service policies)
Selector: `has(host-endpoint)` (for all nodes)

## Build NRP Image

```bash
docker build -f Dockerfile.nrp -t lightscope:nrp-latest .
```

## How It Works

1. **Database name detection**: If database starts with `nrp`, enables NRP mode
2. **Static ports**: Opens 30 static ports at startup (based on real attack data)
3. **No rotation**: Ports stay open permanently (no 4-hour rotation)
4. **Calico handles firewall**: LightScope binds to ports, Calico opens iptables rules

## Testing

After deployment, check logs for:
```
NRP mode detected - using static port list
initial_ports: [2323, 2222, 5555, ...]
Initial startup port 2323 opened successfully
...
```

## View Results

Database name is printed on startup. Visit:
```
https://thelightscope.com/light_table/<database_name>
```

## Files Modified

- ✅ `Dockerfile.nrp` - NEW
- ✅ `lightscope/lightscope_core.py` - MODIFIED (NRP mode detection added)
- 📄 Original `Dockerfile` - UNCHANGED
- 📄 Original `docker-compose.yml` - UNCHANGED
