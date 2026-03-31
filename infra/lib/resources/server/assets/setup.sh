#!/bin/bash
# Enhanced setup script with better error handling and logging
set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/spacetimedb-setup.log
}

log "Starting SpacetimeDB installation and configuration"

# Install nginx first to ensure directories exist
log "Updating system packages"
sudo yum update -y

log "Installing nginx"
sudo yum install nginx -y
sudo mkdir -p /etc/nginx/conf.d

# Create spacetimedb user
log "Creating spacetimedb user and directories"
sudo mkdir -p /stdb
sudo useradd --system spacetimedb 2>/dev/null || log "User spacetimedb already exists"
sudo chown spacetimedb:spacetimedb /stdb

# Install spacetimedb as new user
log "Installing SpacetimeDB"
sudo -u spacetimedb bash -c 'curl -sSf https://install.spacetimedb.com | sh -s -- --root-dir /stdb --yes'

# Verify SpacetimeDB installation
if [ -f "/stdb/spacetime" ]; then
    log "SpacetimeDB installed successfully"
    sudo chmod +x /stdb/spacetime
else
    log "ERROR: SpacetimeDB installation failed"
    exit 1
fi
# Copy service files from current directory to the appropriate locations
SCRIPT_DIR="$(pwd)"
log "Current directory: ${SCRIPT_DIR}"
log "Listing files in current directory:"
ls -la ${SCRIPT_DIR}

# Check if service files exist
if [ -f "${SCRIPT_DIR}/spacetimedb.service" ]; then
    sudo cp "${SCRIPT_DIR}/spacetimedb.service" /etc/systemd/system/
    log "Copied spacetimedb.service to /etc/systemd/system/"
else
    log "ERROR: spacetimedb.service file not found in ${SCRIPT_DIR}"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/spacetimedb.conf" ]; then
    sudo cp "${SCRIPT_DIR}/spacetimedb.conf" /etc/nginx/conf.d/
    log "Copied spacetimedb.conf to /etc/nginx/conf.d/"
else
    log "ERROR: spacetimedb.conf file not found in ${SCRIPT_DIR}"
    exit 1
fi

# Copy health check script
if [ -f "${SCRIPT_DIR}/health-check.sh" ]; then
    sudo cp "${SCRIPT_DIR}/health-check.sh" /usr/local/bin/
    sudo chmod +x /usr/local/bin/health-check.sh
    log "Copied health-check.sh to /usr/local/bin/"
else
    log "WARNING: health-check.sh file not found in ${SCRIPT_DIR}"
fi

# Copy backup script
if [ -f "${SCRIPT_DIR}/backup.sh" ]; then
    sudo cp "${SCRIPT_DIR}/backup.sh" /usr/local/bin/spacetimedb-backup.sh
    sudo chmod +x /usr/local/bin/spacetimedb-backup.sh
    log "Copied backup.sh to /usr/local/bin/"
else
    log "WARNING: backup.sh file not found in ${SCRIPT_DIR}"
fi

# Create spacetimedb and start systemd service
log "Starting SpacetimeDB service"
sudo systemctl daemon-reload
sudo systemctl enable spacetimedb
sudo systemctl start spacetimedb

# Verify service started
if systemctl is-active --quiet spacetimedb; then
    log "SpacetimeDB service started successfully"
else
    log "ERROR: SpacetimeDB service failed to start"
    sudo journalctl -u spacetimedb --no-pager | tail -20
    exit 1
fi

# Start nginx service
log "Starting Nginx service"
sudo systemctl enable nginx
sudo systemctl start nginx

# Verify nginx started
if systemctl is-active --quiet nginx; then
    log "Nginx service started successfully"
else
    log "ERROR: Nginx service failed to start"
    sudo journalctl -u nginx --no-pager | tail -20
    exit 1
fi
# Install and configure certbot
log "Installing certbot and nginx plugin..."
# For Amazon Linux, we need to install certbot from EPEL or use pip
sudo yum install -y python3-pip
sudo pip3 install certbot certbot-nginx

# Alternative method if the above fails:
# sudo yum install -y epel-release
# sudo yum install -y certbot python3-certbot-nginx

# Test certbot installation
if command -v certbot &> /dev/null; then
    log "Certbot installed successfully"
else
    log "ERROR: Certbot installation failed"
    exit 1
fi

log "Requesting SSL certificate..."
sudo certbot --nginx -d spacetime.dilltice.com --non-interactive --agree-tos -m dillon.tice@gmail.com || log "Certbot failed, will need to run manually later"

log "Restarting Nginx with SSL configuration"
sudo systemctl restart nginx

# Set up auto renewal
log "Setting up SSL certificate auto-renewal"
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Set up health check cron job
log "Setting up health check monitoring"
echo "*/5 * * * * root /usr/local/bin/health-check.sh >> /var/log/health-check.log 2>&1" | sudo tee /etc/cron.d/spacetimedb-health-check

# Set up backup cron job (daily at 2 AM)
log "Setting up automated backups"
echo "0 2 * * * root /usr/local/bin/spacetimedb-backup.sh >> /var/log/spacetimedb-backup.log 2>&1" | sudo tee /etc/cron.d/spacetimedb-backup

sudo systemctl restart crond

# Create log rotation configuration
log "Setting up log rotation"
sudo tee /etc/logrotate.d/spacetimedb > /dev/null <<EOF
/var/log/spacetimedb-setup.log
/var/log/health-check.log
/var/log/spacetimedb-backup.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

log "Setup completed successfully!"
log "Services status:"
sudo systemctl status spacetimedb --no-pager
sudo systemctl status nginx --no-pager
log "Installation and configuration complete"
