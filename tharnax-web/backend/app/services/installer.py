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

def create_jellyfin_helm_values(nfs_available: bool, nfs_path: Optional[str] = None, master_ip: str = "localhost"):
    """
    Create Helm values for Jellyfin with NFS storage configuration
    """
    helm_values = {
        "image": {
            "repository": "jellyfin/jellyfin",
            "tag": "latest",
            "pullPolicy": "Always"
        },
        "service": {
            "type": "LoadBalancer",
            "port": 8096,
            "annotations": {}
        },
        "persistence": {
            "config": {
                "enabled": True,
                "size": "2Gi",
                "storageClass": "",
                "accessMode": "ReadWriteOnce"
            },
            "media": {
                "enabled": True,
                "size": "100Gi",
                "storageClass": ""
            }
        },
        "resources": {
            "requests": {
                "memory": "512Mi",
                "cpu": "250m"
            },
            "limits": {
                "memory": "2Gi",
                "cpu": "2000m"
            }
        },
        "env": {
            "TZ": "UTC",
            "JELLYFIN_PublishedServerUrl": f"http://{master_ip}:8096"
        },
        "nodeSelector": {},
        "tolerations": [],
        "affinity": {}
    }
    
    if nfs_available and nfs_path:
        logger.info(f"Configuring Jellyfin with NFS storage: {nfs_path}")
        helm_values["persistence"]["media"]["accessMode"] = "ReadWriteMany"
        helm_values["persistence"]["config"]["accessMode"] = "ReadWriteMany"
    else:
        logger.info("Configuring Jellyfin with default storage")
        helm_values["persistence"]["media"]["accessMode"] = "ReadWriteOnce"
    
    return helm_values

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

async def install_jellyfin_stack(k8s_client: client.CoreV1Api):
    """
    Install Jellyfin using ArgoCD and Helm
    """
    logger.info("Starting Jellyfin installation with ArgoCD")
    
    try:
        nfs_available, nfs_path = detect_nfs_storage()
        logger.info(f"NFS storage detection: available={nfs_available}, path={nfs_path}")
        
        # Get master node IP for service URL
        master_ip = "localhost"
        try:
            nodes = k8s_client.list_node()
            if nodes.items:
                for address in nodes.items[0].status.addresses:
                    if address.type == "InternalIP":
                        master_ip = address.address
                        break
        except Exception as e:
            logger.warning(f"Could not get master IP: {e}")
        
        # Create Helm values
        helm_values = create_jellyfin_helm_values(nfs_available, nfs_path, master_ip)
        
        # Save values to temporary file
        values_file = "/tmp/jellyfin-values.yaml"
        with open(values_file, 'w') as f:
            yaml.dump(helm_values, f)
        
        logger.info("Created Jellyfin Helm values file")
        
        # Create ArgoCD Application manifest
        argocd_app = {
            "apiVersion": "argoproj.io/v1alpha1",
            "kind": "Application",
            "metadata": {
                "name": "jellyfin",
                "namespace": "argocd",
                "finalizers": ["resources-finalizer.argocd.argoproj.io"]
            },
            "spec": {
                "project": "default",
                "source": {
                    "repoURL": "https://jellyfin.github.io/jellyfin-helm",
                    "chart": "jellyfin",
                    "targetRevision": "*",
                    "helm": {
                        "values": yaml.dump(helm_values)
                    }
                },
                "destination": {
                    "server": "https://kubernetes.default.svc",
                    "namespace": "jellyfin"
                },
                "syncPolicy": {
                    "automated": {
                        "prune": True,
                        "selfHeal": True
                    },
                    "syncOptions": [
                        "CreateNamespace=true",
                        "ApplyOutOfSyncOnly=true"
                    ],
                    "retry": {
                        "limit": 5,
                        "backoff": {
                            "duration": "5s",
                            "factor": 2,
                            "maxDuration": "3m0s"
                        }
                    }
                }
            }
        }
        
        # Save ArgoCD application manifest
        app_file = "/tmp/jellyfin-application.yaml"
        with open(app_file, 'w') as f:
            yaml.dump(argocd_app, f)
        
        logger.info("Created ArgoCD Application manifest")
        
        # Apply the ArgoCD Application
        env = os.environ.copy()
        env["KUBERNETES_SERVICE_HOST"] = "kubernetes.default.svc.cluster.local"
        env["KUBERNETES_SERVICE_PORT"] = "443"
        
        # First add the Helm repository to ArgoCD if not already added
        logger.info("Ensuring Jellyfin Helm repository is configured...")
        try:
            import base64
            
            # Check if repository secret exists using Kubernetes API
            try:
                existing_secret = k8s_client.read_namespaced_secret(
                    name="jellyfin-helm-repo",
                    namespace="argocd"
                )
                logger.info("Jellyfin Helm repository already configured")
            except ApiException as e:
                if e.status == 404:
                    # Repository doesn't exist, create it
                    logger.info("Creating Jellyfin Helm repository configuration...")
                    
                    repo_secret = client.V1Secret(
                        metadata=client.V1ObjectMeta(
                            name="jellyfin-helm-repo",
                            namespace="argocd",
                            labels={
                                "argocd.argoproj.io/secret-type": "repository"
                            }
                        ),
                        data={
                            "type": base64.b64encode("helm".encode()).decode(),
                            "name": base64.b64encode("jellyfin".encode()).decode(),
                            "url": base64.b64encode("https://jellyfin.github.io/jellyfin-helm".encode()).decode()
                        }
                    )
                    
                    k8s_client.create_namespaced_secret(namespace="argocd", body=repo_secret)
                    logger.info("Created Jellyfin Helm repository configuration")
                else:
                    raise
                
        except Exception as e:
            logger.warning(f"Could not configure Helm repository: {e}")
        
        # Create ArgoCD Application using Kubernetes API
        logger.info("Creating ArgoCD Application for Jellyfin...")
        try:
            from kubernetes import client as k8s_client_custom
            
            # Create custom API client for ArgoCD CRDs
            api_client = k8s_client.api_client
            custom_api = client.CustomObjectsApi(api_client)
            
            # Create the ArgoCD Application
            result = custom_api.create_namespaced_custom_object(
                group="argoproj.io",
                version="v1alpha1",
                namespace="argocd",
                plural="applications",
                body=argocd_app
            )
            
            logger.info("Jellyfin ArgoCD Application created successfully")
            logger.info(f"Application name: {result.get('metadata', {}).get('name', 'Unknown')}")
            
            # Clean up temporary files
            try:
                os.remove(values_file)
                os.remove(app_file)
            except:
                pass
            
            return True
            
        except ApiException as e:
            logger.error(f"ArgoCD Application creation failed: {e}")
            # Clean up temporary files
            try:
                os.remove(values_file)
                os.remove(app_file)
            except:
                pass
            return False
        
    except Exception as e:
        logger.error(f"Error installing Jellyfin: {e}")
        # Clean up temporary files
        try:
            os.remove("/tmp/jellyfin-values.yaml")
            os.remove("/tmp/jellyfin-application.yaml")
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
        elif component == "jellyfin":
            return await install_jellyfin_stack(k8s_client)
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

