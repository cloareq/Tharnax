import React, { useState, useEffect } from 'react';
import AppCard from '../components/AppCard';
import { apiClient } from '../services/api';

const AppCatalog = () => {
    const [apps, setApps] = useState([]);
    const [categories, setCategories] = useState([]);
    const [selectedCategory, setSelectedCategory] = useState('all');
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchApps = async () => {
            try {
                setLoading(true);
                const response = await apiClient.get('/apps');

                // Make sure data is an array
                const appsData = Array.isArray(response.data) ? response.data : [];
                setApps(appsData);

                // Extract unique categories safely
                const uniqueCategories = Array.isArray(appsData) && appsData.length > 0
                    ? [...new Set(appsData.map(app => app.category))]
                    : [];
                setCategories(uniqueCategories);

                setError(null);
            } catch (err) {
                console.error('Error fetching applications:', err);
                setError('Failed to fetch available applications. Backend might be unavailable.');

                // Set empty arrays as fallback
                setApps([]);
                setCategories([]);
            } finally {
                setLoading(false);
            }
        };

        fetchApps();
    }, []);

    // Mock data for development
    const mockApps = [
        {
            id: "prometheus",
            name: "Prometheus",
            description: "Monitoring and alerting toolkit",
            category: "monitoring",
            icon: "monitoring",
            installed: false
        },
        {
            id: "grafana",
            name: "Grafana",
            description: "Metrics visualization and dashboards",
            category: "monitoring",
            icon: "dashboard",
            installed: false
        }
    ];

    // Use mock data if no apps are available and we're in development
    const displayApps = apps.length > 0 ? apps : (
        process.env.NODE_ENV === 'development' ? mockApps : []
    );

    const filteredApps = selectedCategory === 'all'
        ? displayApps
        : displayApps.filter(app => app.category === selectedCategory);

    return (
        <div>
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-tharnax-text">Application Catalog</h1>
                <p className="text-gray-400">Install and manage applications for your cluster</p>
            </div>

            {error && (
                <div className="mb-6 p-4 bg-red-900/30 border border-red-700 rounded-md text-red-300">
                    <p className="font-bold mb-2">Error</p>
                    <p>{error}</p>
                </div>
            )}

            {/* Category filters */}
            <div className="mb-6 flex flex-wrap gap-2">
                <button
                    onClick={() => setSelectedCategory('all')}
                    className={`px-4 py-2 rounded-full text-sm font-medium ${selectedCategory === 'all'
                        ? 'bg-tharnax-accent text-white'
                        : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                        }`}
                >
                    All
                </button>

                {categories.map(category => (
                    <button
                        key={category}
                        onClick={() => setSelectedCategory(category)}
                        className={`px-4 py-2 rounded-full text-sm font-medium ${selectedCategory === category
                            ? 'bg-tharnax-accent text-white'
                            : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                            }`}
                    >
                        {category.charAt(0).toUpperCase() + category.slice(1)}
                    </button>
                ))}
            </div>

            {loading ? (
                <div className="text-center py-12">
                    <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-tharnax-accent border-t-transparent"></div>
                    <p className="mt-3 text-gray-400">Loading applications...</p>
                </div>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    {filteredApps && filteredApps.length > 0 ? (
                        filteredApps.map(app => (
                            <AppCard key={app.id} app={app} />
                        ))
                    ) : (
                        <div className="text-center py-12 col-span-2 bg-tharnax-primary rounded-lg">
                            <p className="text-gray-400">No applications found in this category</p>
                        </div>
                    )}
                </div>
            )}
        </div>
    );
};

export default AppCatalog; 
