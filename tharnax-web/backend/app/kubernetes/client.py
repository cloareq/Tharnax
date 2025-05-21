from kubernetes import client, config
import os

def get_k8s_client():
    """
    Initialize and return the Kubernetes client.
    When running inside the cluster, this will use the service account.
    When running locally, it will use the kubeconfig file.
    """
    try:
        # Try to load in-cluster config (when running as a pod)
        config.load_incluster_config()
    except config.ConfigException:
        # Fallback to kubeconfig file (for local development)
        try:
            kubeconfig = os.environ.get("KUBECONFIG", os.path.expanduser("~/.kube/config"))
            config.load_kube_config(kubeconfig)
        except Exception as e:
            raise RuntimeError(f"Could not configure Kubernetes client: {e}")
    
    # Return the CoreV1Api client for pod, namespace, etc. operations
    return client.CoreV1Api() 
