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

AVAILABLE_APPS = [
    {
        "id": "argocd",
        "name": "Argo CD",
        "description": "GitOps continuous delivery tool for Kubernetes",
        "category": "cicd",
        "icon": "rocket",
        "url": "http://localhost:8080"
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

async def check_monitoring_status(k8s_client: client.CoreV1Api) -> bool:
    """
    Check if the monitoring stack is properly deployed (direct Helm installation)
    """
    try:
        try:
            pods = k8s_client.list_namespaced_pod(namespace="monitoring")
            if not pods.items:
                logger.info("No pods found in monitoring namespace")
                return False
                
            running_pods = [pod for pod in pods.items if pod.status.phase == "Running"]
            total_pods = len(pods.items)
            
            logger.info(f"Monitoring stack status - {len(running_pods)}/{total_pods} pods running")
            if len(running_pods) >= 3:
                try:
                    services = k8s_client.list_namespaced_service(namespace="monitoring")
                    has_grafana = any("grafana" in svc.metadata.name.lower() for svc in services.items)
                    has_prometheus = any("prometheus" in svc.metadata.name.lower() for svc in services.items)
                    
                    if has_grafana and has_prometheus:
                        logger.info(f"Monitoring stack is healthy with {len(running_pods)} running pods")
                        return True
                    else:
                        logger.info(f"Missing essential services - Grafana: {has_grafana}, Prometheus: {has_prometheus}")
                        return False
                except Exception as e:
                    logger.warning(f"Error checking monitoring services: {e}")
                    return len(running_pods) >= 3
            else:
                logger.info(f"Monitoring stack not ready - only {len(running_pods)}/{total_pods} pods running")
                return False
                
        except client.exceptions.ApiException as e:
            if e.status == 404:
                logger.info("Monitoring namespace not found")
                return False
            else:
                logger.warning(f"Error checking monitoring namespace: {e}")
                return False
            
    except Exception as e:
        logger.error(f"Error checking monitoring status: {e}")
        return False

@router.get("/")
async def get_available_apps(k8s_client: client.CoreV1Api = Depends(get_k8s_client)) -> List[Dict[str, Any]]:
    """
    Get list of available applications and their installation status
    """
    apps_with_status = []
    
    try:
        logger.info("Fetching available applications")
        namespaces = k8s_client.list_namespace()
        namespace_names = [ns.metadata.name for ns in namespaces.items]
        logger.info(f"Found {len(namespace_names)} namespaces")
        
        for app in AVAILABLE_APPS:
            app_data = app.copy()
            

            if app["id"] == "argocd":
                argocd_installed = "argocd" in namespace_names
                app_data["installed"] = argocd_installed
                
                if argocd_installed:
                    try:
                        services = k8s_client.list_namespaced_service(namespace="argocd")
                        argocd_service = None
                        
                        for svc in services.items:
                            if svc.metadata.name == "argocd-server":
                                argocd_service = svc
                                break
                        
                        if argocd_service:
                            if argocd_service.spec.type == "LoadBalancer":
                                if argocd_service.status.load_balancer.ingress:
                                    lb_ip = argocd_service.status.load_balancer.ingress[0].ip
                                    app_data["url"] = f"http://{lb_ip}:8080"
                                else:
                                    nodes = k8s_client.list_node()
                                    if nodes.items:
                                        for address in nodes.items[0].status.addresses:
                                            if address.type == "InternalIP":
                                                app_data["url"] = f"http://{address.address}:8080"
                                                break
                            else:
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
                monitoring_installed = await check_monitoring_status(k8s_client)
                app_data["installed"] = monitoring_installed
                
                if monitoring_installed:
                    try:
                        services = k8s_client.list_namespaced_service(namespace="monitoring")
                        grafana_url = None
                        
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
                            if "grafana" in svc.metadata.name.lower():
                                if svc.spec.type == "LoadBalancer":
                                    if svc.status.load_balancer.ingress:
                                        lb_ip = svc.status.load_balancer.ingress[0].ip
                                        grafana_url = f"http://{lb_ip}:3000"
                                    else:
                                        grafana_url = f"http://{master_ip}:3000"
                                else:
                                    grafana_url = f"http://{master_ip}:3000"
                        
                        app_data["urls"] = {
                            "grafana": grafana_url or f"http://{master_ip}:3000"
                        }
                        app_data["url"] = grafana_url or f"http://{master_ip}:3000"
                        
                    except Exception as e:
                        logger.warning(f"Could not determine monitoring URLs: {str(e)}")
                        app_data["urls"] = {
                            "grafana": f"http://localhost:3000"
                        }
                        app_data["url"] = "http://localhost:3000"
                else:
                    app_data.pop("url", None)
                    app_data.pop("urls", None)
            elif app["id"] == "jellyfin":
                jellyfin_installed = "jellyfin" in namespace_names
                app_data["installed"] = jellyfin_installed
                
                if jellyfin_installed:
                    try:
                        services = k8s_client.list_namespaced_service(namespace="jellyfin")
                        jellyfin_url = None
                        
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
                            if "jellyfin" in svc.metadata.name.lower():
                                if svc.spec.type == "LoadBalancer":
                                    if svc.status.load_balancer.ingress:
                                        lb_ip = svc.status.load_balancer.ingress[0].ip
                                        jellyfin_url = f"http://{lb_ip}:8096"
                                    else:
                                        jellyfin_url = f"http://{master_ip}:8096"
                                else:
                                    jellyfin_url = f"http://{master_ip}:8096"
                        
                        app_data["url"] = jellyfin_url or f"http://{master_ip}:8096"
                        
                    except Exception as e:
                        logger.warning(f"Could not determine Jellyfin URL: {str(e)}")
                        app_data["url"] = "http://localhost:8096"
                else:
                    app_data.pop("url", None)
            else:
                app_data["installed"] = app["id"] in namespace_names
            
            apps_with_status.append(app_data)
            
        logger.info(f"Returning {len(apps_with_status)} applications")
        return apps_with_status
    except Exception as e:
        logger.error(f"Error fetching applications: {str(e)}")
        

        for app in AVAILABLE_APPS:
            app_data = app.copy()
            app_data["installed"] = False
            app_data["status_error"] = True
            app_data.pop("url", None)
            apps_with_status.append(app_data)
        
        return apps_with_status 
