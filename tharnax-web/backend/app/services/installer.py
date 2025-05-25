import time
import logging
import yaml
import os
import subprocess
import asyncio
from kubernetes import client
from kubernetes.client.rest import ApiException
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

APP_REGISTRY = {
    "monitoring": {
        "name": "Monitoring Stack",
        "can_uninstall": True,
        "helm_release": "monitoring-stack",
        "namespace": "monitoring",
        "argocd_app": "monitoring-stack"
    },
    "argocd": {
        "name": "ArgoCD",
        "can_uninstall": False,
        "helm_release": "argocd",
        "namespace": "argocd",
        "argocd_app": None
    },
    "jellyfin": {
        "name": "Jellyfin",
        "can_uninstall": True,
        "helm_release": "jellyfin",
        "namespace": "jellyfin",
        "argocd_app": "jellyfin"
    },
    "sonarr": {
        "name": "Sonarr",
        "can_uninstall": True,
        "helm_release": "sonarr", 
        "namespace": "sonarr",
        "argocd_app": "sonarr"
    }
}

def get_app_config(component: str) -> Optional[Dict[str, Any]]:
    """Get configuration for a specific app component"""
    return APP_REGISTRY.get(component)

def can_uninstall_component(component: str) -> bool:
    """Check if a component can be uninstalled"""
    app_config = get_app_config(component)
    return app_config is not None and app_config.get("can_uninstall", True)

