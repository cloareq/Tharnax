from fastapi import APIRouter, Depends, HTTPException
from app.kubernetes.client import get_k8s_client
from kubernetes import client
import logging
import subprocess
import shutil
import os

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/status",
    tags=["status"],
)

def get_nfs_storage_info(k8s_client=None):
    """
    Get NFS storage information including disk usage
    """
    try:
        # Always prioritize /etc/exports to get the root NFS export path
        nfs_root_path = None
        nfs_server = None
        
        # First check /etc/exports to get the actual NFS export
        if os.path.exists('/etc/exports'):
            try:
                with open('/etc/exports', 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            export_path = line.split()[0]
                            if os.path.exists(export_path):
                                nfs_root_path = export_path
                                # For local exports, use localhost as server
                                nfs_server = "localhost"
                                break
            except Exception:
                pass
        
        # If no exports found, check common mount points        
        if not nfs_root_path:
            common_paths = ['/mnt/tharnax-nfs', '/mnt/nfs', '/srv/nfs', '/data', '/nfs']
            for path in common_paths:
                if os.path.exists(path):
                    # Check if it's a directory and has some content or is a mount point
                    if os.path.isdir(path) and (os.path.ismount(path) or os.listdir(path)):
                        nfs_root_path = path
                        nfs_server = "localhost"
                        break
                        
        if not nfs_root_path:
            return None
            
        # Get disk usage for the root NFS path
        try:
            usage = shutil.disk_usage(nfs_root_path)
            
            total_gb = round(usage.total / (1024**3), 2)
            used_gb = round((usage.total - usage.free) / (1024**3), 2)
            free_gb = round(usage.free / (1024**3), 2)
            usage_percent = round(((usage.total - usage.free) / usage.total) * 100, 1)
            
            # Return the root NFS path, not specific PVC paths
            display_path = f"{nfs_server}:{nfs_root_path}" if nfs_server else nfs_root_path
            
            return {
                "path": display_path,
                "total_gb": total_gb,
                "used_gb": used_gb,
                "free_gb": free_gb,
                "usage_percent": usage_percent,
                "status": "available"
            }
        except Exception as e:
            logger.warning(f"Could not get disk usage for {nfs_root_path}: {str(e)}")
            display_path = f"{nfs_server}:{nfs_root_path}" if nfs_server else nfs_root_path
            return {
                "path": display_path,
                "total_gb": "N/A",
                "used_gb": "N/A",
                "free_gb": "N/A", 
                "usage_percent": 0,
                "status": "available"
            }
        
    except Exception as e:
        logger.warning(f"Could not get NFS storage info: {str(e)}")
        return None

@router.get("/")
async def get_cluster_status(k8s_client: client.CoreV1Api = Depends(get_k8s_client)):
    """
    Get overall cluster status including node count, K3s version, and NFS storage info
    """
    try:
        logger.info("Fetching cluster status")
        
        nodes = k8s_client.list_node()
        node_count = len(nodes.items)
        logger.info(f"Found {node_count} nodes")
        
        k3s_version = "unknown"
        if node_count > 0:
            version = nodes.items[0].status.node_info.kubelet_version
            k3s_version = version
            logger.info(f"K3s version: {k3s_version}")
            
        pods = k8s_client.list_pod_for_all_namespaces()
        pod_count = len(pods.items)
        logger.info(f"Found {pod_count} pods")
        
        nfs_storage = get_nfs_storage_info(k8s_client)
        logger.info(f"NFS storage info: {nfs_storage}")
        
        result = {
            "status": "running",
            "node_count": node_count,
            "k3s_version": k3s_version,
            "pod_count": pod_count
        }
        
        if nfs_storage:
            result["nfs_storage"] = nfs_storage
            
        return result
        
    except Exception as e:
        logger.error(f"Error getting cluster status: {str(e)}")
        
        error_message = str(e)
        if "Unauthorized" in error_message:
            error_message = "Kubernetes API access unauthorized. Check RBAC permissions."
        elif "connection refused" in error_message.lower():
            error_message = "Could not connect to Kubernetes API. Check if cluster is running."
            
        logger.error(f"Exception type: {type(e).__name__}")
        logger.error(f"Exception args: {e.args}")
        
        return {
            "status": "error",
            "message": error_message,
            "node_count": "N/A",
            "k3s_version": "N/A",
            "pod_count": "N/A"
        } 
