# LightScope Package Build Systems

This directory contains two separate build and deployment systems for LightScope packages:

## 📦 DEB Package Build (Debian/Ubuntu)

**Script:** `dpkg_build_all_upload.sh`
**Platform:** macOS/Linux (with dpkg tools)
**Requires:** 
- `dpkg-deb` (usually pre-installed on Debian/Ubuntu)
- Python 3 with cryptography module
- SSH access to deployment server

**Usage:**
```bash
./dpkg_build_all_upload.sh
```

**Output:**
- `lightscope_X.X.X_amd64.deb` - Debian package
- Signed and uploaded to https://thelightscope.com/latest/

## 🔴 RPM Package Build (RHEL/Fedora/CentOS)

**Script:** `rpm_build_all_upload.sh`
**Platform:** Linux only (RHEL, Fedora, CentOS, openSUSE)
**Requires:**
- `rpmbuild` (install with `yum/dnf install rpm-build`)
- Python 3 with cryptography module
- SSH access to deployment server

**Usage:**
```bash
./rpm_build_all_upload.sh
```

**Output:**
- `lightscope-X.X.X-1.noarch.rpm` - RPM package
- Signed and uploaded to https://thelightscope.com/latest/

## 🏗️ Build Workflow

### Development Workflow:
1. **DEB builds** run on macOS/development machines using `dpkg_build_all_upload.sh`
2. **RPM builds** run on separate Linux boxes using `rpm_build_all_upload.sh`
3. Both deploy to the same server location (`/var/www/lightscope/latest/`)

### Why Separate Scripts?

- **Cross-platform compatibility:** RPM tools work best on native Linux
- **Clean separation:** Each script focuses on one package format
- **Deployment flexibility:** Can build packages on appropriate platforms
- **Maintenance:** Easier to maintain separate, focused scripts

## 🚀 Server Deployment

Both scripts deploy to the same server location:
```
/var/www/lightscope/latest/
├── lightscope_core.py           # Main application
├── lightscope_core.py.sig       # Digital signature
├── public-key                   # Public key for verification
├── version                      # Version information JSON
├── lightscope_X.X.X_amd64.deb   # Debian package
├── lightscope-X.X.X-1.noarch.rpm # RPM package
├── lightscope_latest.deb        # Generic latest DEB
└── lightscope_latest.rpm        # Generic latest RPM
```

## 🔧 Installation Commands

### Debian/Ubuntu:
```bash
curl -O https://thelightscope.com/latest/lightscope_latest.deb
sudo dpkg -i lightscope_latest.deb
```

### RHEL/Fedora/CentOS:
```bash
curl -O https://thelightscope.com/latest/lightscope_latest.rpm
sudo rpm -i lightscope_latest.rpm
# OR
sudo dnf install ./lightscope_latest.rpm
```

## 📋 Maintenance Notes

- Both scripts share the same signing keys (`lightscope-private.pem`, `lightscope-public.pem`)
- Version information is extracted from `lightscope/lightscope_core.py`
- Archives are created as `lightscope_vX.X.X_upload.tar.gz` for each build
- Both scripts include automated deployment with password prompts 