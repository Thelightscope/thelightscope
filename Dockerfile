FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libpcap-dev \
    gcc \
    cython3 \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Create lightscope directory structure
WORKDIR /opt/lightscope
RUN mkdir -p bin config logs updates

# Copy python-libpcap first (for better layer caching)
COPY python-libpcap /opt/lightscope/python-libpcap

# Create and setup virtual environment
RUN python3 -m venv /opt/lightscope/venv && \
    /opt/lightscope/venv/bin/pip install --upgrade pip && \
    /opt/lightscope/venv/bin/pip install dpkt psutil requests cryptography packaging scapy && \
    cd /opt/lightscope/python-libpcap && /opt/lightscope/venv/bin/pip install .

# Copy application files
COPY lightscope/lightscope_core.py /opt/lightscope/bin/
COPY lightscope/lightscope-runner.py /opt/lightscope/bin/

# Copy public key
COPY lightscope-public.pem /opt/lightscope/config/

# Copy default config (can be overridden with volume mount)
COPY config.ini /opt/lightscope/config.ini

# Set permissions
RUN chmod +x /opt/lightscope/bin/lightscope-runner.py

ENV PYTHONPATH=/opt/lightscope/bin

# Run directly (no systemd needed in container)
ENTRYPOINT ["/opt/lightscope/venv/bin/python3", "/opt/lightscope/bin/lightscope-runner.py"]
