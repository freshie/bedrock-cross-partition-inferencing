"""
Performance optimizations for VPC-enabled Lambda functions

This module provides optimizations for Lambda functions running in VPC
with focus on cold start reduction, connection pooling, and caching.
"""

import json
import time
import gzip
import logging
from functools import lru_cache, wraps
from typing import Dict, Any, Optional, Callable
from datetime import datetime, timedelta
import threading
import os

logger = logging.getLogger(__name__)

class LambdaPerformanceOptimizer:
    """Performance optimizer for VPC Lambda functions"""
    
    def __init__(self):
        self.connection_pools = {}
        self.cache = {}
        self.metrics = {
            'cold_starts': 0,
            'warm_starts': 0,
            'cache_hits': 0,
            'cache_misses': 0,
            'connection_reuses': 0,
            'connection_creates': 0
        }
        self._lock = threading.Lock()
        self._initialized = False
    
    def initialize(self):
        """Initialize performance optimizations"""
        if self._initialized:
            self.metrics['warm_starts'] += 1
            logger.info("Lambda warm start detected")
            return
        
        start_time = time.time()
        
        # Pre-warm connections
        self._prewarm_connections()
        
        # Pre-load configuration
        self._preload_configuration()
        
        # Initialize caches
        self._initialize_caches()
        
        self._initialized = True
        self.metrics['cold_starts'] += 1
        
        init_time = (time.time() - start_time) * 1000
        logger.info(f"Lambda cold start initialization completed in {init_time:.2f}ms")
    
    def _prewarm_connections(self):
        """Pre-warm VPC endpoint connections"""
        try:
            from vpc_endpoint_clients import get_global_client_manager
            
            client_manager = get_global_client_manager()
            
            # Pre-create clients to avoid cold start delays
            clients_to_prewarm = [
                'get_secrets_client',
                'get_dynamodb_resource',
                'get_cloudwatch_client'
            ]
            
            for client_method in clients_to_prewarm:
                try:
                    getattr(client_manager, client_method)()
                    logger.debug(f"Pre-warmed {client_method}")
                except Exception as e:
                    logger.warning(f"Failed to pre-warm {client_method}: {str(e)}")
        
        except Exception as e:
            logger.error(f"Failed to pre-warm connections: {str(e)}")
    
    def _preload_configuration(self):
        """Pre-load configuration to avoid repeated lookups"""
        try:
            # Cache environment variables
            self.config = {
                'vpc_endpoint_secrets': os.environ.get('VPC_ENDPOINT_SECRETS'),
                'vpc_endpoint_dynamodb': os.environ.get('VPC_ENDPOINT_DYNAMODB'),
                'vpc_endpoint_logs': os.environ.get('VPC_ENDPOINT_LOGS'),
                'vpc_endpoint_monitoring': os.environ.get('VPC_ENDPOINT_MONITORING'),
                'routing_method': os.environ.get('ROUTING_METHOD', 'vpn'),
                'commercial_bedrock_endpoint': os.environ.get('COMMERCIAL_BEDROCK_ENDPOINT'),
                'commercial_credentials_secret': os.environ.get('COMMERCIAL_CREDENTIALS_SECRET'),
                'request_log_table': os.environ.get('REQUEST_LOG_TABLE')
            }
            
            logger.debug("Configuration pre-loaded")
        
        except Exception as e:
            logger.error(f"Failed to pre-load configuration: {str(e)}")
    
    def _initialize_caches(self):
        """Initialize performance caches"""
        try:
            # Initialize model information cache
            self.model_cache = {}
            
            # Initialize credentials cache with TTL
            self.credentials_cache = {
                'data': None,
                'expires_at': None,
                'ttl_seconds': 3600  # 1 hour
            }
            
            # Initialize response cache for frequently requested data
            self.response_cache = {}
            
            logger.debug("Caches initialized")
        
        except Exception as e:
            logger.error(f"Failed to initialize caches: {str(e)}")
    
    def get_cached_credentials(self, force_refresh=False):
        """Get cached commercial credentials with TTL"""
        with self._lock:
            now = datetime.utcnow()
            
            # Check if cache is valid
            if (not force_refresh and 
                self.credentials_cache['data'] is not None and 
                self.credentials_cache['expires_at'] and 
                now < self.credentials_cache['expires_at']):
                
                self.metrics['cache_hits'] += 1
                logger.debug("Using cached credentials")
                return self.credentials_cache['data']
            
            # Cache miss - fetch fresh credentials
            self.metrics['cache_misses'] += 1
            logger.debug("Fetching fresh credentials")
            
            try:
                from vpc_endpoint_clients import get_global_client_manager
                
                client_manager = get_global_client_manager()
                secrets_client = client_manager.get_secrets_client()
                
                response = secrets_client.get_secret_value(
                    SecretId=self.config['commercial_credentials_secret']
                )
                
                credentials = json.loads(response['SecretString'])
                
                # Update cache
                self.credentials_cache['data'] = credentials
                self.credentials_cache['expires_at'] = now + timedelta(
                    seconds=self.credentials_cache['ttl_seconds']
                )
                
                return credentials
            
            except Exception as e:
                logger.error(f"Failed to fetch credentials: {str(e)}")
                # Return cached data if available, even if expired
                if self.credentials_cache['data']:
                    logger.warning("Using expired cached credentials due to fetch failure")
                    return self.credentials_cache['data']
                raise
    
    @lru_cache(maxsize=100)
    def get_model_info(self, model_id: str) -> Dict[str, Any]:
        """Get cached model information"""
        try:
            # This would typically call Bedrock to get model info
            # For now, return cached static info to avoid repeated calls
            model_info = {
                'modelId': model_id,
                'cached_at': datetime.utcnow().isoformat(),
                'supports_streaming': True,
                'max_tokens': 4096
            }
            
            self.metrics['cache_hits'] += 1
            return model_info
        
        except Exception as e:
            self.metrics['cache_misses'] += 1
            logger.error(f"Failed to get model info for {model_id}: {str(e)}")
            return {'modelId': model_id, 'error': str(e)}
    
    def compress_payload(self, data: Dict[str, Any]) -> bytes:
        """Compress large payloads to reduce transfer time"""
        try:
            json_data = json.dumps(data, separators=(',', ':'))
            
            # Only compress if payload is large enough to benefit
            if len(json_data) > 1024:  # 1KB threshold
                compressed = gzip.compress(json_data.encode('utf-8'))
                
                # Only use compression if it actually reduces size
                if len(compressed) < len(json_data):
                    logger.debug(f"Compressed payload from {len(json_data)} to {len(compressed)} bytes")
                    return compressed
            
            return json_data.encode('utf-8')
        
        except Exception as e:
            logger.error(f"Failed to compress payload: {str(e)}")
            return json.dumps(data).encode('utf-8')
    
    def decompress_payload(self, data: bytes) -> Dict[str, Any]:
        """Decompress payload"""
        try:
            # Try to decompress first
            try:
                decompressed = gzip.decompress(data).decode('utf-8')
                return json.loads(decompressed)
            except (gzip.BadGzipFile, OSError):
                # Not compressed, treat as regular JSON
                return json.loads(data.decode('utf-8'))
        
        except Exception as e:
            logger.error(f"Failed to decompress payload: {str(e)}")
            raise
    
    def get_performance_metrics(self) -> Dict[str, Any]:
        """Get performance metrics"""
        return {
            'metrics': self.metrics.copy(),
            'cache_stats': {
                'credentials_cache_valid': (
                    self.credentials_cache['expires_at'] and 
                    datetime.utcnow() < self.credentials_cache['expires_at']
                ) if self.credentials_cache['expires_at'] else False,
                'model_cache_size': len(self.model_cache),
                'response_cache_size': len(self.response_cache)
            },
            'initialization_status': self._initialized
        }

