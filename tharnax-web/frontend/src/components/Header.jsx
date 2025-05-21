import React from 'react';

const Header = () => {
    return (
        <header className="bg-gray-800 border-b border-gray-700 shadow-lg">
            <div className="container mx-auto px-4 py-4 flex items-center justify-between">
                <div className="flex items-center">
                    <svg
                        className="h-8 w-8 text-blue-500 mr-3"
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                    >
                        <path d="M5 12h14"></path>
                        <path d="M12 5v14"></path>
                        <path d="M5 5l14 14"></path>
                    </svg>
                    <h1 className="text-2xl font-bold text-white">Tharnax Web UI</h1>
                </div>
                <div className="text-gray-300 text-sm">
                    Homelab Infrastructure Management
                </div>
            </div>
        </header>
    );
};

export default Header; 
