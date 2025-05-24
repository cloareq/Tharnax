import React, { useState } from 'react';
import {
    ArrowRightIcon,
    CheckCircleIcon,
    XCircleIcon,
    ClockIcon,
    ExternalLinkIcon
} from '@heroicons/react/24/outline';
import { apiClient } from '../services/api';

const AppCard = ({ app = {} }) => {
    const {
        id = 'unknown',
        name = 'Unknown App',
        description = 'No description available',
        category = 'misc',
        installed = false,
        url = null
    } = app;

    const [installing, setInstalling] = useState(false);
    const [status, setStatus] = useState(installed ? 'installed' : 'notInstalled');

    const handleInstall = async () => {
        try {
            setInstalling(true);
            setStatus('installing');

            await apiClient.post(`/install/${id}`);

            // In a real app, we would poll for status until complete
            // For now, simulate a successful installation after 3 seconds
            setTimeout(() => {
                setStatus('installed');
                setInstalling(false);
            }, 3000);
        } catch (error) {
            setStatus('error');
            setInstalling(false);
            console.error(`Error installing ${id}:`, error);
        }
    };

    const handleAppClick = () => {
        if (url && (status === 'installed' || installed)) {
            window.open(url, '_blank', 'noopener,noreferrer');
        }
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

    const isClickable = url && (status === 'installed' || installed);

    return (
        <div className="bg-tharnax-primary rounded-lg shadow-md p-5">
            <div className="flex justify-between items-start">
                <div
                    className={`flex-1 ${isClickable ? 'cursor-pointer' : ''}`}
                    onClick={isClickable ? handleAppClick : undefined}
                >
                    <div className="flex items-center">
                        <h3 className={`text-lg font-medium text-tharnax-text ${isClickable ? 'hover:text-blue-400' : ''}`}>
                            {name}
                        </h3>
                        <div className="ml-2">{getStatusIcon()}</div>
                        {isClickable && (
                            <ExternalLinkIcon className="ml-2 h-4 w-4 text-gray-400" />
                        )}
                    </div>
                    <p className="mt-1 text-sm text-gray-400">{description}</p>
                    <div className="mt-2 inline-block px-2 py-1 text-xs font-medium rounded-full bg-gray-700">
                        {category}
                    </div>
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
