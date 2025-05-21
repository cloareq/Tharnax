import axios from 'axios';

// Determine the base URL based on environment
// In production, this will connect to the backend service
// In development, connect to a local backend
const getBaseUrl = () => {
    // When running in Kubernetes, we'll use the service name
    if (process.env.NODE_ENV === 'production') {
        return '/api';
    }

    // For local development
    return 'http://localhost:8000';
};

export const apiClient = axios.create({
    baseURL: getBaseUrl(),
    headers: {
        'Content-Type': 'application/json',
    },
});

// Add response interceptor for error handling
apiClient.interceptors.response.use(
    response => response,
    error => {
        // Log errors to console in development
        if (process.env.NODE_ENV !== 'production') {
            console.error('API Error:', error);
        }

        return Promise.reject(error);
    }
); 
