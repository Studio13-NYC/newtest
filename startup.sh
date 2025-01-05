#!/bin/bash
set -e

echo "Starting FastAPI application..."
cd /home/site/wwwroot

if [ ! -d "antenv" ]; then
    echo "Creating virtual environment..."
    python -m venv antenv
fi

echo "Activating virtual environment..."
source antenv/bin/activate

echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Starting Gunicorn with FastAPI..."
export PYTHONPATH=/home/site/wwwroot
gunicorn --bind=0.0.0.0:8000 --timeout 600 --workers 4 --worker-class uvicorn.workers.UvicornWorker wsgi:application