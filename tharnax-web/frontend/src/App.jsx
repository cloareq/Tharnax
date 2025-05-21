import React from 'react';
import { Routes, Route } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import AppCatalog from './pages/AppCatalog';
import Navigation from './components/Navigation';

function App() {
    return (
        <div className="min-h-screen bg-gray-900 text-white">
            <header className="p-4 bg-gray-800">
                <h1 className="text-2xl font-bold">Tharnax Web UI</h1>
            </header>
            <main className="container mx-auto p-4">
                <p>Tharnax Web UI is loading...</p>
            </main>
        </div>
    );
}

export default App; 