# Global optimizer instance
_performance_optimizer = None

def get_performance_optimizer() -> LambdaPerformanceOptimizer:
    """Get global performance optimizer instance"""
    global _performance_optimizer
    if _performance_optimizer is None:
        _performance_optimizer = LambdaPerformanceOptimizer()
    return _performance_optimizer

def performance_optimized(func: Callable) -> Callable:
    """Decorator to add performance optimizations to Lambda handler"""
    
    @wraps(func)
    def wrapper(event, context):
        optimizer = get_performance_optimizer()
        
        # Initialize optimizations
        start_time = time.time()
        optimizer.initialize()
        init_time = (time.time() - start_time) * 1000
        
        # Add performance context to event
        event['_performance_context'] = {
            'optimizer': optimizer,
            'init_time_ms': init_time,
            'request_start': time.time()
        }
        
        try:
            # Execute original function
            result = func(event, context)
            
            # Add performance metrics to response
            if isinstance(result, dict) and 'body' in result:
                try:
                    body = json.loads(result['body']) if isinstance(result['body'], str) else result['body']
                    if 'metadata' not in body:
                        body['metadata'] = {}
                    
                    body['metadata']['performance'] = {
                        'init_time_ms': init_time,
                        'total_time_ms': (time.time() - event['_performance_context']['request_start']) * 1000,
                        'optimizer_metrics': optimizer.get_performance_metrics()
                    }
                    
                    result['body'] = json.dumps(body)
                except Exception as e:
                    logger.warning(f"Failed to add performance metrics to response: {str(e)}")
            
            return result
        
        except Exception as e:
            logger.error(f"Error in performance-optimized function: {str(e)}")
            raise
    
    return wrapper

