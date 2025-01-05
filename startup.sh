#!/bin/bash
set -e

echo "Current directory: \D:\Studio13\S13AutonomousFab\newtest"
echo "Listing directory contents:"
ls -la

if [ ! -d "antenv" ]; then
    echo "Creating virtual environment..."
    python -m venv antenv
fi

echo "Activating virtual environment..."
source antenv/bin/activate

echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Starting FastAPI application..."
cd /home/site/wwwroot
export PYTHONPATH=/home/site/wwwroot
gunicorn --bind=0.0.0.0:8000 --timeout 600 --workers 4 --access-logfile - --error-logfile - --log-level debug wsgi:application