#!/bin/bash
# =================================================================
# Abu 3meer Dedicated Ubuntu Server LTS Provisioning Script
# =================================================================
set -e

TARGET_USER="${SUDO_USER:-$USER}"

echo "=== 1. Updating System & Enabling Unattended Security Upgrades ==="
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y unattended-upgrades fail2ban ufw htop curl git jq gnupg lsb-release ca-certificates
sudo dpkg-reconfigure -plow unattended-upgrades

echo "=== 2. Configuring Firewall (UFW) ==="
# Only SSH is opened; API and DB are reached through Cloudflare Tunnel
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw --force enable

echo "=== 3. Hardening SSH & Fail2ban ==="
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "=== 4. Installing Docker Engine & Docker Compose ==="
if ! command -v docker &> /dev/null; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$TARGET_USER"
fi

echo "=== 5. Optimizing Host Kernel for PostgreSQL & High Network Throughput ==="
sudo tee /etc/sysctl.d/99-abu3meer.conf << 'SYSCTL'
# Memory & Swap optimization
vm.swappiness = 10
vm.overcommit_memory = 1
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Network stack tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
SYSCTL

sudo sysctl --system

echo "=== 6. Creating Systemd Service for Auto-Restart After Power Failure / Reboot ==="
sudo tee /etc/systemd/system/abu3meer-backend.service << SERVICE
[Unit]
Description=Abu 3meer Production Docker Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/abu3meer/server
ExecStart=/usr/bin/docker compose --profile production up -d --build
ExecStop=/usr/bin/docker compose --profile production down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable abu3meer-backend.service

echo "=== Server Provisioning Complete! ==="
