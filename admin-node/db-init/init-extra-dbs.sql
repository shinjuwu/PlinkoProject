-- Create additional databases needed by services
-- This runs after the primary dcc_game database is created by POSTGRES_DB env var

CREATE DATABASE dcc_order;
CREATE DATABASE dcc_chat;
CREATE DATABASE monitor;
