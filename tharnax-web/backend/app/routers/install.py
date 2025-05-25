from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from app.kubernetes.client import get_k8s_client
from app.services.installer import install_component, uninstall_component, restart_component, can_uninstall_component, get_app_config
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
VALID_COMPONENTS = ["jellyfin", "sonarr", "prometheus", "grafana", "monitoring", "argocd"]

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
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested installation of unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    if component in installation_status and installation_status[component]["status"] == "installing":
        logger.info(f"Component '{component}' is already being installed")
        return {
            "status": "already_installing",
            "message": f"Installation of {component} is already in progress",
            "component": component
        }
    
    logger.info(f"Starting installation of '{component}'")
    
    installation_status[component] = {
        "status": "installing",
        "progress": 0,
        "message": f"Starting installation of {component}",
        "started_at": datetime.now().isoformat(),
        "component": component
    }
    
    background_tasks.add_task(
        install_component_with_status,
        component,
        config or {},
        k8s_client
    )
    
    return {
        "status": "started",
        "message": f"Installation of {component} started",
        "component": component,
        "progress": 0
    }

@router.delete("/{component}")
async def uninstall_app(
    component: str,
    background_tasks: BackgroundTasks,
    k8s_client: client.CoreV1Api = Depends(get_k8s_client)
):
    """
    Trigger uninstallation of a specific component
    """
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested uninstallation of unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    if not can_uninstall_component(component):
        app_config = get_app_config(component)
        app_name = app_config["name"] if app_config else component
        logger.warning(f"Attempted to uninstall protected component: {component}")
        raise HTTPException(status_code=403, detail=f"{app_name} cannot be uninstalled as it's a protected system component")
    
    if component in installation_status and installation_status[component]["status"] in ["installing", "uninstalling", "restarting"]:
        logger.info(f"Component '{component}' is already being processed")
        return {
            "status": "already_processing",
            "message": f"{component} is already being processed",
            "component": component
        }
    
    logger.info(f"Starting uninstallation of '{component}'")
    
    installation_status[component] = {
        "status": "uninstalling",
        "progress": 0,
        "message": f"Starting uninstallation of {component}",
        "started_at": datetime.now().isoformat(),
        "component": component
    }
    
    background_tasks.add_task(
        uninstall_component_with_status,
        component,
        k8s_client
    )
    
    return {
        "status": "started",
        "message": f"Uninstallation of {component} started",
        "component": component,
        "progress": 0
    }

@router.post("/{component}/restart")
async def restart_app(
    component: str,
    background_tasks: BackgroundTasks,
    config: Dict[str, Any] = None,
    k8s_client: client.CoreV1Api = Depends(get_k8s_client)
):
    """
    Trigger restart (rollout restart) of a specific component's deployments
    """
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested restart of unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    if not can_uninstall_component(component):
        app_config = get_app_config(component)
        app_name = app_config["name"] if app_config else component
        logger.warning(f"Attempted to restart protected component: {component}")
        raise HTTPException(status_code=403, detail=f"{app_name} cannot be restarted as it's a protected system component")
    
    app_config = get_app_config(component)
    namespace = app_config.get("namespace", component) if app_config else component
    
    try:
        pods = k8s_client.list_namespaced_pod(namespace=namespace)
        if not pods.items:
            raise HTTPException(status_code=400, detail=f"{component} is not installed - cannot restart")
        
        running_pods = [pod for pod in pods.items if pod.status.phase == "Running"]
        if len(running_pods) == 0:
            raise HTTPException(status_code=400, detail=f"{component} has no running pods - cannot restart")
            
    except client.exceptions.ApiException as e:
        if e.status == 404:
            raise HTTPException(status_code=400, detail=f"{component} is not installed - cannot restart")
        else:
            raise HTTPException(status_code=500, detail=f"Error checking {component} status")
    
    if component in installation_status and installation_status[component]["status"] in ["installing", "uninstalling", "restarting"]:
        logger.info(f"Component '{component}' is already being processed")
        return {
            "status": "already_processing",
            "message": f"{component} is already being processed",
            "component": component
        }
    
    logger.info(f"Starting restart of '{component}'")
    
    installation_status[component] = {
        "status": "restarting",
        "progress": 0,
        "message": f"Starting rollout restart of {component}",
        "started_at": datetime.now().isoformat(),
        "component": component
    }
    
    background_tasks.add_task(
        restart_component_with_status,
        component,
        config or {},
        k8s_client
    )
    
    return {
        "status": "started",
        "message": f"Rollout restart of {component} started",
        "component": component,
        "progress": 0
    }

