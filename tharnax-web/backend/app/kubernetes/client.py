from kubernetes import client, config
import os
import logging

logger = logging.getLogger(__name__)

def get_k8s_client():
    """
    Initialize and return the Kubernetes client.
    When running inside the cluster, this will use the service account.
    When running locally, it will use the kubeconfig file.
    """
    try:
        # Try to load in-cluster config (when running as a pod)
        logger.info("Attempting to load in-cluster Kubernetes configuration")
        config.load_incluster_config()
        logger.info("Successfully loaded in-cluster Kubernetes configuration")
    except config.ConfigException as e:
        # Fallback to kubeconfig file (for local development)
        logger.info(f"Not running in cluster, falling back to kubeconfig: {e}")
        try:
            kubeconfig = os.environ.get("KUBECONFIG", os.path.expanduser("~/.kube/config"))
            logger.info(f"Loading kubeconfig from: {kubeconfig}")
            config.load_kube_config(kubeconfig)
            logger.info("Successfully loaded kubeconfig")
        except Exception as e:
            logger.error(f"Could not configure Kubernetes client: {e}")
            raise RuntimeError(f"Could not configure Kubernetes client: {e}")
    
    # Return the CoreV1Api client for pod, namespace, etc. operations
    return client.CoreV1Api() 
