# Use the provided base image
FROM ghcr.io/berriai/litellm:main-latest

# Set the working directory to /app
WORKDIR /app

# Copy the configuration file into the container at /app
COPY litellm-config.yaml .

# Make sure your entrypoint.sh is executable
RUN chmod +x entrypoint.sh

# Expose the necessary port
EXPOSE 4000/tcp

# Override the CMD instruction with your desired command and arguments
# WARNING: FOR PROD DO NOT USE `--detailed_debug` it slows down response times, instead use the following CMD
CMD ["--port", "4000", "--config", "litellm-config.yaml", "--num_workers", "8"]

# CMD ["--port", "4000", "--config", "litellm-config.yaml", "--num_workers", "8", "--detailed_debug"]