async def install_component_with_status(component: str, config: Dict[str, Any], k8s_client: client.CoreV1Api):
    """
    Wrapper function to track installation status with real-time pod progress monitoring
    """
    try:
        installation_status[component]["status"] = "installing"
        installation_status[component]["progress"] = 5
        installation_status[component]["message"] = f"Starting installation of {component}"
        
        if component == "monitoring":
            installation_status[component]["progress"] = 10
            installation_status[component]["message"] = "Installing monitoring stack with Helm..."
            
            install_task = asyncio.create_task(install_component(component, config, k8s_client))
            
            expected_pods = 8
            
            while not install_task.done():
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        
                        if total_pods > 0:
                            pod_progress = min((len(running_pods) / expected_pods) * 70, 70)
                            current_progress = max(15 + pod_progress, installation_status[component]["progress"])
                            installation_status[component]["progress"] = int(current_progress)
                            
                            if len(running_pods) == 0 and total_pods > 0:
                                installation_status[component]["message"] = f"Monitoring pods starting... {total_pods} pods created"
                            elif len(running_pods) < total_pods:
                                installation_status[component]["message"] = f"Monitoring pods starting... {len(running_pods)}/{total_pods} pods ready"
                            else:
                                installation_status[component]["message"] = f"Monitoring stack almost ready... {len(running_pods)} pods running"
                        else:
                            installation_status[component]["progress"] = 15
                            installation_status[component]["message"] = "Waiting for monitoring pods to be created..."
                    else:
                        installation_status[component]["progress"] = 15
                        installation_status[component]["message"] = "Creating monitoring namespace and resources..."
                        
                except Exception as pod_check_error:
                    logger.warning(f"Error checking pod status during installation: {pod_check_error}")
                
                await asyncio.sleep(3)
            
            try:
                result = await install_task
            except Exception as e:
                raise e
            
            if result:
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        
                        if len(running_pods) >= expected_pods * 0.75:  # At least 75% of expected pods
                            installation_status[component]["status"] = "completed"
                            installation_status[component]["progress"] = 100
                            installation_status[component]["message"] = f"Monitoring stack installed successfully! {len(running_pods)} pods running."
                        else:
                            # Installation succeeded but pods not all ready yet
                            installation_status[component]["status"] = "installing"
                            installation_status[component]["progress"] = 90
                            installation_status[component]["message"] = f"Installation complete, waiting for all pods... {len(running_pods)}/{total_pods} ready"
                    else:
                        installation_status[component]["status"] = "error"
                        installation_status[component]["progress"] = 0
                        installation_status[component]["message"] = "Installation completed but no pods found"
                except Exception as final_check_error:
                    logger.warning(f"Error in final pod check: {final_check_error}")
                    installation_status[component]["status"] = "completed"
                    installation_status[component]["progress"] = 100
                    installation_status[component]["message"] = "Monitoring stack installation completed"
                
                logger.info(f"Monitoring installation completed successfully")
            else:
                installation_status[component]["status"] = "error"
                installation_status[component]["progress"] = 0
                installation_status[component]["message"] = f"Failed to install {component}"
        elif component == "jellyfin":
            installation_status[component]["progress"] = 10
            installation_status[component]["message"] = "Creating Jellyfin ArgoCD application..."
            
            install_task = asyncio.create_task(install_component(component, config, k8s_client))
            
            expected_pods = 1  # Jellyfin typically runs as a single pod
            
            while not install_task.done():
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="jellyfin")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        
                        if total_pods > 0:
                            pod_progress = min((len(running_pods) / expected_pods) * 70, 70)
                            current_progress = max(15 + pod_progress, installation_status[component]["progress"])
                            installation_status[component]["progress"] = int(current_progress)
                            
                            if len(running_pods) == 0 and total_pods > 0:
                                installation_status[component]["message"] = f"Jellyfin pod starting... {total_pods} pods created"
                            elif len(running_pods) < total_pods:
                                installation_status[component]["message"] = f"Jellyfin pod starting... {len(running_pods)}/{total_pods} pods ready"
                            else:
                                installation_status[component]["message"] = f"Jellyfin almost ready... {len(running_pods)} pods running"
                        else:
                            installation_status[component]["progress"] = 15
                            installation_status[component]["message"] = "Waiting for Jellyfin pod to be created..."
                    else:
                        installation_status[component]["progress"] = 15
                        installation_status[component]["message"] = "Creating Jellyfin namespace and resources..."
                        
                except Exception as pod_check_error:
                    logger.warning(f"Error checking pod status during installation: {pod_check_error}")
                
                await asyncio.sleep(3)
            
            try:
                result = await install_task
            except Exception as e:
                raise e
            
            if result:
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="jellyfin")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        
                        if len(running_pods) >= expected_pods * 0.75:  # At least 75% of expected pods
                            installation_status[component]["status"] = "completed"
                            installation_status[component]["progress"] = 100
                            installation_status[component]["message"] = f"Jellyfin installed successfully! {len(running_pods)} pods running."
                        else:
                            # Installation succeeded but pods not all ready yet
                            installation_status[component]["status"] = "installing"
                            installation_status[component]["progress"] = 90
                            installation_status[component]["message"] = f"Installation complete, waiting for pod... {len(running_pods)}/{total_pods} ready"
                    else:
                        installation_status[component]["status"] = "error"
                        installation_status[component]["progress"] = 0
                        installation_status[component]["message"] = "Installation completed but no pods found"
                except Exception as final_check_error:
                    logger.warning(f"Error in final pod check: {final_check_error}")
                    installation_status[component]["status"] = "completed"
                    installation_status[component]["progress"] = 100
                    installation_status[component]["message"] = "Jellyfin installation completed"
                
                logger.info(f"Jellyfin installation completed successfully")
            else:
                installation_status[component]["status"] = "error"
                installation_status[component]["progress"] = 0
                installation_status[component]["message"] = f"Failed to install {component}"
        else:
            # For other components, perform the installation with simulated progress
            steps = ["preparing", "deploying", "configuring", "starting", "completed"]
            
            for i, step in enumerate(steps):
                progress = int((i + 1) / len(steps) * 100)
                installation_status[component]["progress"] = progress
                installation_status[component]["message"] = f"{component}: {step}"
                
                if i < len(steps) - 1:  # Don't sleep on the last step
                    await asyncio.sleep(2)
            
            # Perform the actual installation
            result = await install_component(component, config, k8s_client)
            
            if result:
                installation_status[component]["status"] = "completed"
                installation_status[component]["progress"] = 100
                installation_status[component]["message"] = f"{component} installed successfully!"
            else:
                installation_status[component]["status"] = "error"
                installation_status[component]["progress"] = 0
                installation_status[component]["message"] = f"Failed to install {component}"
    
    except Exception as e:
        logger.error(f"Error installing {component}: {str(e)}")
        installation_status[component]["status"] = "error"
        installation_status[component]["progress"] = 0
        installation_status[component]["message"] = f"Installation failed: {str(e)}"

