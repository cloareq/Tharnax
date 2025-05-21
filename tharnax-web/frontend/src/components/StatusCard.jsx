import React from 'react';

const StatusCard = ({ title, value, icon: Icon }) => {
    return (
        <div className="bg-gray-800 rounded-lg shadow-md overflow-hidden">
            <div className="p-5">
                <div className="flex items-center">
                    {Icon && (
                        <div className="p-3 rounded-full bg-blue-500 mr-4">
                            <Icon className="h-6 w-6 text-white" />
                        </div>
                    )}
                    <div>
                        <p className="text-sm font-medium text-gray-400">{title}</p>
                        <p className="text-2xl font-semibold text-white">{value || '-'}</p>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default StatusCard; 
