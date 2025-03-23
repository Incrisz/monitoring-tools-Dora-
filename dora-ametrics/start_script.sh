#!/bin/bash
sudo apt install python3.12-venv -y
python3 -m venv venv

source venv/bin/activate
pip install -r requirements.txt
export $(grep -v '^#' .env | xargs)
source .env
nohup python3 main.py