async def uninstall_component_with_status(component: str, k8s_client: client.CoreV1Api):
    """
    Wrapper function to track uninstallation status
    """
    try:
        # Update status to uninstalling
        installation_status[component]["status"] = "uninstalling"
        installation_status[component]["progress"] = 10
        installation_status[component]["message"] = f"Uninstalling {component}..."
        
        # Perform the actual uninstallation
        result = await uninstall_component(component, k8s_client)
        
        if result:
            installation_status[component]["status"] = "not_installed"
            installation_status[component]["progress"] = 100
            installation_status[component]["message"] = f"{component} uninstalled successfully!"
            logger.info(f"{component} uninstallation completed successfully")
        else:
            installation_status[component]["status"] = "error"
            installation_status[component]["progress"] = 0
            installation_status[component]["message"] = f"Failed to uninstall {component}"
    
    except Exception as e:
        logger.error(f"Error uninstalling {component}: {str(e)}")
        installation_status[component]["status"] = "error"
        installation_status[component]["progress"] = 0
        installation_status[component]["message"] = f"Uninstallation failed: {str(e)}"

async def restart_component_with_status(component: str, config: Dict[str, Any], k8s_client: client.CoreV1Api):
    """
    Wrapper function to track restart status with real-time pod progress monitoring
    """
    try:
        # Update status to restarting
        installation_status[component]["status"] = "restarting"
        installation_status[component]["progress"] = 10
        installation_status[component]["message"] = f"Starting rollout restart of {component}..."
        
        if component == "monitoring":
            # Enhanced monitoring restart with real-time progress
            installation_status[component]["progress"] = 15
            installation_status[component]["message"] = "Triggering rollout restart of monitoring components..."
            
            # Get initial pod state before restart
            try:
                initial_pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                expected_pods = len(initial_pods.items) if initial_pods.items else 8
                initial_pod_uids = {pod.metadata.uid for pod in initial_pods.items}
            except Exception as e:
                logger.warning(f"Could not get initial pod state: {e}")
                expected_pods = 8
                initial_pod_uids = set()
            
            # Start the restart in a separate task so we can monitor progress
            restart_task = asyncio.create_task(restart_component(component, config, k8s_client))
            
            # Wait a moment for restart to be triggered
            await asyncio.sleep(2)
            installation_status[component]["progress"] = 20
            installation_status[component]["message"] = "Rollout restart triggered, monitoring pod recreation..."
            
            # Monitor progress while restart is happening
            restart_started = False
            max_wait_time = 180  # 3 minutes max
            wait_time = 0
            
            while not restart_task.done() and wait_time < max_wait_time:
                try:
                    # Check current pod status
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        current_pod_uids = {pod.metadata.uid for pod in pods.items}
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        
                        # Check if restart has started (new pods with different UIDs)
                        new_pods = current_pod_uids - initial_pod_uids
                        if new_pods or len(current_pod_uids) < len(initial_pod_uids):
                            restart_started = True
                        
                        if restart_started:
                            # Calculate progress based on pod readiness after restart
                            if total_pods > 0:
                                # Progress from 25% to 90% based on pod readiness
                                pod_progress = min((len(running_pods) / expected_pods) * 65, 65)
                                current_progress = max(25 + pod_progress, installation_status[component]["progress"])
                                installation_status[component]["progress"] = int(current_progress)
                                
                                if len(running_pods) == 0:
                                    installation_status[component]["message"] = f"Restarting pods... {total_pods} pods recreated"
                                elif len(running_pods) < expected_pods:
                                    installation_status[component]["message"] = f"Pods restarting... {len(running_pods)}/{total_pods} pods ready"
                                else:
                                    installation_status[component]["message"] = f"Restart almost complete... {len(running_pods)} pods running"
                            else:
                                installation_status[component]["progress"] = 30
                                installation_status[component]["message"] = "Pods being recreated..."
                        else:
                            # Still waiting for restart to begin
                            installation_status[component]["progress"] = 20
                            installation_status[component]["message"] = "Waiting for pod restart to begin..."
                    else:
                        installation_status[component]["progress"] = 25
                        installation_status[component]["message"] = "Pods being recreated..."
                        
                except Exception as pod_check_error:
                    logger.warning(f"Error checking pod status during restart: {pod_check_error}")
                
                # Wait a bit before checking again
                await asyncio.sleep(3)
                wait_time += 3
            
            # Get the restart result
            try:
                result = await restart_task
            except Exception as e:
                raise e
            
            if result:
                # Final verification of pod status
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        
                        if len(running_pods) >= expected_pods * 0.75:  # At least 75% of expected pods
                            installation_status[component]["status"] = "completed"
                            installation_status[component]["progress"] = 100
                            installation_status[component]["message"] = f"Restart completed successfully! {len(running_pods)} pods running."
                        else:
                            # Restart succeeded but pods not all ready yet
                            installation_status[component]["status"] = "restarting"
                            installation_status[component]["progress"] = 95
                            installation_status[component]["message"] = f"Restart complete, finalizing... {len(running_pods)}/{total_pods} ready"
                    else:
                        installation_status[component]["status"] = "error"
                        installation_status[component]["progress"] = 0
                        installation_status[component]["message"] = "Restart completed but no pods found"
                except Exception as final_check_error:
                    logger.warning(f"Error in final pod check: {final_check_error}")
                    installation_status[component]["status"] = "completed"
                    installation_status[component]["progress"] = 100
                    installation_status[component]["message"] = "Restart completed"
                
                logger.info(f"Monitoring restart completed successfully")
            else:
                installation_status[component]["status"] = "error"
                installation_status[component]["progress"] = 0
                installation_status[component]["message"] = f"Failed to restart {component}"
        else:
            # For other components, perform restart with simulated progress
            steps = ["triggering restart", "recreating pods", "waiting for readiness", "completed"]
            
            for i, step in enumerate(steps):
                progress = int(20 + (i / len(steps)) * 80)  # 20% to 100%
                installation_status[component]["progress"] = progress
                installation_status[component]["message"] = f"{component}: {step}"
                
                if i < len(steps) - 1:  # Don't sleep on the last step
                    await asyncio.sleep(3)
            
            # Perform the actual restart
            result = await restart_component(component, config, k8s_client)
            
            if result:
                installation_status[component]["status"] = "completed"
                installation_status[component]["progress"] = 100
                installation_status[component]["message"] = f"{component} restarted successfully!"
            else:
                installation_status[component]["status"] = "error"
                installation_status[component]["progress"] = 0
                installation_status[component]["message"] = f"Failed to restart {component}"
    
    except Exception as e:
        logger.error(f"Error restarting {component}: {str(e)}")
        installation_status[component]["status"] = "error"
        installation_status[component]["progress"] = 0
        installation_status[component]["message"] = f"Restart failed: {str(e)}"

