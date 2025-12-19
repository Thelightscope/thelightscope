# LightScope

Network security monitor and honeypot for Linux, macOS, Windows, and containers.

LightScope captures network packets, analyzes traffic patterns, detects unwanted connections, and runs honeypot services to identify attackers. Data is reported to a central dashboard at [thelightscope.com](https://thelightscope.com).

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
