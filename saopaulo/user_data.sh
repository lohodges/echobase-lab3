#!/bin/bash
dnf update -y
dnf install -y python3-pip
pip3 install flask pymysql boto3

mkdir -p /opt/rdsapp
mkdir -p /opt/rdsapp/static

cat >/opt/rdsapp/static/example.txt <<EOF
This is a sample file that should be cached.
EOF

cat >/opt/rdsapp/app.py <<'PY'
import json
import os
import boto3
import pymysql
import time
import random
from datetime import datetime, timezone
from flask import Flask, request, make_response, jsonify

REGION = os.environ.get("AWS_REGION", "ap-northeast-1")
SECRET_ID = os.environ.get("SECRET_ID", "shinjuku/rds/mysql")

LOG_GROUP = "/aws/ec2/liberdade-rds-app"
LOG_STREAM = "liberdade-rds-app"

secrets = boto3.client("secretsmanager", region_name=REGION)
logs_client = boto3.client("logs", region_name=REGION)

def log_to_cloudwatch(message):                                                                                                                                                                                                                                  
    try:                                                                                                                                                                                                                                                         
        logs_client.put_log_events(                                                                                                                                                                                                                              
            logGroupName=LOG_GROUP,                                                                                                                                                                                                                              
            logStreamName=LOG_STREAM,                                                                                                                                                                                                                            
            logEvents=[{                                                                                                                                                                                                                                         
                'timestamp': int(time.time() * 1000),                                                                                                                                                                                                            
                'message': message                                                                                                                                                                                                                               
            }]                                                                                                                                                                                                                                                   
        )                                                                                                                                                                                                                                                        
    except Exception as e:                                                                                                                                                                                                                                       
        print(f"Failed to log to CloudWatch: {e}")

def get_db_creds():
    resp = secrets.get_secret_value(SecretId=SECRET_ID)
    s = json.loads(resp["SecretString"])
    # When you use "Credentials for RDS database", AWS usually stores:
    # username, password, host, port, dbname (sometimes)
    return s

def get_conn():                                                                                                                                                                                                                                                  
    try:                                                                                                                                                                                                                                                         
        c = get_db_creds()                                                                                                                                                                                                                                       
        host = c["host"]                                                                                                                                                                                                                                         
        user = c["username"]                                                                                                                                                                                                                                     
        password = c["password"]                                                                                                                                                                                                                                 
        port = int(c.get("port", 3306))                                                                                                                                                                                                                          
        db = c.get("dbname", "notesappdb")                                                                                                                                                                                                                       
        return pymysql.connect(host=host, user=user, password=password, port=port, database=db, autocommit=True)                                                                                                                                                 
    except Exception as e:                                                                                                                                                                                                                                       
        log_to_cloudwatch(f"DBConnectionErrors: DB connection failed - {e}")                                                                                                                                                                                                  
        raise

app = Flask(__name__)

@app.route("/")
def home():
    return """
    <h2>EC2 → RDS Notes App</h2>
    <p>POST /add?note=hello</p>
    <p>GET /list</p>
    """

@app.route("/init")
def init_db():
    c = get_db_creds()
    host = c["host"]
    user = c["username"]
    password = c["password"]
    port = int(c.get("port", 3306))

    # connect without specifying a DB first
    conn = pymysql.connect(host=host, user=user, password=password, port=port, autocommit=True)
    cur = conn.cursor()
    cur.execute("CREATE DATABASE IF NOT EXISTS notesappdb;")
    cur.execute("USE notesappdb;")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS notes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            note VARCHAR(255) NOT NULL
        );
    """)
    cur.close()
    conn.close()
    return "Initialized notesappdb + notes table."

@app.route("/add", methods=["POST", "GET"])
def add_note():
    note = request.args.get("note", "").strip()
    if not note:
        return "Missing note param. Try: /add?note=hello", 400
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO notes(note) VALUES(%s);", (note,))
    cur.close()
    conn.close()
    return f"Inserted note: {note}"

@app.route("/list")
def list_notes():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, note FROM notes ORDER BY id DESC;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    out = "<h3>Notes</h3><ul>"
    for r in rows:
        out += f"<li>{r[0]}: {r[1]}</li>"
    out += "</ul>"
    return out

@app.route("/api/public-feed")
def public_feed():
    messages = ["If you believe it will work, you'll see opportunities. If you believe it won't, you will see obstacles.",
    "Believe you can and you're halfway there.",
    "Success is not final, failure is not fatal: it is the courage to continue that counts."]
    server_time_utc = datetime.now(timezone.utc)
    message_index = random.randrange(0, 3)
    message_of_the_minute = messages[message_index]
    response_data = make_response({
        "combined": {
                "message": message_of_the_minute,
                "server_time_utc": server_time_utc
                }
        })
    response_data.headers["Cache-Control"] = "public, s-maxage=30, max-age=0"
    return response_data

@app.route("/api/user-feed")
def private_feed():
    response_data = make_response("private user data")
    response_data.headers["Cache-Control"] = "private, no-store"
    return response_data

@app.route("/example.txt")
def example_file():
    return app.send_static_file("example.txt")

@app.route("/health")
def health_check():
    return "healthy"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
PY

cat >/etc/systemd/system/rdsapp.service <<'SERVICE'
[Unit]
Description=EC2 to RDS Notes App
After=network.target

[Service]
WorkingDirectory=/opt/rdsapp
Environment=SECRET_ID=shinjuku/rds/mysql
ExecStart=/usr/bin/python3 /opt/rdsapp/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable rdsapp
systemctl start rdsapp

# added by Lonnie Hodges 2026-01-16
# install Cloudwatch Agent
yum install -y selinux-policy-devel policycoreutils-devel rpm-build git
mkdir -p /opt/cwagent
wget -P /opt/cwagent "https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
rpm -U /opt/cwagent/amazon-cloudwatch-agent.rpm

# Create CloudWatch Agent config
cat >/opt/aws/amazon-cloudwatch-agent/bin/config.json <<'CWCONFIG'
{
"agent": {
    "metrics_collection_interval": 600,
    "run_as_user": "root"
},
"metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 600,
                "totalcpu": true
            },
            "disk": {
                "measurement": ["used_percent", "inodes_free"],
                "metrics_collection_interval": 600,
                "resources": ["*"]
            },
            "diskio": {
                "measurement": ["io_time", "read_bytes", "write_bytes"],
                "metrics_collection_interval": 600,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 600
            },
            "swap": {
                "measurement": ["swap_used_percent"],
                "metrics_collection_interval": 600
            }
        }
    }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent
# ^^^ added by Lonnie Hodges 2026-01-16