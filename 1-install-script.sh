#!/bin/bash

# Define installation directory
INSTALL_DIR="/opt/monitoring"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Update system and install prerequisites
sudo apt-get update
sudo apt-get install -y wget tar curl
sudo apt install python3-pip -y

# Set versions
PROMETHEUS_VERSION="2.50.1"
NODE_EXPORTER_VERSION="1.7.0"
BLACKBOX_EXPORTER_VERSION="0.24.0"
ALERTMANAGER_VERSION="0.27.0"

# Install components
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xvfz prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 prometheus
rm prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 node_exporter
rm node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

wget https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_EXPORTER_VERSION}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz
mv blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64 blackbox_exporter
rm blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz

wget https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
tar xvfz alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
mv alertmanager-${ALERTMANAGER_VERSION}.linux-amd64 alertmanager
rm alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz

wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

# Create Prometheus configuration
cat << EOF > $INSTALL_DIR/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets: ['localhost:9093']

rule_files:
  - "rules/node_exporter_alerts.yml"
  - "rules/blackbox_exporter_alerts.yml"
  - "rules/test_alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'alert'
    static_configs:
      - targets: ['localhost:9093']
  - job_name: 'dora_metrics'
    static_configs:
      - targets: ['localhost:8001']
  - job_name: 'blackbox_http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://reconxi.com
        - https://dev.reconxi.com
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
  - job_name: 'blackbox_ssl'
    metrics_path: /probe
    params:
      module: [http_ssl]
    static_configs:
      - targets:
        - https://reconxi.com
        - https://dev.reconxi.com
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
EOF

# Create Blackbox Exporter configuration
cat << EOF > $INSTALL_DIR/blackbox_exporter/blackbox.yml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2"]
      valid_status_codes: [200]
      method: GET
  http_ssl:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2"]
      method: GET
      tls_config:
        insecure_skip_verify: false
EOF

# Create rules directory
mkdir -p $INSTALL_DIR/prometheus/rules

