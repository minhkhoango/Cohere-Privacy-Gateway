# Cohere Privacy Gateway (FastAPI Demo)

This project is a FastAPI-based proof-of-concept for running Cohere models privately inside your infrastructure.

## ✅ Features
- Healthcheck route at `/health`
- Easy to containerize with Docker
- Secure: No public endpoints exposed unless explicitly configured

## 🚀 Running Locally

```bash
# Install dependencies
poetry install

# Run the app
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8080
```

## 🔒 Environment Variables

Create a `.env` file with:

```
COHERE_API_KEY=your-api-key
```

## 🐳 Docker Support

Make sure Dockerfile binds to port 8080 and uses this structure.

---
