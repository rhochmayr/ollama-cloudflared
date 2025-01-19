#!/bin/bash
#set -euo pipefail

# ----------------------------
# Logging Function
# ----------------------------
log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $*"
}

# ----------------------------
# Required Environment Variables
# ----------------------------
: "${SUPABASE_INSTANCE_ID:?Please set SUPABASE_INSTANCE_ID}"
: "${SUPABASE_URL:?Please set SUPABASE_URL}"               # e.g. https://stfdtptqjrkgzefbrfal.supabase.co
: "${SUPABASE_ANON_KEY:?Please set SUPABASE_ANON_KEY}"       # Supabase anon key
SERVICE_URL=${SERVICE_URL:-http://localhost:11434}         # Defaults if not provided

# Construct the PATCH URL and headers based on the values above.
PATCH_URL="${SUPABASE_URL}/rest/v1/ollama_instances?id=eq.${SUPABASE_INSTANCE_ID}"
HEADER_APIKEY="apikey: ${SUPABASE_ANON_KEY}"
HEADER_AUTH="Authorization: Bearer ${SUPABASE_ANON_KEY}"
HEADER_CONTENT="Content-Type: application/json"
HEADER_PREFER="Prefer: return=minimal"

# ----------------------------
# Step 1: Notify Supabase: Starting
# ----------------------------
log "Patching instance status to 'starting'..."
curl -s -X PATCH "$PATCH_URL" \
    -H "$HEADER_APIKEY" \
    -H "$HEADER_AUTH" \
    -H "$HEADER_CONTENT" \
    -H "$HEADER_PREFER" \
    -d '{ "status": "starting" }'
log "Status patched to 'starting'."

# ----------------------------
# Step 2: Start Cloudflared Tunnel
# ----------------------------
if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    log "No CLOUDFLARE_TUNNEL_TOKEN provided. Starting cloudflared with trycloudflare.com..."
    cloudflared tunnel --no-autoupdate --metrics 0.0.0.0:55555 --url "$SERVICE_URL" &
else
    log "Starting cloudflared with provided CLOUDFLARE_TUNNEL_TOKEN..."
    cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" --url "$SERVICE_URL" &
fi

# ----------------------------
# Step 3: Wait for the Tunnel to Establish and Capture the Tunnel Address
# ----------------------------
log "Waiting for the tunnel to establish (polling http://localhost:55555/quicktunnel)..."
while true; do
    OUTPUT=$(wget -qO- http://localhost:55555/quicktunnel)
    if [[ "$OUTPUT" == *"hostname"* ]]; then
        # Extract the hostname. Adjust the regex as needed.
        TUNNEL_ADDRESS=$(echo "$OUTPUT" | grep -oP '(?<="hostname":")[^"]+')
        log "Tunnel established with hostname: $TUNNEL_ADDRESS"
        break
    else
        log "Tunnel not yet established. Waiting 1 second..."
        sleep 1
    fi
done

# ----------------------------
# Step 4: Update Supabase: Ready and Provide the Endpoint
# ----------------------------
log "Patching instance status to 'ready' with endpoint..."
json_data=$(printf '{"status": "ready", "endpoint": "%s"}' "https://$TUNNEL_ADDRESS")
log "PATCH URL: $PATCH_URL"
log "Sending data: $json_data"
curl -s -X PATCH "$PATCH_URL" \
    -H "$HEADER_APIKEY" \
    -H "$HEADER_AUTH" \
    -H "$HEADER_CONTENT" \
    -H "$HEADER_PREFER" \
    -d "$json_data"
log "Instance updated to 'ready' with endpoint $TUNNEL_ADDRESS."

# ----------------------------
# Step 5: Start the Main Application with a Timeout of 5 minutes
# ----------------------------
log "Starting main application..."
exec timeout 300 /bin/ollama serve
