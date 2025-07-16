# LightScope for macOS v1.0.4

## Installation

1. Run the installation script:
   ```
   ./install.sh
   ```

2. When prompted, allow the BPF permissions setup for packet capture

3. LightScope will start automatically and run in the background

## Network Monitoring

LightScope monitors network traffic using the Berkeley Packet Filter (BPF). This requires special permissions but does NOT require running as root.

### First-time Setup

The installer will offer to run the BPF permissions setup script:
```
sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh
```

This one-time setup:
- Creates an 'access_bpf' group
- Adds you to the group
- Sets up automatic BPF permissions at boot
- Allows packet capture without root privileges

### Manual BPF Setup

If you skipped the setup during installation, you can run it later:
```
sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh
```

## Configuration

Edit the configuration file at:
`/Applications/LightScope.app/Contents/Resources/config/config.ini`

## Logs

View logs at:
`/Applications/LightScope.app/Contents/Resources/logs/`

## Management

- **Stop**: `launchctl unload ~/Library/LaunchAgents/com.thelightscope.lightscope.plist`
- **Start**: `launchctl load ~/Library/LaunchAgents/com.thelightscope.lightscope.plist`
- **Uninstall**: `./uninstall.sh`

## Requirements

- macOS 10.14 or later
- Python 3.8 or later
- Network access for monitoring
- BPF permissions for packet capture

## Features

- Runs as user application (no root required)
- Automatic startup at login
- Background operation
- Network packet monitoring
- Honeypot functionality
- Automatic updates

## Security

- Does not require root privileges to run
- Uses Berkeley Packet Filter (BPF) for safe packet capture
- Group-based permissions following macOS security best practices
- Same approach used by Wireshark and other professional tools

## Troubleshooting

If packet capture fails:
1. Check BPF permissions: `ls -la /dev/bpf*`
2. Verify group membership: `groups`
3. Re-run setup: `sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh`
4. Log out and log back in for group changes to take effect
