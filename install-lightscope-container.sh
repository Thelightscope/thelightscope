#!/bin/bash
# LightScope Container Installation Script
# Automated installation of LightScope Network Security Monitor in Docker

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LIGHTSCOPE_DIR="/opt/lightscope-container"
COMPOSE_VERSION="2.21.0"
MIN_DOCKER_VERSION="20.10"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "This installer only supports Linux. Detected OS: $OSTYPE"
    fi
    
    # Check if user has sudo privileges
    if ! sudo -n true 2>/dev/null; then
        error "This script requires sudo privileges. Please ensure your user can run sudo commands."
    fi
    
    # Check available memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 2 ]]; then
        warn "System has less than 2GB RAM. LightScope may experience performance issues."
    fi
    
    # Check available disk space
    local disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $disk_gb -lt 5 ]]; then
        warn "Less than 5GB free disk space available. Consider freeing up space."
    fi
    
    log "System requirements check completed"
}

# Install Docker if not present
install_docker() {
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        info "Docker is already installed (version $docker_version)"
        
        # Check if version is sufficient
        if [[ $(echo "$docker_version $MIN_DOCKER_VERSION" | tr " " "\n" | sort -V | head -n1) != "$MIN_DOCKER_VERSION" ]]; then
            warn "Docker version $docker_version is older than recommended $MIN_DOCKER_VERSION"
        fi
        return 0
    fi
    
    log "Installing Docker..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    log "Docker installed successfully"
    info "You may need to log out and back in for Docker group membership to take effect"
}

# Install Docker Compose if not present
install_docker_compose() {
    if docker compose version &> /dev/null; then
        local compose_version=$(docker compose version --short)
        info "Docker Compose is already installed (version $compose_version)"
        return 0
    fi
    
    log "Installing Docker Compose..."
    
    # Docker Compose is included with Docker Desktop and recent Docker installations
    # If not available, install standalone version
    sudo curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    log "Docker Compose installed successfully"
}

# Create installation directory and files
setup_lightscope() {
    log "Setting up LightScope installation..."
    
    # Create installation directory
    sudo mkdir -p "$LIGHTSCOPE_DIR"
    sudo chown $USER:$USER "$LIGHTSCOPE_DIR"
    
    # Create subdirectories
    mkdir -p "$LIGHTSCOPE_DIR"/{config,logs,data}
    
    # Download or copy LightScope files
    if [[ -f "docker-compose.yml" ]]; then
        # Running from source directory
        cp docker-compose.yml "$LIGHTSCOPE_DIR/"
        cp Dockerfile "$LIGHTSCOPE_DIR/"
        cp -r lightscope "$LIGHTSCOPE_DIR/"
        cp config.ini "$LIGHTSCOPE_DIR/config/"
    else
        # Download from repository
        log "Downloading LightScope files..."
        cd "$LIGHTSCOPE_DIR"
        
        # Create a minimal docker-compose.yml for download
        cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  lightscope:
    image: thelightscope/lightscope:latest
    container_name: lightscope-monitor
    restart: unless-stopped
    network_mode: host
    cap_add: [NET_RAW, NET_ADMIN, NET_BIND_SERVICE]
    deploy:
      resources:
        limits:
          memory: 512M
    environment:
      - PYTHONUNBUFFERED=1
      - CONTAINER_MEMORY_LIMIT_MB=512
    volumes:
      - lightscope-config:/opt/lightscope/config
      - lightscope-logs:/opt/lightscope/logs
      - lightscope-updates:/opt/lightscope/updates
    healthcheck:
      test: ["CMD", "python3", "-c", "import psutil; exit(0 if any('lightscope' in p.name() for p in psutil.process_iter()) else 1)"]
      interval: 30s
      retries: 3
volumes:
  lightscope-config:
  lightscope-logs:
  lightscope-updates:
EOF
    fi
    
    log "LightScope files setup completed"
}

