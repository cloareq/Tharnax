import React, { useState, useEffect } from 'react';
import {
    ServerIcon,
    CpuChipIcon,
    CircleStackIcon,
    CodeBracketIcon
} from '@heroicons/react/24/outline';
import StatusCard from '../components/StatusCard';
import { apiClient } from '../services/api';

const Dashboard = () => {
    const [clusterStats, setClusterStats] = useState({
        status: 'loading',
        node_count: '-',
        k3s_version: '-',
        pod_count: '-'
    });

    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchClusterStatus = async () => {
            try {
                setLoading(true);
                const response = await apiClient.get('/status');
                setClusterStats(response.data);
                setError(null);
            } catch (err) {
                setError('Failed to fetch cluster status. Please check if the API is running.');
                console.error('Error fetching cluster status:', err);
            } finally {
                setLoading(false);
            }
        };

        fetchClusterStatus();

        // Poll for updates every 10 seconds
        const intervalId = setInterval(fetchClusterStatus, 10000);

        return () => clearInterval(intervalId);
    }, []);

    return (
        <div>
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-tharnax-text">Cluster Dashboard</h1>
                <p className="text-gray-400">Monitor and manage your K3s cluster</p>
            </div>

            {error && (
                <div className="mb-6 p-4 bg-red-900/30 border border-red-700 rounded-md text-red-300">
                    {error}
                </div>
            )}

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <StatusCard
                    title="Nodes"
                    value={clusterStats.node_count}
                    icon={ServerIcon}
                    color="blue"
                />
                <StatusCard
                    title="Pods"
                    value={clusterStats.pod_count}
                    icon={CircleStackIcon}
                    color="green"
                />
                <StatusCard
                    title="K3s Version"
                    value={clusterStats.k3s_version}
                    icon={CodeBracketIcon}
                    color="purple"
                />
                <StatusCard
                    title="Status"
                    value={clusterStats.status === 'running' ? 'Healthy' : 'Issues'}
                    icon={CpuChipIcon}
                    color={clusterStats.status === 'running' ? 'green' : 'red'}
                />
            </div>

            <div className="mt-8 bg-tharnax-primary rounded-lg shadow-md p-6">
                <h2 className="text-xl font-semibold mb-4">Cluster Information</h2>
                <div className="space-y-2">
                    <p className="text-gray-400">
                        Your K3s cluster is managed by Tharnax. Use the Applications page to install
                        additional components.
                    </p>
                </div>
            </div>
        </div>
    );
};

export default Dashboard; 
