# Use the official image as a parent image.
FROM index.docker.io/library/python:3-slim AS base

# We copy just the requirements.txt first to leverage Docker cache
COPY ./src/requirements.txt /app/requirements.txt

WORKDIR /app

RUN pip3 install -r requirements.txt

COPY ./src/ /app

EXPOSE 5000

# Development Stage
FROM base AS DEV

CMD [ "python", "-B", "-m", "flask", "--app", "app", "--debug", "run", "--host=0.0.0.0" ]


# Production Stage
FROM base AS PRD

RUN pip3 install --no-cache-dir gunicorn

CMD ["gunicorn", "--log-level", "info", "--access-logfile", "-", "-b", "0.0.0.0:80", "app:app"]