async def uninstall_jellyfin_stack(k8s_client: client.CoreV1Api):
    """
    Uninstall Jellyfin by removing ArgoCD application
    """
    logger.info("Starting Jellyfin uninstallation")
    
    try:
        logger.info("Deleting ArgoCD Application for Jellyfin...")
        try:
            custom_api = client.CustomObjectsApi()
            
            # Delete the ArgoCD Application
            custom_api.delete_namespaced_custom_object(
                group="argoproj.io",
                version="v1alpha1",
                namespace="argocd",
                plural="applications",
                name="jellyfin"
            )
            logger.info("Jellyfin ArgoCD application deleted successfully")
            
        except ApiException as e:
            if e.status == 404:
                logger.info("ArgoCD application not found (already deleted)")
            else:
                logger.warning(f"ArgoCD application deletion warning: {e}")
        
        # Give ArgoCD time to clean up resources
        await asyncio.sleep(10)
        
        # Clean up any remaining resources
        logger.info("Cleaning up remaining Jellyfin resources...")
        try:
            # Delete PVCs
            pvcs = k8s_client.list_namespaced_persistent_volume_claim(namespace="jellyfin")
            for pvc in pvcs.items:
                try:
                    k8s_client.delete_namespaced_persistent_volume_claim(
                        name=pvc.metadata.name,
                        namespace="jellyfin"
                    )
                except ApiException:
                    pass
            
            # Delete the namespace (will be recreated on next install)
            try:
                k8s_client.delete_namespace(name="jellyfin")
            except ApiException as e:
                if e.status != 404:
                    logger.warning(f"Could not delete namespace: {e}")
            
        except Exception as e:
            logger.warning(f"Error during resource cleanup: {e}")
        
        await asyncio.sleep(5)
        
        logger.info("Jellyfin uninstalled successfully")
        return True
        
    except Exception as e:
        logger.error(f"Error uninstalling Jellyfin: {e}")
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
        elif component == "jellyfin":
            return await uninstall_jellyfin_stack(k8s_client)
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
                    
                    sts.spec.template.metadata.annotations = sts.spec.template.metadata.annotations or {}
                    sts.spec.template.metadata.annotations.update(restart_annotation)
                    
                    apps_v1.patch_namespaced_stateful_set(
                        name=sts_name,
                        namespace=namespace,
                        body=sts
                    )
                    
                    logger.info(f"Successfully triggered restart for StatefulSet {sts_name}")
                    
                except Exception as e:
                    logger.warning(f"Failed to restart StatefulSet {sts_name}: {e}")
                    
        elif component == "jellyfin":
            logger.info("Restarting Jellyfin deployment...")
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
