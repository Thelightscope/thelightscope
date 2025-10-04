# LightScope Network Security Monitor - Container Build
# Multi-stage build for optimized container size

FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpcap-dev \
    pkg-config \
    python3-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create requirements file from pyproject.toml dependencies
COPY pyproject.toml .
RUN python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
deps = data['project']['dependencies']
# Filter out platform-specific dependencies for Linux
linux_deps = []
for dep in deps:
    if 'sys_platform' in dep:
        if 'win32' not in dep:  # Include non-Windows deps
            linux_deps.append(dep.split(';')[0].strip())
    else:
        linux_deps.append(dep)
# Add container-specific dependencies
linux_deps.extend(['systemd-python', 'cryptography'])
with open('requirements.txt', 'w') as f:
    for dep in linux_deps:
        f.write(dep + '\n')
"

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.11-slim as runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libpcap0.8 \
    libsystemd0 \
    procps \
    iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r lightscope \
    && useradd -r -g lightscope -s /bin/false -d /opt/lightscope lightscope

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Create application directories with proper permissions
RUN mkdir -p /opt/lightscope/{bin,config,logs,updates} && \
    chown -R lightscope:lightscope /opt/lightscope

# Copy application files
COPY lightscope/lightscope-runner.py /opt/lightscope/bin/
COPY lightscope/lightscope_core.py /opt/lightscope/bin/
COPY config.ini /opt/lightscope/config/config.ini.template

# Create memory-aware wrapper script
COPY <<EOF /opt/lightscope/bin/lightscope-container-wrapper.py
#!/usr/bin/env python3
"""
LightScope Container Wrapper
Handles graceful memory management and container lifecycle
"""
import os
import sys
import time
import signal
import subprocess
from threading import Thread

def setup_signal_handlers():
    """Setup signal handlers for graceful shutdown"""
    def signal_handler(signum, frame):
        print(f"Received signal {signum}, shutting down gracefully...")
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

def memory_monitor():
    """Monitor memory usage and trigger graceful restart if needed"""
    try:
        import psutil
    except ImportError:
        print("psutil not available, memory monitoring disabled")
        return
    
    while True:
        try:
            process = psutil.Process(os.getpid())
            memory_mb = process.memory_info().rss / 1024 / 1024
            
            # Get memory limit from environment or default to 512MB
            limit_mb = int(os.environ.get('CONTAINER_MEMORY_LIMIT_MB', '512'))
            threshold = limit_mb * 0.85  # Restart at 85% of limit
            
            if memory_mb > threshold:
                print(f"Memory usage {memory_mb:.1f}MB exceeds threshold {threshold:.1f}MB")
                print("Initiating graceful restart...")
                os.kill(os.getpid(), signal.SIGTERM)
                break
                
            time.sleep(30)  # Check every 30 seconds
        except Exception as e:
            print(f"Memory monitor error: {e}")
            time.sleep(60)

def main():
    """Main container entry point"""
    print("Starting LightScope Container...")
    print(f"Memory limit: {os.environ.get('CONTAINER_MEMORY_LIMIT_MB', '512')}MB")
    
    # Setup signal handling
    setup_signal_handlers()
    
    # Start memory monitor in background
    monitor_thread = Thread(target=memory_monitor, daemon=True)
    monitor_thread.start()
    
    # Ensure config file exists
    config_template = "/opt/lightscope/config/config.ini.template"
    config_file = "/opt/lightscope/config/config.ini"
    
    if not os.path.exists(config_file) and os.path.exists(config_template):
        import shutil
        shutil.copy2(config_template, config_file)
        print(f"Created config file from template: {config_file}")
    
    # Start LightScope runner
    try:
        cmd = [sys.executable, "/opt/lightscope/bin/lightscope-runner.py"]
        print(f"Executing: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd="/opt/lightscope")
        sys.exit(result.returncode)
    except KeyboardInterrupt:
        print("Received interrupt, shutting down...")
        sys.exit(0)
    except Exception as e:
        print(f"Error starting LightScope: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Set proper permissions
RUN chmod +x /opt/lightscope/bin/lightscope-container-wrapper.py && \
    chmod +x /opt/lightscope/bin/lightscope-runner.py && \
    chown -R lightscope:lightscope /opt/lightscope

# Switch to lightscope user
USER lightscope
WORKDIR /opt/lightscope

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import psutil; import sys; \
    try: \
        procs = [p for p in psutil.process_iter(['name']) if 'lightscope' in p.info['name']]; \
        mem_mb = psutil.Process().memory_info().rss / 1024 / 1024; \
        limit = int(__import__('os').environ.get('CONTAINER_MEMORY_LIMIT_MB', '512')); \
        sys.exit(0 if procs and mem_mb < limit * 0.9 else 1) \
    except: sys.exit(1)"

# Expose common ports (honeypots will bind dynamically)
EXPOSE 2222 2323 8080 5555

# Container metadata
LABEL maintainer="LightScope Team <e@alumni.usc.edu>"
LABEL description="LightScope Network Security Monitor"
LABEL version="1.0.15"

# Entry point
ENTRYPOINT ["/usr/local/bin/python3", "/opt/lightscope/bin/lightscope-container-wrapper.py"]
