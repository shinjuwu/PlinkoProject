#!/bin/bash

# Generates GCP Firewall rules for the deployment
# All traffic goes through nginx HTTPS reverse proxy — only 80/443 needed
# Usage: bash gcloud_firewall.sh

echo "=================================================="
echo "      GCP Firewall Rule Generator"
echo "=================================================="

# Admin Node: only HTTP/HTTPS (nginx proxies all services)
echo ""
echo "--- Admin Node Firewall Rules ---"
echo "Run this command to open ports for the Admin Node:"
echo ""
echo "gcloud compute firewall-rules create allow-admin-node-ports \\"
echo "    --direction=INGRESS \\"
echo "    --priority=1000 \\"
echo "    --network=default \\"
echo "    --action=ALLOW \\"
echo "    --rules=tcp:80,tcp:443"
echo ""

# Game Node: only HTTP/HTTPS (nginx proxies WS + GameHub API)
echo ""
echo "--- Game Node Firewall Rules ---"
echo "Run this command to open ports for the Game Node:"
echo ""
echo "gcloud compute firewall-rules create allow-game-node-ports \\"
echo "    --direction=INGRESS \\"
echo "    --priority=1000 \\"
echo "    --network=default \\"
echo "    --action=ALLOW \\"
echo "    --rules=tcp:80,tcp:443"
echo ""

echo "=================================================="
echo "All services are behind nginx HTTPS reverse proxy."
echo "No internal ports (9986, 8896, 17782, 9643, 10101) are exposed."
echo ""
echo "Database (5432) and Redis (6379) are NOT exposed."
echo "Use SSH tunneling for remote DB administration:"
echo "  ssh -L 5432:localhost:5432 user@admin-server"
echo "=================================================="
