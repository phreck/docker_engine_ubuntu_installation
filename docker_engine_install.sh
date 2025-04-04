#!/bin/bash
#
# Script to uninstall old/conflicting Docker packages and install the latest
# official Docker Engine, CLI, containerd, and Docker Compose plugin on
# Debian-based systems (like Ubuntu).
#
# Options:
#   -c : Create/update /etc/docker/daemon.json with default log rotation settings.
#   -d <path> : Configure Docker to use a custom data-root directory.
#   -h : Display this help message.
#
# Requires: curl, gnupg, lsb-release, jq
# Based on the official Docker installation guide.
#

# --- Configuration ---
# Add any user other than the one running the script if needed
# Example: ADDITIONAL_USERS=("user1" "user2")
ADDITIONAL_USERS=()

# Default configuration settings (used if -c is specified)
DEFAULT_DAEMON_CFG='{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "features": {
    "buildkit": true
  }
}'

# --- Script Options ---
CREATE_DAEMON_JSON=false
CUSTOM_DATA_ROOT=""

usage() {
  echo "Usage: $0 [-c] [-d <path>] [-h]"
  echo "  -c : Create or update /etc/docker/daemon.json with default log rotation."
  echo "  -d <path> : Set a custom Docker data-root directory (e.g., /mnt/docker-data)."
  echo "              The daemon will attempt to create this directory if it doesn't exist."
  echo "  -h : Display this help message."
  exit 1
}

# Parse command-line options
while getopts "cd:h" opt; do
  case ${opt} in
    c )
      CREATE_DAEMON_JSON=true
      ;;
    d )
      CUSTOM_DATA_ROOT="$OPTARG"
      ;;
    h )
      usage
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      usage
      ;;
  esac
done
shift $((OPTIND -1))

