-- Create additional databases for local integration test
-- This script is mounted into admin-postgres's docker-entrypoint-initdb.d/
-- It runs automatically on first container startup (when volume is empty)

CREATE DATABASE dcc_order;
CREATE DATABASE dcc_chat;
CREATE DATABASE monitor;
