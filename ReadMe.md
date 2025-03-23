https://hooks.slack.com/services/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

#team-3


curl -X POST -H 'Content-type: application/json' \
--data '{"text":"Test from Incrisz"}' \
https://hooks.slack.com/services/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









#to run test

pkill -f "alertmanager --config.file=/opt/monitoring/alertmanager/alertmanager.yml"
/opt/monitoring/alertmanager/alertmanager --config.file=/opt/monitoring/alertmanager/alertmanager.yml


pkill -f "prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml"
/opt/monitoring/prometheus/prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml &



sudo systemctl restart prometheus
sudo systemctl restart node_exporter
sudo systemctl restart blackbox_exporter
sudo systemctl restart alertmanager
sudo systemctl restart grafana-server


mkdir dora_metrics_exporter
cd dora_metrics_exporter
python3 -m venv venv
touch requirements.txt .env exporter.py
source venv/bin/activate  # On Windows use `venv\Scripts\activate`
touch requirements.txt .env exporter.py


pip install -r requirements.txt


python exporter.py
OR
nohup python exporter.py & (This cmd runs your application in the background without your terminal being held hostage)