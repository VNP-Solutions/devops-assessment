#!/bin/bash
# Re-run the seed/init sql inside the container
cat scripts/init.sql | docker exec -i assessment_postgres_1 psql -U postgres -d toy_production
# Note: container name might vary slightly depending on folder name (assessment-postgres-1 or assessment_postgres_1)
# A more robust way is getting container id by service name
CONTAINER_ID=$(docker-compose ps -q postgres)
cat scripts/init.sql | docker exec -i $CONTAINER_ID psql -U postgres -d toy_production
echo "Database seeded."
