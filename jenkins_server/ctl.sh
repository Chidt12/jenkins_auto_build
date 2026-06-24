#!/bin/bash
set -e

cd "$(dirname "$0")"

case "${1:-help}" in
  start)
    echo "Starting Jenkins..."
    docker compose up -d
    echo "Jenkins started. Open: $(grep JENKINS_URL .env 2>/dev/null | cut -d= -f2 || echo 'http://localhost:9090')"
    ;;
  stop)
    echo "Stopping Jenkins..."
    docker compose down
    echo "Jenkins stopped."
    ;;
  restart)
    echo "Restarting Jenkins..."
    docker compose down
    docker compose up -d
    echo "Jenkins restarted."
    ;;
  rebuild)
    echo "Rebuilding and starting Jenkins..."
    docker compose up -d --build
    echo "Jenkins rebuilt and started."
    ;;
  logs)
    docker compose logs -f jenkins
    ;;
  status)
    docker compose ps
    ;;
  reset)
    read -p "This will DELETE all Jenkins data. Are you sure? (y/N) " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      docker compose down -v
      echo "Jenkins data wiped. Run './ctl.sh rebuild' to start fresh."
    else
      echo "Cancelled."
    fi
    ;;
  *)
    echo "Usage: ./ctl.sh <command>"
    echo ""
    echo "Commands:"
    echo "  start    Start Jenkins"
    echo "  stop     Stop Jenkins"
    echo "  restart  Restart Jenkins (use after .env changes)"
    echo "  rebuild  Rebuild image and start (use after Dockerfile/plugins/yaml changes)"
    echo "  logs     Follow Jenkins logs"
    echo "  status   Show container status"
    echo "  reset    DELETE all data and start fresh"
    ;;
esac
