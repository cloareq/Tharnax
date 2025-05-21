/** @type {import('tailwindcss').Config} */
module.exports = {
    content: [
        "./src/**/*.{js,jsx,ts,tsx}",
        "./public/index.html",
    ],
    theme: {
        extend: {
            colors: {
                'tharnax-primary': '#1F2937',
                'tharnax-secondary': '#111827',
                'tharnax-accent': '#3B82F6',
                'tharnax-text': '#F9FAFB',
            },
        },
    },
    plugins: [],
    darkMode: 'class',
} 
