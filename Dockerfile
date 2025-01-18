# Use the existing ollama Dockerfile as the base
FROM ollama/ollama

# Update and install wget to download cloudflared
RUN apt-get update && apt-get install -y wget curl

# Run ollama in the background so we can embedd the model
RUN nohup bash -c "ollama serve &" && \
    until curl -s http://127.0.0.1:11434 > /dev/null; do \
        echo "Waiting for ollama to start..."; \
        sleep 5; \
    done && \
    ollama pull llama3.2:3b

# Download and install cloudflared
RUN wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared-linux-amd64.deb

EXPOSE 11434

# Set the environment variable for the ollama host
ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_ORIGINS="*"

# Copy a script to start both ollama and cloudflared
COPY start_services.sh /start_services.sh
RUN chmod +x /start_services.sh

# Set the entrypoint to the script
ENTRYPOINT ["/start_services.sh"]
