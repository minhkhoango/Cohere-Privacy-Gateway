# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install poetry
RUN pip install poetry

# Copy only the files poetry needs to install dependencies
COPY poetry.lock pyproject.toml ./

# Install dependencies without installing the project itself
RUN poetry config virtualenvs.create false && poetry install --no-root

# Copy the application source code
COPY . .

# Expose the port the app runs on
EXPOSE 80

# Command to run the application using uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]