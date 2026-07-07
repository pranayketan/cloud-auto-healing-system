#!/bin/bash

set -e

echo "======================================================"
echo " Cloud Auto-Healing Monitoring System Installer"
echo "======================================================"

if [ "$EUID" -ne 0 ]; then
  echo "Please run using sudo:"
  echo "sudo ./install.sh"
  exit 1
fi

echo "[1/8] Updating packages..."
apt update -y

echo "[2/8] Installing required packages..."
apt install -y apache2 wget tar curl apt-transport-https software-properties-common gpg cron

echo "[3/8] Starting Apache..."
systemctl start apache2
systemctl enable apache2

echo "[4/8] Installing Node Exporter..."
cd /tmp

NODE_EXPORTER_VERSION="1.8.2"

wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/

chmod +x /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

echo "[5/8] Installing Prometheus..."
cd /tmp

PROMETHEUS_VERSION="2.54.1"

wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

rm -rf /opt/prometheus

mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus

mkdir -p /opt/prometheus/data

cat > /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF

cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=ubuntu
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data

[Install]
WantedBy=multi-user.target
EOF

chown -R ubuntu:ubuntu /opt/prometheus

systemctl daemon-reload
systemctl start prometheus
systemctl enable prometheus

echo "[6/8] Installing Grafana..."

mkdir -p /etc/apt/keyrings

wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

apt update -y

apt install -y grafana

systemctl start grafana-server
systemctl enable grafana-server

echo "[7/8] Installing auto-healing script..."

cat > /usr/local/bin/auto_heal_apache.sh << 'EOF'
#!/bin/bash

SERVICE_NAME="apache2"
LOG_FILE="/var/log/auto_healing.log"
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

if systemctl is-active --quiet "$SERVICE_NAME"
then
    echo "$DATE_TIME - $SERVICE_NAME is running." >> "$LOG_FILE"
else
    echo "$DATE_TIME - ALERT: $SERVICE_NAME is down. Restarting..." >> "$LOG_FILE"

    systemctl restart "$SERVICE_NAME"

    sleep 5

    NEW_DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    if systemctl is-active --quiet "$SERVICE_NAME"
    then
        echo "$NEW_DATE_TIME - SUCCESS: $SERVICE_NAME restarted successfully." >> "$LOG_FILE"
    else
        echo "$NEW_DATE_TIME - ERROR: Failed to restart $SERVICE_NAME." >> "$LOG_FILE"
    fi
fi
EOF

chmod +x /usr/local/bin/auto_heal_apache.sh

touch /var/log/auto_healing.log
chmod 644 /var/log/auto_healing.log

echo "[8/8] Adding Cron Job..."

(crontab -l 2>/dev/null | grep -v "/usr/local/bin/auto_heal_apache.sh" || true; echo "* * * * * /usr/local/bin/auto_heal_apache.sh") | crontab -

echo "======================================================"
echo " Installation Completed Successfully!"
echo "======================================================"
echo "Apache:        http://YOUR_EC2_PUBLIC_IP"
echo "Prometheus:    http://YOUR_EC2_PUBLIC_IP:9090"
echo "Node Exporter: http://YOUR_EC2_PUBLIC_IP:9100/metrics"
echo "Grafana:       http://YOUR_EC2_PUBLIC_IP:3000"
echo ""
echo "Grafana login: admin / admin"
echo ""
echo "Test auto-healing:"
echo "sudo systemctl stop apache2"
echo "Wait 1 minute"
echo "sudo systemctl status apache2"
echo "sudo cat /var/log/auto_healing.log"
echo "======================================================"
