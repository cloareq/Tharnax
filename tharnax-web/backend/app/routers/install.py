from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from app.kubernetes.client import get_k8s_client
from app.services.installer import install_component
from kubernetes import client
from typing import Dict, Any
import logging

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/install",
    tags=["install"],
)

# List of valid components that can be installed
VALID_COMPONENTS = ["nfs-server", "jellyfin", "sonarr", "prometheus", "grafana", "monitoring"]

@router.post("/{component}")
async def install_app(
    component: str,
    background_tasks: BackgroundTasks,
    config: Dict[str, Any] = None,
    k8s_client: client.CoreV1Api = Depends(get_k8s_client)
):
    """
    Trigger installation of a specific component
    """
    # Check if component is valid
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested installation of unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    logger.info(f"Starting installation of '{component}'")
    
    # Start installation in background
    try:
        background_tasks.add_task(install_component, component, config, k8s_client)
        
        return {
            "status": "started",
            "message": f"Installation of {component} has started",
            "component": component
        }
    except Exception as e:
        logger.error(f"Failed to start installation of {component}: {str(e)}")
        return {
            "status": "error",
            "message": f"Failed to start installation: {str(e)}",
            "component": component
        }

@router.get("/{component}/status")
async def get_install_status(
    component: str,
    k8s_client: client.CoreV1Api = Depends(get_k8s_client)
):
    """
    Get installation status for a specific component
    """
    # Check if component is valid
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested status for unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    logger.info(f"Checking installation status for '{component}'")
    
    try:
        # This would check the installation status
        # For now we return a placeholder
        return {
            "component": component,
            "status": "pending", 
            "progress": 0,
            "message": "Installation not yet implemented"
        }
    except Exception as e:
        logger.error(f"Error checking status for {component}: {str(e)}")
        return {
            "component": component,
            "status": "error",
            "progress": 0,
            "message": f"Error checking status: {str(e)}"
        } 
