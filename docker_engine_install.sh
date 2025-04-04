#!/bin/bash
#
# Script to uninstall old/conflicting Docker packages and install the latest
# official Docker Engine, CLI, containerd, and Docker Compose plugin on
# Debian-based systems (like Ubuntu).
#
# Based on the official Docker installation guide.
#

# --- Configuration ---
# Add any user other than the one running the script if needed
# Example: ADDITIONAL_USERS=("user1" "user2")
ADDITIONAL_USERS=()

# --- Safety Checks ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
# set -u # Commented out as $SUDO_USER might be unset if run directly as root
# Ensure pipelines return the exit status of the last command that failed.
set -o pipefail

# Check for root/sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ This script requires root/sudo privileges to run." >&2
  exit 1
fi

# --- Main Script ---

echo "🚀 Starting Docker Engine installation..."

# 1. Uninstall Old/Conflicting Versions
echo "🔎 Checking for and uninstalling older Docker versions..."
OLD_PACKAGES=(
    docker.io docker-doc docker-compose docker-compose-v2 podman-docker
    containerd runc docker-engine
)
PACKAGES_TO_REMOVE=()
for pkg in "${OLD_PACKAGES[@]}"; do
    # Check if package is installed before trying to remove
    if dpkg -s "$pkg" &> /dev/null; then
        echo "   - Found '$pkg', marking for removal."
        PACKAGES_TO_REMOVE+=("$pkg")
    else
        echo "   - '$pkg' not installed."
    fi
done

if [ ${#PACKAGES_TO_REMOVE[@]} -gt 0 ]; then
    echo "   Removing identified packages: ${PACKAGES_TO_REMOVE[*]}"
    sudo apt-get remove -y "${PACKAGES_TO_REMOVE[@]}"
    sudo apt-get autoremove -y # Clean up dependencies
    echo "✅ Old packages removed."
else
    echo "✅ No conflicting old packages found to remove."
fi
echo # Newline for readability

# 2. Set up Docker's APT Repository
echo "🛠️ Setting up Docker's official APT repository..."
# Update package index and install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_PATH="$KEYRING_DIR/docker.gpg"
sudo install -m 0755 -d "$KEYRING_DIR"
# Use --batch and --yes to avoid prompts if overwriting
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --batch --yes -o "$KEYRING_PATH"
sudo chmod a+r "$KEYRING_PATH" # Ensure readable by apt

# Set up the repository
REPO_STRING="deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING_PATH] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
echo "$REPO_STRING" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again with the new repository
sudo apt-get update
echo "✅ Docker APT repository set up."
echo # Newline

# 3. Install Docker Engine
echo "📦 Installing Docker Engine, CLI, containerd, and plugins..."
DOCKER_PACKAGES=(
    docker-ce docker-ce-cli containerd.io
    docker-buildx-plugin docker-compose-plugin
)
sudo apt-get install -y "${DOCKER_PACKAGES[@]}"
echo "✅ Docker packages installed."
echo # Newline

# 4. Post-installation Steps
echo "⚙️ Performing post-installation steps..."

# Create docker group (if it doesn't exist)
if ! getent group docker > /dev/null; then
    sudo groupadd docker
    echo "   - Created 'docker' group."
else
    echo "   - 'docker' group already exists."
fi

# Add the user who invoked sudo (or current user if run as root) to the docker group
# $SUDO_USER is set by sudo, $USER is the fallback.
CURRENT_USER=${SUDO_USER:-$(whoami)}
if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
    if groups "$CURRENT_USER" | grep -q '\bdocker\b'; then
        echo "   - User '$CURRENT_USER' is already in the 'docker' group."
    else
        sudo usermod -aG docker "$CURRENT_USER"
        echo "   - Added user '$CURRENT_USER' to the 'docker' group."
        NEEDS_RELOGIN=true
    fi
else
     echo "   - Skipping adding current user to 'docker' group (running as root or user unknown)."
fi

# Add any additional specified users
for user in "${ADDITIONAL_USERS[@]}"; do
    if id "$user" &>/dev/null; then
        if groups "$user" | grep -q '\bdocker\b'; then
            echo "   - Additional user '$user' is already in the 'docker' group."
        else
            sudo usermod -aG docker "$user"
            echo "   - Added additional user '$user' to the 'docker' group."
            NEEDS_RELOGIN=true
         fi
    else
        echo "   - Warning: Additional user '$user' not found, skipping." >&2
    fi
done


# Enable and start Docker services
echo "   - Enabling and starting Docker services (docker.service, containerd.service)..."
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
sudo systemctl start docker.service
sudo systemctl start containerd.service

echo "✅ Post-installation steps completed."
echo # Newline

# 5. Verification
echo "🧪 Verifying installation by running hello-world container (using sudo)..."
if sudo docker run hello-world; then
  echo "✅ Docker appears to be installed and working correctly!"
else
  echo "❌ The 'sudo docker run hello-world' command failed." >&2
  echo "   Please check the Docker service status: sudo systemctl status docker" >&2
  exit 1
fi
echo # Newline

# --- Final Instructions ---
echo "🎉 Docker installation successful!"
if [ "$NEEDS_RELOGIN" = true ]; then
    echo "⚠️ IMPORTANT: For users added to the 'docker' group (${CURRENT_USER:-''} ${ADDITIONAL_USERS[*]}),"
    echo "   you must log out and log back in, or run 'newgrp docker',"
    echo "   before you can run Docker commands without sudo."
fi
echo "   You can test Docker without sudo (after re-logging in) by running:"
echo "   docker run hello-world"

exit 0