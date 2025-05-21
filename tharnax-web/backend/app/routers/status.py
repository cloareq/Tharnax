from fastapi import APIRouter, Depends
from app.kubernetes.client import get_k8s_client
from kubernetes import client

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
        # Get nodes info
        nodes = k8s_client.list_node()
        node_count = len(nodes.items)
        
        # Get K3s version from the first node
        k3s_version = "unknown"
        if node_count > 0:
            version = nodes.items[0].status.node_info.kubelet_version
            k3s_version = version
            
        # Get pod count
        pods = k8s_client.list_pod_for_all_namespaces()
        pod_count = len(pods.items)
        
        return {
            "status": "running",
            "node_count": node_count,
            "k3s_version": k3s_version,
            "pod_count": pod_count
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        } 
