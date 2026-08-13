git clone https://github.com/saleor/saleor-platform.git saleor-platform
git clone https://github.com/saleor/storefront.git storefront
git clone --branch 3.23.26 https://github.com/saleor/saleor.git saleor

cd storefront

if (!(Test-Path .env)) {
    cp .env.example .env
}
(Get-Content .env) -replace '^NEXT_PUBLIC_SALEOR_API_URL=.*', 'NEXT_PUBLIC_SALEOR_API_URL=http://localhost:8000/graphql/' | Set-Content .env
cd ..

cd saleor-platform
if (Test-Path docker-compose.yml) {
    Remove-Item docker-compose.yml -Force
}
Copy-Item ../docker-compose.yml docker-compose.yml

docker compose up -d api db cache worker mailpit --build

Write-Host "Waiting 15 seconds for the API to fully initialize..."
Start-Sleep -Seconds 15

docker compose run --rm api python manage.py migrate

docker compose up -d storefront --build

docker compose ps
cd ..

Write-Host "Setup complete! Access your Admin Dashboard at http://localhost:9000" -ForegroundColor Green