from fastapi import APIRouter, Depends, HTTPException
from app.kubernetes.client import get_k8s_client
from kubernetes import client
import logging

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/status",
    tags=["status"],
)

@router.get("/")
async def get_cluster_status(k8s_client: client.CoreV1Api = Depends(get_k8s_client)):
    """
    Get overall cluster status including node count, K3s version, etc.
    """
    try:
        logger.info("Fetching cluster status")
        
        # Get nodes info
        nodes = k8s_client.list_node()
        node_count = len(nodes.items)
        logger.info(f"Found {node_count} nodes")
        
        # Get K3s version from the first node
        k3s_version = "unknown"
        if node_count > 0:
            version = nodes.items[0].status.node_info.kubelet_version
            k3s_version = version
            logger.info(f"K3s version: {k3s_version}")
            
        # Get pod count
        pods = k8s_client.list_pod_for_all_namespaces()
        pod_count = len(pods.items)
        logger.info(f"Found {pod_count} pods")
        
        return {
            "status": "running",
            "node_count": node_count,
            "k3s_version": k3s_version,
            "pod_count": pod_count
        }
    except Exception as e:
        logger.error(f"Error getting cluster status: {str(e)}")
        
        # Return a more detailed error message
        error_message = str(e)
        if "Unauthorized" in error_message:
            error_message = "Kubernetes API access unauthorized. Check RBAC permissions."
        elif "connection refused" in error_message.lower():
            error_message = "Could not connect to Kubernetes API. Check if cluster is running."
            
        # Log detailed information about the error
        logger.error(f"Exception type: {type(e).__name__}")
        logger.error(f"Exception args: {e.args}")
        
        return {
            "status": "error",
            "message": error_message,
            "node_count": "N/A",
            "k3s_version": "N/A",
            "pod_count": "N/A"
        } 
