# Docker Installation Scripts for Debian/Ubuntu

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This repository contains a robust bash script (`docker_enginer_install.sh`) designed to automate the installation of the official Docker Engine on Debian-based Linux distributions like Ubuntu, Debian, Linux Mint, etc.

It simplifies the process by handling:
* Uninstalling older or conflicting Docker packages (`docker.io`, `podman-docker`, etc.).
* Setting up Docker's official APT repository correctly.
* Installing the latest stable versions of Docker Engine, CLI, containerd, Docker Buildx plugin, and Docker Compose plugin.
* Performing essential post-installation steps like adding the current user to the `docker` group.
* Offering options to configure Docker's `daemon.json` with sensible defaults or a custom data directory.

## Features

* **Idempotent Uninstallation:** Checks for and removes known older/conflicting packages.
* **Official Repository Setup:** Correctly adds Docker's GPG key and APT repository source.
* **Prerequisite Handling:** Installs necessary dependencies like `ca-certificates`, `curl`, `gnupg`, `lsb-release`, and `jq`.
* **Latest Stable Docker:** Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
* **User Group Management:** Automatically adds the user running the script (via `sudo`) to the `docker` group for passwordless Docker command execution (requires logout/login).
* **Optional Default Configuration (`-c`):** Creates/updates `/etc/docker/daemon.json` to set log rotation limits (`json-file` driver, 10m size, 3 files) and enable BuildKit. Merges settings safely if the file exists and is valid JSON.
* **Optional Custom Data Root (`-d <path>`):** Configures Docker to use a specified directory for storing images, containers, volumes, etc., by setting the `data-root` option in `/etc/docker/daemon.json`. Merges settings safely.
* **Robust JSON Handling:** Uses `jq` to safely create or modify the `/etc/docker/daemon.json` file.
* **Safety Checks:** Includes `set -e`, `set -o pipefail`, and requires root/sudo privileges to run.

## Prerequisites

* A Debian-based Linux distribution (e.g., Ubuntu 20.04+, Debian 10+, Linux Mint 20+, etc.).
* `sudo` privileges.
* An active internet connection to download packages and GPG keys.

## Script Included

* `docker_engine_install.sh`: The main installation and configuration script.

## Usage

1.  **Download or Clone the Script:**
    ```bash
    git clone https://github.com/phreck/Docker_Engine_Ubuntu.git
    cd Docker_Engine_Ubuntu
    ```
    Or download the `docker_engine_install.sh` file directly.

2.  **Make the Script Executable:**
    ```bash
    chmod +x docker_engine_install.sh
    ```

3.  **Run the Script with `sudo`:**

    * **Standard Installation:**
        ```bash
        sudo ./docker_engine_install.sh
        ```

    * **Install and Configure Default `daemon.json`:**
        ```bash
        sudo ./docker_engine_install.sh -c
        ```

    * **Install and Configure Custom Data Root:**
        ```bash
        # Make sure the parent directory (e.g., /mnt) exists and is suitable
        sudo ./docker_engine_install.sh -d /mnt/my-docker-data
        ```
        *(The script configures Docker to use this path; the Docker daemon will attempt to create the final directory if it doesn't exist when it starts)*

    * **Install with Both Default Config and Custom Data Root:**
        ```bash
        sudo ./docker_engine_install.sh -c -d /var/lib/docker-custom-directory
        ```

    * **Display Help Message:**
        ```bash
        ./docker_engine_install.sh -h
        ```

## Command-Line Options

* `-c`: Create or update `/etc/docker/daemon.json`. If the file exists and is valid JSON, merges the default settings below. If the file doesn't exist or is invalid, it will be created/overwritten with these settings (plus any `-d` setting).
* `-d <path>`: Set a custom absolute path for Docker's data-root directory in `/etc/docker/daemon.json`. Merges the setting if the file exists and is valid JSON. Requires an absolute path (e.g., `/opt/docker`).
* `-h`: Display the help message and exit.

## Default `daemon.json` Configuration (`-c` flag)

When the `-c` flag is used, the script aims to configure `/etc/docker/daemon.json` to include the following settings (merged with existing settings or the `-d` option):

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "features": {
    "buildkit": true
  }
}