class ConnectionPool:
    """Connection pool for external services"""
    
    def __init__(self, max_connections: int = 10, connection_timeout: int = 30):
        self.max_connections = max_connections
        self.connection_timeout = connection_timeout
        self.connections = {}
        self.connection_counts = {}
        self._lock = threading.Lock()
    
    def get_connection(self, service_name: str, create_func: Callable):
        """Get or create connection for service"""
        with self._lock:
            if service_name not in self.connections:
                if len(self.connections) >= self.max_connections:
                    # Remove least used connection
                    least_used = min(self.connection_counts.items(), key=lambda x: x[1])
                    del self.connections[least_used[0]]
                    del self.connection_counts[least_used[0]]
                
                # Create new connection
                self.connections[service_name] = create_func()
                self.connection_counts[service_name] = 0
                
                optimizer = get_performance_optimizer()
                optimizer.metrics['connection_creates'] += 1
                logger.debug(f"Created new connection for {service_name}")
            else:
                optimizer = get_performance_optimizer()
                optimizer.metrics['connection_reuses'] += 1
                logger.debug(f"Reusing connection for {service_name}")
            
            self.connection_counts[service_name] += 1
            return self.connections[service_name]
    
    def close_all(self):
        """Close all connections"""
        with self._lock:
            for service_name, connection in self.connections.items():
                try:
                    if hasattr(connection, 'close'):
                        connection.close()
                except Exception as e:
                    logger.warning(f"Failed to close connection for {service_name}: {str(e)}")
            
            self.connections.clear()
            self.connection_counts.clear()

# Global connection pool
_connection_pool = ConnectionPool()

def get_connection_pool() -> ConnectionPool:
    """Get global connection pool"""
    return _connection_pool

class ResponseCache:
    """Response cache with TTL support"""
    
    def __init__(self, default_ttl: int = 300):  # 5 minutes default
        self.cache = {}
        self.default_ttl = default_ttl
        self._lock = threading.Lock()
    
    def get(self, key: str) -> Optional[Any]:
        """Get cached response"""
        with self._lock:
            if key in self.cache:
                entry = self.cache[key]
                if datetime.utcnow() < entry['expires_at']:
                    optimizer = get_performance_optimizer()
                    optimizer.metrics['cache_hits'] += 1
                    logger.debug(f"Cache hit for key: {key}")
                    return entry['data']
                else:
                    # Expired entry
                    del self.cache[key]
            
            optimizer = get_performance_optimizer()
            optimizer.metrics['cache_misses'] += 1
            logger.debug(f"Cache miss for key: {key}")
            return None
    
    def set(self, key: str, data: Any, ttl: Optional[int] = None) -> None:
        """Set cached response"""
        with self._lock:
            ttl = ttl or self.default_ttl
            self.cache[key] = {
                'data': data,
                'expires_at': datetime.utcnow() + timedelta(seconds=ttl),
                'created_at': datetime.utcnow()
            }
            logger.debug(f"Cached response for key: {key} (TTL: {ttl}s)")
    
    def clear_expired(self) -> int:
        """Clear expired entries"""
        with self._lock:
            now = datetime.utcnow()
            expired_keys = [
                key for key, entry in self.cache.items()
                if now >= entry['expires_at']
            ]
            
            for key in expired_keys:
                del self.cache[key]
            
            logger.debug(f"Cleared {len(expired_keys)} expired cache entries")
            return len(expired_keys)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        with self._lock:
            now = datetime.utcnow()
            valid_entries = sum(
                1 for entry in self.cache.values()
                if now < entry['expires_at']
            )
            
            return {
                'total_entries': len(self.cache),
                'valid_entries': valid_entries,
                'expired_entries': len(self.cache) - valid_entries
            }

# Global response cache
_response_cache = ResponseCache()

def get_response_cache() -> ResponseCache:
    """Get global response cache"""
    return _response_cache

def cache_response(key_func: Callable[[Any], str], ttl: int = 300):
    """Decorator to cache function responses"""
    
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            cache = get_response_cache()
            
            # Generate cache key
            cache_key = key_func(*args, **kwargs)
            
            # Try to get from cache
            cached_result = cache.get(cache_key)
            if cached_result is not None:
                return cached_result
            
            # Execute function and cache result
            result = func(*args, **kwargs)
            cache.set(cache_key, result, ttl)
            
            return result
        
        return wrapper
    return decorator

# Memory optimization utilities
def optimize_memory_usage():
    """Optimize memory usage for Lambda function"""
    import gc
    
    # Force garbage collection
    collected = gc.collect()
    logger.debug(f"Garbage collection freed {collected} objects")
    
    # Clear expired cache entries
    cache = get_response_cache()
    expired_count = cache.clear_expired()
    logger.debug(f"Cleared {expired_count} expired cache entries")

def get_memory_usage() -> Dict[str, Any]:
    """Get current memory usage statistics"""
    import psutil
    import os
    
    try:
        process = psutil.Process(os.getpid())
        memory_info = process.memory_info()
        
        return {
            'rss_mb': memory_info.rss / 1024 / 1024,  # Resident Set Size
            'vms_mb': memory_info.vms / 1024 / 1024,  # Virtual Memory Size
            'percent': process.memory_percent(),
            'available_mb': psutil.virtual_memory().available / 1024 / 1024
        }
    except ImportError:
        # psutil not available
        return {'error': 'psutil not available'}
    except Exception as e:
        return {'error': str(e)}