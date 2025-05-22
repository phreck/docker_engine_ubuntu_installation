#!/bin/bash
#
# Script to reliably set up the official Docker APT repository
# on Debian-based systems (like Ubuntu).
#
# Installs prerequisites, adds Docker's GPG key, and configures the APT source list.
# Assumes it's being run on a supported Debian/Ubuntu derivative.
#

# --- Safety Checks ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Ensure pipelines return the exit status of the last command that failed.
set -o pipefail

# Check for root/sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ This script requires root/sudo privileges to run." >&2
  exit 1
fi

echo "🚀 Setting up Docker APT repository..."

# --- Main Script ---

# 1. Install Prerequisites
echo "   - Updating package list and installing prerequisites..."
# Run update once before installing needed packages
sudo apt-get update
# Install packages needed for HTTPS transport, GPG key handling, and codename detection
# Use -y for non-interactive installation
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
echo "✅ Prerequisites installed."

# 2. Add Docker's Official GPG Key
# Define standard directory for keyring storage
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_PATH="$KEYRING_DIR/docker.gpg" # Use .gpg extension (binary format) as recommended

echo "   - Ensuring keyring directory '$KEYRING_DIR' exists..."
# Create the directory with secure permissions if it doesn't exist
sudo install -m 0755 -d "$KEYRING_DIR"

echo "   - Downloading and adding Docker's official GPG key to '$KEYRING_PATH'..."
# Download the key, dearmor it (convert from ASCII to binary), and save it
# -fsSL: Fail silently, show errors, follow redirects, Location aware
# gpg --dearmor: Convert the key to the format apt expects
# --batch --yes: Ensure gpg doesn't prompt if overwriting the file
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --batch --yes -o "$KEYRING_PATH"

echo "   - Setting permissions for the GPG key file..."
# Ensure the key file is readable by the apt process
sudo chmod a+r "$KEYRING_PATH"
echo "✅ Docker GPG key added and permissions set."

# 3. Set up the Docker APT Repository Source List
echo "   - Adding Docker repository to APT sources..."
# Determine OS codename reliably using lsb_release
OS_CODENAME=$(lsb_release -cs)
# Determine architecture reliably using dpkg
ARCHITECTURE=$(dpkg --print-architecture)
# Define the repository string using the key path, architecture, and codename
REPO_STRING="deb [arch=${ARCHITECTURE} signed-by=${KEYRING_PATH}] https://download.docker.com/linux/ubuntu ${OS_CODENAME} stable"
# Define the target sources list file
SOURCES_LIST_FILE="/etc/apt/sources.list.d/docker.list"

# Write the repository information to the sources list file
echo "$REPO_STRING" | sudo tee "$SOURCES_LIST_FILE" > /dev/null
echo "✅ Docker repository added to '$SOURCES_LIST_FILE'."

# 4. Update Package List with New Repository
echo "   - Updating package list to include Docker repository..."
sudo apt-get update
echo "✅ Package list updated successfully."
echo # Newline for readability

# --- Final Instructions ---
echo "🎉 Docker APT repository setup complete!"
echo "   You can now proceed to install Docker packages using apt-get."
echo "   Example:"
echo "   sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

# Explicitly exit with success status
exit 0