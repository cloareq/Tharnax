# Tharnax Web UI

The Tharnax Web UI provides a dashboard for monitoring and managing your K3s cluster. It allows you to:

- View cluster status and information
- Deploy and manage applications
- Configure cluster services

## Deployment

The Tharnax Web UI is automatically deployed at the end of the `tharnax-init.sh` script if you select the option. You can also deploy it manually using the provided deployment script.

### Prerequisites

- A running K3s cluster installed with Tharnax
- `kubectl` configured to access your cluster

### Manual Deployment

To deploy the Tharnax Web UI manually:

```bash
# Make sure you run this from the Tharnax root directory
chmod +x tharnax-web/deploy.sh
./tharnax-web/deploy.sh
```

This script will:
1. Apply the necessary Kubernetes manifests (namespace, RBAC, deployment, service)
2. Wait for the deployment to be ready
3. Display the LoadBalancer IP when available

## Accessing the Web UI

Once deployed, you can access the Tharnax Web UI through:

- http://<load-balancer-ip> (automatically provided by your Kubernetes LoadBalancer)
- If LoadBalancer is pending, you may temporarily access it via a node IP

## Troubleshooting

If you encounter deployment issues:

1. Ensure kubectl is properly configured: `kubectl cluster-info`
2. Check deployment status: `kubectl -n tharnax-web get deployments`
3. Check pod status: `kubectl -n tharnax-web get pods`
4. View pod logs: `kubectl -n tharnax-web logs -l app=tharnax-web`
5. Check service status: `kubectl -n tharnax-web get svc`

## Architecture

The Tharnax Web UI consists of:

- **Frontend**: React-based UI with Tailwind CSS for styling
- **Backend**: FastAPI service that interacts with the Kubernetes API
- **Nginx**: Web server that serves frontend assets and proxies API requests
- **RBAC**: ServiceAccount with permissions to manage the cluster

## Image

The application uses a combined Docker image hosted on Docker Hub:

- `quentinc/tharnax:latest` - A single image containing both the React frontend (served via Nginx) and the FastAPI backend

This all-in-one image is maintained by the Tharnax project maintainers. 
