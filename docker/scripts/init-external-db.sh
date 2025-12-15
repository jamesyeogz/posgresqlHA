#!/bin/bash

# Supabase Database Initialization Script for External Agents
# This script helps external agents initialize their PostgreSQL database for Supabase compatibility
# 
# Usage: ./init-external-db.sh [OPTIONS]
# 
# Options:
#   -h, --host HOST        PostgreSQL host (default: localhost)
#   -p, --port PORT        PostgreSQL port (default: 5432)
#   -U, --username USER    PostgreSQL username (default: postgres)
#   -d, --database DB      PostgreSQL database name (default: postgres)
#   -W, --password         Prompt for password
#   --no-password          Don't prompt for password
#   --dry-run              Show what would be done without executing
#   --help                 Show this help message

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
HOST="localhost"
PORT="5432"
USERNAME="postgres"
DATABASE="postgres"
PASSWORD=""
DRY_RUN=false
NO_PASSWORD=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
Supabase Database Initialization Script for External Agents

This script initializes a PostgreSQL database to be compatible with Supabase services.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --host HOST        PostgreSQL host (default: localhost)
    -p, --port PORT        PostgreSQL port (default: 5432)
    -U, --username USER    PostgreSQL username (default: postgres)
    -d, --database DB      PostgreSQL database name (default: postgres)
    -W, --password         Prompt for password
    --no-password          Don't prompt for password
    --dry-run              Show what would be done without executing
    --help                 Show this help message

EXAMPLES:
    # Basic usage with password prompt
    $0 -h mydb.example.com -p 5432 -U myuser -d mydb

    # Dry run to see what would be executed
    $0 --dry-run -h mydb.example.com -U myuser

    # No password (trust authentication)
    $0 --no-password -h localhost -U postgres

REQUIREMENTS:
    - PostgreSQL 12+ with superuser privileges
    - psql client installed
    - Required extensions: uuid-ossp, pgcrypto, pg_stat_statements
    - Optional extensions: pgjwt, pg_graphql, pg_jsonschema, wrappers, vault

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if psql is available
    if ! command -v psql >/dev/null 2>&1; then
        print_error "psql command not found. Please install PostgreSQL client tools."
        exit 1
    fi
    
    # Check if the SQL script exists
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SQL_SCRIPT="$SCRIPT_DIR/init-supabase-db.sql"
    
    if [[ ! -f "$SQL_SCRIPT" ]]; then
        print_error "SQL script not found: $SQL_SCRIPT"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to test database connection
test_connection() {
    print_status "Testing database connection..."
    
    local psql_cmd="psql -h $HOST -p $PORT -U $USERNAME -d $DATABASE"
    
    if [[ -n "$PASSWORD" ]]; then
        psql_cmd="PGPASSWORD=$PASSWORD $psql_cmd"
    fi
    
    if [[ "$NO_PASSWORD" == true ]]; then
        psql_cmd="$psql_cmd --no-password"
    fi
    
    # Test connection
    if $psql_cmd -c "SELECT version();" >/dev/null 2>&1; then
        print_success "Database connection successful"
    else
        print_error "Failed to connect to database. Please check your connection parameters."
        exit 1
    fi
}

# Function to check database requirements
check_database_requirements() {
    print_status "Checking database requirements..."
    
    local psql_cmd="psql -h $HOST -p $PORT -U $USERNAME -d $DATABASE"
    
    if [[ -n "$PASSWORD" ]]; then
        psql_cmd="PGPASSWORD=$PASSWORD $psql_cmd"
    fi
    
    if [[ "$NO_PASSWORD" == true ]]; then
        psql_cmd="$psql_cmd --no-password"
    fi
    
    # Check PostgreSQL version
    local version=$($psql_cmd -t -c "SELECT version();" | head -1)
    print_status "PostgreSQL version: $version"
    
    # Check if user has superuser privileges
    local is_superuser=$($psql_cmd -t -c "SELECT rolsuper FROM pg_roles WHERE rolname = current_user;" | tr -d ' ')
    if [[ "$is_superuser" != "t" ]]; then
        print_warning "Current user is not a superuser. Some operations may fail."
    fi
    
    # Check available extensions
    print_status "Checking available extensions..."
    $psql_cmd -c "
        SELECT 
            name as extension_name,
            CASE 
                WHEN EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = e.name) 
                THEN 'Available' 
                ELSE 'Not Available' 
            END as status
        FROM (VALUES 
            ('uuid-ossp'), ('pgcrypto'), ('pg_stat_statements'),
            ('pgjwt'), ('pg_graphql'), ('pg_jsonschema'), ('wrappers'), ('vault')
        ) AS e(name)
        ORDER BY e.name;
    "
    
    print_success "Database requirements check completed"
}

# Function to run the initialization
run_initialization() {
    print_status "Starting Supabase database initialization..."
    
    local psql_cmd="psql -h $HOST -p $PORT -U $USERNAME -d $DATABASE"
    
    if [[ -n "$PASSWORD" ]]; then
        psql_cmd="PGPASSWORD=$PASSWORD $psql_cmd"
    fi
    
    if [[ "$NO_PASSWORD" == true ]]; then
        psql_cmd="$psql_cmd --no-password"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status "DRY RUN: Would execute: $psql_cmd -f $SQL_SCRIPT"
        print_status "DRY RUN: SQL script location: $SQL_SCRIPT"
        return 0
    fi
    
    # Run the SQL script
    if $psql_cmd -f "$SQL_SCRIPT"; then
        print_success "Supabase database initialization completed successfully!"
    else
        print_error "Database initialization failed. Please check the error messages above."
        exit 1
    fi
}

# Function to display connection information
show_connection_info() {
    print_success "Initialization completed!"
    echo
    print_status "Database Connection Information:"
    echo "  Host: $HOST"
    echo "  Port: $PORT"
    echo "  Database: $DATABASE"
    echo "  Username: $USERNAME"
    echo
    print_status "Connection String:"
    if [[ -n "$PASSWORD" ]]; then
        echo "  postgresql://$USERNAME:<password>@$HOST:$PORT/$DATABASE"
    else
        echo "  postgresql://$USERNAME@$HOST:$PORT/$DATABASE"
    fi
    echo
    print_status "Test Connection:"
    echo "  psql -h $HOST -p $PORT -U $USERNAME -d $DATABASE"
    echo
    print_status "Next Steps:"
    echo "  1. Configure your Supabase services to use this database"
    echo "  2. Update connection strings in your Supabase configuration"
    echo "  3. Test the connection with the command above"
    echo "  4. Deploy your Supabase services"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -U|--username)
            USERNAME="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -W|--password)
            read -s -p "Password: " PASSWORD
            echo
            shift
            ;;
        --no-password)
            NO_PASSWORD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Supabase External Database Initializer${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    check_prerequisites
    
    if [[ "$DRY_RUN" == false ]]; then
        test_connection
        check_database_requirements
    fi
    
    run_initialization
    
    if [[ "$DRY_RUN" == false ]]; then
        show_connection_info
    fi
}

# Run main function
main "$@"
