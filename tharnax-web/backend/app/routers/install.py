from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from app.kubernetes.client import get_k8s_client
from app.services.installer import install_component
from kubernetes import client
from typing import Dict, Any

router = APIRouter(
    prefix="/install",
    tags=["install"],
)

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
    valid_components = ["nfs-server", "jellyfin", "sonarr", "prometheus", "grafana"]
    if component not in valid_components:
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    # Start installation in background
    background_tasks.add_task(install_component, component, config, k8s_client)
    
    return {
        "status": "started",
        "message": f"Installation of {component} has started",
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
    valid_components = ["nfs-server", "jellyfin", "sonarr", "prometheus", "grafana"]
    if component not in valid_components:
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    # This would check the installation status
    # For now we return a placeholder
    return {
        "component": component,
        "status": "pending", 
        "progress": 0,
        "message": "Installation not yet implemented"
    } 
