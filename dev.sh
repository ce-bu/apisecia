#!/usr/bin/env bash

set -euo pipefail

# Configuration adapted directly from your specification
CONTAINER_NAME="apisecia_postgres"
IMAGE="docker.io/library/postgres:17-alpine"
DB_USER="user"
DB_PASSWORD="user"
DB_NAME="apisecia"
VOLUME_NAME="pgdata"
DB_TIMEOUT=10

# Database URL used internally for SQLx tasks
DATABASE_URL_STR="postgres://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}"

show_help() {
    cat << EOF
Apisecia PostgreSQL Dev Management Script

Usage: ./dev.sh [option]

Options:
  install   Install development prerequisites (Rust tools & CLI engines)
  up        Start the apisecia_postgres container natively
  down      Stop and delete the apisecia_postgres container
  reset     Wipe volume, restart container, and run migrations (Destructive)
  migrate   Run pending SQLx migrations
  psql      Open an interactive PostgreSQL terminal session inside the container
  status    Check container and port status
  help      Show this help menu
EOF
}

wait_for_db() {
    echo "Waiting for PostgreSQL to be ready on port 5432..."
    local count=0
    until podman exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" &> /dev/null; do
        if [ "$count" -ge "$DB_TIMEOUT" ]; then
            echo "Error: Database timed out or failed to start." >&2
            exit 1
        fi
        sleep 1
        ((count++))
    done
    echo "Database is ready!"
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

case "$1" in
    install)
        echo "=== Checking & Installing Prerequisites ==="
        
        # 1. Check for Rust/Cargo
        if ! command -v cargo &> /dev/null; then
            echo "Error: Rust/Cargo is not installed. Please install it first from https://rustup.rs" >&2
            exit 1
        fi
        
        # 2. Check for Podman
        if ! command -v podman &> /dev/null; then
            echo "Error: Podman engine is not installed on your system." >&2
            exit 1
        fi

        # 3. Install sqlx-cli if missing
        if ! command -v sqlx &> /dev/null; then
            echo "Installing sqlx-cli (Postgres features only to speed up compilation)..."
            cargo install sqlx-cli --no-default-features --features postgres
        else
            echo "✅ sqlx-cli is already installed."
        fi

        # 4. Install cargo-watch (Highly useful helper for live reloading Axum projects)
        if ! command -v cargo-watch &> /dev/null; then
            echo "Installing cargo-watch for hot-reloading your Axum code..."
            cargo install cargo-watch
        else
            echo "✅ cargo-watch is already installed."
        fi

        echo -e "\n🎉 Setup Complete! Run './dev.sh up' to launch your stack."
        ;;

    up)
        if podman ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
            echo "Container '$CONTAINER_NAME' already exists."
            if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" == "false" ]; then
                echo "Starting existing container..."
                podman start "$CONTAINER_NAME"
                wait_for_db
            else
                echo "Container is already running."
            fi
        else
            echo "Creating and starting fresh PostgreSQL container..."
            podman run -d \
                --name "$CONTAINER_NAME" \
                -e POSTGRES_USER="$DB_USER" \
                -e POSTGRES_PASSWORD="$DB_PASSWORD" \
                -e POSTGRES_DB="$DB_NAME" \
                -p 5432:5432 \
                -v "${VOLUME_NAME}:/var/lib/postgresql/data:Z" \
                "$IMAGE"
            wait_for_db
        fi
        ;;

    down)
        echo "Stopping and removing container..."
        podman stop "$CONTAINER_NAME" &>/dev/null || true
        podman rm "$CONTAINER_NAME" &>/dev/null || true
        echo "Container cleaned up."
        ;;

    reset)
        read -p "⚠️ WARNING: This will delete ALL local database data. Continue? (y/N)  " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Wiping local container and persistent volume..."
            podman stop "$CONTAINER_NAME" &>/dev/null || true
            podman rm "$CONTAINER_NAME" &>/dev/null || true
            podman volume rm "$VOLUME_NAME" &>/dev/null || true
            
            $0 up
            
            if command -v sqlx &> /dev/null; then
                echo "Running SQLx database setup and migrations..."
                export DATABASE_URL="$DATABASE_URL_STR"
                sqlx database create
                sqlx migrate run
            else
                echo "Notice: sqlx-cli not found. Run './dev.sh install' first."
            fi
        else
            echo "Reset aborted."
        fi
        ;;

    migrate)
        if command -v sqlx &> /dev/null; then
            echo "Applying pending migrations..."
            export DATABASE_URL="$DATABASE_URL_STR"
            sqlx migrate run
        else
            echo "Error: sqlx-cli is not installed. Run './dev.sh install' to add it." >&2
            exit 1
        fi
        ;;

    psql)
        echo "Connecting to $CONTAINER_NAME terminal session..."
        if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" == "true" ]; then
            podman exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME"
        else
            echo "Error: Container '$CONTAINER_NAME' is offline. Turn it on first with: ./dev.sh up" >&2
            exit 1
        fi
        ;;

    status)
        echo "=== Container Status ==="
        podman ps --filter name="$CONTAINER_NAME"
        echo -e "\n=== Port Status (5432) ==="
        ss -tuln | grep 5432 || echo "Port 5432 is idle."
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        echo "Error: Unknown option '$1'" >&2
        show_help
        exit 1
        ;;
esac
