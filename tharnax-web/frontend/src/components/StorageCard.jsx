import React from 'react';

const StorageIcon = (props) => (
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
        <ellipse cx="12" cy="5" rx="9" ry="3"></ellipse>
        <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"></path>
        <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"></path>
    </svg>
);

const StorageCard = ({ nfsStorage }) => {
    if (!nfsStorage) {
        return (
            <div className="bg-gray-800 rounded-lg shadow-md overflow-hidden">
                <div className="p-5">
                    <div className="flex items-center">
                        <div className="p-3 rounded-full bg-gray-600 mr-4">
                            <StorageIcon className="h-6 w-6 text-gray-400" />
                        </div>
                        <div>
                            <p className="text-sm font-medium text-gray-400">NFS Storage</p>
                            <p className="text-lg font-semibold text-gray-500">Not Available</p>
                        </div>
                    </div>
                </div>
            </div>
        );
    }

    const { total_gb, used_gb, free_gb, usage_percent, path } = nfsStorage;

    const getUsageColor = (percent) => {
        if (percent >= 90) return 'text-red-400';
        if (percent >= 75) return 'text-yellow-400';
        return 'text-green-400';
    };

    const getBarColor = (percent) => {
        if (percent >= 90) return 'bg-red-500';
        if (percent >= 75) return 'bg-yellow-500';
        return 'bg-green-500';
    };

    return (
        <div className="bg-gray-800 rounded-lg shadow-md overflow-hidden">
            <div className="p-5">
                <div className="flex items-start">
                    <div className="p-3 rounded-full bg-blue-500 mr-4 flex-shrink-0">
                        <StorageIcon className="h-6 w-6 text-white" />
                    </div>
                    <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-gray-400">NFS Storage</p>
                        <p className="text-lg font-semibold text-white truncate" title={path}>
                            {path}
                        </p>

                        <div className="mt-2">
                            <div className="flex justify-between text-xs text-gray-400 mb-1">
                                <span>{used_gb} GB used</span>
                                <span>{free_gb} GB free</span>
                            </div>
                            <div className="w-full bg-gray-700 rounded-full h-2">
                                <div
                                    className={`h-2 rounded-full ${getBarColor(usage_percent)}`}
                                    style={{ width: `${usage_percent}%` }}
                                ></div>
                            </div>
                            <div className="flex justify-between text-xs mt-1">
                                <span className="text-gray-400">{total_gb} GB total</span>
                                <span className={`font-medium ${getUsageColor(usage_percent)}`}>
                                    {usage_percent}% used
                                </span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default StorageCard; 