@router.get("/{component}/status")
async def get_install_status(
    component: str,
    k8s_client: client.CoreV1Api = Depends(get_k8s_client)
):
    """
    Get installation status for a specific component (simplified without ArgoCD)
    """
    if component not in VALID_COMPONENTS:
        logger.warning(f"Requested status for unknown component: {component}")
        raise HTTPException(status_code=404, detail=f"Component '{component}' not found")
    
    logger.info(f"Checking installation status for '{component}'")
    
    try:
        # Special handling for monitoring and jellyfin components
        if component == "monitoring":
            # Check if we have an existing installation status
            if component in installation_status:
                status_info = installation_status[component]
                
                # Enhanced progress tracking for monitoring
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        expected_pods = 8
                        
                        # If we have pods, calculate real-time progress
                        if status_info["status"] == "installing":
                            # Installation in progress - show live progress
                            if total_pods == 0:
                                # No pods yet
                                return {
                                    "status": "installing",
                                    "progress": max(status_info.get("progress", 0), 15),
                                    "message": status_info.get("message", "Creating monitoring resources..."),
                                    "pods_running": 0,
                                    "total_pods": 0
                                }
                            else:
                                # Pods exist, calculate progress based on readiness
                                base_progress = max(status_info.get("progress", 15), 15)
                                pod_progress = min((len(running_pods) / expected_pods) * 70, 70)
                                current_progress = max(base_progress, 15 + pod_progress)
                                
                                return {
                                    "status": "installing",
                                    "progress": int(current_progress),
                                    "message": f"Monitoring pods starting... {len(running_pods)}/{total_pods} pods ready",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                        elif status_info["status"] == "completed":
                            # Installation marked complete, verify all pods are ready
                            if len(running_pods) >= expected_pods * 0.75:
                                return {
                                    "status": "completed",
                                    "progress": 100,
                                    "message": f"Monitoring stack deployed successfully! {len(running_pods)} pods running.",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                            else:
                                # Installation complete but not all pods ready
                                progress = max(90, 90 + (len(running_pods) / expected_pods) * 10)
                                return {
                                    "status": "installing",
                                    "progress": int(progress),
                                    "message": f"Installation complete, pods starting... {len(running_pods)}/{total_pods} ready",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                        elif status_info["status"] == "restarting":
                            # Restart in progress - show live restart progress
                            base_progress = max(status_info.get("progress", 20), 20)
                            
                            if total_pods > 0:
                                # Calculate restart progress based on pod readiness
                                pod_progress = min((len(running_pods) / expected_pods) * 65, 65)
                                current_progress = max(base_progress, 25 + pod_progress)
                                
                                return {
                                    "status": "restarting", 
                                    "progress": int(current_progress),
                                    "message": f"Restarting pods... {len(running_pods)}/{total_pods} pods ready",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                            else:
                                return {
                                    "status": "restarting",
                                    "progress": base_progress,
                                    "message": status_info.get("message", "Pods being recreated..."),
                                    "pods_running": 0,
                                    "total_pods": 0
                                }
                        else:
                            # Other statuses (error, etc.) - return as-is but with pod info
                            return {
                                **status_info,
                                "pods_running": len(running_pods),
                                "total_pods": total_pods
                            }
                    else:
                        # No pods yet during installation
                        if status_info["status"] == "installing":
                            return {
                                "status": "installing",
                                "progress": max(status_info.get("progress", 10), 10),
                                "message": status_info.get("message", "Starting monitoring installation..."),
                                "pods_running": 0,
                                "total_pods": 0
                            }
                        else:
                            return status_info
                            
                except Exception as pod_check_error:
                    logger.warning(f"Error checking pod status: {pod_check_error}")
                    # Fall back to installation status
                    return status_info
            else:
                # No installation status, check if component is already installed
                try:
                    # Check if monitoring namespace exists and has running pods
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        if len(running_pods) >= 3:
                            return {
                                "component": component,
                                "status": "installed",
                                "progress": 100,
                                "message": f"Monitoring stack is already installed ({len(running_pods)} pods running)",
                                "pods_running": len(running_pods),
                                "total_pods": len(pods.items)
                            }
                except:
                    pass
                
                return {
                    "component": component,
                    "status": "not_installed",
                    "progress": 0,
                    "message": f"{component} is not installed"
                }
        elif component == "jellyfin":
            # Check if we have an existing installation status
            if component in installation_status:
                status_info = installation_status[component]
                
                # Enhanced progress tracking for Jellyfin
                try:
                    pods = k8s_client.list_namespaced_pod(namespace="jellyfin")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        total_pods = len(pods.items)
                        expected_pods = 1
                        
                        # If we have pods, calculate real-time progress
                        if status_info["status"] == "installing":
                            # Installation in progress - show live progress
                            if total_pods == 0:
                                # No pods yet
                                return {
                                    "status": "installing",
                                    "progress": max(status_info.get("progress", 0), 15),
                                    "message": status_info.get("message", "Creating Jellyfin resources..."),
                                    "pods_running": 0,
                                    "total_pods": 0
                                }
                            else:
                                # Pods exist, calculate progress based on readiness
                                base_progress = max(status_info.get("progress", 15), 15)
                                pod_progress = min((len(running_pods) / expected_pods) * 70, 70)
                                current_progress = max(base_progress, 15 + pod_progress)
                                
                                return {
                                    "status": "installing",
                                    "progress": int(current_progress),
                                    "message": f"Jellyfin pod starting... {len(running_pods)}/{total_pods} pods ready",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                        elif status_info["status"] == "completed":
                            # Installation marked complete, verify pod is ready
                            if len(running_pods) >= expected_pods:
                                return {
                                    "status": "completed",
                                    "progress": 100,
                                    "message": f"Jellyfin deployed successfully! {len(running_pods)} pods running.",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                            else:
                                # Installation complete but pod not ready
                                progress = max(90, 90 + (len(running_pods) / expected_pods) * 10)
                                return {
                                    "status": "installing",
                                    "progress": int(progress),
                                    "message": f"Installation complete, pod starting... {len(running_pods)}/{total_pods} ready",
                                    "pods_running": len(running_pods),
                                    "total_pods": total_pods
                                }
                        else:
                            # Other statuses (error, etc.) - return as-is but with pod info
                            return {
                                **status_info,
                                "pods_running": len(running_pods),
                                "total_pods": total_pods
                            }
                    else:
                        # No pods yet during installation
                        if status_info["status"] == "installing":
                            return {
                                "status": "installing",
                                "progress": max(status_info.get("progress", 10), 10),
                                "message": status_info.get("message", "Starting Jellyfin installation..."),
                                "pods_running": 0,
                                "total_pods": 0
                            }
                        else:
                            return status_info
                            
                except Exception as pod_check_error:
                    logger.warning(f"Error checking pod status: {pod_check_error}")
                    # Fall back to installation status
                    return status_info
            else:
                # No installation status, check if component is already installed
                try:
                    # Check if Jellyfin namespace exists and has running pods
                    pods = k8s_client.list_namespaced_pod(namespace="jellyfin")
                    if pods.items:
                        running_pods = [pod for pod in pods.items if pod.status.phase == "Running" and 
                                      all(container.ready for container in (pod.status.container_statuses or []))]
                        if len(running_pods) >= 1:
                            return {
                                "component": component,
                                "status": "installed",
                                "progress": 100,
                                "message": f"Jellyfin is already installed ({len(running_pods)} pods running)",
                                "pods_running": len(running_pods),
                                "total_pods": len(pods.items)
                            }
                except:
                    pass
                
                return {
                    "component": component,
                    "status": "not_installed",
                    "progress": 0,
                    "message": f"{component} is not installed"
                }
        
        # For non-monitoring/jellyfin components, use existing logic
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
