#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

echo "Applying Kubernetes manifests..."
kubectl apply -f "${SCRIPT_DIR}/kubernetes/namespace.yaml"
kubectl apply -f "${SCRIPT_DIR}/kubernetes/rbac.yaml"
kubectl apply -f "${SCRIPT_DIR}/kubernetes/tharnax.yaml"

echo "Deployment completed!"

echo "Waiting for deployment to be ready..."
kubectl -n tharnax-web rollout status deployment/tharnax-web

echo ""
echo "Tharnax Web is now available at:"
sleep 5
EXTERNAL_IP=$(kubectl -n tharnax-web get service tharnax-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -n "$EXTERNAL_IP" ]; then
    echo "* http://${EXTERNAL_IP} (LoadBalancer IP)"
else
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    if [ -n "$NODE_IP" ]; then
        echo "* LoadBalancer pending, try http://${NODE_IP} (via node IP)"
    fi
    echo "* Run 'kubectl -n tharnax-web get svc' to check LoadBalancer status"
fi 
