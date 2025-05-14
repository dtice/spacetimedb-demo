#!/bin/bash -xe

# Create spacetimedb user
sudo mkdir /stdb
sudo useradd --system spacetimedb
sudo chown spacetimedb:spacetimedb /stdb

# Install spacetimedb as new user
sudo -u spacetimedb bash -c 'curl -sSf https://install.spacetimedb.com | sh -s -- --root-dir /stdb --yes'

# Create spacetimedb and start systemd service
sudo cp /home/spacetimedb/spacetimedb.service /etc/systemd/system/
sudo systemctl enable spacetimedb
sudo systemctl start spacetimedb

# Install and configure nginx
sudo yum update
sudo yum install nginx -y
sudo cp /home/spacetimedb/spacetimedb.conf /etc/nginx/conf.d/
sudo systemctl restart nginx

# Install and configure certbot
# sudo yum install certbot python3-certbot-nginx -y
# sudo certbot --nginx -d spacetime.dilltice.com
# sudo systemctl restart nginx
# sudo systemctl status certbot.timer