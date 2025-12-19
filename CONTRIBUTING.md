# Contributing to LightScope

Thank you for your interest in contributing to LightScope.

## Reporting Issues

- Search existing issues before opening a new one
- Include your OS, Python version, and LightScope version
- Provide steps to reproduce the problem
- Include relevant log output

## Pull Requests

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Test on your target platform
5. Submit a PR with a clear description

Keep PRs focused on a single change. Large changes should be discussed in an issue first.

## Development Setup

### Requirements

- Python 3.8+
- libpcap (Linux/macOS) or Npcap (Windows)
- Platform-specific dependencies

### Linux (Debian/Ubuntu)

```bash
sudo apt-get install libpcap-dev python3-dev
pip install -r requirements.txt
```

### macOS

```bash
# libpcap is included with macOS
pip install -r requirements.txt
```

### Windows

1. Install Npcap from https://nmap.org/npcap/
2. Install dependencies:
```bash
pip install -r requirements.txt
```

### Running Locally

```bash
# Requires root/admin or appropriate capabilities
python -m lightscope
```

## Code Style

- Follow existing code patterns
- Use descriptive variable and function names
- Add comments for non-obvious logic

## Testing

There is no automated test suite. Test changes manually on your target platform before submitting.

Verify:
- Application starts without errors
- Packet capture works
- No regressions in existing functionality

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
