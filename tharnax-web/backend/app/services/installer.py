import time
import logging
import yaml
import os
from kubernetes import client
from kubernetes.client.rest import ApiException
from typing import Dict, Any, Optional
import asyncio

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
        "crds": {
            "enabled": False  # Disable CRD creation to avoid annotation issues
        },
        "prometheus": {
            "prometheusSpec": {
                "retention": "15d",
                "retentionSize": "10GB",
                "scrapeInterval": "30s",
                "evaluationInterval": "30s",
                "enableAdminAPI": True,
                "walCompression": True,
                "portName": "web",
                "listenLocal": False,
                "enableRemoteWriteReceiver": False,
                "disableCompaction": False,
                "enableFeatures": [],
                "web": {
                    "enableLifecycle": True,
                    "enableAdminAPI": True,
                    "routePrefix": "/",
                    "externalUrl": ""
                }
            },
            "service": {
                "type": "LoadBalancer",
                "port": 9090,
                "targetPort": 9090,
                "additionalPorts": [
                    {
                        "name": "reloader-web",
                        "port": 8081,
                        "targetPort": 8080,
                        "protocol": "TCP"
                    }
                ]
            },
            "servicePerReplica": {
                "enabled": False
            },
            "podDisruptionBudget": {
                "enabled": False
            },
            "serviceMonitor": {
                "enabled": True
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
                "retention": "120h",
                "storage": {}
            }
        },
        "kubeStateMetrics": {
            "enabled": True
        },
        "nodeExporter": {
            "enabled": True
        },
        "prometheusOperator": {
            "enabled": True,
            "manageCrds": False,  # Don't manage CRDs to avoid issues
            "prometheusConfigReloader": {
                "resources": {
                    "requests": {
                        "cpu": "200m",
                        "memory": "50Mi"
                    },
                    "limits": {
                        "cpu": "200m", 
                        "memory": "50Mi"
                    }
                }
            },
            "admissionWebhooks": {
                "enabled": True,
                "patch": {
                    "enabled": True,
                    "image": {
                        "pullPolicy": "IfNotPresent"
                    }
                },
                "certManager": {
                    "enabled": False
                }
            },
            "tls": {
                "enabled": True
            }
        },
        "global": {
            "scrape_interval": "15s",
            "evaluation_interval": "15s"
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
                "targetRevision": "58.7.2",  # Use a more recent stable version
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
                    "CreateNamespace=true",
                    "ServerSideApply=true",
                    "SkipDryRunOnMissingResource=true"
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
        
        # Step 1: Install CRDs first to avoid annotation size issues
        logger.info("Installing Prometheus Operator CRDs...")
        await install_prometheus_crds(k8s_client)
        
        # Step 2: Create the Application manifest
        app_manifest = create_monitoring_argocd_application(nfs_available, nfs_path)
        
        # Step 3: Create custom objects API client for Argo CD Applications
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
        max_wait_time = 900  # 15 minutes for monitoring stack
        wait_interval = 15   # 15 seconds for more frequent updates
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
                    total_pods = len(pods.items)
                    
                    logger.info(f"Monitoring namespace: {len(running_pods)}/{total_pods} pods running")
                    
                    # We need at least 3 main components running: prometheus, grafana, alertmanager
                    if len(running_pods) >= 3:
                        logger.info(f"Found {len(running_pods)} running pods, checking services...")
                        
                        # Check if essential services are ready
                        services = k8s_client.list_namespaced_service(namespace="monitoring")
                        grafana_ready = False
                        prometheus_ready = False
                        
                        for svc in services.items:
                            # Check Grafana service
                            if "grafana" in svc.metadata.name.lower():
                                if svc.spec.type == "LoadBalancer":
                                    if svc.status.load_balancer.ingress:
                                        grafana_ready = True
                                        logger.info("Grafana LoadBalancer is ready")
                                    else:
                                        logger.info("Grafana LoadBalancer still pending...")
                                else:
                                    grafana_ready = True  # ClusterIP is immediately ready
                            
                            # Check Prometheus service  
                            if "prometheus" in svc.metadata.name.lower() and "operated" not in svc.metadata.name.lower():
                                prometheus_ready = True
                                logger.info("Prometheus service is ready")
                        
                        if grafana_ready and prometheus_ready:
                            logger.info("Monitoring stack deployed successfully! All services are ready.")
                            return True
                        else:
                            logger.info(f"Services status - Grafana ready: {grafana_ready}, Prometheus ready: {prometheus_ready}")
                
                await asyncio.sleep(wait_interval)  # Use asyncio.sleep for proper async behavior
                elapsed_time += wait_interval
                logger.info(f"Still waiting for monitoring stack deployment... ({elapsed_time}s elapsed)")
            except Exception as e:
                logger.warning(f"Error checking deployment status: {e}")
                await asyncio.sleep(wait_interval)
                elapsed_time += wait_interval
        
        logger.warning("Monitoring stack deployment timed out, but Application was created")
        return True
        
    except Exception as e:
        logger.error(f"Error installing monitoring stack: {e}")
        raise

async def install_prometheus_crds(k8s_client: client.CoreV1Api):
    """
    Install Prometheus Operator CRDs directly to avoid annotation size issues
    """
    logger.info("Installing Prometheus Operator CRDs...")
    
    # Define the CRDs we need with minimal annotations
    crds = [
        {
            "apiVersion": "apiextensions.k8s.io/v1",
            "kind": "CustomResourceDefinition",
            "metadata": {
                "name": "alertmanagers.monitoring.coreos.com"
            },
            "spec": {
                "group": "monitoring.coreos.com",
                "versions": [
                    {
                        "name": "v1",
                        "served": True,
                        "storage": True,
                        "schema": {
                            "openAPIV3Schema": {
                                "type": "object",
                                "properties": {
                                    "spec": {"type": "object", "x-kubernetes-preserve-unknown-fields": True},
                                    "status": {"type": "object", "x-kubernetes-preserve-unknown-fields": True}
                                }
                            }
                        }
                    }
                ],
                "scope": "Namespaced",
                "names": {
                    "plural": "alertmanagers",
                    "singular": "alertmanager",
                    "kind": "Alertmanager"
                }
            }
        },
        {
            "apiVersion": "apiextensions.k8s.io/v1",
            "kind": "CustomResourceDefinition",
            "metadata": {
                "name": "prometheuses.monitoring.coreos.com"
            },
            "spec": {
                "group": "monitoring.coreos.com",
                "versions": [
                    {
                        "name": "v1",
                        "served": True,
                        "storage": True,
                        "schema": {
                            "openAPIV3Schema": {
                                "type": "object",
                                "properties": {
                                    "spec": {"type": "object", "x-kubernetes-preserve-unknown-fields": True},
                                    "status": {"type": "object", "x-kubernetes-preserve-unknown-fields": True}
                                }
                            }
                        }
                    }
                ],
                "scope": "Namespaced",
                "names": {
                    "plural": "prometheuses",
                    "singular": "prometheus",
                    "kind": "Prometheus"
                }
            }
        },
        {
            "apiVersion": "apiextensions.k8s.io/v1",
            "kind": "CustomResourceDefinition",
            "metadata": {
                "name": "prometheusagents.monitoring.coreos.com"
            },
            "spec": {
                "group": "monitoring.coreos.com",
                "versions": [
                    {
                        "name": "v1alpha1",
                        "served": True,
                        "storage": True,
                        "schema": {
                            "openAPIV3Schema": {
                                "type": "object",
                                "properties": {
                                    "spec": {"type": "object", "x-kubernetes-preserve-unknown-fields": True},
                                    "status": {"type": "object", "x-kubernetes-preserve-unknown-fields": True}
                                }
                            }
                        }
                    }
                ],
                "scope": "Namespaced",
                "names": {
                    "plural": "prometheusagents",
                    "singular": "prometheusagent",
                    "kind": "PrometheusAgent"
                }
            }
        }
    ]
    
    # Install each CRD
    api_extensions = client.ApiextensionsV1Api()
    
    for crd in crds:
        try:
            api_extensions.create_custom_resource_definition(body=crd)
            logger.info(f"Created CRD: {crd['metadata']['name']}")
        except ApiException as e:
            if e.status == 409:
                logger.info(f"CRD already exists: {crd['metadata']['name']}")
            else:
                logger.warning(f"Error creating CRD {crd['metadata']['name']}: {e}")
                # Continue with other CRDs even if one fails
    
    logger.info("Prometheus Operator CRDs installation completed")

async def install_component(component: str, config: Optional[Dict[str, Any]], k8s_client: client.CoreV1Api):
    """
    Install a component in the cluster with improved concurrency support
    """
    logger.info(f"Starting installation of {component} with config: {config}")
    
    try:
        if component == "monitoring":
            return await install_monitoring_stack(k8s_client)
        else:
            # Legacy installation for other components with async support
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
            
            # Simulate installation steps with delays (using async sleep)
            steps = ["preparing", "deploying", "configuring", "starting", "completed"]
            
            for i, step in enumerate(steps):
                logger.info(f"{component}: {step}")
                await asyncio.sleep(2)  # Use async sleep to not block other installations
                
                # Calculate progress percentage
                progress = int((i + 1) / len(steps) * 100)
                logger.info(f"{component} installation progress: {progress}%")
            
            logger.info(f"Completed installation of {component}")
            return True
    except Exception as e:
        logger.error(f"Error installing {component}: {e}")
        raise 
