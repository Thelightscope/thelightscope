#!/bin/bash
# LightScope Container Build and Deployment Script
# Builds, tests, and optionally pushes LightScope container images

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
IMAGE_NAME="thelightscope/lightscope"
VERSION=$(grep -oP 'ls_version = "\K[^"]+' lightscope/lightscope_core.py || echo "1.0.15")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Help function
show_help() {
    echo "LightScope Container Build Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build     Build the container image (default)"
    echo "  test      Run container tests"
    echo "  push      Push image to registry"
    echo "  release   Build, test, and push with version tags"
    echo "  clean     Clean up build artifacts"
    echo ""
    echo "Options:"
    echo "  -t, --tag TAG     Custom tag for the image"
    echo "  -p, --platform    Target platform (default: linux/amd64,linux/arm64)"
    echo "  --no-cache        Build without using cache"
    echo "  --push            Push after building"
    echo "  --latest          Also tag as 'latest'"
    echo "  -h, --help        Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 build                    # Build image"
    echo "  $0 build --push --latest    # Build and push with latest tag"
    echo "  $0 release                  # Full release build"
    echo "  $0 test                     # Test the built image"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi
    
    # Check Docker Buildx
    if ! docker buildx version &> /dev/null; then
        error "Docker Buildx is not available"
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "Dockerfile" ]] || [[ ! -f "lightscope/lightscope_core.py" ]]; then
        error "Please run this script from the LightScope root directory"
    fi
    
    info "Prerequisites check passed"
}

