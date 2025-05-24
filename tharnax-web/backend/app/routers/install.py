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
    Wrapper function to track installation status with ArgoCD integration
    """
    try:
        # Update status to installing
        installation_status[component]["status"] = "installing"
        installation_status[component]["progress"] = 5
        installation_status[component]["message"] = f"Starting installation of {component}"
        
        if component == "monitoring":
            # Special handling for monitoring with ArgoCD tracking
            installation_status[component]["progress"] = 10
            installation_status[component]["message"] = "Creating ArgoCD Application..."
            
            # Perform the actual installation
            result = await install_component(component, config, k8s_client)
            
            if result:
                # Don't immediately mark as completed - let ArgoCD tracking handle this
                installation_status[component]["progress"] = 20
                installation_status[component]["message"] = "ArgoCD Application created, deployment starting..."
                
                # The actual completion will be tracked by the status endpoint checking ArgoCD
                logger.info(f"Monitoring installation initiated successfully, ArgoCD will handle deployment")
            else:
                installation_status[component]["status"] = "error"
                installation_status[component]["progress"] = 0
                installation_status[component]["message"] = f"Failed to create ArgoCD Application for {component}"
        else:
            # Legacy installation for other components
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
    Get installation status for a specific component with ArgoCD integration
    """
    # Check if component is valid
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested status for unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    logger.info(f"Checking installation status for '{component}'")
    
    try:
        # Special handling for monitoring component with ArgoCD integration
        if component == "monitoring":
            # Check if we have an existing installation status
            if component in installation_status:
                status_info = installation_status[component]
                
                # First check actual pod status - this is more reliable than ArgoCD health
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in pod.status.container_statuses or [])]
                        total_pods = len(pods.items)
                        
                        if len(running_pods) >= 3:  # Main components: prometheus, grafana, alertmanager
                            # Check if we have the essential services
                            services = k8s_client.list_namespaced_service(namespace="monitoring")
                            has_grafana = any("grafana" in svc.metadata.name for svc in services.items)
                            has_prometheus = any("prometheus" in svc.metadata.name and "operated" not in svc.metadata.name 
                                               for svc in services.items)
                            
                            if has_grafana and has_prometheus and len(running_pods) >= 7:  # All pods running
                                return {
                                    "status": "completed",
                                    "progress": 100,
                                    "message": f"Monitoring stack deployed successfully! {len(running_pods)} pods running.",
                                    "argocd_health": "Healthy (forced)",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                            elif len(running_pods) >= 3:
                                progress = min(50 + (len(running_pods) * 6), 95)  # 50-95% based on pods
                                return {
                                    "status": "installing",
                                    "progress": progress,
                                    "message": f"Monitoring services starting... {len(running_pods)}/{total_pods} pods ready",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                        else:
                            progress = max(20, len(running_pods) * 10)
                            return {
                                "status": "installing", 
                                "progress": progress,
                                "message": f"Monitoring stack deploying... {len(running_pods)}/{total_pods} pods ready",
                                "pods_running": len(running_pods),
                                "total_pods": total_pods
                            }
                    else:
                        # No pods yet, check ArgoCD status
                        argocd_status = await get_argocd_application_status("monitoring-stack")
                        if argocd_status and argocd_status.get("sync_status") == "Synced":
                            return {
                                "status": "installing",
                                "progress": 15,
                                "message": "ArgoCD application synced, waiting for pods...",
                                "argocd_sync": argocd_status.get("sync_status"),
                                "argocd_health": argocd_status.get("health_status")
                            }
                except Exception as pod_check_error:
                    logger.warning(f"Error checking pod status: {pod_check_error}")
                
                # Fall back to ArgoCD status if pod check fails
                argocd_status = await get_argocd_application_status("monitoring-stack")
        
        # For non-monitoring components, use existing logic
        if component in installation_status:
            status_info = installation_status[component].copy()
            
            # If installation is completed, also check actual deployment status
            if status_info["status"] == "completed":
                # Verify the component is actually installed
                namespaces = k8s_client.list_namespace()
                namespace_names = [ns.metadata.name for ns in namespaces.items]
                actually_installed = component in namespace_names
                
                if not actually_installed:
                    status_info["status"] = "error"
                    status_info["message"] = f"Installation reported complete but {component} not found"
            
            return status_info
        else:
            # No installation status, check if component is already installed
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

async def get_argocd_application_progress(k8s_client: client.CoreV1Api, app_name: str = "monitoring-stack"):
    """
    Get detailed progress information from ArgoCD Application
    """
    try:
        custom_api = client.CustomObjectsApi()
        
        # Check if the Application exists
        try:
            app = custom_api.get_namespaced_custom_object(
                group="argoproj.io",
                version="v1alpha1",
                namespace="argocd",
                plural="applications",
                name=app_name
            )
        except client.exceptions.ApiException as e:
            if e.status == 404:
                return {
                    "progress": 0,
                    "status": "not_found",
                    "message": "ArgoCD Application not found",
                    "health": "Unknown",
                    "sync": "Unknown"
                }
            else:
                raise
        
        # Parse Application status
        status = app.get("status", {})
        health = status.get("health", {})
        sync = status.get("sync", {})
        operation_state = status.get("operationState", {})
        resources = status.get("resources", [])
        
        health_status = health.get("status", "Unknown")
        sync_status = sync.get("status", "Unknown")
        operation_phase = operation_state.get("phase", "Unknown")
        
        # Calculate progress based on ArgoCD status
        progress = 0
        detailed_message = "Starting installation..."
        
        # Base progress on sync status
        if sync_status == "Synced":
            progress = 70  # Synced means resources are applied
            detailed_message = "Application synced, waiting for health check..."
        elif sync_status == "OutOfSync":
            progress = 30
            detailed_message = "Synchronizing application resources..."
        elif operation_phase == "Running":
            progress = 50
            detailed_message = "Deployment in progress..."
        elif operation_phase == "Succeeded":
            progress = 80
            detailed_message = "Deployment completed, checking health..."
        
        # Additional progress based on health status
        if health_status == "Healthy":
            progress = 95
            detailed_message = "Application healthy, verifying services..."
            
            # Check if actual pods are running for final progress
            try:
                pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                running_pods = [pod for pod in pods.items if pod.status.phase == "Running"]
                total_pods = len(pods.items)
                
                if total_pods > 0:
                    pod_progress = (len(running_pods) / total_pods) * 100
                    progress = max(progress, min(99, 90 + (pod_progress / 10)))
                    detailed_message = f"Services ready: {len(running_pods)}/{total_pods} pods running"
                
                # Final check - if we have essential services running
                if len(running_pods) >= 3:  # Prometheus, Grafana, AlertManager
                    services = k8s_client.list_namespaced_service(namespace="monitoring")
                    service_count = len([svc for svc in services.items if "grafana" in svc.metadata.name.lower() or "prometheus" in svc.metadata.name.lower()])
                    
                    if service_count >= 2:  # Grafana + Prometheus services
                        progress = 100
                        detailed_message = "Installation completed successfully"
                        
            except Exception as e:
                logger.warning(f"Error checking pods for progress: {e}")
        elif health_status == "Progressing":
            progress = max(progress, 60)
            detailed_message = "Application progressing..."
        elif health_status == "Degraded":
            progress = 40
            detailed_message = "Application health degraded, retrying..."
        
        # Handle error states
        if operation_phase == "Failed" or health_status == "Unknown":
            return {
                "progress": 0,
                "status": "error",
                "message": "Installation failed - check ArgoCD logs",
                "health": health_status,
                "sync": sync_status
            }
        
        # Determine overall status
        overall_status = "installing"
        if progress >= 100:
            overall_status = "completed"
        elif health_status == "Healthy" and sync_status == "Synced":
            overall_status = "completed"
            progress = 100
            detailed_message = "Installation completed successfully"
        
        return {
            "progress": int(progress),
            "status": overall_status,
            "message": detailed_message,
            "health": health_status,
            "sync": sync_status,
            "resources_count": len(resources)
        }
        
    except Exception as e:
        logger.error(f"Error getting ArgoCD application progress: {e}")
        return {
            "progress": 0,
            "status": "error",
            "message": f"Error checking progress: {str(e)}",
            "health": "Unknown",
            "sync": "Unknown"
        } 

async def get_argocd_application_status(app_name: str):
    """
    Get basic ArgoCD application status
    """
    try:
        custom_api = client.CustomObjectsApi()
        
        app = custom_api.get_namespaced_custom_object(
            group="argoproj.io",
            version="v1alpha1",
            namespace="argocd",
            plural="applications",
            name=app_name
        )
        
        status = app.get("status", {})
        health = status.get("health", {})
        sync = status.get("sync", {})
        
        return {
            "health_status": health.get("status"),
            "sync_status": sync.get("status"),
            "message": status.get("operationState", {}).get("message", "")
        }
        
    except Exception as e:
        logger.warning(f"Error getting ArgoCD application status: {e}")
        return None 
