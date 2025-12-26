# LightScope

**See Your Scanners**

<p align="center">
  <img src="ls.png" alt="LightScope" width="128">
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Docker-lightgrey.svg)]()

LightScope is a lightweight, open-source network security monitor that transforms closed ports into honeypots. See who's scanning your systems without dedicated infrastructure.

Provided by [USC Information Sciences Institute](https://www.isi.edu/).

## What It Does

- Monitors closed ports for attacker connections
- Runs honeypot services to observe attack patterns
- Reports attackers to AbuseIPDB and ISPs
- Generates personalized IP blocklists
- Provides a web dashboard at [thelightscope.com](https://thelightscope.com)

## What It Isn't

LightScope is not antivirus or EDR. It won't slow down your system or interfere with your applications. It observes network traffic passively and runs lightweight honeypot services on ports you're not using.

## Use Cases

**Servers**: See who's targeting your infrastructure. Get automatic ISP abuse reporting.

**Home/Laptop**: Detect compromised routers or IoT devices on your network. Identify threats on public WiFi.

## Quick Install

### Linux (Debian/Ubuntu)

```bash
curl -O https://thelightscope.com/latest/lightscope_latest.deb
sudo dpkg -i lightscope_latest.deb
```

### Linux (RHEL/Fedora/CentOS)

```bash
curl -O https://thelightscope.com/latest/lightscope_latest.rpm
sudo rpm -i lightscope_latest.rpm
```

### macOS

Download from [Releases](https://github.com/Thelightscope/thelightscope/releases) and run the installer.

### Container

```bash
curl -fsSL https://raw.githubusercontent.com/thelightscope/lightscope/main/install-lightscope-container.sh | bash
```

### Windows

Download the installer from [Releases](https://github.com/Thelightscope/thelightscope/releases) and run as Administrator.

## Features

- Packet capture and traffic analysis
- Honeypot services on configurable ports
- Automatic detection of unwanted connections
- Secure auto-updates with signature verification
- Runs as a system service (systemd, launchd, Windows Service)
- Web dashboard for monitoring

## Privacy

LightScope anonymizes all data before transmission:

- Internal IP addresses are randomized
- No personally identifiable information is collected
- Anonymization methods are IRB-approved (study UP-25-00124)

## Documentation

- Installation
  - [Linux (dpkg)](docs/installation/linux-dpkg.md)
  - [macOS](docs/installation/macos.md)
  - [Windows](docs/installation/windows.md)
  - [Container](docs/installation/container.md)
- [Container Quick Start](docs/container-quickstart.md)
- [Building Packages](docs/build.md)
- [Deployment](docs/deployment.md)
- [Firewall Configuration](docs/firewall.md)

## Configuration

After installation, edit the config file:

- Linux: `/opt/lightscope/config/config.ini`
- macOS: `/Applications/LightScope.app/Contents/Resources/config/config.ini`
- Windows: `C:\Program Files\LightScope\config\config.ini`
- Container: `/opt/lightscope-container/config/config.ini`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Support

- Website: https://thelightscope.com
- Issues: https://github.com/Thelightscope/thelightscope/issues
- Email: e@alumni.usc.edu
