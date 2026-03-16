FROM python:3.11-slim

# Prevent Python from writing .pyc files and buffer stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Create a non-root user to run the application securely
RUN addgroup --system appgroup && adduser --system --group appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files and set ownership to the non-root user
COPY --chown=appuser:appgroup . .

# Switch to the non-root user
USER appuser

# Expose port 8501 for Streamlit
EXPOSE 8501

ENTRYPOINT ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
