#!/bin/bash

# Define the service URL, defaulting to http://localhost:11434 if not set
SERVICE_URL=${SERVICE_URL:-http://localhost:11434}

# Check if CLOUDFLARE_TUNNEL_TOKEN is provided
if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    # If the token is not provided, use trycloudflare.com
    echo "No CLOUDFLARE_TUNNEL_TOKEN provided. Starting cloudflared with trycloudflare.com..."
    cloudflared tunnel --no-autoupdate --metrics localhost:55555 --url $SERVICE_URL &
else
    # If the token is provided, use it to run the tunnel
    echo "Starting cloudflared with provided CLOUDFLARE_TUNNEL_TOKEN..."
    cloudflared tunnel --no-autoupdate run --token $CLOUDFLARE_TUNNEL_TOKEN --url $SERVICE_URL &
fi

# Wait for the tunnel to establish and capture the hostname
while :; do
    OUTPUT=$(wget -qO- http://localhost:55555/quicktunnel)
    if [[ $OUTPUT == *"hostname"* ]]; then
        HOSTNAME=$(echo $OUTPUT | grep -oP '(?<="hostname":")[^"]+')
        echo "Tunnel established with hostname: $HOSTNAME"
        
        # Or send hostname to an API
        curl -X POST -H "Content-Type: application/json" -d "{\"hostname\":\"$HOSTNAME\"}" https://677f60590476123f76a62811.mockapi.io/api/v1/hostname
        
        break
    else
        echo "Waiting for tunnel to establish..."
        sleep 1
    fi
done

# Start the main application
exec /bin/ollama serve
