import React, { useState, useEffect } from 'react';
import { fetchClusterStatus } from '../services/api';
import StatusCard from './StatusCard';
import StorageCard from './StorageCard';

const ServerIcon = (props) => (
    <svg
        {...props}
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
    >
        <rect x="2" y="2" width="20" height="8" rx="2" ry="2"></rect>
        <rect x="2" y="14" width="20" height="8" rx="2" ry="2"></rect>
        <line x1="6" y1="6" x2="6.01" y2="6"></line>
        <line x1="6" y1="18" x2="6.01" y2="18"></line>
    </svg>
);

const TagIcon = (props) => (
    <svg
        {...props}
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
    >
        <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"></path>
        <line x1="7" y1="7" x2="7.01" y2="7"></line>
    </svg>
);

const Dashboard = () => {
    const [clusterInfo, setClusterInfo] = useState({
        node_count: '-',
        k3s_version: '-',
        pod_count: '-',
        nfs_storage: null,
        status: 'loading'
    });
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchData = async () => {
            try {
                setLoading(true);
                const data = await fetchClusterStatus();
                setClusterInfo(data);
                setError(null);
            } catch (err) {
                setError('Failed to fetch cluster status. Please check if the API is running.');
                console.error(err);
            } finally {
                setLoading(false);
            }
        };

        fetchData();

        const intervalId = setInterval(fetchData, 30000);

        return () => clearInterval(intervalId);
    }, []);

    return (
        <div className="py-6">
            <h2 className="text-xl font-bold text-white mb-4">Cluster Dashboard</h2>

            {error && (
                <div className="mb-6 p-4 bg-red-900/30 border border-red-700 rounded-md text-red-300">
                    {error}
                </div>
            )}

            {loading && clusterInfo.status === 'loading' ? (
                <div className="flex justify-center items-center h-40">
                    <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
                </div>
            ) : (
                <div className="space-y-6">
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
                        <StatusCard
                            title="Nodes"
                            value={clusterInfo.node_count}
                            icon={ServerIcon}
                        />
                        <StatusCard
                            title="K3s Version"
                            value={clusterInfo.k3s_version}
                            icon={TagIcon}
                        />
                        <StatusCard
                            title="Pod Count"
                            value={clusterInfo.pod_count}
                            icon={ServerIcon}
                        />
                    </div>

                    {clusterInfo.nfs_storage && (
                        <div>
                            <h3 className="text-lg font-semibold text-white mb-3">Storage</h3>
                            <StorageCard nfsStorage={clusterInfo.nfs_storage} />
                        </div>
                    )}
                </div>
            )}
        </div>
    );
};

export default Dashboard; 
