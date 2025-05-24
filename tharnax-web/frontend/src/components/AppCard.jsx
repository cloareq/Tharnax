import React, { useState } from 'react';
import {
    ArrowRightIcon,
    CheckCircleIcon,
    XCircleIcon,
    ClockIcon
} from '@heroicons/react/24/outline';
import { apiClient } from '../services/api';

const ExternalLinkIcon = ({ className }) => (
    <svg
        className={className}
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
        />
    </svg>
);

const AppCard = ({ app = {} }) => {
    const {
        id = 'unknown',
        name = 'Unknown App',
        description = 'No description available',
        category = 'misc',
        installed = false,
        url = null,
        urls = null
    } = app;

    const [installing, setInstalling] = useState(false);
    const [status, setStatus] = useState(installed ? 'installed' : 'notInstalled');
    const [progress, setProgress] = useState(0);
    const [installMessage, setInstallMessage] = useState('');

    const handleInstall = async () => {
        // Prevent multiple installation attempts
        if (installing || status === 'installed') {
            return;
        }

        try {
            setInstalling(true);
            setStatus('installing');
            setProgress(0);
            setInstallMessage('Starting installation...');

            const response = await apiClient.post(`/install/${id}`);

            if (response.data.status === 'already_installing') {
                setInstallMessage('Installation already in progress');
                // Start polling for existing installation
                startPolling();
                return;
            }

            // Start polling for installation status
            startPolling();

        } catch (error) {
            setStatus('error');
            setInstalling(false);
            setInstallMessage('Failed to start installation');
            console.error(`Error installing ${id}:`, error);
        }
    };

    const startPolling = () => {
        const pollInterval = 3000; // 3 seconds
        const maxAttempts = 300; // 15 minutes total (300 * 3 seconds)
        let attempts = 0;

        const pollStatus = async () => {
            try {
                const response = await apiClient.get(`/install/${id}/status`);
                const statusData = response.data;

                setProgress(statusData.progress || 0);
                setInstallMessage(statusData.message || 'Installing...');

                if (statusData.status === 'completed' || statusData.status === 'installed') {
                    setStatus('installed');
                    setInstalling(false);
                    setProgress(100);
                    setInstallMessage('Installation completed');
                    // Refresh the page to get updated URLs
                    setTimeout(() => {
                        window.location.reload();
                    }, 1000);
                    return;
                } else if (statusData.status === 'error') {
                    setStatus('error');
                    setInstalling(false);
                    setInstallMessage(statusData.message || 'Installation failed');
                    return;
                } else if (statusData.status === 'installing') {
                    setStatus('installing');
                    setInstalling(true);
                }

                attempts++;
                if (attempts < maxAttempts) {
                    setTimeout(pollStatus, pollInterval);
                } else {
                    // Timeout - check one more time if it's actually installed
                    const appsResponse = await apiClient.get('/apps');
                    const updatedApp = appsResponse.data.find(a => a.id === id);

                    if (updatedApp && updatedApp.installed) {
                        setStatus('installed');
                        setInstalling(false);
                        setProgress(100);
                        window.location.reload();
                    } else {
                        setStatus('error');
                        setInstalling(false);
                        setInstallMessage('Installation timed out');
                    }
                }
            } catch (error) {
                console.error('Error polling status:', error);
                attempts++;
                if (attempts < maxAttempts) {
                    setTimeout(pollStatus, pollInterval);
                } else {
                    setStatus('error');
                    setInstalling(false);
                    setInstallMessage('Status check failed');
                }
            }
        };

        // Start polling immediately
        pollStatus();
    };

    const handleUrlClick = (targetUrl) => {
        window.open(targetUrl, '_blank', 'noopener,noreferrer');
    };

    const getStatusIcon = () => {
        switch (status) {
            case 'installed':
                return <CheckCircleIcon className="h-6 w-6 text-green-500" />;
            case 'notInstalled':
                return <XCircleIcon className="h-6 w-6 text-gray-400" />;
            case 'installing':
                return <ClockIcon className="h-6 w-6 text-yellow-500 animate-pulse" />;
            case 'error':
                return <XCircleIcon className="h-6 w-6 text-red-500" />;
            default:
                return null;
        }
    };

    const hasUrls = urls && Object.keys(urls).length > 0;
    const hasUrl = url && !hasUrls;
    const isInstalled = status === 'installed' || installed;

    return (
        <div className="bg-tharnax-primary rounded-lg shadow-md p-5">
            <div className="flex justify-between items-start">
                <div className="flex-1">
                    <div className="flex items-center">
                        <h3 className="text-lg font-medium text-tharnax-text">
                            {name}
                        </h3>
                        <div className="ml-2">{getStatusIcon()}</div>
                    </div>
                    <p className="mt-1 text-sm text-gray-400">{description}</p>
                    <div className="mt-2 inline-block px-2 py-1 text-xs font-medium rounded-full bg-gray-700">
                        {category}
                    </div>

                    {/* Installation progress */}
                    {installing && (
                        <div className="mt-3">
                            <div className="text-xs text-gray-400 mb-1">{installMessage}</div>
                            <div className="w-full bg-gray-700 rounded-full h-2">
                                <div
                                    className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                                    style={{ width: `${progress}%` }}
                                ></div>
                            </div>
                            <div className="text-xs text-gray-400 mt-1">{progress}%</div>
                        </div>
                    )}

                    {/* Multiple URL buttons for monitoring stack */}
                    {isInstalled && hasUrls && (
                        <div className="mt-3 flex flex-wrap gap-2">
                            {Object.entries(urls).map(([serviceName, serviceUrl]) => (
                                <button
                                    key={serviceName}
                                    onClick={() => handleUrlClick(serviceUrl)}
                                    className="flex items-center px-3 py-1 text-xs font-medium bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
                                >
                                    <span className="capitalize">{serviceName}</span>
                                    <ExternalLinkIcon className="ml-1 h-3 w-3" />
                                </button>
                            ))}
                        </div>
                    )}

                    {/* Single URL button for other apps */}
                    {isInstalled && hasUrl && (
                        <div className="mt-3">
                            <button
                                onClick={() => handleUrlClick(url)}
                                className="flex items-center px-3 py-1 text-xs font-medium bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
                            >
                                Open
                                <ExternalLinkIcon className="ml-1 h-3 w-3" />
                            </button>
                        </div>
                    )}
                </div>

                <button
                    onClick={handleInstall}
                    disabled={installing || status === 'installed'}
                    className={`flex items-center px-3 py-2 rounded-md text-sm font-medium ${status === 'installed'
                        ? 'bg-gray-700 text-gray-400 cursor-not-allowed'
                        : installing
                            ? 'bg-yellow-600 text-white cursor-wait'
                            : 'bg-tharnax-accent text-white hover:bg-blue-700'
                        }`}
                >
                    {status === 'installed' ? 'Installed' : installing ? 'Installing...' : 'Install'}
                    {!installing && status !== 'installed' && (
                        <ArrowRightIcon className="ml-1 h-4 w-4" />
                    )}
                </button>
            </div>
        </div>
    );
};

export default AppCard; 
