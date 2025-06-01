#!/bin/bash
# Add error handling
set -e
# Install nginx first to ensure directories exist
sudo yum update -y
sudo yum install nginx -y
sudo mkdir -p /etc/nginx/conf.d
# Create spacetimedb user
sudo mkdir -p /stdb
sudo useradd --system spacetimedb 2>/dev/null || echo "User spacetimedb already exists"
sudo chown spacetimedb:spacetimedb /stdb
# Install spacetimedb as new user
sudo -u spacetimedb bash -c 'curl -sSf https://install.spacetimedb.com | sh -s -- --root-dir /stdb --yes'
# Copy service files from current directory to the appropriate locations
SCRIPT_DIR="$(pwd)"
echo "Current directory: ${SCRIPT_DIR}"
echo "Listing files in current directory:"
ls -la ${SCRIPT_DIR}
# Check if service files exist
if [ -f "${SCRIPT_DIR}/spacetimedb.service" ]; then
    sudo cp "${SCRIPT_DIR}/spacetimedb.service" /etc/systemd/system/
    echo "Copied spacetimedb.service to /etc/systemd/system/"
else
    echo "ERROR: spacetimedb.service file not found in ${SCRIPT_DIR}"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/spacetimedb.conf" ]; then
    sudo cp "${SCRIPT_DIR}/spacetimedb.conf" /etc/nginx/conf.d/
    echo "Copied spacetimedb.conf to /etc/nginx/conf.d/"
else
    echo "ERROR: spacetimedb.conf file not found in ${SCRIPT_DIR}"
    exit 1
fi
# Create spacetimedb and start systemd service
sudo systemctl daemon-reload
sudo systemctl enable spacetimedb
sudo systemctl start spacetimedb
echo "SpacetimeDB service enabled and started"
# Start nginx service
sudo systemctl enable nginx
sudo systemctl start nginx
echo "Nginx enabled and started"
# Install and configure certbot
echo "Installing certbot..."
sudo yum install -y certbot python3-certbot-nginx
echo "Requesting SSL certificate..."
sudo certbot --nginx -d spacetime.dilltice.com --non-interactive --agree-tos -m dillon.tice@gmail.com || echo "Certbot failed, will need to run manually later"
sudo systemctl restart nginx
echo "Nginx restarted with SSL configuration"
# Set up auto renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
echo "Certbot renewal timer enabled"
# Output success message
echo "Setup completed successfully!"
