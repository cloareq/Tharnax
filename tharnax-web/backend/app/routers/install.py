from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from app.kubernetes.client import get_k8s_client
from app.services.installer import install_component
from app.routers.apps import check_monitoring_argocd_status
from kubernetes import client
from typing import Dict, Any
import logging
import asyncio
from datetime import datetime

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/install",
    tags=["install"],
)

# List of valid components that can be installed
VALID_COMPONENTS = ["nfs-server", "jellyfin", "sonarr", "prometheus", "grafana", "monitoring"]

# Global installation status tracking
installation_status = {}

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
    
    # Check if component is already being installed
    if component in installation_status and installation_status[component]["status"] == "installing":
        logger.info(f"Component '{component}' is already being installed")
        return {
            "status": "already_installing",
            "message": f"Installation of {component} is already in progress",
            "component": component
        }
    
    logger.info(f"Starting installation of '{component}'")
    
    # Initialize installation status
    installation_status[component] = {
        "status": "installing",
        "progress": 0,
        "message": f"Starting installation of {component}",
        "started_at": datetime.now().isoformat(),
        "component": component
    }
    
    # Start installation in background
    try:
        background_tasks.add_task(install_component_with_status, component, config, k8s_client)
        
        return {
            "status": "started",
            "message": f"Installation of {component} has started",
            "component": component
        }
    except Exception as e:
        logger.error(f"Failed to start installation of {component}: {str(e)}")
        installation_status[component] = {
            "status": "error",
            "progress": 0,
            "message": f"Failed to start installation: {str(e)}",
            "component": component
        }
        return {
            "status": "error",
            "message": f"Failed to start installation: {str(e)}",
            "component": component
        }

async def install_component_with_status(component: str, config: Dict[str, Any], k8s_client: client.CoreV1Api):
    """
    Wrapper function to track installation status
    """
    try:
        # Update status to installing
        installation_status[component]["status"] = "installing"
        installation_status[component]["progress"] = 10
        installation_status[component]["message"] = f"Installing {component}..."
        
        # Perform the actual installation
        result = await install_component(component, config, k8s_client)
        
        if result:
            installation_status[component]["status"] = "completed"
            installation_status[component]["progress"] = 100
            installation_status[component]["message"] = f"Installation of {component} completed successfully"
            installation_status[component]["completed_at"] = datetime.now().isoformat()
        else:
            installation_status[component]["status"] = "error"
            installation_status[component]["progress"] = 0
            installation_status[component]["message"] = f"Installation of {component} failed"
    
    except Exception as e:
        logger.error(f"Error during installation of {component}: {str(e)}")
        installation_status[component]["status"] = "error"
        installation_status[component]["progress"] = 0
        installation_status[component]["message"] = f"Installation failed: {str(e)}"

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
        # Check if we have status information
        if component in installation_status:
            status_info = installation_status[component].copy()
            
            # If installation is completed, also check actual deployment status
            if status_info["status"] == "completed":
                # Verify the component is actually installed
                if component == "monitoring":
                    actually_installed = await check_monitoring_argocd_status(k8s_client)
                else:
                    # For other components, check if namespace exists
                    namespaces = k8s_client.list_namespace()
                    namespace_names = [ns.metadata.name for ns in namespaces.items]
                    actually_installed = component in namespace_names
                
                if not actually_installed:
                    status_info["status"] = "error"
                    status_info["message"] = f"Installation reported complete but {component} not found"
            
            return status_info
        else:
            # No installation status, check if component is already installed
            if component == "monitoring":
                installed = await check_monitoring_argocd_status(k8s_client)
            else:
                namespaces = k8s_client.list_namespace()
                namespace_names = [ns.metadata.name for ns in namespaces.items]
                installed = component in namespace_names
            
            if installed:
                return {
                    "component": component,
                    "status": "installed",
                    "progress": 100,
                    "message": f"{component} is already installed"
                }
            else:
                return {
                    "component": component,
                    "status": "not_installed",
                    "progress": 0,
                    "message": f"{component} is not installed"
                }
    except Exception as e:
        logger.error(f"Error checking status for {component}: {str(e)}")
        return {
            "component": component,
            "status": "error",
            "progress": 0,
            "message": f"Error checking status: {str(e)}"
        }

@router.get("/status/all")
async def get_all_install_status():
    """
    Get installation status for all components
    """
    return {
        "installations": installation_status,
        "count": len(installation_status)
    } 
