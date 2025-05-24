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
        "id": "argocd",
        "name": "Argo CD",
        "description": "GitOps continuous delivery tool for Kubernetes",
        "category": "cicd",
        "icon": "rocket",
        "url": "http://localhost:8080"  # This will be dynamically set based on cluster configuration
    },
    {
        "id": "monitoring",
        "name": "Monitoring Stack",
        "description": "Prometheus and Grafana monitoring stack",
        "category": "monitoring",
        "icon": "monitoring"
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
    }
]

@router.get("/")
async def get_available_apps(k8s_client: client.CoreV1Api = Depends(get_k8s_client)) -> List[Dict[str, Any]]:
    """
    Get list of available applications and their installation status
    """
    apps_with_status = []
    
    try:
        logger.info("Fetching available applications")
        
        # Get all namespaces to check for app namespaces
        namespaces = k8s_client.list_namespace()
        namespace_names = [ns.metadata.name for ns in namespaces.items]
        logger.info(f"Found {len(namespace_names)} namespaces")
        
        for app in AVAILABLE_APPS:
            app_data = app.copy()
            
            # Special handling for ArgoCD
            if app["id"] == "argocd":
                argocd_installed = "argocd" in namespace_names
                app_data["installed"] = argocd_installed
                
                if argocd_installed:
                    # Try to get the ArgoCD service URL
                    try:
                        services = k8s_client.list_namespaced_service(namespace="argocd")
                        argocd_service = None
                        
                        for svc in services.items:
                            if svc.metadata.name == "argocd-server":
                                argocd_service = svc
                                break
                        
                        if argocd_service:
                            # Check if it's a LoadBalancer service
                            if argocd_service.spec.type == "LoadBalancer":
                                if argocd_service.status.load_balancer.ingress:
                                    lb_ip = argocd_service.status.load_balancer.ingress[0].ip
                                    app_data["url"] = f"http://{lb_ip}:8080"
                                else:
                                    # LoadBalancer pending, use node IP fallback
                                    # Try to get master node IP
                                    nodes = k8s_client.list_node()
                                    if nodes.items:
                                        for address in nodes.items[0].status.addresses:
                                            if address.type == "InternalIP":
                                                app_data["url"] = f"http://{address.address}:8080"
                                                break
                            else:
                                # Not a LoadBalancer, use generic localhost
                                app_data["url"] = "http://localhost:8080"
                        else:
                            app_data["url"] = "http://localhost:8080"
                    except Exception as e:
                        logger.warning(f"Could not determine ArgoCD URL: {str(e)}")
                        app_data["url"] = "http://localhost:8080"
                else:
                    # Not installed, remove URL
                    app_data.pop("url", None)
            elif app["id"] == "monitoring":
                monitoring_installed = "monitoring" in namespace_names
                app_data["installed"] = monitoring_installed
                
                if monitoring_installed:
                    # Try to get both Grafana and Prometheus service URLs
                    try:
                        services = k8s_client.list_namespaced_service(namespace="monitoring")
                        grafana_url = None
                        prometheus_url = None
                        
                        # Get master node IP for fallback
                        master_ip = "localhost"
                        try:
                            nodes = k8s_client.list_node()
                            if nodes.items:
                                for address in nodes.items[0].status.addresses:
                                    if address.type == "InternalIP":
                                        master_ip = address.address
                                        break
                        except:
                            pass
                        
                        for svc in services.items:
                            # Check Grafana service
                            if "grafana" in svc.metadata.name.lower():
                                if svc.spec.type == "LoadBalancer":
                                    if svc.status.load_balancer.ingress:
                                        lb_ip = svc.status.load_balancer.ingress[0].ip
                                        grafana_url = f"http://{lb_ip}"
                                    else:
                                        # LoadBalancer pending, use node IP fallback
                                        grafana_url = f"http://{master_ip}:3000"
                                else:
                                    # ClusterIP service
                                    grafana_url = f"http://{master_ip}:3000"
                            
                            # Check Prometheus service
                            if "prometheus" in svc.metadata.name.lower() and "operated" not in svc.metadata.name.lower():
                                if svc.spec.type == "LoadBalancer":
                                    if svc.status.load_balancer.ingress:
                                        lb_ip = svc.status.load_balancer.ingress[0].ip
                                        prometheus_url = f"http://{lb_ip}:9090"
                                    else:
                                        # LoadBalancer pending, use node IP fallback  
                                        prometheus_url = f"http://{master_ip}:9090"
                                else:
                                    # ClusterIP service
                                    prometheus_url = f"http://{master_ip}:9090"
                        
                        # Set URLs for the monitoring stack
                        app_data["urls"] = {
                            "grafana": grafana_url or f"http://{master_ip}:3000",
                            "prometheus": prometheus_url or f"http://{master_ip}:9090"
                        }
                        
                        # Keep the legacy single URL for backward compatibility (defaults to Grafana)
                        app_data["url"] = grafana_url or f"http://{master_ip}:3000"
                        
                    except Exception as e:
                        logger.warning(f"Could not determine monitoring URLs: {str(e)}")
                        app_data["urls"] = {
                            "grafana": f"http://localhost:3000",
                            "prometheus": f"http://localhost:9090"
                        }
                        app_data["url"] = "http://localhost:3000"
                else:
                    # Not installed, remove URLs
                    app_data.pop("url", None)
                    app_data.pop("urls", None)
            else:
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
            # Remove URL for safety on error
            app_data.pop("url", None)
            apps_with_status.append(app_data)
        
        return apps_with_status 
