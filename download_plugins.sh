#!/bin/sh
# This script downloads a single SonarQube plugin from a specified URL.
# It is intended to be run as an initialization container.

set -e # Exit immediately if a command exits with a non-zero status.

# Define the target directory for plugins within the SonarQube extensions volume
PLUGIN_DIR="/opt/sonarqube/extensions/plugins"

echo "Starting plugin download script for sonar-cnes-report ${CNESREPORT_VERSION}..."

# Ensure the plugins directory exists
mkdir -p "$PLUGIN_DIR"

# Install curl (ensure it's available in the alpine image)
apk update && apk add --no-cache curl

# Define the URL using the environment variable
PLUGIN_URL="https://github.com/cnescatlab/sonar-cnes-report/releases/download/${CNESREPORT_VERSION}/sonar-cnes-report-${CNESREPORT_VERSION}.jar"
# Define the expected filename
PLUGIN_FILENAME="sonar-cnes-report-${CNESREPORT_VERSION}.jar"
# Define the full path where the plugin should be saved
PLUGIN_DEST="$PLUGIN_DIR/$PLUGIN_FILENAME"


echo "Downloading ${PLUGIN_FILENAME} from ${PLUGIN_URL}..."

# Use curl to download the file
# -L: Follow redirects
# -s: Silent mode (can remove for more output during download)
# -f: Fail fast (exit with non-zero status on error)
# -o: Output file path
curl -L -s -f -o "$PLUGIN_DEST" "$PLUGIN_URL";

# Check the exit status of the last command (curl).
if [ $? -ne 0 ]; then
  echo "Error downloading ${PLUGIN_URL}";
  # Clean up any partial file if download failed
  rm -f "$PLUGIN_DEST"
  exit 1; # Exit the script with an error status
fi

echo "${PLUGIN_FILENAME} download complete."
exit 0 # Indicate success