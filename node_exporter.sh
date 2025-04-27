#!/bin/bash

# Define installation directory
INSTALL_DIR="/opt/monitoring"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Update system and install prerequisites
sudo apt-get update
sudo apt-get install -y wget tar curl

# Set Node Exporter version
NODE_EXPORTER_VERSION="1.7.0"

# Install Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 node_exporter
rm node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

# Create systemd service for Node Exporter
cat << EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$INSTALL_DIR/node_exporter/node_exporter
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
sudo chown -R $(whoami):$(whoami) $INSTALL_DIR
sudo chmod 644 /etc/systemd/system/node_exporter.service

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable node_exporter

# Start Node Exporter
sudo systemctl start node_exporter

# Print completion message
echo "Node Exporter installed in $INSTALL_DIR!"
echo "To manage Node Exporter service:"
echo "Start: systemctl start node_exporter"
echo "Stop: systemctl stop node_exporter"
echo "Status: systemctl status node_exporter"
echo "Access Node Exporter metrics at http://localhost:9100/metrics"
