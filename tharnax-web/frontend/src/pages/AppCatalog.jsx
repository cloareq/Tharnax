import React, { useState, useEffect } from 'react';
import AppCard from '../components/AppCard';
import { apiClient } from '../services/api';

const AppCatalog = () => {
    const [apps, setApps] = useState([]);
    const [categories, setCategories] = useState([]);
    const [selectedCategory, setSelectedCategory] = useState('all');
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [filterOptions, setFilterOptions] = useState(['all', 'management', 'monitoring']);

    const fetchApps = async () => {
        try {
            setLoading(true);
            const appsData = await apiClient.get('/apps');

            if (Array.isArray(appsData?.data)) {
                setApps(appsData.data);

                const categories = appsData.data
                    .map(app => app.category || 'misc')
                    .filter((category, index, array) => array.indexOf(category) === index);

                setFilterOptions(['all', ...categories]);
            } else {
                setApps([]);
                setFilterOptions(['all']);
            }
        } catch (error) {
            console.error('Error fetching apps:', error);
            setError('Failed to load applications catalog.');

            if (process.env.NODE_ENV === 'development') {
                const mockApps = [
                    {
                        id: 'portainer',
                        name: 'Portainer',
                        description: 'Container management UI',
                        category: 'management',
                        installed: false,
                        url: null
                    },
                    {
                        id: 'grafana',
                        name: 'Grafana',
                        description: 'Monitoring and observability platform',
                        category: 'monitoring',
                        installed: false,
                        url: null
                    }
                ];
                setApps(mockApps);
                setFilterOptions(['all', 'management', 'monitoring']);
            }
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchApps();
    }, []);

    const filteredApps = Array.isArray(apps) && apps.length > 0
        ? apps.filter(app => selectedCategory === 'all' || app.category === selectedCategory)
        : [];

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
                {filterOptions.map(category => (
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
