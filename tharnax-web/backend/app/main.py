from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from app.routers import status, apps, install

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

# Include routers
app.include_router(status.router)
app.include_router(apps.router)
app.include_router(install.router)

@app.get("/")
async def root():
    return {"message": "Welcome to Tharnax Web API"}

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True) 
