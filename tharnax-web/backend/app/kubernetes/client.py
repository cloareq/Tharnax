from kubernetes import client, config
import os
import logging
import sys

logger = logging.getLogger(__name__)

def get_k8s_client():
    """
    Initialize and return the Kubernetes client.
    When running inside the cluster, this will use the service account.
    When running locally, it will use the kubeconfig file.
    """
    try:
        logger.info(f"Python version: {sys.version}")
        logger.info(f"Running as user: {os.getuid()}:{os.getgid()}")
        logger.info(f"Working directory: {os.getcwd()}")
        
        logger.info("Attempting to load in-cluster Kubernetes configuration")
        config.load_incluster_config()
        logger.info("Successfully loaded in-cluster Kubernetes configuration")
        
        v1 = client.CoreV1Api()
        try:
            version = client.VersionApi().get_code()
            logger.info(f"Connected to Kubernetes API version: {version.git_version}")
        except Exception as e:
            logger.warning(f"Could not get Kubernetes version: {e}")
            
    except config.ConfigException as e:
        logger.info(f"Not running in cluster, falling back to kubeconfig: {e}")
        try:
            kubeconfig = os.environ.get("KUBECONFIG", os.path.expanduser("~/.kube/config"))
            logger.info(f"Loading kubeconfig from: {kubeconfig}")
            if not os.path.exists(kubeconfig):
                logger.warning(f"Kubeconfig file {kubeconfig} does not exist")
                
            config.load_kube_config(kubeconfig)
            logger.info("Successfully loaded kubeconfig")
            
            v1 = client.CoreV1Api()
            try:
                version = client.VersionApi().get_code()
                logger.info(f"Connected to Kubernetes API version: {version.git_version}")
            except Exception as e:
                logger.warning(f"Could not get Kubernetes version: {e}")
                
        except Exception as e:
            logger.error(f"Could not configure Kubernetes client: {e}")
            raise RuntimeError(f"Could not configure Kubernetes client: {e}")
    
    # Return the CoreV1Api client for pod, namespace, etc. operations
    return client.CoreV1Api() 