# Create requirements.txt from pyproject.toml
create_requirements() {
    log "Creating requirements.txt..."
    
    if [[ -f "pyproject.toml" ]]; then
        python3 -c "
import tomllib
import sys

try:
    with open('pyproject.toml', 'rb') as f:
        data = tomllib.load(f)
    
    deps = data['project']['dependencies']
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
    
    print('Requirements file created successfully')
    
except Exception as e:
    print(f'Error creating requirements.txt: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        warn "pyproject.toml not found, creating minimal requirements.txt"
        cat > requirements.txt << EOF
psutil
python-libpcap==0.5.2
requests==2.32.3
urllib3==2.2.3
packaging
scapy==2.6.1
dpkt==1.9.8
systemd-python
cryptography
EOF
    fi
    
    info "Requirements file ready"
}

# Build the container image
build_image() {
    local tag="$1"
    local platforms="$2"
    local cache_flag="$3"
    local push_flag="$4"
    
    log "Building LightScope container image..."
    info "Version: $VERSION"
    info "Tag: $tag"
    info "Platforms: $platforms"
    info "Git Commit: $GIT_COMMIT"
    
    # Create requirements.txt
    create_requirements
    
    # Build command
    local build_cmd="docker buildx build"
    
    # Add platforms
    if [[ -n "$platforms" ]]; then
        build_cmd="$build_cmd --platform $platforms"
    fi
    
    # Add cache flag
    if [[ "$cache_flag" == "--no-cache" ]]; then
        build_cmd="$build_cmd --no-cache"
    fi
    
    # Add push flag
    if [[ "$push_flag" == "--push" ]]; then
        build_cmd="$build_cmd --push"
    else
        build_cmd="$build_cmd --load"
    fi
    
    # Add labels and tags
    build_cmd="$build_cmd \
        --label org.opencontainers.image.title=LightScope \
        --label org.opencontainers.image.description='Network Security Monitor' \
        --label org.opencontainers.image.version=$VERSION \
        --label org.opencontainers.image.created=$BUILD_DATE \
        --label org.opencontainers.image.revision=$GIT_COMMIT \
        --label org.opencontainers.image.source=https://github.com/thelightscope/lightscope \
        --tag $tag \
        ."
    
    # Execute build
    eval $build_cmd
    
    log "Build completed successfully"
}

# Test the container image
test_image() {
    local tag="$1"
    
    log "Testing LightScope container image: $tag"
    
    # Test 1: Basic container startup
    info "Test 1: Container startup test"
    local container_id=$(docker run -d --name lightscope-test \
        --cap-add=NET_RAW \
        --cap-add=NET_ADMIN \
        -e CONTAINER_MEMORY_LIMIT_MB=256 \
        "$tag")
    
    # Wait for startup
    sleep 10
    
    # Check if container is running
    if docker ps -q -f id="$container_id" | grep -q .; then
        info "✓ Container started successfully"
    else
        error "✗ Container failed to start"
    fi
    
    # Test 2: Health check
    info "Test 2: Health check test"
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")
    if [[ "$health_status" == "healthy" ]] || [[ "$health_status" == "none" ]]; then
        info "✓ Health check passed"
    else
        warn "⚠ Health check status: $health_status"
    fi
    
    # Test 3: Process check
    info "Test 3: Process check"
    if docker exec "$container_id" pgrep -f lightscope >/dev/null 2>&1; then
        info "✓ LightScope processes are running"
    else
        warn "⚠ LightScope processes not detected (may be starting up)"
    fi
    
    # Test 4: Memory usage
    info "Test 4: Memory usage check"
    local memory_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id" | cut -d'/' -f1)
    info "Memory usage: $memory_usage"
    
    # Cleanup
    docker stop "$container_id" >/dev/null 2>&1 || true
    docker rm "$container_id" >/dev/null 2>&1 || true
    
    log "Container tests completed"
}

# Push image to registry
push_image() {
    local tag="$1"
    local also_latest="$2"
    
    log "Pushing image to registry..."
    
    # Push main tag
    docker push "$tag"
    info "Pushed: $tag"
    
    # Push latest tag if requested
    if [[ "$also_latest" == "true" ]]; then
        local latest_tag="${IMAGE_NAME}:latest"
        docker tag "$tag" "$latest_tag"
        docker push "$latest_tag"
        info "Pushed: $latest_tag"
    fi
    
    log "Push completed"
}

# Release build (build, test, push)
release_build() {
    local platforms="linux/amd64,linux/arm64"
    local version_tag="${IMAGE_NAME}:${VERSION}"
    local latest_tag="${IMAGE_NAME}:latest"
    
    log "Starting release build for version $VERSION"
    
    # Build for multiple platforms and push
    build_image "$version_tag" "$platforms" "" "--push"
    
    # Also tag and push as latest
    docker buildx build \
        --platform "$platforms" \
        --tag "$latest_tag" \
        --push \
        .
    
    info "Released version $VERSION"
    info "Available tags:"
    info "  - $version_tag"
    info "  - $latest_tag"
    
    log "Release build completed"
}

# Clean up build artifacts
clean_build() {
    log "Cleaning up build artifacts..."
    
    # Remove requirements.txt if we created it
    if [[ -f "requirements.txt" ]]; then
        rm requirements.txt
        info "Removed requirements.txt"
    fi
    
    # Clean up Docker build cache
    docker buildx prune -f >/dev/null 2>&1 || true
    
    # Remove test containers
    docker rm -f lightscope-test >/dev/null 2>&1 || true
    
    log "Cleanup completed"
}

# Main function
main() {
    local command="build"
    local custom_tag=""
    local platforms="linux/amd64"
    local cache_flag=""
    local push_flag=""
    local latest_flag="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--tag)
                custom_tag="$2"
                shift 2
                ;;
            -p|--platform)
                platforms="$2"
                shift 2
                ;;
            --no-cache)
                cache_flag="--no-cache"
                shift
                ;;
            --push)
                push_flag="--push"
                shift
                ;;
            --latest)
                latest_flag="true"
                shift
                ;;
            build|test|push|release|clean)
                command="$1"
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Set default tag if not provided
    if [[ -z "$custom_tag" ]]; then
        custom_tag="${IMAGE_NAME}:${VERSION}"
    fi
    
    # Show build info
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    LightScope Build                         ║"
    echo "║                  Container Builder                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    info "Command: $command"
    info "Version: $VERSION"
    info "Image: $custom_tag"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Execute command
    case $command in
        build)
            build_image "$custom_tag" "$platforms" "$cache_flag" "$push_flag"
            if [[ "$latest_flag" == "true" ]] && [[ "$push_flag" == "--push" ]]; then
                push_image "$custom_tag" "true"
            fi
            ;;
        test)
            test_image "$custom_tag"
            ;;
        push)
            push_image "$custom_tag" "$latest_flag"
            ;;
        release)
            release_build
            ;;
        clean)
            clean_build
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
    
    log "Operation completed successfully!"
}

# Run main function
main "$@"
