import axios from 'axios';

// Create axios instance with base URL
const apiClient = axios.create({
    baseURL: '/api',
    headers: {
        'Content-Type': 'application/json',
    },
});

// Add response interceptor for error handling
apiClient.interceptors.response.use(
    response => response,
    error => {
        console.error('API Error:', error);
        return Promise.reject(error);
    }
);

// API endpoints
export const fetchClusterStatus = async () => {
    try {
        const response = await apiClient.get('/status');
        return response.data;
    } catch (error) {
        console.error('Error fetching cluster status:', error);
        throw error;
    }
};

export const fetchApps = async () => {
    try {
        const response = await apiClient.get('/apps');
        return response.data;
    } catch (error) {
        console.error('Error fetching apps:', error);
        throw error;
    }
};

export const installApp = async (appId, config = {}) => {
    try {
        const response = await apiClient.post(`/install/${appId}`, config);
        return response.data;
    } catch (error) {
        console.error(`Error installing ${appId}:`, error);
        throw error;
    }
};

export const getAppInstallStatus = async (appId) => {
    try {
        const response = await apiClient.get(`/install/${appId}/status`);
        return response.data;
    } catch (error) {
        console.error(`Error fetching install status for ${appId}:`, error);
        throw error;
    }
};

export default {
    fetchClusterStatus,
    fetchApps,
    installApp,
    getAppInstallStatus
}; 
