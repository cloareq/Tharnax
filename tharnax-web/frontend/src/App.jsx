import React from 'react';
import { Routes, Route } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import AppCatalog from './pages/AppCatalog';
import Navigation from './components/Navigation';

function App() {
    return (
        <div className="min-h-screen bg-tharnax-secondary">
            <Navigation />
            <main className="container mx-auto px-4 py-6">
                <Routes>
                    <Route path="/" element={<Dashboard />} />
                    <Route path="/apps" element={<AppCatalog />} />
                </Routes>
            </main>
        </div>
    );
}

export default App; 
