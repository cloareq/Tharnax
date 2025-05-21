from fastapi import APIRouter, Depends
from app.kubernetes.client import get_k8s_client
from kubernetes import client
from typing import List, Dict, Any
import logging

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/apps",
    tags=["apps"],
)

# Define available applications
AVAILABLE_APPS = [
    {
        "id": "nfs-server",
        "name": "NFS Server",
        "description": "Network File System server for cluster storage",
        "category": "storage",
        "icon": "storage"
    },
    {
        "id": "jellyfin",
        "name": "Jellyfin",
        "description": "Free Software Media System",
        "category": "media",
        "icon": "play_circle"
    },
    {
        "id": "sonarr",
        "name": "Sonarr",
        "description": "TV series management",
        "category": "media",
        "icon": "tv"
    },
    {
        "id": "prometheus",
        "name": "Prometheus",
        "description": "Monitoring and alerting toolkit",
        "category": "monitoring",
        "icon": "monitoring"
    },
    {
        "id": "grafana",
        "name": "Grafana",
        "description": "Metrics visualization and dashboards",
        "category": "monitoring",
        "icon": "dashboard"
    }
]

@router.get("/")
async def get_available_apps(k8s_client: client.CoreV1Api = Depends(get_k8s_client)) -> List[Dict[str, Any]]:
    """
    Get list of available applications and their installation status
    """
    # Here we would check if apps are installed by looking for deployments, services, etc.
    # For now, we'll just return the static list with a placeholder status
    apps_with_status = []
    
    try:
        logger.info("Fetching available applications")
        
        # Get all namespaces to check for app namespaces
        namespaces = k8s_client.list_namespace()
        namespace_names = [ns.metadata.name for ns in namespaces.items]
        logger.info(f"Found {len(namespace_names)} namespaces")
        
        for app in AVAILABLE_APPS:
            # This is simplistic - in reality we'd check for specific resources
            app_data = app.copy()
            app_data["installed"] = app["id"] in namespace_names
            apps_with_status.append(app_data)
            
        logger.info(f"Returning {len(apps_with_status)} applications")
        return apps_with_status
    except Exception as e:
        logger.error(f"Error fetching applications: {str(e)}")
        
        # On error, still return the apps with error status
        for app in AVAILABLE_APPS:
            app_data = app.copy()
            app_data["installed"] = False
            app_data["status_error"] = True
            apps_with_status.append(app_data)
        
        return apps_with_status 
