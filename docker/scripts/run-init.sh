#!/bin/bash
# Supabase Database Initialization Script Wrapper
# This script is called by Patroni's post_init hook during bootstrap
# It only runs on the PRIMARY node when the cluster is first created

set -e

echo "=============================================="
echo "Running Supabase database initialization..."
echo "=============================================="

# Wait for PostgreSQL to be fully ready
sleep 5

# Run the Supabase init SQL script
psql -U postgres -d postgres -f /scripts/init-supabase-db.sql

echo "=============================================="
echo "Supabase database initialization completed!"
echo "=============================================="

