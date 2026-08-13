#!/bin/bash
set -e

if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

run_sudo() {
    if command -v sudo &> /dev/null; then
        sudo "$@"
    else
        "$@"
    fi
}

echo "===================================================="
echo "Checking and Installing Docker Dependencies..."
echo "===================================================="

if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."
    run_sudo apt update -y
    run_sudo apt upgrade -y
    run_sudo apt install -y curl git
    
    curl -fsSL https://get.docker.com -o get-docker.sh
    run_sudo sh get-docker.sh
    rm get-docker.sh

    if [ -n "$USER" ]; then
        run_sudo usermod -aG docker "$USER"
        echo "User added to the 'docker' group."
    fi
else
    echo "Docker is already installed."
fi

if ! docker compose version &> /dev/null; then
    echo "Docker Compose plugin missing. Installing..."
    run_sudo apt update -y
    run_sudo apt install -y docker-compose-plugin
else
    echo "Docker Compose is already installed."
fi

echo "===================================================="
echo "Checking Repositories (Skipping if they exist)..."
echo "===================================================="

if [ ! -d "saleor-platform" ] || [ -z "$(ls -A saleor-platform)" ]; then
    echo "Cloning saleor-platform..."
    git clone https://github.com/saleor/saleor-platform.git saleor-platform
else
    echo "saleor-platform already exists. Skipping clone."
fi

if [ ! -d "saleor" ] || [ -z "$(ls -A saleor)" ]; then
    echo "Cloning saleor (3.23.26)..."
    git clone --branch 3.23.26 https://github.com/saleor/saleor.git saleor
else
    echo "saleor already exists. Skipping clone."
fi

if [ ! -d "storefront" ] || [ -z "$(ls -A storefront)" ]; then
    echo "Cloning storefront..."
    git clone https://github.com/saleor/storefront.git storefront
else
    echo "storefront already exists. Skipping clone."
fi

echo "===================================================="
echo "Updating System Packages & Configuring Environment..."
echo "===================================================="

run_sudo apt update -y
run_sudo apt upgrade -y || true
run_sudo apt install -y git python3

cd storefront
if [ ! -f .env ]; then
    cp .env.example .env
fi

cd ..

cd saleor-platform
if [ -f docker-compose.yml ]; then
    rm docker-compose.yml
fi
cp ../docker-compose.yml docker-compose.yml

echo "===================================================="
echo "Starting Backend & Running Migrations..."
echo "===================================================="

docker compose build api db cache worker mailpit
docker compose run --rm api python manage.py migrate
docker compose down
docker compose up -d api db cache worker mailpit

echo "===================================================="
echo "Creating Superuser..."
echo "===================================================="

docker compose run --rm \
    -e DJANGO_SUPERUSER_EMAIL="${DJANGO_SUPERUSER_EMAIL:-admin@example.com}" \
    -e DJANGO_SUPERUSER_PASSWORD="${DJANGO_SUPERUSER_PASSWORD:?Set DJANGO_SUPERUSER_PASSWORD before running}" \
    api python manage.py createsuperuser --noinput --email "${DJANGO_SUPERUSER_EMAIL:-admin@example.com}" || echo "Superuser already exists or creation was skipped."
    
echo "===================================================="
echo "Building and Starting Storefront..."
echo "===================================================="

docker compose up -d storefront --build

echo "===================================================="
echo "Verifying Full Stack Starts Correctly..."
echo "===================================================="

docker compose up -d --build
docker compose ps

docker compose down
cd ..

echo -e "\033[32mSetup complete!\033[0m"