# Create systemd service for container management
create_systemd_service() {
    log "Creating systemd service..."
    
    sudo tee /etc/systemd/system/lightscope-container.service > /dev/null << EOF
[Unit]
Description=LightScope Network Security Monitor (Container)
Documentation=https://thelightscope.com/docs
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USER
Group=$USER
WorkingDirectory=$LIGHTSCOPE_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
TimeoutStopSec=60

# Restart configuration
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable lightscope-container.service
    
    log "Systemd service created and enabled"
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts..."
    
    # Main management script
    cat > "$LIGHTSCOPE_DIR/lightscope-ctl" << 'EOF'
#!/bin/bash
# LightScope Container Management Script

LIGHTSCOPE_DIR="/opt/lightscope-container"
cd "$LIGHTSCOPE_DIR"

case "$1" in
    start)
        echo "Starting LightScope..."
        sudo systemctl start lightscope-container.service
        ;;
    stop)
        echo "Stopping LightScope..."
        sudo systemctl stop lightscope-container.service
        ;;
    restart)
        echo "Restarting LightScope..."
        sudo systemctl restart lightscope-container.service
        ;;
    status)
        echo "=== Service Status ==="
        sudo systemctl status lightscope-container.service --no-pager
        echo ""
        echo "=== Container Status ==="
        docker ps -f name=lightscope-monitor
        echo ""
        echo "=== Resource Usage ==="
        docker stats lightscope-monitor --no-stream 2>/dev/null || echo "Container not running"
        ;;
    logs)
        echo "=== Container Logs ==="
        docker logs lightscope-monitor -f
        ;;
    update)
        echo "Updating LightScope..."
        docker compose pull
        docker compose up -d
        ;;
    uninstall)
        echo "Uninstalling LightScope..."
        sudo systemctl stop lightscope-container.service
        sudo systemctl disable lightscope-container.service
        docker compose down -v
        docker rmi $(docker images -q thelightscope/lightscope) 2>/dev/null || true
        sudo rm -f /etc/systemd/system/lightscope-container.service
        sudo systemctl daemon-reload
        echo "LightScope uninstalled. Data remains in $LIGHTSCOPE_DIR"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|update|uninstall}"
        echo ""
        echo "Commands:"
        echo "  start     - Start LightScope service"
        echo "  stop      - Stop LightScope service"
        echo "  restart   - Restart LightScope service"
        echo "  status    - Show service and container status"
        echo "  logs      - Show container logs (follow mode)"
        echo "  update    - Update to latest version"
        echo "  uninstall - Remove LightScope (keeps data)"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$LIGHTSCOPE_DIR/lightscope-ctl"
    
    # Create symlink for global access
    sudo ln -sf "$LIGHTSCOPE_DIR/lightscope-ctl" /usr/local/bin/lightscope-ctl
    
    log "Management scripts created"
}

# Start LightScope
start_lightscope() {
    log "Starting LightScope..."
    
    cd "$LIGHTSCOPE_DIR"
    
    # Build image if Dockerfile exists
    if [[ -f "Dockerfile" ]]; then
        log "Building LightScope container image..."
        docker compose build
    fi
    
    # Start the service
    sudo systemctl start lightscope-container.service
    
    # Wait a moment for startup
    sleep 5
    
    # Check status
    if sudo systemctl is-active --quiet lightscope-container.service; then
        log "LightScope started successfully!"
    else
        error "Failed to start LightScope. Check logs with: lightscope-ctl logs"
    fi
}

# Display final information
show_completion_info() {
    log "LightScope installation completed successfully!"
    echo ""
    info "Installation Directory: $LIGHTSCOPE_DIR"
    info "Management Command: lightscope-ctl"
    echo ""
    echo "Common commands:"
    echo "  lightscope-ctl status   - Check service status"
    echo "  lightscope-ctl logs     - View logs"
    echo "  lightscope-ctl restart  - Restart service"
    echo "  lightscope-ctl update   - Update to latest version"
    echo ""
    
    # Show database URL if config exists
    if [[ -f "$LIGHTSCOPE_DIR/config/config.ini" ]]; then
        local db_name=$(grep -oP 'database\s*=\s*\K.*' "$LIGHTSCOPE_DIR/config/config.ini" 2>/dev/null || echo "")
        if [[ -n "$db_name" ]]; then
            echo -e "${GREEN}🌐 View your LightScope reports at:${NC}"
            echo -e "${BLUE}   https://thelightscope.com/light_table/$db_name${NC}"
            echo ""
        fi
    fi
    
    warn "If you added your user to the docker group, you may need to log out and back in."
    info "LightScope is now monitoring your network traffic!"
}

# Main installation function
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    LightScope Container                      ║"
    echo "║              Network Security Monitor                        ║"
    echo "║                                                              ║"
    echo "║  This installer will set up LightScope in a Docker          ║"
    echo "║  container with automatic restarts and memory management.    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # Confirmation
    read -p "Do you want to continue with the installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    # Run installation steps
    check_root
    check_requirements
    install_docker
    install_docker_compose
    setup_lightscope
    create_systemd_service
    create_management_scripts
    start_lightscope
    show_completion_info
}

# Run main function
main "$@"
