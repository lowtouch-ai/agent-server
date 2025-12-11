#!/bin/bash
echo "=============================="
echo " Fluentd Installation Script "
echo "=============================="

# Ensure script runs as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "Removing td-agent if installed..."
apt-get remove --purge -y td-agent
rm -f /etc/apt/sources.list.d/treasure-data.list
rm -f /etc/apt/trusted.gpg.d/treasure-data.asc

echo "Installing dependencies..."
apt-get update
apt-get install -y curl gnupg build-essential libssl-dev zlib1g-dev libyaml-dev libreadline-dev libncurses5-dev libffi-dev ruby ruby-dev

echo "Installing Fluentd..."
gem install fluentd --no-document

echo "Verifying Fluentd installation..."
if command -v fluentd >/dev/null 2>&1; then
  echo "Fluentd installed successfully."
else
  echo "Fluentd command not found. Something went wrong."
  exit 1
fi
echo "Installing Fluentd Plugins..."
PLUGINS=("fluent-plugin-grok-parser" "fluent-plugin-record-modifier" "fluent-plugin-graylog")

for plugin in "${PLUGINS[@]}"; do
  if fluent-gem install "$plugin"; then
    echo "Fluentd plugin $plugin installed successfully."
  else
    echo "Failed to install Fluentd plugin $plugin."
    exit 1
  fi
done

echo "Fluentd setup is complete!"

