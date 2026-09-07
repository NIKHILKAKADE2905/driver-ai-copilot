FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

COPY pyproject.toml ./
COPY server.py ai_voice_copilot.py route_planner.py schemas.py ./

RUN pip install --no-cache-dir \
    "fastapi[standard]>=0.115.0" \
    "langchain>=1.0.0" \
    "langchain-groq>=1.0.0" \
    "langgraph>=0.2.0" \
    "pydantic>=2.0.0" \
    "python-dotenv>=1.0.0" \
    "python-multipart>=0.0.9" \
    "requests>=2.32.0" \
    "speechrecognition>=3.10.0" \
    "uvicorn>=0.32.0"

EXPOSE 8000

CMD ["sh", "-c", "uvicorn server:app --host 0.0.0.0 --port ${PORT}"]
