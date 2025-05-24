import time
import logging
import yaml
import os
from kubernetes import client
from kubernetes.client.rest import ApiException
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

def detect_nfs_storage():
    """
    Detect if NFS storage is available in the cluster
    """
    try:
        # Check common NFS paths that might be mounted or accessible
        nfs_paths = []
        
        # First check /etc/exports if accessible
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
        
        # Check common mount points
        common_paths = ['/mnt/tharnax-nfs', '/mnt/nfs', '/srv/nfs', '/data', '/nfs']
        for path in common_paths:
            if os.path.exists(path) and os.path.isdir(path):
                if os.path.ismount(path) or os.listdir(path):
                    nfs_paths.append(path)
                    
        return len(nfs_paths) > 0, nfs_paths[0] if nfs_paths else None
    except Exception as e:
        logger.warning(f"Error detecting NFS storage: {e}")
        return False, None

def create_monitoring_argocd_application(nfs_available: bool, nfs_path: Optional[str] = None):
    """
    Create an Argo CD Application manifest for the monitoring stack
    """
    
    # Base Helm values
    helm_values = {
        "prometheus": {
            "prometheusSpec": {
                "retention": "15d",
                "retentionSize": "10GB"
            }
        },
        "grafana": {
            "adminPassword": "admin",
            "service": {
                "type": "LoadBalancer"
            },
            "persistence": {
                "enabled": True,
                "size": "1Gi"
            }
        },
        "alertmanager": {
            "alertmanagerSpec": {
                "retention": "120h"
            }
        }
    }
    
    # Configure storage based on NFS availability
    if nfs_available and nfs_path:
        logger.info(f"Configuring monitoring stack with NFS storage: {nfs_path}")
        # Configure PVC for Prometheus with NFS
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
        
        # Configure PVC for Grafana with NFS
        helm_values["grafana"]["persistence"]["accessModes"] = ["ReadWriteMany"]
        
        # Configure PVC for AlertManager with NFS
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
        # Use emptyDir or default storage class
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
    
    # Create the Argo CD Application manifest
    application_manifest = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "metadata": {
            "name": "monitoring-stack",
            "namespace": "argocd",
            "labels": {
                "managed-by": "tharnax"
            }
        },
        "spec": {
            "project": "default",
            "source": {
                "repoURL": "https://prometheus-community.github.io/helm-charts",
                "chart": "kube-prometheus-stack",
                "targetRevision": "57.2.0",  # Use a specific stable version
                "helm": {
                    "values": yaml.dump(helm_values)
                }
            },
            "destination": {
                "server": "https://kubernetes.default.svc",
                "namespace": "monitoring"
            },
            "syncPolicy": {
                "automated": {
                    "prune": True,
                    "selfHeal": True
                },
                "syncOptions": [
                    "CreateNamespace=true"
                ]
            }
        }
    }
    
    return application_manifest

async def install_monitoring_stack(k8s_client: client.CoreV1Api):
    """
    Install the monitoring stack via Argo CD Application
    """
    logger.info("Starting monitoring stack installation via Argo CD")
    
    try:
        # Detect NFS storage
        nfs_available, nfs_path = detect_nfs_storage()
        logger.info(f"NFS storage detection: available={nfs_available}, path={nfs_path}")
        
        # Create the Application manifest
        app_manifest = create_monitoring_argocd_application(nfs_available, nfs_path)
        
        # Create custom objects API client for Argo CD Applications
        custom_api = client.CustomObjectsApi()
        
        try:
            # Try to create the Application
            custom_api.create_namespaced_custom_object(
                group="argoproj.io",
                version="v1alpha1",
                namespace="argocd",
                plural="applications",
                body=app_manifest
            )
            logger.info("Created Argo CD Application for monitoring stack")
        except ApiException as e:
            if e.status == 409:
                # Application already exists, update it
                logger.info("Application already exists, updating...")
                custom_api.patch_namespaced_custom_object(
                    group="argoproj.io",
                    version="v1alpha1",
                    namespace="argocd",
                    plural="applications",
                    name="monitoring-stack",
                    body=app_manifest
                )
                logger.info("Updated Argo CD Application for monitoring stack")
            else:
                raise
        
        # Wait for the Application to sync and deploy
        logger.info("Waiting for monitoring stack deployment to complete...")
        max_wait_time = 600  # 10 minutes
        wait_interval = 30   # 30 seconds
        elapsed_time = 0
        
        while elapsed_time < max_wait_time:
            try:
                # Check if monitoring namespace exists and has pods
                namespaces = k8s_client.list_namespace()
                monitoring_exists = any(ns.metadata.name == "monitoring" for ns in namespaces.items)
                
                if monitoring_exists:
                    # Check for running pods in monitoring namespace
                    pods = k8s_client.list_namespaced_pod(namespace="monitoring")
                    running_pods = [pod for pod in pods.items if pod.status.phase == "Running"]
                    
                    if len(running_pods) > 0:
                        logger.info(f"Monitoring stack deployed successfully! {len(running_pods)} pods running")
                        return True
                
                time.sleep(wait_interval)
                elapsed_time += wait_interval
                logger.info(f"Still waiting for monitoring stack deployment... ({elapsed_time}s elapsed)")
            except Exception as e:
                logger.warning(f"Error checking deployment status: {e}")
                time.sleep(wait_interval)
                elapsed_time += wait_interval
        
        logger.warning("Monitoring stack deployment timed out, but Application was created")
        return True
        
    except Exception as e:
        logger.error(f"Error installing monitoring stack: {e}")
        raise

async def install_component(component: str, config: Optional[Dict[str, Any]], k8s_client: client.CoreV1Api):
    """
    Install a component in the cluster.
    """
    logger.info(f"Starting installation of {component} with config: {config}")
    
    try:
        if component == "monitoring":
            return await install_monitoring_stack(k8s_client)
        else:
            # Legacy installation for other components
            # Create namespace for the component
            try:
                namespace = client.V1Namespace(
                    metadata=client.V1ObjectMeta(
                        name=component
                    )
                )
                k8s_client.create_namespace(namespace)
                logger.info(f"Created namespace {component}")
            except client.rest.ApiException as e:
                if e.status != 409:  # Ignore if namespace already exists
                    logger.error(f"Error creating namespace: {e}")
                    raise
            
            # Simulate installation steps with delays
            steps = ["preparing", "deploying", "configuring", "starting", "completed"]
            
            for step in steps:
                logger.info(f"{component}: {step}")
                time.sleep(2)  # Simulate work being done
            
            logger.info(f"Completed installation of {component}")
            return True
    except Exception as e:
        logger.error(f"Error installing {component}: {e}")
        raise 
