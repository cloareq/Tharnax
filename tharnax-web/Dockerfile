# Stage 1: Build the React frontend
FROM node:18-alpine AS frontend-build

WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm install

# Copy the frontend source code and build it
COPY frontend/ ./
RUN npm run build

# Stage 2: Set up the combined image with Python backend and Nginx
FROM python:3.11-slim

# Install Nginx and supervisor
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Set up the backend
WORKDIR /app/backend
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the backend code
COPY backend/ .

# Copy the built frontend from the first stage
COPY --from=frontend-build /app/frontend/build /var/www/html

# Configure Nginx to serve the frontend and proxy API requests
RUN rm /etc/nginx/sites-enabled/default
COPY docker/nginx.conf /etc/nginx/sites-available/tharnax
RUN ln -s /etc/nginx/sites-available/tharnax /etc/nginx/sites-enabled/

# Set up supervisor to run both services
COPY docker/supervisord.conf /etc/supervisor/conf.d/tharnax.conf

# Expose the web port
EXPOSE 80

# Start supervisor (which will start both nginx and the backend)
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"] 
