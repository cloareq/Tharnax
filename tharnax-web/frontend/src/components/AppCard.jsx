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
    const [uninstalling, setUninstalling] = useState(false);
    const [restarting, setRestarting] = useState(false);
    const [status, setStatus] = useState(installed ? 'installed' : 'notInstalled');
    const [progress, setProgress] = useState(0);
    const [installMessage, setInstallMessage] = useState('');

    // Check if this component can be uninstalled (exclude ArgoCD)
    const canUninstall = id !== 'argocd';

    const handleInstall = async () => {
        // Prevent multiple installation attempts
        if (installing || status === 'installed') {
            return;
        }

        try {
            setInstalling(true);
            setStatus('installing');
            setProgress(5);
            setInstallMessage('Starting installation...');

            console.log(`[${id}] Starting installation...`);

            const response = await apiClient.post(`/install/${id}`);

            console.log(`[${id}] Installation response:`, response.data);

            if (response.data.status === 'already_installing') {
                setInstallMessage('Installation already in progress');
                setProgress(10);
                // Start polling for existing installation
                startPolling();
                return;
            } else if (response.data.status === 'started') {
                setProgress(15);
                setInstallMessage('Installation initiated successfully');
                // Start polling for installation status
                startPolling();
                return;
            } else if (response.data.status === 'error') {
                setStatus('error');
                setInstalling(false);
                setProgress(0);
                setInstallMessage(response.data.message || 'Failed to start installation');
                console.error(`[${id}] Installation start error:`, response.data);
                return;
            }

            // Default case - start polling anyway
            setProgress(10);
            setInstallMessage('Installation request submitted');
            startPolling();

        } catch (error) {
            console.error(`[${id}] Error starting installation:`, error);
            setStatus('error');
            setInstalling(false);
            setProgress(0);

            // Provide more specific error messages
            if (error.response) {
                if (error.response.status === 404) {
                    setInstallMessage('Installation service not available');
                } else if (error.response.status >= 500) {
                    setInstallMessage('Server error - please try again later');
                } else {
                    setInstallMessage(error.response.data?.message || 'Failed to start installation');
                }
            } else if (error.request) {
                setInstallMessage('Cannot connect to installation service');
            } else {
                setInstallMessage('Failed to start installation');
            }
        }
    };

    const handleUninstall = async () => {
        // Prevent multiple operations
        if (installing || uninstalling || restarting || status === 'notInstalled') {
            return;
        }

        try {
            setUninstalling(true);
            setStatus('uninstalling');
            setProgress(5);
            setInstallMessage('Starting uninstallation...');

            console.log(`[${id}] Starting uninstallation...`);

            const response = await apiClient.delete(`/install/${id}`);

            console.log(`[${id}] Uninstallation response:`, response.data);

            if (response.data.status === 'already_processing') {
                setInstallMessage('Already being processed');
                setProgress(10);
                startPolling();
                return;
            } else if (response.data.status === 'started') {
                setProgress(15);
                setInstallMessage('Uninstallation initiated successfully');
                startPolling();
                return;
            } else if (response.data.status === 'error') {
                setStatus('error');
                setUninstalling(false);
                setProgress(0);
                setInstallMessage(response.data.message || 'Failed to start uninstallation');
                console.error(`[${id}] Uninstallation start error:`, response.data);
                return;
            }

            // Default case - start polling anyway
            setProgress(10);
            setInstallMessage('Uninstallation request submitted');
            startPolling();

        } catch (error) {
            console.error(`[${id}] Error starting uninstallation:`, error);
            setStatus('error');
            setUninstalling(false);
            setProgress(0);

            if (error.response) {
                if (error.response.status === 403) {
                    setInstallMessage('Cannot uninstall protected component');
                } else if (error.response.status === 404) {
                    setInstallMessage('Uninstallation service not available');
                } else if (error.response.status >= 500) {
                    setInstallMessage('Server error - please try again later');
                } else {
                    setInstallMessage(error.response.data?.message || 'Failed to start uninstallation');
                }
            } else {
                setInstallMessage('Failed to start uninstallation');
            }
        }
    };

    const handleRestart = async () => {
        // Prevent multiple operations and ensure app is installed
        if (installing || uninstalling || restarting || !isInstalled) {
            return;
        }

        try {
            setRestarting(true);
            setStatus('restarting');
            setProgress(5);
            setInstallMessage('Starting rollout restart...');

            console.log(`[${id}] Starting rollout restart...`);

            const response = await apiClient.post(`/install/${id}/restart`);

            console.log(`[${id}] Restart response:`, response.data);

            if (response.data.status === 'already_processing') {
                setInstallMessage('Already being processed');
                setProgress(10);
                startPolling();
                return;
            } else if (response.data.status === 'started') {
                setProgress(20);
                setInstallMessage('Rollout restart initiated successfully');
                startPolling();
                return;
            } else if (response.data.status === 'error') {
                setStatus('error');
                setRestarting(false);
                setProgress(0);
                setInstallMessage(response.data.message || 'Failed to start restart');
                console.error(`[${id}] Restart start error:`, response.data);
                return;
            }

            // Default case - start polling anyway
            setProgress(10);
            setInstallMessage('Rollout restart request submitted');
            startPolling();

        } catch (error) {
            console.error(`[${id}] Error starting restart:`, error);
            setStatus('error');
            setRestarting(false);
            setProgress(0);

            if (error.response) {
                if (error.response.status === 400) {
                    setInstallMessage('App must be installed to restart');
                } else if (error.response.status === 403) {
                    setInstallMessage('Cannot restart protected component');
                } else if (error.response.status === 404) {
                    setInstallMessage('Restart service not available');
                } else if (error.response.status >= 500) {
                    setInstallMessage('Server error - please try again later');
                } else {
                    setInstallMessage(error.response.data?.message || 'Failed to start restart');
                }
            } else {
                setInstallMessage('Failed to start restart');
            }
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

                console.log(`[${id}] Status polling response:`, statusData); // Debug logging

                setProgress(statusData.progress || 0);
                setInstallMessage(statusData.message || 'Installing...');

                // Handle different status values from the new ArgoCD integration
                if (statusData.status === 'completed' || statusData.status === 'installed') {
                    setStatus('installed');
                    setInstalling(false);
                    setUninstalling(false);
                    setRestarting(false);
                    setProgress(100);
                    setInstallMessage('Installation completed');
                    // Refresh the page to get updated URLs
                    setTimeout(() => {
                        window.location.reload();
                    }, 1000);
                    return;
                } else if (statusData.status === 'not_installed') {
                    setStatus('notInstalled');
                    setInstalling(false);
                    setUninstalling(false);
                    setRestarting(false);
                    setProgress(100);
                    setInstallMessage('Uninstallation completed');
                    // Refresh the page to get updated state
                    setTimeout(() => {
                        window.location.reload();
                    }, 1000);
                    return;
                } else if (statusData.status === 'error') {
                    setStatus('error');
                    setInstalling(false);
                    setUninstalling(false);
                    setRestarting(false);
                    setInstallMessage(statusData.message || 'Operation failed');
                    console.error(`[${id}] Operation error:`, statusData);
                    return;
                } else if (statusData.status === 'installing' || statusData.status === 'not_found') {
                    // Keep polling for 'installing' status or if ArgoCD app not found yet
                    setStatus('installing');
                    setInstalling(true);
                    setUninstalling(false);
                    setRestarting(false);
                    // For monitoring, show more detailed status if available
                    if (id === 'monitoring' && statusData.argocd_health && statusData.argocd_sync) {
                        setInstallMessage(`${statusData.message} (Health: ${statusData.argocd_health}, Sync: ${statusData.argocd_sync})`);
                    }
                } else if (statusData.status === 'uninstalling') {
                    setStatus('uninstalling');
                    setInstalling(false);
                    setUninstalling(true);
                    setRestarting(false);
                } else if (statusData.status === 'restarting') {
                    setStatus('restarting');
                    setInstalling(false);
                    setUninstalling(false);
                    setRestarting(true);
                } else {
                    // For unknown statuses, try to infer the operation state
                    if (uninstalling) {
                        setStatus('uninstalling');
                    } else if (restarting) {
                        setStatus('restarting');
                    } else {
                        setStatus('installing');
                        setInstalling(true);
                    }
                }

                attempts++;
                if (attempts < maxAttempts) {
                    setTimeout(pollStatus, pollInterval);
                } else {
                    // Timeout - check one more time if it's actually installed
                    try {
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
                            setInstallMessage('Installation timed out - check ArgoCD for details');
                        }
                    } catch (finalCheckError) {
                        console.error(`[${id}] Final check error:`, finalCheckError);
                        setStatus('error');
                        setInstalling(false);
                        setInstallMessage('Installation status unknown');
                    }
                }
            } catch (error) {
                console.error(`[${id}] Error polling status:`, error);

                // More sophisticated error handling
                if (error.response && error.response.status === 404) {
                    // Component not found, keep trying for a bit
                    if (attempts < 10) {
                        setInstallMessage('Waiting for installation service...');
                        attempts++;
                        setTimeout(pollStatus, pollInterval);
                        return;
                    }
                }

                // For other errors, be more lenient in the beginning
                if (attempts < 5) {
                    setInstallMessage('Connecting to installation service...');
                    attempts++;
                    setTimeout(pollStatus, pollInterval);
                } else {
                    setStatus('error');
                    setInstalling(false);
                    setInstallMessage(`Status check failed: ${error.message || 'Unknown error'}`);
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
            case 'uninstalling':
                return <ClockIcon className="h-6 w-6 text-orange-500 animate-pulse" />;
            case 'restarting':
                return <ClockIcon className="h-6 w-6 text-blue-500 animate-pulse" />;
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
                    {(installing || uninstalling || restarting) && (
                        <div className="mt-3">
                            <div className="text-xs text-gray-400 mb-1">{installMessage}</div>
                            <div className="w-full bg-gray-700 rounded-full h-2">
                                <div
                                    className={`h-2 rounded-full transition-all duration-300 ${restarting ? 'bg-blue-600' :
                                        uninstalling ? 'bg-orange-600' :
                                            'bg-blue-600'
                                        }`}
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

                <div className="flex flex-col gap-2">
                    {/* Install Button */}
                    <button
                        onClick={handleInstall}
                        disabled={installing || uninstalling || restarting || status === 'installed'}
                        className={`flex items-center px-3 py-2 rounded-md text-sm font-medium ${status === 'installed'
                            ? 'bg-gray-700 text-gray-400 cursor-not-allowed'
                            : installing || uninstalling || restarting
                                ? 'bg-yellow-600 text-white cursor-wait'
                                : 'bg-tharnax-accent text-white hover:bg-blue-700'
                            }`}
                    >
                        {status === 'installed' ? 'Installed' :
                            installing ? 'Installing...' :
                                uninstalling ? 'Processing...' :
                                    restarting ? 'Processing...' : 'Install'}
                        {!installing && !uninstalling && !restarting && status !== 'installed' && (
                            <ArrowRightIcon className="ml-1 h-4 w-4" />
                        )}
                    </button>

                    {/* Uninstall Button - only show if installed and can be uninstalled */}
                    {isInstalled && canUninstall && (
                        <button
                            onClick={handleUninstall}
                            disabled={installing || uninstalling || restarting}
                            className={`flex items-center px-3 py-2 rounded-md text-sm font-medium ${installing || uninstalling || restarting
                                ? 'bg-gray-600 text-gray-400 cursor-wait'
                                : 'bg-red-600 text-white hover:bg-red-700'
                                }`}
                        >
                            {uninstalling ? 'Uninstalling...' : 'Uninstall'}
                        </button>
                    )}

                    {/* Restart Button - only show if installed and can be uninstalled */}
                    {isInstalled && canUninstall && (
                        <button
                            onClick={handleRestart}
                            disabled={installing || uninstalling || restarting}
                            className={`flex items-center px-3 py-2 rounded-md text-sm font-medium ${installing || uninstalling || restarting
                                ? 'bg-gray-600 text-gray-400 cursor-wait'
                                : 'bg-orange-600 text-white hover:bg-orange-700'
                                }`}
                        >
                            {restarting ? 'Restarting...' : 'Restart'}
                        </button>
                    )}
                </div>
            </div>
        </div>
    );
};

export default AppCard; 
