#!/bin/bash

# Health check script for SpacetimeDB
# This script checks if SpacetimeDB and Nginx are running properly

check_spacetimedb() {
    if systemctl is-active --quiet spacetimedb; then
        echo "SpacetimeDB service is running"
        
        # Check if the port is responding
        if curl -f -s http://localhost:3000/v1/identity > /dev/null; then
            echo "SpacetimeDB endpoint is responding"
            return 0
        else
            echo "SpacetimeDB endpoint is not responding"
            return 1
        fi
    else
        echo "SpacetimeDB service is not running"
        return 1
    fi
}

check_nginx() {
    if systemctl is-active --quiet nginx; then
        echo "Nginx service is running"
        
        # Check if nginx config is valid
        if nginx -t 2>/dev/null; then
            echo "Nginx configuration is valid"
            return 0
        else
            echo "Nginx configuration is invalid"
            return 1
        fi
    else
        echo "Nginx service is not running"
        return 1
    fi
}

restart_if_needed() {
    local service=$1
    echo "Attempting to restart $service..."
    
    if systemctl restart "$service"; then
        echo "$service restarted successfully"
        # Wait a bit for the service to start
        sleep 10
        return 0
    else
        echo "Failed to restart $service"
        return 1
    fi
}

# Main health check logic
echo "Starting health check at $(date)"

spacetimedb_healthy=true
nginx_healthy=true

if ! check_spacetimedb; then
    spacetimedb_healthy=false
    restart_if_needed spacetimedb
    if ! check_spacetimedb; then
        echo "CRITICAL: SpacetimeDB failed to restart properly"
        spacetimedb_healthy=false
    else
        spacetimedb_healthy=true
    fi
fi

if ! check_nginx; then
    nginx_healthy=false
    restart_if_needed nginx
    if ! check_nginx; then
        echo "CRITICAL: Nginx failed to restart properly"
        nginx_healthy=false
    else
        nginx_healthy=true
    fi
fi

if $spacetimedb_healthy && $nginx_healthy; then
    echo "All services are healthy"
    exit 0
else
    echo "One or more services are unhealthy"
    exit 1
fi
