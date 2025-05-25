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

    // Group apps by installation status
    const installedApps = filteredApps.filter(app => app.installed);
    const availableApps = filteredApps.filter(app => !app.installed);

    // Get category counts for display
    const getCategoryCounts = (category) => {
        const categoryApps = category === 'all'
            ? apps
            : apps.filter(app => app.category === category);
        const installed = categoryApps.filter(app => app.installed).length;
        const total = categoryApps.length;
        return { installed, available: total - installed, total };
    };

    return (
        <div>
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-tharnax-text">Application Catalog</h1>
                <p className="text-gray-400">Install and manage applications for your cluster</p>

                {/* Summary Stats */}
                <div className="mt-4 flex gap-4 text-sm">
                    <div className="flex items-center">
                        <div className="w-2 h-2 bg-green-500 rounded-full mr-2"></div>
                        <span className="text-green-400">{apps.filter(app => app.installed).length} Installed</span>
                    </div>
                    <div className="flex items-center">
                        <div className="w-2 h-2 bg-gray-500 rounded-full mr-2"></div>
                        <span className="text-gray-400">{apps.filter(app => !app.installed).length} Available</span>
                    </div>
                </div>
            </div>

            {error && (
                <div className="mb-6 p-4 bg-red-900/30 border border-red-700 rounded-md text-red-300">
                    <p className="font-bold mb-2">Error</p>
                    <p>{error}</p>
                </div>
            )}

            {/* Category filters */}
            <div className="mb-6 flex flex-wrap gap-2">
                {filterOptions.map(category => {
                    const counts = getCategoryCounts(category);
                    return (
                        <button
                            key={category}
                            onClick={() => setSelectedCategory(category)}
                            className={`px-4 py-2 rounded-full text-sm font-medium flex items-center gap-2 ${selectedCategory === category
                                ? 'bg-tharnax-accent text-white'
                                : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                                }`}
                        >
                            <span>{category.charAt(0).toUpperCase() + category.slice(1)}</span>
                            <div className="flex items-center gap-1 text-xs">
                                {counts.installed > 0 && (
                                    <span className={`px-1.5 py-0.5 rounded-full ${selectedCategory === category
                                        ? 'bg-green-400 text-green-900'
                                        : 'bg-green-600 text-green-100'
                                        }`}>
                                        {counts.installed}
                                    </span>
                                )}
                                {counts.available > 0 && (
                                    <span className={`px-1.5 py-0.5 rounded-full ${selectedCategory === category
                                        ? 'bg-gray-300 text-gray-700'
                                        : 'bg-gray-600 text-gray-300'
                                        }`}>
                                        {counts.available}
                                    </span>
                                )}
                            </div>
                        </button>
                    );
                })}
            </div>

            {loading ? (
                <div className="text-center py-12">
                    <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-tharnax-accent border-t-transparent"></div>
                    <p className="mt-3 text-gray-400">Loading applications...</p>
                </div>
            ) : (
                <div className="space-y-8">
                    {/* Installed Applications Section */}
                    {installedApps.length > 0 && (
                        <div>
                            <div className="flex items-center mb-4">
                                <h2 className="text-xl font-semibold text-white flex items-center">
                                    <div className="w-3 h-3 bg-green-500 rounded-full mr-3 animate-pulse"></div>
                                    Installed Applications
                                </h2>
                                <div className="ml-3 px-2 py-1 bg-green-700 text-green-100 text-xs font-medium rounded-full">
                                    {installedApps.length} active
                                </div>
                            </div>
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                {installedApps.map(app => (
                                    <AppCard key={app.id} app={app} />
                                ))}
                            </div>
                        </div>
                    )}

                    {/* Available Applications Section */}
                    {availableApps.length > 0 && (
                        <div>
                            <div className="flex items-center mb-4">
                                <h2 className="text-xl font-semibold text-gray-300 flex items-center">
                                    <div className="w-3 h-3 bg-gray-500 rounded-full mr-3"></div>
                                    Available Applications
                                </h2>
                                <div className="ml-3 px-2 py-1 bg-gray-700 text-gray-300 text-xs font-medium rounded-full">
                                    {availableApps.length} available
                                </div>
                            </div>
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                {availableApps.map(app => (
                                    <AppCard key={app.id} app={app} />
                                ))}
                            </div>
                        </div>
                    )}

                    {/* No applications found */}
                    {filteredApps.length === 0 && (
                        <div className="text-center py-12 bg-tharnax-primary rounded-lg">
                            <p className="text-gray-400">No applications found in this category</p>
                        </div>
                    )}
                </div>
            )}
        </div>
    );
};

export default AppCatalog; 
