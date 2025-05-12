# SonarQube with Custom Plugins via Docker Compose

This project provides a Docker Compose setup to run SonarQube along with a PostgreSQL database, and automatically pre-install custom plugins during startup.


## Prerequisites

Before you begin, ensure you have:

1.  **Docker:** Installed and running on your system.
    *   [Install Docker Engine](https://docs.docker.com/engine/install/)
2.  **Docker Compose:** Installed. This setup uses the `docker compose` CLI plugin (V2+).
    *   [Install Docker Compose](https://docs.docker.com/compose/install/)
3.  **Internet Access:** The initialization container needs internet access to download plugins.

## Setup

1.  **Navigate to the Project Directory:**
    ```bash
    cd my-sonarqube-setup
    ```

2.  **Create and Configure the `.env` file:**
    This file holds environment variables used by Docker Compose and the plugin download script, such as plugin versions. Create a file named `.env` in the `my-sonarqube-setup` directory and add the required variables.

    For example, if you only need the `sonar-cnes-report` plugin version `5.0.2`:

    ```dotenv
    # .env file

    # Specify the version for the CNES Report plugin
    CNESREPORT_VERSION=5.0.2

    # Add other plugin version variables here if needed
    # Example: ANSIBLE_LINT=5.4.1
    ```
    **Note:** Replace `5.0.2` with the actual version you need if different. If adding more plugins, add their corresponding `VARIABLE=version` lines here.

3.  **Create the Plugin Download Script (`download_plugins.sh`):**
    This script runs in a lightweight container *before* the main SonarQube service. It downloads the specified plugin JARs into a shared Docker volume. Create a file named `download_plugins.sh` in the `my-sonarqube-setup` directory and add the following content:

    ```bash
    #!/bin/sh
    # This script downloads SonarQube plugins from specified URLs.
    # It is intended to be run as an initialization container.

    set -e # Exit immediately if a command exits with a non-zero status.

    # Define the target directory for plugins within the SonarQube extensions volume
    PLUGIN_DIR="/opt/sonarqube/extensions/plugins"

    echo "Starting plugin download script..."

    # Ensure the plugins directory exists
    mkdir -p "$PLUGIN_DIR"
    echo "Ensured plugin directory exists: $PLUGIN_DIR" # Added confirmation

    # Install curl (ensure it's available in the alpine image)
    echo "Installing curl..."
    apk update && apk add --no-cache curl
    echo "Curl installed."

    # List of plugin URLs. These use environment variables passed into the container
    # by Docker Compose (which are sourced from your .env file).
    # Make sure the variables used here match the ones defined in your .env file
    # and passed via the docker-compose.yml environment block.
    PLUGINS="
    https://github.com/cnescatlab/sonar-cnes-report/releases/download/${CNESREPORT_VERSION}/sonar-cnes-report-${CNESREPORT_VERSION}.jar
    # Add other plugin URLs here if needed, using their respective variables:
    # https://github.com/sbaudoin/sonar-ansible/releases/download/v${ANSIBLE_LINT}/sonar-ansible-plugin-${ANSIBLE_LINT}.jar
    # ... list all your desired plugins here ...
    "

    # Iterate through URLs and download
    echo "Downloading plugins from the list..."
    echo "$PLUGINS" | while read url; do
      if [ -n "$url" ]; then # Check if line is not empty
        filename=$(basename "$url"); # Extract filename from URL
        echo "Attempting to download $filename from $url...";
        # Use curl to download the file
        # -L: Follow redirects
        # -s: Silent mode
        # -f: Fail fast (exit with non-zero status on error)
        # -o: Output file path
        curl -L -s -f -o "$PLUGIN_DIR/$filename" "$url";

        if [ $? -ne 0 ]; then
          echo "Error downloading $url";
          # Clean up any partial file if download failed
          rm -f "$PLUGIN_DIR/$filename"
          exit 1; # Exit the script with an error status
        fi
        echo "Successfully downloaded $filename."
      fi
    done

    echo "Plugin download complete."
    exit 0 # Indicate success
    ```
    **Note:** If you add more plugins to your `.env` file, make sure to add their corresponding URLs to the `PLUGINS` variable in this script. Use the exact variable names from your `.env` file.

4.  **Make the script executable:**
    ```bash
    chmod +x download_plugins.sh
    ```

5.  **Create the Docker Compose file (`docker-compose.yml`):**
    This file defines the services (PostgreSQL, plugin downloader, SonarQube), volumes, and network. Create a file named `docker-compose.yml` in the `my-sonarqube-setup` directory and add the following content:

    ```yaml
    # Save this as docker-compose.yml

    # Note: The 'version' attribute is obsolete in recent Docker Compose versions
    # and can be safely removed. Keeping it for compatibility with older syntax.
    version: "3.8"

    services:
      # PostgreSQL database for SonarQube
      postgres:
        image: postgres:13
        container_name: sonarqube_postgres
        environment:
          POSTGRES_USER: sonar
          POSTGRES_PASSWORD: sonar
          POSTGRES_DB: sonarqube
        ports:
          # Map PostgreSQL port on the host to the container port
          - "5432:5432"
        volumes:
          # Persistent volume for database data
          - postgres_data:/var/lib/postgresql/data
        networks:
          # Connect to the shared network
          - sonarnet

      # Service to download plugins into the shared volume before SonarQube starts.
      # This ensures plugins are available on the volume when SonarQube mounts it.
      # This service will run once and exit.
      sonarqube_init_plugins:
        image: alpine:latest # Use a lightweight image suitable for running shell scripts
        container_name: sonarqube_init_plugins_download
        # This service needs access to the sonarqube_extensions volume and the script file.
        volumes:
          # Mount the target SonarQube extensions volume where plugins should go
          - sonarqube_extensions:/opt/sonarqube/extensions
          # Mount the download script into the container
          - ./download_plugins.sh:/app/download_plugins.sh:ro # Mount script read-only
        working_dir: /app # Set working directory to where the script is mounted
        # Define the plugin versions as environment variables for this container.
        # Docker Compose will read the values from your host environment (.env file).
        environment:
          # Pass the variable needed by the download script from the .env file
          - CNESREPORT_VERSION=${CNESREPORT_VERSION}
          # Add other variables needed by your download_plugins.sh script here:
          # - ANSIBLE_LINT=${ANSIBLE_LINT}
          # ... list all variables used in the script ...
        # Command to execute the mounted script.
        # The script itself handles variable substitution and downloads.
        command: ["/app/download_plugins.sh"]
        networks:
          # Needs network access to download plugins from the internet
          - sonarnet
        # Ensure this container runs its command once and exits, does not restart automatically
        restart: "no"

      # SonarQube application service
      sonarqube:
        image: sonarqube:community
        container_name: sonarqube_ce
        # This service depends on postgres and the plugin download service.
        # This ensures SonarQube only starts after the database is ready
        # and the plugins have been successfully downloaded into the volume.
        depends_on:
          - postgres
          - sonarqube_init_plugins
        environment:
          # Database connection details (using the service name 'postgres')
          SONAR_JDBC_URL: jdbc:postgresql://postgres:5432/sonarqube
          SONAR_JDBC_USERNAME: sonar
          SONAR_JDBC_PASSWORD: sonar
          # Optional: Configure JVM memory settings if needed, especially with many plugins
          # uncomment and adjust values as necessary
          # SONAR_SEARCH_JAVA_OPTS: "-Xmx1g -Xms256m"
          # SONAR_WEB_JAVA_OPTS: "-Xmx512m -Xms256m"
          # SONAR_CE_JAVA_OPTS: "-Xmx512m -Xms256m"
        ports:
          # Map SonarQube web UI port on the host to the container port
          - "9000:9000"
        volumes:
          # Persistent volume for SonarQube data (configuration, logs, search index)
          - sonarqube_data:/opt/sonarqube/data
          # Persistent volume for extensions (plugins, etc.).
          # This volume is populated by the init_plugins service.
          - sonarqube_extensions:/opt/sonarqube/extensions
        networks:
          # Connect to the shared network
          - sonarnet
        # Optional: Add a healthcheck to verify SonarQube is fully started before considering it 'healthy'
        # uncomment and adjust if you need docker compose to wait longer for SonarQube
        # healthcheck:
        #   test: ["CMD", "curl", "-f", "http://localhost:9000/api/system/ping"]
        #   interval: 30s
        #   timeout: 10s
        #   retries: 5
        #   start_period: 60s # Gives SonarQube extra time to start up with plugins

    # Define the named volumes for persistence
    volumes:
      postgres_data:
      sonarqube_data:
      sonarqube_extensions:

    # Define the shared network
    networks:
      sonarnet:

    ```
    **Note:** Ensure the `environment` block in `sonarqube_init_plugins` passes *all* variables that you intend to use in the `download_plugins.sh` script (those used within `${...}`).

## Usage

1.  **Make sure you are in the `my-sonarqube-setup` directory.**

2.  **Start the services:**
    Docker Compose will read the `.env` file automatically and substitute the variables in `docker-compose.yml`.
    ```bash
    docker compose up -d
    ```
    This will:
    *   Create network and volumes if they don't exist.
    *   Start the `postgres` container.
    *   Start the `sonarqube_init_plugins` container, which runs the `download_plugins.sh` script to download the plugin(s) into the `sonarqube_extensions` volume. This container will then exit.
    *   Start the `sonarqube` container *after* the `sonarqube_init_plugins` container successfully exits. The `sonarqube` container will mount the `sonarqube_extensions` volume and find the downloaded plugin(s).

3.  **Check the plugin download logs:**
    Since the `sonarqube_init_plugins_download` container exits after running, you need to view its historical logs:
    ```bash
    docker compose logs sonarqube_init_plugins
    ```
    Verify that `curl` successfully downloaded the plugin(s) and the "Plugin download complete." message is present. If there were download errors, this is where you'll see them.

4.  **Check SonarQube logs:**
    Monitor the SonarQube container logs to ensure it starts up without issues:
    ```bash
    docker compose logs sonarqube
    ```
    Look for lines indicating the web server and compute engine are operational.

5.  **Access SonarQube:**
    Once the `sonarqube` container is running, access the SonarQube web interface in your browser:
    ```
    http://localhost:9000
    ```
    The default login is `admin` / `admin` (you will be prompted to change the password). Go to Administration -> Marketplace -> Installed to confirm your plugin(s) are listed.

## Stopping and Cleaning Up

To stop the running containers:
```bash
docker compose down
```
## Authors

- [@nani-1205](https://github.com/nani-1205)

- [@dattaprabhakar](https://github.com/dattaprabhakar)