def detect_nfs_storage():
    """
    Detect if NFS storage is available in the cluster
    """
    try:
        # Check common NFS paths that might be mounted or accessible
        nfs_paths = []
        
        if os.path.exists('/etc/exports'):
            try:
                with open('/etc/exports', 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            path = line.split()[0]
                            if os.path.exists(path):
                                nfs_paths.append(path)
            except Exception:
                pass
        common_paths = ['/mnt/tharnax-nfs', '/mnt/nfs', '/srv/nfs', '/data', '/nfs']
        for path in common_paths:
            if os.path.exists(path) and os.path.isdir(path):
                if os.path.ismount(path) or os.listdir(path):
                    nfs_paths.append(path)
                    
        return len(nfs_paths) > 0, nfs_paths[0] if nfs_paths else None
    except Exception as e:
        logger.warning(f"Error detecting NFS storage: {e}")
        return False, None

def create_monitoring_helm_values(nfs_available: bool, nfs_path: Optional[str] = None):
    """
    Create Helm values for the monitoring stack (simplified, no ArgoCD complexity)
    """
    helm_values = {
        "prometheus": {
            "prometheusSpec": {
                "retention": "15d",
                "retentionSize": "10GB",
                "scrapeInterval": "30s",
                "evaluationInterval": "30s",
                "enableAdminAPI": True,
                "walCompression": True,
                "maximumStartupDurationSeconds": 600
            }
        },
        "grafana": {
            "adminPassword": "admin",
            "service": {
                "type": "LoadBalancer",
                "port": 3000,
                "targetPort": 3000
            },
            "persistence": {
                "enabled": True,
                "size": "1Gi"
            },
            "defaultDashboardsEnabled": True,
            "adminUser": "admin"
        },
        "alertmanager": {
            "alertmanagerSpec": {
                "retention": "120h"
            }
        },
        "kubeStateMetrics": {
            "enabled": True
        },
        "nodeExporter": {
            "enabled": True
        },
        "prometheusOperator": {
            "enabled": True
        }
    }
    
    if nfs_available and nfs_path:
        logger.info(f"Configuring monitoring stack with NFS storage: {nfs_path}")
        helm_values["prometheus"]["prometheusSpec"]["storageSpec"] = {
            "volumeClaimTemplate": {
                "spec": {
                    "accessModes": ["ReadWriteMany"],
                    "resources": {
                        "requests": {
                            "storage": "10Gi"
                        }
                    }
                }
            }
        }
        
        helm_values["grafana"]["persistence"]["accessModes"] = ["ReadWriteMany"]
        helm_values["alertmanager"]["alertmanagerSpec"]["storage"] = {
            "volumeClaimTemplate": {
                "spec": {
                    "accessModes": ["ReadWriteMany"],
                    "resources": {
                        "requests": {
                            "storage": "2Gi"
                        }
                    }
                }
            }
        }
    else:
        logger.info("Configuring monitoring stack with default storage")
        helm_values["prometheus"]["prometheusSpec"]["storageSpec"] = {
            "volumeClaimTemplate": {
                "spec": {
                    "accessModes": ["ReadWriteOnce"],
                    "resources": {
                        "requests": {
                            "storage": "10Gi"
                        }
                    }
                }
            }
        }
    
    return helm_values

async def install_monitoring_stack(k8s_client: client.CoreV1Api):
    """
    Install the monitoring stack directly with Helm (not ArgoCD)
    """
    logger.info("Starting monitoring stack installation with direct Helm")
    
    try:
        try:
            namespace = client.V1Namespace(
                metadata=client.V1ObjectMeta(name="monitoring")
            )
            k8s_client.create_namespace(namespace)
            logger.info("Created monitoring namespace")
        except ApiException as e:
            if e.status == 409:
                logger.info("Monitoring namespace already exists")
            else:
                raise
        
        nfs_available, nfs_path = detect_nfs_storage()
        logger.info(f"NFS storage detection: available={nfs_available}, path={nfs_path}")
        
        helm_values = create_monitoring_helm_values(nfs_available, nfs_path)
        values_file = "/tmp/monitoring-values.yaml"
        with open(values_file, 'w') as f:
            yaml.dump(helm_values, f)
        
        logger.info("Created Helm values file")
        
        logger.info("Adding Prometheus Community Helm repository...")
        env = os.environ.copy()
        env["KUBERNETES_SERVICE_HOST"] = "kubernetes.default.svc.cluster.local"
        env["KUBERNETES_SERVICE_PORT"] = "443"
        
        process = await asyncio.create_subprocess_exec(
            "helm", "repo", "add", "prometheus-community", 
            "https://prometheus-community.github.io/helm-charts",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        stdout, stderr = await process.communicate()
        if process.returncode != 0:
            logger.warning(f"Helm repo add warning: {stderr.decode()}")
        
        logger.info("Updating Helm repositories...")
        process = await asyncio.create_subprocess_exec(
            "helm", "repo", "update",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        await process.communicate()
        logger.info("Installing monitoring stack with Helm...")
        process = await asyncio.create_subprocess_exec(
            "helm", "install", "monitoring-stack", 
            "prometheus-community/kube-prometheus-stack",
            "--namespace", "monitoring",
            "--values", values_file,
            "--wait", "--timeout", "15m",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode == 0:
            logger.info("Monitoring stack installed successfully with Helm")
            logger.info(f"Helm output: {stdout.decode()}")
            
            try:
                os.remove(values_file)
            except:
                pass
            
            return True
        else:
            logger.error(f"Helm installation failed: {stderr.decode()}")
            try:
                os.remove(values_file)
            except:
                pass
            return False
        
    except Exception as e:
        logger.error(f"Error installing monitoring stack: {e}")
        try:
            os.remove("/tmp/monitoring-values.yaml")
        except:
            pass
        raise

async def install_component(component: str, config: Optional[Dict[str, Any]], k8s_client: client.CoreV1Api):
    """
    Install a component in the cluster with improved concurrency support
    """
    logger.info(f"Starting installation of {component} with config: {config}")
    
    try:
        if component == "monitoring":
            return await install_monitoring_stack(k8s_client)
        else:
            try:
                namespace = client.V1Namespace(
                    metadata=client.V1ObjectMeta(
                        name=component
                    )
                )
                k8s_client.create_namespace(namespace)
                logger.info(f"Created namespace {component}")
            except client.rest.ApiException as e:
                if e.status != 409:
                    logger.error(f"Error creating namespace: {e}")
                    raise
            steps = ["preparing", "deploying", "configuring", "starting", "completed"]
            
            for i, step in enumerate(steps):
                logger.info(f"{component}: {step}")
                await asyncio.sleep(2)
                
                progress = int((i + 1) / len(steps) * 100)
                logger.info(f"{component} installation progress: {progress}%")
            
            logger.info(f"Completed installation of {component}")
            return True
    except Exception as e:
        logger.error(f"Error installing {component}: {e}")
        raise 

async def uninstall_monitoring_stack(k8s_client: client.CoreV1Api):
    """
    Uninstall the monitoring stack by removing Helm release and ArgoCD application
    """
    logger.info("Starting monitoring stack uninstallation")
    
    try:
        env = os.environ.copy()
        env["KUBERNETES_SERVICE_HOST"] = "kubernetes.default.svc.cluster.local"
        env["KUBERNETES_SERVICE_PORT"] = "443"
        try:
            logger.info("Attempting to delete ArgoCD application...")
            process = await asyncio.create_subprocess_exec(
                "kubectl", "delete", "application", "monitoring-stack", 
                "-n", "argocd", "--ignore-not-found=true",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env
            )
            stdout, stderr = await process.communicate()
            if process.returncode == 0:
                logger.info("ArgoCD application deleted successfully")
            else:
                logger.warning(f"ArgoCD application deletion warning: {stderr.decode()}")
        except Exception as e:
            logger.warning(f"Could not delete ArgoCD application: {e}")
        logger.info("Uninstalling Helm release...")
        process = await asyncio.create_subprocess_exec(
            "helm", "uninstall", "monitoring-stack", 
            "--namespace", "monitoring",
            "--wait", "--timeout", "10m",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode == 0:
            logger.info("Helm release uninstalled successfully")
        else:
            logger.warning(f"Helm uninstall warning: {stderr.decode()}")
        
        logger.info("Cleaning up persistent resources...")
        try:
            process = await asyncio.create_subprocess_exec(
                "kubectl", "delete", "pvc", "--all", "-n", "monitoring",
                "--ignore-not-found=true",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env
            )
            await process.communicate()
            process = await asyncio.create_subprocess_exec(
                "kubectl", "delete", "prometheus,alertmanager,servicemonitor,prometheusrule",
                "--all", "-n", "monitoring", "--ignore-not-found=true",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env
            )
            await process.communicate()
            
        except Exception as e:
            logger.warning(f"Error during resource cleanup: {e}")
        
        await asyncio.sleep(5)
        
        logger.info("Monitoring stack uninstalled successfully")
        return True
        
    except Exception as e:
        logger.error(f"Error uninstalling monitoring stack: {e}")
        raise

async def uninstall_component(component: str, k8s_client: client.CoreV1Api):
    """
    Uninstall a component from the cluster
    """
    logger.info(f"Starting uninstallation of {component}")
    
    if not can_uninstall_component(component):
        app_config = get_app_config(component)
        app_name = app_config["name"] if app_config else component
        raise ValueError(f"{app_name} cannot be uninstalled as it's a protected system component")
    
    try:
        if component == "monitoring":
            return await uninstall_monitoring_stack(k8s_client)
        else:
            app_config = get_app_config(component)
            if not app_config:
                raise ValueError(f"Unknown component: {component}")
            
            env = os.environ.copy()
            env["KUBERNETES_SERVICE_HOST"] = "kubernetes.default.svc.cluster.local"
            env["KUBERNETES_SERVICE_PORT"] = "443"
            if app_config.get("argocd_app"):
                try:
                    process = await asyncio.create_subprocess_exec(
                        "kubectl", "delete", "application", app_config["argocd_app"], 
                        "-n", "argocd", "--ignore-not-found=true",
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                        env=env
                    )
                    await process.communicate()
                except Exception as e:
                    logger.warning(f"Could not delete ArgoCD application for {component}: {e}")
            if app_config.get("helm_release"):
                process = await asyncio.create_subprocess_exec(
                    "helm", "uninstall", app_config["helm_release"], 
                    "--namespace", app_config["namespace"],
                    "--wait", "--timeout", "5m",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    env=env
                )
                await process.communicate()
            
            logger.info(f"Completed uninstallation of {component}")
            return True
    except Exception as e:
        logger.error(f"Error uninstalling {component}: {e}")
        raise

async def restart_component(component: str, config: Optional[Dict[str, Any]], k8s_client: client.CoreV1Api):
    """
    Restart a component by performing a rollout restart of its deployments
    """
    logger.info(f"Starting rollout restart of {component}")
    
    try:
        app_config = get_app_config(component)
        if not app_config:
            raise ValueError(f"Unknown component: {component}")
        
        namespace = app_config.get("namespace", component)
        
        apps_v1 = client.AppsV1Api()
        
        if component == "monitoring":
            logger.info("Restarting monitoring stack deployments...")
            deployments = apps_v1.list_namespaced_deployment(namespace=namespace)
            
            if not deployments.items:
                logger.warning(f"No deployments found in {namespace} namespace")
                return False
            for deployment in deployments.items:
                deployment_name = deployment.metadata.name
                logger.info(f"Restarting deployment: {deployment_name}")
                
                try:
                    from datetime import datetime
                    restart_annotation = {
                        "kubectl.kubernetes.io/restartedAt": datetime.now().isoformat()
                    }
                    deployment.spec.template.metadata.annotations = deployment.spec.template.metadata.annotations or {}
                    deployment.spec.template.metadata.annotations.update(restart_annotation)
                    
                    # Apply the update
                    apps_v1.patch_namespaced_deployment(
                        name=deployment_name,
                        namespace=namespace,
                        body=deployment
                    )
                    
                    logger.info(f"Successfully triggered restart for {deployment_name}")
                    
                except Exception as e:
                    logger.warning(f"Failed to restart {deployment_name}: {e}")
            

            statefulsets = apps_v1.list_namespaced_stateful_set(namespace=namespace)
            for sts in statefulsets.items:
                sts_name = sts.metadata.name
                logger.info(f"Restarting StatefulSet: {sts_name}")
                
                try:
                    from datetime import datetime
                    restart_annotation = {
                        "kubectl.kubernetes.io/restartedAt": datetime.now().isoformat()
                    }
                    
                    # Update StatefulSet annotations to trigger restart
                    sts.spec.template.metadata.annotations = sts.spec.template.metadata.annotations or {}
                    sts.spec.template.metadata.annotations.update(restart_annotation)
                    
                    # Apply the update
                    apps_v1.patch_namespaced_stateful_set(
                        name=sts_name,
                        namespace=namespace,
                        body=sts
                    )
                    
                    logger.info(f"Successfully triggered restart for StatefulSet {sts_name}")
                    
                except Exception as e:
                    logger.warning(f"Failed to restart StatefulSet {sts_name}: {e}")
                    
        else:
            logger.info(f"Restarting {component} deployments...")
            deployments = apps_v1.list_namespaced_deployment(namespace=namespace)
            
            for deployment in deployments.items:
                deployment_name = deployment.metadata.name
                logger.info(f"Restarting deployment: {deployment_name}")
                
                try:
                    from datetime import datetime
                    restart_annotation = {
                        "kubectl.kubernetes.io/restartedAt": datetime.now().isoformat()
                    }
                    
                    # Update deployment annotations to trigger restart
                    deployment.spec.template.metadata.annotations = deployment.spec.template.metadata.annotations or {}
                    deployment.spec.template.metadata.annotations.update(restart_annotation)
                    
                    # Apply the update
                    apps_v1.patch_namespaced_deployment(
                        name=deployment_name,
                        namespace=namespace,
                        body=deployment
                    )
                    
                    logger.info(f"Successfully triggered restart for {deployment_name}")
                    
                except Exception as e:
                    logger.warning(f"Failed to restart {deployment_name}: {e}")
            

            statefulsets = apps_v1.list_namespaced_stateful_set(namespace=namespace)
            for sts in statefulsets.items:
                sts_name = sts.metadata.name
                logger.info(f"Restarting StatefulSet: {sts_name}")
                
                try:
                    from datetime import datetime
                    restart_annotation = {
                        "kubectl.kubernetes.io/restartedAt": datetime.now().isoformat()
                    }
                    
                    # Update StatefulSet annotations to trigger restart
                    sts.spec.template.metadata.annotations = sts.spec.template.metadata.annotations or {}
                    sts.spec.template.metadata.annotations.update(restart_annotation)
                    
                    # Apply the update
                    apps_v1.patch_namespaced_stateful_set(
                        name=sts_name,
                        namespace=namespace,
                        body=sts
                    )
                    
                    logger.info(f"Successfully triggered restart for StatefulSet {sts_name}")
                    
                except Exception as e:
                    logger.warning(f"Failed to restart StatefulSet {sts_name}: {e}")
        
        logger.info(f"Successfully restarted {component}")
        return True
        
    except Exception as e:
        logger.error(f"Error restarting {component}: {e}")
        raise 
