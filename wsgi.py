from app.main import app
from fastapi.middleware.wsgi import WSGIMiddleware
import uvicorn

# Create WSGI app
wsgi_app = WSGIMiddleware(app)

# This is needed for Azure App Service
application = wsgi_app

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
