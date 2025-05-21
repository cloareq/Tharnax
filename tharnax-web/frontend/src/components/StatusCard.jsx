import React from 'react';

const StatusCard = ({ title, value, icon: Icon, color = 'blue' }) => {
    const bgColorMap = {
        blue: 'bg-blue-500',
        green: 'bg-green-500',
        yellow: 'bg-yellow-500',
        red: 'bg-red-500',
        purple: 'bg-purple-500',
    };

    const iconBgColor = bgColorMap[color] || bgColorMap.blue;

    return (
        <div className="bg-tharnax-primary rounded-lg shadow-md overflow-hidden">
            <div className="p-5">
                <div className="flex items-center">
                    <div className={`p-3 rounded-full ${iconBgColor} mr-4`}>
                        <Icon className="h-6 w-6 text-white" />
                    </div>
                    <div>
                        <p className="text-sm font-medium text-gray-400">{title}</p>
                        <p className="text-2xl font-semibold text-tharnax-text">{value}</p>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default StatusCard; 
