#!/bin/bash

echo "=============================="
echo " Fluentd Installation Script "
echo "=============================="

# Ensure script runs as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "Removing any existing td-agent installation..."
dnf remove -y td-agent || true

# Install dependencies
echo "Installing dependencies..."
dnf update -y
dnf install -y curl gnupg gcc gcc-c++ make \
  openssl-devel zlib-devel readline-devel ncurses-devel libffi-devel ruby ruby-devel

# Verify Ruby and gem installation
if ! command -v ruby >/dev/null 2>&1; then
  echo "Error: Ruby installation failed."
  exit 1
fi

if ! command -v gem >/dev/null 2>&1; then
  echo "Error: gem command not found."
  exit 1
fi

# Install Fluentd with retry logic
echo "Installing Fluentd..."
attempt=1
while [ $attempt -le 3 ]; do
  if gem install fluentd --no-document --source "https://rubygems.org/"; then
    echo "Fluentd installed successfully."
    break
  else
    echo "Fluentd installation failed. Retrying ($attempt/3)..."
    attempt=$((attempt+1))
    sleep 5
  fi
done

if [ $attempt -gt 3 ]; then
  echo "Fluentd installation failed after multiple attempts."
  exit 1
fi

# Verify Fluentd installation
if ! command -v fluentd >/dev/null 2>&1; then
  echo "Error: Fluentd command not found. Something went wrong."
  exit 1
fi

# Install Fluentd plugins
echo "Installing Fluentd Plugins..."
PLUGINS=("fluent-plugin-grok-parser" "fluent-plugin-record-modifier")

for plugin in "${PLUGINS[@]}"; do
  attempt=1
  while [ $attempt -le 3 ]; do
    if fluent-gem install "$plugin"; then
      echo "Fluentd plugin $plugin installed successfully."
      break
    else
      echo "Failed to install Fluentd plugin $plugin. Retrying ($attempt/3)..."
      attempt=$((attempt+1))
      sleep 2
    fi
  done
  if [ $attempt -gt 3 ]; then
    echo "Error: Fluentd plugin $plugin installation failed after multiple attempts."
    exit 1
  fi
done

echo "Fluentd setup is complete!"
