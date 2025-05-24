from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import logging

from app.routers import status, apps, install

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Tharnax Web API",
    description="API for managing Tharnax Kubernetes cluster",
    version="0.1.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(status.router, prefix="/api")
app.include_router(apps.router, prefix="/api")
app.include_router(install.router, prefix="/api")

@app.get("/")
async def root():
    logger.info("Root endpoint accessed")
    return {"message": "Welcome to Tharnax Web API"}

@app.get("/api")
async def api_root():
    logger.info("API Root endpoint accessed")
    return {"message": "Welcome to Tharnax Web API", "version": "0.1.0"}

if __name__ == "__main__":
    logger.info("Starting Tharnax Web API")
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True) 
