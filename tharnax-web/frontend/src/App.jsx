import React from 'react';
import Dashboard from './pages/Dashboard';
import AppCatalog from './pages/AppCatalog';
import Header from './components/Header';

function App() {
    return (
        <div className="min-h-screen bg-gray-900 text-white">
            <Header />
            <main className="container mx-auto p-4">
                <Dashboard />
                <div className="mt-8">
                    <AppCatalog />
                </div>
            </main>
        </div>
    );
}

export default App; 