# Validate custom data root path (basic check)
if [ -n "$CUSTOM_DATA_ROOT" ] && [[ ! "$CUSTOM_DATA_ROOT" = /* ]]; then
    echo "❌ Error: Custom data-root path '$CUSTOM_DATA_ROOT' must be absolute." >&2
    exit 1
fi

# Determine if daemon.json needs management
MANAGE_DAEMON_JSON=false
if [ "$CREATE_DAEMON_JSON" = true ] || [ -n "$CUSTOM_DATA_ROOT" ]; then
    MANAGE_DAEMON_JSON=true
fi

# --- Safety Checks ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
# set -u
# Ensure pipelines return the exit status of the last command that failed.
set -o pipefail

# Check for root/sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ This script requires root/sudo privileges to run." >&2
  exit 1
fi

# --- Main Script ---

echo "🚀 Starting Docker Engine installation..."
if [ "$CREATE_DAEMON_JSON" = true ]; then
    echo "   (Option -c: Will configure default daemon settings)"
fi
if [ -n "$CUSTOM_DATA_ROOT" ]; then
    echo "   (Option -d: Will configure data-root to '$CUSTOM_DATA_ROOT')"
fi

# 1. Uninstall Old/Conflicting Versions
# (Code remains the same)
echo "🔎 Checking for and uninstalling older Docker versions..."
OLD_PACKAGES=(
    docker.io docker-doc docker-compose docker-compose-v2 podman-docker
    containerd runc docker-engine
)
PACKAGES_TO_REMOVE=()
for pkg in "${OLD_PACKAGES[@]}"; do
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
    sudo apt-get autoremove -y
    echo "✅ Old packages removed."
else
    echo "✅ No conflicting old packages found to remove."
fi
echo

# 2. Set up Docker's APT Repository & Install Prerequisites
echo "🛠️ Setting up Docker's official APT repository and prerequisites..."
sudo apt-get update
# Added jq prerequisite
sudo apt-get install -y ca-certificates curl gnupg lsb-release jq
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_PATH="$KEYRING_DIR/docker.gpg"
sudo install -m 0755 -d "$KEYRING_DIR"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --batch --yes -o "$KEYRING_PATH"
sudo chmod a+r "$KEYRING_PATH"
REPO_STRING="deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING_PATH] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
echo "$REPO_STRING" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
echo "✅ Docker APT repository & prerequisites set up (including jq)."
echo

# 3. Install Docker Engine
# (Code remains the same)
echo "📦 Installing Docker Engine, CLI, containerd, and plugins..."
DOCKER_PACKAGES=(
    docker-ce docker-ce-cli containerd.io
    docker-buildx-plugin docker-compose-plugin
)
sudo apt-get install -y "${DOCKER_PACKAGES[@]}"
echo "✅ Docker packages installed."
echo

# 4. Configure Docker Daemon (daemon.json) - Conditional
DAEMON_CONFIG_FILE="/etc/docker/daemon.json"
DAEMON_CONFIG_DIR=$(dirname "$DAEMON_CONFIG_FILE")
NEEDS_RESTART=false

if [ "$MANAGE_DAEMON_JSON" = true ]; then
    echo "⚙️ Configuring Docker daemon ($DAEMON_CONFIG_FILE)..."

    # Start with empty or existing JSON
    current_json="{}"
    if [ -f "$DAEMON_CONFIG_FILE" ]; then
        echo "   - Found existing configuration file."
        # Read existing config, handle potential errors
        if ! current_json=$(sudo jq -e . "$DAEMON_CONFIG_FILE"); then
             echo "   - Warning: Existing '$DAEMON_CONFIG_FILE' is not valid JSON. It will be overwritten." >&2
             current_json="{}" # Start fresh if invalid
        fi
    else
        echo "   - No existing configuration file found."
        # Ensure directory exists only if we are creating the file
         sudo install -d -m 755 "$DAEMON_CONFIG_DIR" # install -d creates if not exists
    fi

    # Build the desired state using jq merges
    desired_json="$current_json"
    if [ "$CREATE_DAEMON_JSON" = true ]; then
        echo "   - Merging default settings (log rotation, buildkit)..."
        # Merge default config into desired state (jq 'slurpfile' or direct string merge)
        # Using process substitution for cleaner merge: desired = current * default
         if ! desired_json=$(jq -n --argjson current "$desired_json" --argjson defaults "$DEFAULT_DAEMON_CFG" '$current * $defaults'); then
             echo "   - Error: Failed to merge default JSON settings." >&2
             # Decide how to handle: skip? error? For now, continue without defaults.
             desired_json="$current_json" # Revert to current state before merge attempt
         fi
    fi

    if [ -n "$CUSTOM_DATA_ROOT" ]; then
        echo "   - Merging custom data-root setting: '$CUSTOM_DATA_ROOT'..."
        # Merge data-root setting into desired state: desired + {"data-root": path}
        if ! desired_json=$(jq --arg path "$CUSTOM_DATA_ROOT" '. + {"data-root": $path}' <<< "$desired_json"); then
             echo "   - Error: Failed to merge data-root JSON setting." >&2
             # Decide how to handle: skip? error? For now, continue without data-root.
             # Revert might be complex if defaults were already merged, proceed with caution.
        fi
    fi

    # Compare current (on disk) with desired, write only if changed or file was new
    write_changes=false
    if ! sudo jq -e . "$DAEMON_CONFIG_FILE" > /dev/null 2>&1 ; then
        # File doesn't exist or is invalid, needs creation/overwrite
        write_changes=true
        echo "   - Creating/overwriting $DAEMON_CONFIG_FILE."
    else
        # File exists and is valid JSON, compare contents
        if ! echo "$desired_json" | sudo jq -e --argfile current "$DAEMON_CONFIG_FILE" '. == $current' > /dev/null; then
             write_changes=true
             echo "   - Configuration differs, updating $DAEMON_CONFIG_FILE."
        else
             echo "   - Desired configuration already matches $DAEMON_CONFIG_FILE. No changes needed."
        fi
    fi

    if [ "$write_changes" = true ]; then
        # Write the desired JSON content using sudo tee
        if echo "$desired_json" | sudo tee "$DAEMON_CONFIG_FILE" > /dev/null; then
            sudo chmod 644 "$DAEMON_CONFIG_FILE" # Set permissions
            echo "✅ $DAEMON_CONFIG_FILE configured."
            NEEDS_RESTART=true # Mark that Docker needs restart/reload
        else
            echo "❌ Error: Failed to write $DAEMON_CONFIG_FILE." >&2
            # Potentially exit here if this failure is critical
        fi
    fi
else
     echo "ℹ️ Skipping daemon.json configuration (options -c or -d not specified)."
fi
echo # Newline

# 5. Post-installation Steps (User/Group Management & Service Enable/Start/Restart)
# (Code largely the same, restart logic integrated)
echo "⚙️ Performing post-installation steps (user groups, services)..."

# Create docker group
if ! getent group docker > /dev/null; then
    sudo groupadd docker
    echo "   - Created 'docker' group."
else
    echo "   - 'docker' group already exists."
fi

# Add users
NEEDS_RELOGIN=false
CURRENT_USER=${SUDO_USER:-$(whoami)}
# ... (user adding logic remains identical to previous version) ...
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

# Enable and start/restart Docker services
echo "   - Enabling Docker services (docker.service, containerd.service)..."
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

if [ "$NEEDS_RESTART" = true ]; then
    echo "   - Restarting Docker service to apply configuration changes..."
    sudo systemctl restart docker.service
else
    # Start only if not already running (check added) or if restart wasn't needed
    if ! systemctl is-active --quiet docker.service; then
        echo "   - Starting Docker services..."
        sudo systemctl start docker.service
        sudo systemctl start containerd.service
    else
         echo "   - Docker service already active."
    fi
fi

echo "✅ Post-installation steps completed."
echo # Newline

# 6. Verification
# (Code remains the same)
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
# (Code remains the same)
echo "🎉 Docker installation successful!"
if [ "$NEEDS_RELOGIN" = true ]; then
    echo "⚠️ IMPORTANT: For users added to the 'docker' group (${CURRENT_USER:-''} ${ADDITIONAL_USERS[*]}),"
    echo "   you must log out and log back in, or run 'newgrp docker',"
    echo "   before you can run Docker commands without sudo."
fi
echo "   You can test Docker without sudo (after re-logging in) by running:"
echo "   docker run hello-world"

exit 0