# Create Node Exporter alert rules
cat << EOF > $INSTALL_DIR/prometheus/rules/node_exporter_alerts.yml
groups:
- name: node-exporter-alerts
  rules:
  - alert: NodeDown
    expr: up{job="node"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Node {{ \$labels.instance }} is down"
      description: "{{ \$labels.instance }} has been down for more than 5 minutes."

  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage on {{ \$labels.instance }}"
      description: "CPU usage is above 80% on {{ \$labels.instance }} for more than 10 minutes."

  - alert: LowDiskSpace
    expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 20
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Low disk space on {{ \$labels.instance }}"
      description: "Available disk space is less than 20% on {{ \$labels.instance }} for more than 5 minutes."
EOF

# Create Blackbox Exporter alert rules
cat << EOF > $INSTALL_DIR/prometheus/rules/blackbox_exporter_alerts.yml
groups:
- name: blackbox-exporter-alerts
  rules:
  - alert: WebsiteDown
    expr: probe_success{job="blackbox_http"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Website {{ \$labels.instance }} is down"
      description: "{{ \$labels.instance }} has been unreachable for more than 1 minute."
      error: "Connection failed"
      http_status: "No response"

  - alert: SSLCertificateExpiring
    expr: probe_ssl_earliest_cert_expiry{job="blackbox_ssl"} - time() < 2592000
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "SSL certificate for {{ \$labels.instance }} expiring soon"
      description: "SSL certificate for {{ \$labels.instance }} will expire in less than 30 days."

  - alert: SSLCheckFailed
    expr: probe_success{job="blackbox_ssl"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "SSL check failed for {{ \$labels.instance }}"
      description: "SSL certificate check failed for {{ \$labels.instance }} for more than 2 minutes."
EOF

# Create Alertmanager configuration with custom Slack template
cat << EOF > $INSTALL_DIR/alertmanager/alertmanager.yml
global:
  resolve_timeout: 1m
  slack_api_url: 'https://hooks.slack.com/services/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'

route:
  group_by: ['alertname', 'instance', 'job']
  group_wait: 30s
  group_interval: 1m
  repeat_interval: 4h
  receiver: 'slack-notifications'
  routes:
    - match:
        severity: critical
      receiver: 'slack-critical'
    - match:
        severity: warning
      receiver: 'slack-warning'

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - send_resolved: true
        channel: '#team-3'
        title: '{{ if eq .Status "firing" }}:police_car_light: ALERT{{ else }}:large_green_circle: RESOLVED{{ end }}: {{ .CommonLabels.alertname }}'
        text: |
          {{ if eq .Status "firing" }}*SYSTEM ALERT*{{ else }}*SYSTEM RECOVERED*{{ end }}
          {{ range .Alerts }}
          *{{ if eq .Status "firing" }}{{ .Annotations.summary }}{{ else }}{{ .Annotations.resolved_summary }}{{ end }}*
          {{ if eq .Status "firing" }}{{ .Annotations.description }}{{ else }}{{ .Annotations.resolved_description }}{{ end }}
          *:alarm_clock: Incident Details:*
          • Started: {{ .StartsAt }}
          • Status: {{ .Status | toUpper }}
          *:magnifying_glass: Technical Information:*
          • System: {{ .Labels.instance }}
          • Job: {{ .Labels.job }}
          {{ if eq .Status "firing" }}
          • Severity: {{ .Labels.severity }}
          *:silhouettes: Impact Assessment:*
          • Users affected: {{ if eq .Labels.job "blackbox_http" }}Website visitors{{ else }}Service users{{ end }}
          *:link: Diagnostic Links:*
          • <https://grafana.website.com|View Dashboard>
          • <https://logs.website.com|View Logs>
          *:silhouettes: Team to Notify:* @team-reconxi-devops
          {{ end }}
          *:siren: Attention:* <@U08ASEFTPFW> <@U08AQBRT1EG> <@U08BD1J3C5N> <@U08BFNMP18U> <@U08AX7P0G9K> <@U08B1TXE9LZ> <@U08BDQA218Q> <@U08AR58UXMJ> <@U08B5JG3GP3> <@U08A7RXNHFZ> <@U08AM349U2Z>
          {{ end }}
        icon_emoji: '{{ if eq .Status "firing" }}:police_car_light:{{ else }}:green_circle:{{ end }}'

  - name: 'slack-critical'
    slack_configs:
      - send_resolved: true
        channel: '#team-3'
        title: '{{ if eq .Status "firing" }}:police_car_light: CRITICAL{{ else }}:large_green_circle: RESOLVED{{ end }}: {{ .CommonLabels.alertname }}'
        text: |
          {{ if eq .Status "firing" }}*CRITICAL SYSTEM ALERT*{{ else }}*SYSTEM RECOVERED*{{ end }}
          {{ range .Alerts }}
          *{{ if eq .Status "firing" }}{{ .Annotations.summary }}{{ else }}{{ .Annotations.resolved_summary }}{{ end }}*
          {{ if eq .Status "firing" }}{{ .Annotations.description }}{{ else }}{{ .Annotations.resolved_description }}{{ end }}
          *:alarm_clock: Incident Details:*
          • Started: {{ .StartsAt }}
          • Status: {{ .Status | toUpper }}
          *:magnifying_glass: Technical Information:*
          • System: {{ .Labels.instance }}
          • Job: {{ .Labels.job }}
          {{ if eq .Status "firing" }}
          {{ if eq .Labels.job "blackbox_http" }}
          • Error: Connection failed
          • HTTP Status: No response
          {{ end }}
          *:silhouettes: Impact Assessment:*
          • Severity: Critical
          • User Impact: {{ if eq .Labels.job "blackbox_http" }}All website users affected{{ else }}Service degradation{{ end }}
          *Related Systems:*
          • API Gateway: {{ if eq .Labels.job "blackbox_http" }}Operational{{ end }}
          • Database: Operational
          *:link: Diagnostic Links:*
          • <https://grafana.reconxi.com|View Dashboard>
          *:memo: Actions:*
          {{ if eq .Labels.job "blackbox_http" }}Check load balancer, verify instances, review logs before restarting services.{{ else }}Check for runaway processes, recent deployments, or traffic spikes.{{ end }}
          {{ end }}
          *:siren: Attention:* <@U08ASEFTPFW> <@U08AQBRT1EG> <@U08BD1J3C5N> <@U08BFNMP18U> <@U08AX7P0G9K> <@U08B1TXE9LZ> <@U08BDQA218Q> <@U08AR58UXMJ> <@U08B5JG3GP3> <@U08A7RXNHFZ> <@U08AM349U2Z>
          {{ end }}
        icon_emoji: '{{ if eq .Status "firing" }}:fire:{{ else }}:white_check_mark:{{ end }}'
        link_names: true

  - name: 'slack-warning'
    slack_configs:
      - send_resolved: true
        channel: '#team-3'
        title: '{{ if eq .Status "firing" }}:warning: WARNING{{ else }}:large_green_circle: RESOLVED{{ end }}: {{ .CommonLabels.alertname }}'
        text: |
          {{ if eq .Status "firing" }}*WARNING ALERT*{{ else }}*WARNING RESOLVED*{{ end }}
          {{ range .Alerts }}
          *{{ if eq .Status "firing" }}{{ .Annotations.summary }}{{ else }}{{ .Annotations.resolved_summary }}{{ end }}*
          {{ if eq .Status "firing" }}{{ .Annotations.description }}{{ else }}{{ .Annotations.resolved_description }}{{ end }}
          *:alarm_clock: Incident Details:*
          • Started: {{ .StartsAt }}
          • Status: {{ .Status | toUpper }}
          *:magnifying_glass: Technical Information:*
          • System: {{ .Labels.instance }}
          • Job: {{ .Labels.job }}
          {{ if eq .Status "firing" }}
          {{ if eq .Labels.alertname "SlowResponseTime" }}
          • Response Time: {{ if eq .Labels.job "blackbox_http" }}Slow{{ end }}
          {{ end }}
          {{ if eq .Labels.alertname "SSLCertExpiringSoon" }}
          • Certificate Expires: Soon
          {{ end }}
          {{ if eq .Labels.alertname "HighCPULoad" }}
          • CPU Load: High
          {{ end }}
          {{ if eq .Labels.alertname "HighMemoryLoad" }}
          • Memory Use: High
          {{ end }}
          {{ if eq .Labels.alertname "HighDiskUsage" }}
          • Disk Usage: High
          {{ end }}
          *:silhouettes: Impact Assessment:*
          • Severity: Warning
          • User Impact: Potential performance degradation
          *:link: Diagnostic Links:*
          • <https://grafana.reconxi.com|View Dashboard>
          *:bulb: Recommended Actions:*
          {{ if eq .Labels.alertname "SlowResponseTime" }}Check database queries or high backend resource usage.{{ else if eq .Labels.alertname "SSLCertExpiringSoon" }}Renew SSL certificate before expiration.{{ else if eq .Labels.alertname "HighCPULoad" }}Identify CPU-intensive processes and optimize.{{ else if eq .Labels.alertname "HighMemoryLoad" }}Check for memory leaks or increase available memory.{{ else if eq .Labels.alertname "HighDiskUsage" }}Clean up disk space or expand storage.{{ end }}
          {{ end }}
          *:siren: Attention:* <@U08ASEFTPFW> <@U08AQBRT1EG> <@U08BD1J3C5N> <@U08BFNMP18U> <@U08AX7P0G9K> <@U08B1TXE9LZ> <@U08BDQA218Q> <@U08AR58UXMJ> <@U08B5JG3GP3> <@U08A7RXNHFZ> <@U08AM349U2Z>
          {{ end }}
        icon_emoji: '{{ if eq .Status "firing" }}:warning:{{ else }}:white_check_mark:{{ end }}'
        link_names: true
EOF

# Create systemd service files
cat << EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$INSTALL_DIR/prometheus/prometheus --config.file=$INSTALL_DIR/prometheus/prometheus.yml
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

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

cat << EOF > /etc/systemd/system/blackbox_exporter.service
[Unit]
Description=Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$INSTALL_DIR/blackbox_exporter/blackbox_exporter --config.file=$INSTALL_DIR/blackbox_exporter/blackbox.yml
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/alertmanager.service
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$INSTALL_DIR/alertmanager/alertmanager --config.file=$INSTALL_DIR/alertmanager/alertmanager.yml
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
sudo chown -R $(whoami):$(whoami) $INSTALL_DIR
sudo chmod 644 /etc/systemd/system/prometheus.service
sudo chmod 644 /etc/systemd/system/node_exporter.service
sudo chmod 644 /etc/systemd/system/blackbox_exporter.service
sudo chmod 644 /etc/systemd/system/alertmanager.service

# Reload systemd and enable services
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl enable node_exporter
sudo systemctl enable blackbox_exporter
sudo systemctl enable alertmanager
sudo systemctl enable grafana-server

# Start services
sudo systemctl start prometheus
sudo systemctl start node_exporter
sudo systemctl start blackbox_exporter
sudo systemctl start alertmanager
sudo systemctl start grafana-server

# Print completion message
echo "Installation completed in $INSTALL_DIR!"
echo "Components installed with systemd services and Slack integration:"
echo "- Prometheus: $INSTALL_DIR/prometheus (systemctl status prometheus)"
echo "- Node Exporter: $INSTALL_DIR/node_exporter (systemctl status node_exporter)"
echo "- Blackbox Exporter: $INSTALL_DIR/blackbox_exporter (systemctl status blackbox_exporter)"
echo "- Alertmanager: $INSTALL_DIR/alertmanager (systemctl status alertmanager)"
echo "- Grafana: System-wide (systemctl status grafana-server)"

echo -e "\nTo manage services:"
echo "Start: systemctl start <service_name>"
echo "Stop: systemctl stop <service_name>"
echo "Status: systemctl status <service_name>"
echo "Services: prometheus, node_exporter, blackbox_exporter, alertmanager, grafana-server"

echo -e "\nNext steps:"
echo "1. Replace Slack webhook URL in alertmanager.yml if needed"
echo "2. Update monitored targets in prometheus.yml (use HTTPS URLs)"
echo "3. Adjust alert thresholds in rules/*.yml as needed"
echo "4. Access Prometheus at http://localhost:9090"
echo "5. Access Grafana at http://localhost:3000 (default user/pass: admin/admin)"