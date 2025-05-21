import React from 'react';
import { Routes, Route } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import AppCatalog from './pages/AppCatalog';
import Navigation from './components/Navigation';
import Header from './components/Header';

function App() {
    return (
        <div className="min-h-screen bg-gray-900 text-white">
            <Header />
            <div className="flex">
                <Navigation />
                <main className="container mx-auto p-4 flex-1">
                    <Routes>
                        <Route path="/" element={<Dashboard />} />
                        <Route path="/apps" element={<AppCatalog />} />
                    </Routes>
                </main>
            </div>
        </div>
    );
}

export default App; 
