"""
VPC Endpoint Client Configuration Module

This module provides optimized boto3 clients configured to use VPC endpoints
with connection caching, retry logic, and timeout optimization.
"""

import boto3
import logging
import time
import os
from functools import lru_cache
from typing import Dict, Any, Optional
from botocore.config import Config
from botocore.exceptions import ClientError, EndpointConnectionError

logger = logging.getLogger(__name__)

class VPCEndpointClientManager:
    """
    Manages boto3 clients configured for VPC endpoints with optimized settings
    """
    
    def __init__(self):
        self.vpc_endpoint_secrets = os.environ.get('VPC_ENDPOINT_SECRETS')
        self.vpc_endpoint_dynamodb = os.environ.get('VPC_ENDPOINT_DYNAMODB')
        self.vpc_endpoint_logs = os.environ.get('VPC_ENDPOINT_LOGS')
        self.vpc_endpoint_monitoring = os.environ.get('VPC_ENDPOINT_MONITORING')
        self.vpc_endpoint_lambda = os.environ.get('VPC_ENDPOINT_LAMBDA')
        self.vpc_endpoint_sts = os.environ.get('VPC_ENDPOINT_STS')
        
        # Client cache to avoid recreation
        self._client_cache = {}
        
        # Default configuration optimized for VPC endpoints
        self.default_config = Config(
            region_name=os.environ.get('AWS_REGION', 'us-gov-west-1'),
            retries={
                'max_attempts': 3,
                'mode': 'adaptive'
            },
            max_pool_connections=50,
            read_timeout=30,
            connect_timeout=10
        )
    
    @lru_cache(maxsize=10)
    def get_secrets_client(self) -> boto3.client:
        """
        Get Secrets Manager client configured for VPC endpoint
        
        Returns:
            boto3.client: Configured Secrets Manager client
        """
        cache_key = 'secretsmanager'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('secretsmanager')
            
            if self.vpc_endpoint_secrets:
                logger.info(f"Creating Secrets Manager client with VPC endpoint: {self.vpc_endpoint_secrets}")
                client = boto3.client(
                    'secretsmanager',
                    endpoint_url=self.vpc_endpoint_secrets,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_SECRETS not configured, using default endpoint")
                client = boto3.client('secretsmanager', config=config)
            
            self._client_cache[cache_key] = client
        
        return self._client_cache[cache_key]
    
    @lru_cache(maxsize=10)
    def get_dynamodb_resource(self) -> boto3.resource:
        """
        Get DynamoDB resource configured for VPC endpoint
        
        Returns:
            boto3.resource: Configured DynamoDB resource
        """
        cache_key = 'dynamodb_resource'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('dynamodb')
            
            if self.vpc_endpoint_dynamodb:
                logger.info(f"Creating DynamoDB resource with VPC endpoint: {self.vpc_endpoint_dynamodb}")
                resource = boto3.resource(
                    'dynamodb',
                    endpoint_url=self.vpc_endpoint_dynamodb,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_DYNAMODB not configured, using default endpoint")
                resource = boto3.resource('dynamodb', config=config)
            
            self._client_cache[cache_key] = resource
        
        return self._client_cache[cache_key]
    
    @lru_cache(maxsize=10)
    def get_dynamodb_client(self) -> boto3.client:
        """
        Get DynamoDB client configured for VPC endpoint
        
        Returns:
            boto3.client: Configured DynamoDB client
        """
        cache_key = 'dynamodb_client'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('dynamodb')
            
            if self.vpc_endpoint_dynamodb:
                logger.info(f"Creating DynamoDB client with VPC endpoint: {self.vpc_endpoint_dynamodb}")
                client = boto3.client(
                    'dynamodb',
                    endpoint_url=self.vpc_endpoint_dynamodb,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_DYNAMODB not configured, using default endpoint")
                client = boto3.client('dynamodb', config=config)
            
            self._client_cache[cache_key] = client
        
        return self._client_cache[cache_key]
    
    @lru_cache(maxsize=10)
    def get_logs_client(self) -> boto3.client:
        """
        Get CloudWatch Logs client configured for VPC endpoint
        
        Returns:
            boto3.client: Configured CloudWatch Logs client
        """
        cache_key = 'logs'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('logs')
            
            if self.vpc_endpoint_logs:
                logger.info(f"Creating CloudWatch Logs client with VPC endpoint: {self.vpc_endpoint_logs}")
                client = boto3.client(
                    'logs',
                    endpoint_url=self.vpc_endpoint_logs,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_LOGS not configured, using default endpoint")
                client = boto3.client('logs', config=config)
            
            self._client_cache[cache_key] = client
        
        return self._client_cache[cache_key]
    
    @lru_cache(maxsize=10)
    def get_cloudwatch_client(self) -> boto3.client:
        """
        Get CloudWatch client configured for VPC endpoint
        
        Returns:
            boto3.client: Configured CloudWatch client
        """
        cache_key = 'cloudwatch'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('cloudwatch')
            
            if self.vpc_endpoint_monitoring:
                logger.info(f"Creating CloudWatch client with VPC endpoint: {self.vpc_endpoint_monitoring}")
                client = boto3.client(
                    'cloudwatch',
                    endpoint_url=self.vpc_endpoint_monitoring,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_MONITORING not configured, using default endpoint")
                client = boto3.client('cloudwatch', config=config)
            
            self._client_cache[cache_key] = client
        
        return self._client_cache[cache_key]
    
    @lru_cache(maxsize=10)
    def get_lambda_client(self) -> boto3.client:
        """
        Get Lambda client configured for VPC endpoint
        
        Returns:
            boto3.client: Configured Lambda client
        """
        cache_key = 'lambda'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('lambda')
            
            if self.vpc_endpoint_lambda:
                logger.info(f"Creating Lambda client with VPC endpoint: {self.vpc_endpoint_lambda}")
                client = boto3.client(
                    'lambda',
                    endpoint_url=self.vpc_endpoint_lambda,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_LAMBDA not configured, using default endpoint")
                client = boto3.client('lambda', config=config)
            
            self._client_cache[cache_key] = client
        
        return self._client_cache[cache_key]
    
    @lru_cache(maxsize=10)
    def get_sts_client(self) -> boto3.client:
        """
        Get STS client configured for VPC endpoint
        
        Returns:
            boto3.client: Configured STS client
        """
        cache_key = 'sts'
        
        if cache_key not in self._client_cache:
            config = self._get_service_config('sts')
            
            if self.vpc_endpoint_sts:
                logger.info(f"Creating STS client with VPC endpoint: {self.vpc_endpoint_sts}")
                client = boto3.client(
                    'sts',
                    endpoint_url=self.vpc_endpoint_sts,
                    config=config
                )
            else:
                logger.warning("VPC_ENDPOINT_STS not configured, using default endpoint")
                client = boto3.client('sts', config=config)
            
            self._client_cache[cache_key] = client
        
        return self._client_cache[cache_key]
    
    def _get_service_config(self, service_name: str) -> Config:
        """
        Get service-specific configuration optimized for VPC endpoints
        
        Args:
            service_name: Name of the AWS service
            
        Returns:
            Config: Service-specific boto3 configuration
        """
        # Service-specific timeout and retry configurations
        service_configs = {
            'secretsmanager': {
                'read_timeout': 20,
                'connect_timeout': 5,
                'retries': {'max_attempts': 3, 'mode': 'adaptive'}
            },
            'dynamodb': {
                'read_timeout': 30,
                'connect_timeout': 5,
                'retries': {'max_attempts': 3, 'mode': 'adaptive'}
            },
            'logs': {
                'read_timeout': 25,
                'connect_timeout': 5,
                'retries': {'max_attempts': 3, 'mode': 'adaptive'}
            },
            'cloudwatch': {
                'read_timeout': 25,
                'connect_timeout': 5,
                'retries': {'max_attempts': 3, 'mode': 'adaptive'}
            },
            'lambda': {
                'read_timeout': 60,  # Lambda invocations can take longer
                'connect_timeout': 10,
                'retries': {'max_attempts': 2, 'mode': 'adaptive'}
            },
            'sts': {
                'read_timeout': 15,
                'connect_timeout': 5,
                'retries': {'max_attempts': 3, 'mode': 'adaptive'}
            }
        }
        
        config_params = service_configs.get(service_name, {
            'read_timeout': 30,
            'connect_timeout': 10,
            'retries': {'max_attempts': 3, 'mode': 'adaptive'}
        })
        
        return Config(
            region_name=os.environ.get('AWS_REGION', 'us-gov-west-1'),
            max_pool_connections=50,
            **config_params
        )
    
    def test_vpc_endpoint_connectivity(self) -> Dict[str, Any]:
        """
        Test connectivity to all configured VPC endpoints
        
        Returns:
            Dict[str, Any]: Test results for each service
        """
        test_results = {
            'timestamp': time.time(),
            'tests': {}
        }
        
        # Test Secrets Manager
        try:
            secrets_client = self.get_secrets_client()
            start_time = time.time()
            secrets_client.list_secrets(MaxResults=1)
            latency = (time.time() - start_time) * 1000
            test_results['tests']['secretsmanager'] = {
                'status': 'SUCCESS',
                'latency_ms': round(latency, 2),
                'endpoint': self.vpc_endpoint_secrets or 'default'
            }
        except Exception as e:
            test_results['tests']['secretsmanager'] = {
                'status': 'FAILED',
                'error': str(e),
                'endpoint': self.vpc_endpoint_secrets or 'default'
            }
        
        # Test DynamoDB
        try:
            dynamodb_client = self.get_dynamodb_client()
            start_time = time.time()
            dynamodb_client.list_tables(Limit=1)
            latency = (time.time() - start_time) * 1000
            test_results['tests']['dynamodb'] = {
                'status': 'SUCCESS',
                'latency_ms': round(latency, 2),
                'endpoint': self.vpc_endpoint_dynamodb or 'default'
            }
        except Exception as e:
            test_results['tests']['dynamodb'] = {
                'status': 'FAILED',
                'error': str(e),
                'endpoint': self.vpc_endpoint_dynamodb or 'default'
            }
        
        # Test CloudWatch Logs
        try:
            logs_client = self.get_logs_client()
            start_time = time.time()
            logs_client.describe_log_groups(limit=1)
            latency = (time.time() - start_time) * 1000
            test_results['tests']['logs'] = {
                'status': 'SUCCESS',
                'latency_ms': round(latency, 2),
                'endpoint': self.vpc_endpoint_logs or 'default'
            }
        except Exception as e:
            test_results['tests']['logs'] = {
                'status': 'FAILED',
                'error': str(e),
                'endpoint': self.vpc_endpoint_logs or 'default'
            }
        
        # Test CloudWatch
        try:
            cloudwatch_client = self.get_cloudwatch_client()
            start_time = time.time()
            cloudwatch_client.list_metrics(MaxRecords=1)
            latency = (time.time() - start_time) * 1000
            test_results['tests']['cloudwatch'] = {
                'status': 'SUCCESS',
                'latency_ms': round(latency, 2),
                'endpoint': self.vpc_endpoint_monitoring or 'default'
            }
        except Exception as e:
            test_results['tests']['cloudwatch'] = {
                'status': 'FAILED',
                'error': str(e),
                'endpoint': self.vpc_endpoint_monitoring or 'default'
            }
        
        # Test STS
        try:
            sts_client = self.get_sts_client()
            start_time = time.time()
            sts_client.get_caller_identity()
            latency = (time.time() - start_time) * 1000
            test_results['tests']['sts'] = {
                'status': 'SUCCESS',
                'latency_ms': round(latency, 2),
                'endpoint': self.vpc_endpoint_sts or 'default'
            }
        except Exception as e:
            test_results['tests']['sts'] = {
                'status': 'FAILED',
                'error': str(e),
                'endpoint': self.vpc_endpoint_sts or 'default'
            }
        
        # Calculate overall health
        successful_tests = sum(1 for test in test_results['tests'].values() if test['status'] == 'SUCCESS')
        total_tests = len(test_results['tests'])
        test_results['overall_health'] = {
            'status': 'HEALTHY' if successful_tests == total_tests else 'DEGRADED' if successful_tests > 0 else 'UNHEALTHY',
            'successful_tests': successful_tests,
            'total_tests': total_tests,
            'success_rate': round((successful_tests / total_tests) * 100, 2) if total_tests > 0 else 0
        }
        
        return test_results
    
    def clear_cache(self):
        """Clear the client cache to force recreation of clients"""
        self._client_cache.clear()
        # Clear LRU caches
        self.get_secrets_client.cache_clear()
        self.get_dynamodb_resource.cache_clear()
        self.get_dynamodb_client.cache_clear()
        self.get_logs_client.cache_clear()
        self.get_cloudwatch_client.cache_clear()
        self.get_lambda_client.cache_clear()
        self.get_sts_client.cache_clear()
        logger.info("VPC endpoint client cache cleared")


class RetryableVPCEndpointClient:
    """
    Wrapper class that adds retry logic with exponential backoff for VPC endpoint calls
    """
    
    def __init__(self, client, service_name: str, max_retries: int = 3):
        self.client = client
        self.service_name = service_name
        self.max_retries = max_retries
    
    def call_with_retry(self, method_name: str, *args, **kwargs):
        """
        Call a client method with retry logic and exponential backoff
        
        Args:
            method_name: Name of the client method to call
            *args: Positional arguments for the method
            **kwargs: Keyword arguments for the method
            
        Returns:
            The result of the method call
            
        Raises:
            Exception: If all retry attempts fail
        """
        method = getattr(self.client, method_name)
        last_exception = None
        
        for attempt in range(self.max_retries):
            try:
                return method(*args, **kwargs)
            except (ClientError, EndpointConnectionError) as e:
                last_exception = e
                
                if attempt < self.max_retries - 1:
                    # Calculate exponential backoff delay
                    delay = 0.1 * (2 ** attempt)
                    logger.warning(
                        f"VPC endpoint call failed for {self.service_name}.{method_name} "
                        f"(attempt {attempt + 1}/{self.max_retries}), retrying in {delay}s: {str(e)}"
                    )
                    time.sleep(delay)
                else:
                    logger.error(
                        f"All retry attempts failed for {self.service_name}.{method_name}: {str(e)}"
                    )
        
        # If we get here, all retries failed
        raise last_exception


def create_vpc_endpoint_clients() -> VPCEndpointClientManager:
    """
    Factory function to create a VPC endpoint client manager
    
    Returns:
        VPCEndpointClientManager: Configured client manager
    """
    return VPCEndpointClientManager()


def test_all_vpc_endpoints() -> Dict[str, Any]:
    """
    Test connectivity to all VPC endpoints
    
    Returns:
        Dict[str, Any]: Test results
    """
    client_manager = create_vpc_endpoint_clients()
    return client_manager.test_vpc_endpoint_connectivity()


# Global client manager instance for Lambda function reuse
_global_client_manager = None

def get_global_client_manager() -> VPCEndpointClientManager:
    """
    Get the global client manager instance (singleton pattern for Lambda)
    
    Returns:
        VPCEndpointClientManager: Global client manager instance
    """
    global _global_client_manager
    if _global_client_manager is None:
        _global_client_manager = VPCEndpointClientManager()
    return _global_client_manager