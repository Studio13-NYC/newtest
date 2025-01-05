#!/bin/bash
set -e

echo "Starting FastAPI application..."
cd /home/site/wwwroot

# Use the Python version specified by Azure
PYTHON_VERSION=$(ls /usr/local/python/*)
PYTHON_PATH=$PYTHON_VERSION/bin/python3

if [ ! -d "antenv" ]; then
    echo "Creating virtual environment..."
    $PYTHON_PATH -m venv antenv
fi

echo "Activating virtual environment..."
source antenv/bin/activate

echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Starting Gunicorn with FastAPI..."
export PYTHONPATH=/home/site/wwwroot
gunicorn wsgi:application --bind=0.0.0.0:8000 --timeout 600 --workers 4 --access-logfile - --error-logfile - --log-level debug