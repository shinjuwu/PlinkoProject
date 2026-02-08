#!/bin/bash
# =============================================================================
# VM Environment Init Script
# =============================================================================
# Run this on each GCP VM after creation (Ubuntu 22.04 / Debian 12).
# Installs: Docker, Docker Compose, openssl, and common tools.
#
# Usage:
#   sudo bash vm-init.sh
# =============================================================================

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo: sudo bash vm-init.sh"
    exit 1
fi

echo "=================================================="
echo "  VM Environment Setup"
echo "=================================================="

# ─── 1. System update ───

echo "[1/4] Updating system packages..."
apt-get update -y
apt-get upgrade -y

# ─── 2. Install Docker ───

echo "[2/4] Installing Docker..."
if command -v docker &>/dev/null; then
    echo "Docker already installed: $(docker --version)"
else
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings

    # Detect distro (ubuntu or debian)
    . /etc/os-release
    DISTRO="$ID"  # "ubuntu" or "debian"

    curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/${DISTRO} ${VERSION_CODENAME} stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
fi

# ─── 3. Add user to docker group ───

echo "[3/4] Configuring docker group..."
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" != "root" ]; then
    usermod -aG docker "$REAL_USER"
    echo "Added $REAL_USER to docker group (re-login to take effect)"
fi

# ─── 4. Install helper tools ───

echo "[4/4] Installing helper tools..."
apt-get install -y openssl curl wget htop

# ─── 5. Create deploy directory ───

DEPLOY_DIR="/opt/deploy"
mkdir -p "$DEPLOY_DIR"
if [ "$REAL_USER" != "root" ]; then
    chown "$REAL_USER":"$REAL_USER" "$DEPLOY_DIR"
fi

# ─── Done ───

echo ""
echo "=================================================="
echo "  Setup Complete!"
echo "=================================================="
echo ""
docker --version
docker compose version
echo ""
echo "Deploy directory: $DEPLOY_DIR"
echo ""
echo "IMPORTANT: Log out and log back in for docker group to take effect."
echo "    exit"
echo "    gcloud compute ssh $(hostname) --zone=YOUR_ZONE"
echo ""
echo "Next steps:"
echo "  1. Upload project:  gcloud compute scp --recurse /local/project $REAL_USER@$(hostname):$DEPLOY_DIR/ --zone=ZONE"
echo "  2. Run setup.sh:    cd $DEPLOY_DIR/deployment-project && bash setup.sh"
echo "  3. Follow DEPLOY_GUIDE.md"
echo "=================================================="
