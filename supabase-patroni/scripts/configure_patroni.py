#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Patroni Configuration Generator for Supabase PostgreSQL

This script generates Patroni configuration based on environment variables,
similar to how Zalando Spilo handles configuration.

Environment Variables:
    PATRONI_SCOPE          - Cluster name (default: postgres-ha)
    PATRONI_NAME           - Node name (required)
    PATRONI_ETCD_HOSTS     - Comma-separated etcd hosts (e.g., etcd1:2379,etcd2:2379)
    PATRONI_ETCD_URL       - Single etcd URL (alternative to ETCD_HOSTS)
    PATRONI_SUPERUSER_PASSWORD - PostgreSQL superuser password
    PATRONI_REPLICATION_PASSWORD - Replication user password
    PGDATA                 - PostgreSQL data directory
    POD_IP                 - Node IP address (for Kubernetes)
    HOSTNAME               - Fallback for node name
"""

import argparse
import json
import logging
import os
import re
import socket
import subprocess
import sys
from copy import deepcopy
from collections import defaultdict

import yaml

# Configuration
RW_DIR = os.environ.get('RW_DIR', '/run')
PATRONI_CONFIG_FILE = os.path.join(RW_DIR, 'patroni.yml')
PGVERSION = os.environ.get('PGVERSION', '16')
PGHOME = os.environ.get('PGHOME', '/home/postgres')
PGDATA_DEFAULT = os.path.join(PGHOME, 'pgdata', 'data')

# DCS options
PATRONI_DCS = ('kubernetes', 'zookeeper', 'exhibitor', 'consul', 'etcd3', 'etcd')

# Extensions that require shared_preload_libraries
SHARED_PRELOAD_EXTENSIONS = [
    'pg_stat_statements',
    'pg_cron',
    'pgsodium',
    'timescaledb',
]

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def get_local_ip():
    """Get the local IP address of this machine"""
    try:
        # Try to get POD_IP first (Kubernetes)
        pod_ip = os.environ.get('POD_IP')
        if pod_ip:
            return pod_ip
        
        # Try to connect to an external address to determine local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'


def get_node_name():
    """Get the node name from environment or hostname"""
    name = os.environ.get('PATRONI_NAME')
    if name:
        return name
    
    name = os.environ.get('HOSTNAME')
    if name:
        return name
    
    return socket.gethostname()


def get_dcs_config():
    """Generate DCS (Distributed Configuration Store) configuration"""
    dcs_config = {}
    
    # Check for etcd configuration
    etcd_hosts = os.environ.get('PATRONI_ETCD_HOSTS') or os.environ.get('ETCD_HOSTS')
    etcd_url = os.environ.get('PATRONI_ETCD_URL') or os.environ.get('ETCD_URL')
    etcd_host = os.environ.get('PATRONI_ETCD_HOST') or os.environ.get('ETCD_HOST')
    
    if etcd_hosts:
        # Multiple etcd hosts
        hosts = [h.strip() for h in etcd_hosts.split(',')]
        dcs_config['etcd3'] = {
            'hosts': hosts
        }
        logger.info(f"Configured etcd3 with hosts: {hosts}")
    elif etcd_url:
        # Single etcd URL
        dcs_config['etcd3'] = {
            'host': etcd_url
        }
        logger.info(f"Configured etcd3 with URL: {etcd_url}")
    elif etcd_host:
        # Single etcd host
        port = os.environ.get('PATRONI_ETCD_PORT', os.environ.get('ETCD_PORT', '2379'))
        dcs_config['etcd3'] = {
            'host': f"{etcd_host}:{port}"
        }
        logger.info(f"Configured etcd3 with host: {etcd_host}:{port}")
    
    # Check for Consul configuration
    consul_host = os.environ.get('PATRONI_CONSUL_HOST') or os.environ.get('CONSUL_HOST')
    if consul_host and not dcs_config:
        consul_port = os.environ.get('PATRONI_CONSUL_PORT', os.environ.get('CONSUL_PORT', '8500'))
        dcs_config['consul'] = {
            'host': f"{consul_host}:{consul_port}"
        }
        logger.info(f"Configured Consul with host: {consul_host}:{consul_port}")
    
    # Check for Kubernetes configuration
    kubernetes_host = os.environ.get('KUBERNETES_SERVICE_HOST')
    if kubernetes_host and not dcs_config:
        dcs_config['kubernetes'] = {
            'namespace': os.environ.get('POD_NAMESPACE', 'default'),
            'labels': json.loads(os.environ.get('PATRONI_KUBERNETES_LABELS', '{"application": "supabase-patroni"}'))
        }
        logger.info("Configured Kubernetes DCS")
    
    # Check for ZooKeeper configuration
    zk_hosts = os.environ.get('PATRONI_ZOOKEEPER_HOSTS') or os.environ.get('ZOOKEEPER_HOSTS')
    if zk_hosts and not dcs_config:
        hosts = [h.strip() for h in zk_hosts.split(',')]
        dcs_config['zookeeper'] = {
            'hosts': hosts
        }
        logger.info(f"Configured ZooKeeper with hosts: {hosts}")
    
    return dcs_config


def get_shared_preload_libraries():
    """Get the list of shared preload libraries"""
    libs = []
    
    # Add configured extensions
    for ext in SHARED_PRELOAD_EXTENSIONS:
        ext_lib = f"/usr/lib/postgresql/{PGVERSION}/lib/{ext}.so"
        if os.path.exists(ext_lib):
            libs.append(ext)
    
    # Add from environment if specified
    env_libs = os.environ.get('PATRONI_SHARED_PRELOAD_LIBRARIES', '')
    if env_libs:
        for lib in env_libs.split(','):
            lib = lib.strip()
            if lib and lib not in libs:
                libs.append(lib)
    
    return ','.join(libs) if libs else 'pg_stat_statements'


def generate_patroni_config():
    """Generate the complete Patroni configuration"""
    
    node_name = get_node_name()
    node_ip = get_local_ip()
    
    scope = os.environ.get('PATRONI_SCOPE', os.environ.get('SCOPE', 'postgres-ha'))
    
    # PostgreSQL paths
    pgdata = os.environ.get('PGDATA', PGDATA_DEFAULT)
    pgbin = f"/usr/lib/postgresql/{PGVERSION}/bin"
    
    # Credentials
    superuser_password = os.environ.get('PATRONI_SUPERUSER_PASSWORD', 
                                        os.environ.get('POSTGRES_PASSWORD', 'postgres'))
    replication_password = os.environ.get('PATRONI_REPLICATION_PASSWORD',
                                          os.environ.get('REPLICATION_PASSWORD', 'replication'))
    
    # Build configuration
    config = {
        'scope': scope,
        'name': node_name,
        
        'restapi': {
            'listen': '0.0.0.0:8008',
            'connect_address': f'{node_ip}:8008'
        },
        
        'bootstrap': {
            'dcs': {
                'ttl': 30,
                'loop_wait': 10,
                'retry_timeout': 10,
                'maximum_lag_on_failover': 1048576,
                'postgresql': {
                    'use_pg_rewind': True,
                    'use_slots': True,
                    'parameters': {
                        'wal_level': 'replica',
                        'hot_standby': 'on',
                        'max_connections': 200,
                        'max_wal_senders': 10,
                        'max_replication_slots': 10,
                        'wal_keep_size': '1GB',
                        'hot_standby_feedback': 'on',
                        'log_destination': 'stderr',
                        'logging_collector': 'off',
                        'log_min_duration_statement': 1000,
                        'shared_preload_libraries': get_shared_preload_libraries(),
                        # Supabase recommended settings
                        'password_encryption': 'scram-sha-256',
                        'timezone': 'UTC',
                    }
                }
            },
            'initdb': [
                {'encoding': 'UTF8'},
                {'locale': 'en_US.UTF-8'},
                'data-checksums'
            ],
            'pg_hba': [
                'local all all trust',
                'host all all 0.0.0.0/0 scram-sha-256',
                'host all all ::0/0 scram-sha-256',
                'host replication replicator 0.0.0.0/0 scram-sha-256',
                'host replication replicator ::0/0 scram-sha-256',
            ],
            'users': {
                'postgres': {
                    'password': superuser_password,
                    'options': ['superuser']
                },
                'replicator': {
                    'password': replication_password,
                    'options': ['replication']
                }
            }
        },
        
        'postgresql': {
            'listen': f'0.0.0.0:5432',
            'connect_address': f'{node_ip}:5432',
            'data_dir': pgdata,
            'bin_dir': pgbin,
            'pgpass': os.path.join(PGHOME, '.pgpass'),
            'authentication': {
                'superuser': {
                    'username': 'postgres',
                    'password': superuser_password
                },
                'replication': {
                    'username': 'replicator',
                    'password': replication_password
                }
            },
            'parameters': {
                'unix_socket_directories': '/var/run/postgresql'
            },
            'pg_hba': [
                'local all all trust',
                'host all all 0.0.0.0/0 scram-sha-256',
                'host all all ::0/0 scram-sha-256',
                'host replication replicator 0.0.0.0/0 scram-sha-256',
                'host replication replicator ::0/0 scram-sha-256',
            ]
        },
        
        'tags': {
            'nofailover': False,
            'noloadbalance': False,
            'clonefrom': False,
            'nosync': False
        }
    }
    
    # Add DCS configuration
    dcs_config = get_dcs_config()
    if dcs_config:
        config.update(dcs_config)
    else:
        logger.warning("No DCS configured! Patroni needs etcd, consul, kubernetes, or zookeeper.")
        # Default to etcd on localhost for development
        config['etcd3'] = {'host': 'localhost:2379'}
    
    # Add post_init callback if script exists
    post_init_script = '/scripts/post_init.sh'
    if os.path.exists(post_init_script):
        config['bootstrap']['post_init'] = post_init_script
        logger.info(f"Configured post_init script: {post_init_script}")
    
    # Add callbacks if configured
    callbacks_dir = os.environ.get('PATRONI_CALLBACKS_DIR')
    if callbacks_dir and os.path.isdir(callbacks_dir):
        callbacks = {}
        for cb_type in ['on_start', 'on_stop', 'on_restart', 'on_role_change']:
            cb_script = os.path.join(callbacks_dir, cb_type)
            if os.path.exists(cb_script) and os.access(cb_script, os.X_OK):
                callbacks[cb_type] = cb_script
        if callbacks:
            config['postgresql']['callbacks'] = callbacks
    
    return config


def write_config(config, force=False):
    """Write Patroni configuration to file"""
    if not force and os.path.exists(PATRONI_CONFIG_FILE):
        logger.warning(f"Config file {PATRONI_CONFIG_FILE} already exists, use --force to overwrite")
        return False
    
    # Ensure directory exists
    config_dir = os.path.dirname(PATRONI_CONFIG_FILE)
    os.makedirs(config_dir, exist_ok=True)
    
    with open(PATRONI_CONFIG_FILE, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, width=120)
    
    # Set permissions
    os.chmod(PATRONI_CONFIG_FILE, 0o600)
    
    logger.info(f"Wrote Patroni configuration to {PATRONI_CONFIG_FILE}")
    return True


def main():
    parser = argparse.ArgumentParser(description='Configure Patroni for Supabase PostgreSQL')
    parser.add_argument('-f', '--force', action='store_true', help='Overwrite existing config')
    parser.add_argument('-o', '--output', help='Output file path', default=PATRONI_CONFIG_FILE)
    parser.add_argument('--dry-run', action='store_true', help='Print config without writing')
    parser.add_argument('sections', nargs='*', default=['all'], 
                        help='Sections to configure: all, patroni')
    
    args = parser.parse_args()
    
    global PATRONI_CONFIG_FILE
    PATRONI_CONFIG_FILE = args.output
    
    config = generate_patroni_config()
    
    if args.dry_run:
        print(yaml.dump(config, default_flow_style=False, width=120))
        return 0
    
    if write_config(config, args.force):
        logger.info("Patroni configuration generated successfully")
        return 0
    else:
        return 1


if __name__ == '__main__':
    sys.exit(main())
