# VPN Connectivity Design Document

## Overview

This design document outlines the Site-to-Site VPN architecture for secure cross-partition AI inference between AWS GovCloud and Commercial partitions. This solution builds upon the existing internet-based MVP by adding network-level security through encrypted VPN tunnels and complete private connectivity using VPC endpoints.

## Architecture

### High-Level Architecture

The VPN-based solution creates secure, encrypted tunnels between AWS partitions while ensuring all AWS service communications remain private through comprehensive VPC endpoint deployment.

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                AWS GovCloud                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                            VPC (10.0.0.0/16)                                │   │
│  │                                                                             │   │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐        │   │
│  │  │   API Gateway   │    │  Private Subnet │    │  VPC Endpoints  │        │   │
│  │  │                 │    │                 │    │                 │        │   │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │    │  • Secrets Mgr  │        │   │
│  │  │  │ REST API  │  │    │  │  Lambda   │  │    │  • DynamoDB     │        │   │
│  │  │  │ /bedrock  │  │    │  │ Function  │  │    │  • CloudWatch   │        │   │
│  │  │  └───────────┘  │    │  └───────────┘  │    │                 │        │   │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘        │   │
│  │                                   │                                        │   │
│  │                                   │                                        │   │
│  │  ┌─────────────────────────────────┼─────────────────────────────────┐    │   │
│  │  │              VPN Gateway        │                                 │    │   │
│  │  │                                 │                                 │    │   │
│  │  │  ┌─────────────┐  ┌─────────────┐                                │    │   │
│  │  │  │   Tunnel 1  │  │   Tunnel 2  │  (Redundant for HA)           │    │   │
│  │  │  │  IPSec/BGP  │  │  IPSec/BGP  │                                │    │   │
│  │  │  └─────────────┘  └─────────────┘                                │    │   │
│  │  └─────────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ Encrypted VPN Tunnel
                                        │ (IPSec + BGP Routing)
                                        │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS Commercial                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                           VPC (172.16.0.0/16)                               │   │
│  │                                                                             │   │
│  │  ┌─────────────────────────────────┐    ┌─────────────────┐                │   │
│  │  │              VPN Gateway        │    │  VPC Endpoints  │                │   │
│  │  │                                 │    │                 │                │   │
│  │  │  ┌─────────────┐  ┌─────────────┐    │  • Bedrock      │                │   │
│  │  │  │   Tunnel 1  │  │   Tunnel 2  │    │  • CloudWatch   │                │   │
│  │  │  │  IPSec/BGP  │  │  IPSec/BGP  │    │                 │                │   │
│  │  │  └─────────────┘  └─────────────┘    └─────────────────┘                │   │
│  │  └─────────────────────────────────┘                                       │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### GovCloud Components

#### 1. VPC Infrastructure
- **VPC CIDR**: 10.0.0.0/16
- **Private Subnet**: 10.0.1.0/24 (Lambda deployment)
- **VPN Subnet**: 10.0.2.0/24 (VPN Gateway)
- **No Internet Gateway**: Complete private connectivity

#### 2. API Gateway
- **Type**: REST API with Lambda proxy integration
- **Authentication**: IAM-based with API keys
- **Endpoints**: Same as existing MVP solution
- **Location**: Public subnet (customer-facing)

#### 3. Lambda Function (Enhanced)
- **Runtime**: Python 3.11
- **Deployment**: Private subnet with VPC configuration
- **Memory**: 512MB (optimized for VPC cold starts)
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `VPC_ENDPOINT_SECRETS`: Secrets Manager VPC endpoint URL
  - `VPC_ENDPOINT_DYNAMODB`: DynamoDB VPC endpoint URL
  - `COMMERCIAL_BEDROCK_ENDPOINT`: Private IP for cross-partition access

#### 4. VPC Endpoints (GovCloud)
- **Secrets Manager**: com.amazonaws.vpce.us-gov-west-1.secretsmanager
- **DynamoDB**: com.amazonaws.vpce.us-gov-west-1.dynamodb
- **CloudWatch Logs**: com.amazonaws.vpce.us-gov-west-1.logs
- **CloudWatch Metrics**: com.amazonaws.vpce.us-gov-west-1.monitoring

#### 5. VPN Gateway
- **Type**: AWS VPN Gateway with BGP routing
- **Redundancy**: Dual tunnels for high availability
- **Routing**: Dynamic BGP for automatic failover
- **Encryption**: IPSec with AES-256

### Commercial Components

#### 1. VPC Infrastructure
- **VPC CIDR**: 172.16.0.0/16
- **Private Subnet**: 172.16.1.0/24
- **VPN Subnet**: 172.16.2.0/24 (VPN Gateway)
- **No Internet Gateway**: Complete private connectivity

#### 2. VPC Endpoints (Commercial)
- **Bedrock**: com.amazonaws.vpce.us-east-1.bedrock-runtime
- **CloudWatch Logs**: com.amazonaws.vpce.us-east-1.logs
- **CloudWatch Metrics**: com.amazonaws.vpce.us-east-1.monitoring

#### 3. VPN Gateway
- **Type**: AWS VPN Gateway with BGP routing
- **Redundancy**: Dual tunnels matching GovCloud
- **Routing**: Dynamic BGP for automatic failover
- **Encryption**: IPSec with AES-256

### Network Routing

#### Route Tables (GovCloud)
```
Destination         Target              Priority
10.0.0.0/16        Local               1
172.16.0.0/16      VPN Gateway         2
0.0.0.0/0          None (Blocked)      -
```

#### Route Tables (Commercial)
```
Destination         Target              Priority
172.16.0.0/16      Local               1
10.0.0.0/16        VPN Gateway         2
0.0.0.0/0          None (Blocked)      -
```

## Data Models

### VPN Configuration Model
```python
@dataclass
class VPNConfiguration:
    govcloud_vpc_id: str
    commercial_vpc_id: str
    govcloud_cidr: str = "10.0.0.0/16"
    commercial_cidr: str = "172.16.0.0/16"
    tunnel_1_psk: str
    tunnel_2_psk: str
    bgp_asn_govcloud: int = 65000
    bgp_asn_commercial: int = 65001
```

### VPC Endpoint Configuration Model
```python
@dataclass
class VPCEndpointConfig:
    service_name: str
    vpc_id: str
    subnet_ids: List[str]
    security_group_ids: List[str]
    policy_document: Optional[str] = None
    private_dns_enabled: bool = True
```

### Enhanced Request Model
```python
@dataclass
class CrossPartitionRequest:
    request_id: str
    source_partition: str = "govcloud"
    target_partition: str = "commercial"
    model_id: str
    request_body: Dict[str, Any]
    routing_method: str = "vpn"
    timestamp: datetime
    vpc_endpoint_used: bool = True
```

## Error Handling

### VPN-Specific Error Scenarios

#### 1. VPN Tunnel Failure
```python
class VPNTunnelError(Exception):
    def __init__(self, tunnel_id: str, status: str):
        self.tunnel_id = tunnel_id
        self.status = status
        super().__init__(f"VPN Tunnel {tunnel_id} failed: {status}")

def handle_vpn_failure(tunnel_status):
    if tunnel_status == "DOWN":
        # Attempt failover to backup tunnel
        return route_via_backup_tunnel()
    elif tunnel_status == "DEGRADED":
        # Log warning and continue with reduced performance
        logger.warning("VPN performance degraded")
        return continue_with_monitoring()
```

#### 2. VPC Endpoint Connectivity Issues
```python
class VPCEndpointError(Exception):
    def __init__(self, service: str, endpoint_id: str):
        self.service = service
        self.endpoint_id = endpoint_id
        super().__init__(f"VPC Endpoint {endpoint_id} for {service} unavailable")

def handle_vpc_endpoint_failure(service_name):
    # Implement circuit breaker pattern
    if circuit_breaker.is_open(service_name):
        raise ServiceUnavailableError(f"{service_name} circuit breaker open")
    
    # Retry with exponential backoff
    return retry_with_backoff(service_name)
```

#### 3. Cross-Partition Routing Failures
```python
def handle_routing_failure(destination_cidr):
    # Check route table configuration
    routes = get_route_table_entries()
    if destination_cidr not in routes:
        logger.error(f"No route to {destination_cidr}")
        raise RoutingError(f"Destination {destination_cidr} unreachable")
    
    # Verify VPN Gateway status
    vpn_status = check_vpn_gateway_status()
    if vpn_status != "available":
        raise VPNGatewayError(f"VPN Gateway status: {vpn_status}")
```

## Testing Strategy

### Unit Testing

#### VPN Configuration Tests
```python
def test_vpn_configuration_validation():
    config = VPNConfiguration(
        govcloud_vpc_id="vpc-12345",
        commercial_vpc_id="vpc-67890",
        tunnel_1_psk="secure-key-1",
        tunnel_2_psk="secure-key-2"
    )
    assert config.govcloud_cidr == "10.0.0.0/16"
    assert config.bgp_asn_govcloud == 65000
```

#### VPC Endpoint Tests
```python
def test_vpc_endpoint_connectivity():
    endpoint_config = VPCEndpointConfig(
        service_name="com.amazonaws.vpce.us-gov-west-1.secretsmanager",
        vpc_id="vpc-12345",
        subnet_ids=["subnet-abc123"],
        security_group_ids=["sg-def456"]
    )
    
    # Mock VPC endpoint creation and test connectivity
    with mock_vpc_endpoint(endpoint_config):
        assert test_secrets_manager_access() == True
```

### Integration Testing

#### End-to-End VPN Flow Test
```python
def test_cross_partition_vpn_flow():
    # Test complete flow through VPN tunnel
    request = {
        "modelId": "anthropic.claude-3-sonnet-20240229-v1:0",
        "body": {"messages": [{"role": "user", "content": "Hello"}]}
    }
    
    response = invoke_cross_partition_bedrock(request)
    
    assert response["statusCode"] == 200
    assert "routing_method" in response["metadata"]
    assert response["metadata"]["routing_method"] == "vpn"
```

#### VPN Failover Testing
```python
def test_vpn_tunnel_failover():
    # Simulate primary tunnel failure
    with mock_tunnel_failure("tunnel-1"):
        response = invoke_cross_partition_bedrock(test_request)
        
        # Should automatically failover to tunnel-2
        assert response["statusCode"] == 200
        assert response["metadata"]["tunnel_used"] == "tunnel-2"
```

### Performance Testing

#### Latency Benchmarking
```python
def test_vpn_latency_performance():
    latencies = []
    for _ in range(100):
        start_time = time.time()
        response = invoke_cross_partition_bedrock(test_request)
        end_time = time.time()
        latencies.append(end_time - start_time)
    
    avg_latency = sum(latencies) / len(latencies)
    assert avg_latency < 0.5  # Should be under 500ms
    
    p95_latency = sorted(latencies)[95]
    assert p95_latency < 1.0  # 95th percentile under 1 second
```

### Security Testing

#### Network Isolation Verification
```python
def test_network_isolation():
    # Verify no internet access from private subnets
    with pytest.raises(ConnectionError):
        requests.get("https://google.com", timeout=5)
    
    # Verify VPC endpoint access works
    secrets_client = boto3.client('secretsmanager')
    response = secrets_client.list_secrets()
    assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
```

#### Encryption Verification
```python
def test_vpn_encryption():
    # Capture network traffic during cross-partition call
    with network_capture() as capture:
        invoke_cross_partition_bedrock(test_request)
    
    # Verify all traffic is encrypted (no plaintext AI model data)
    packets = capture.get_packets()
    for packet in packets:
        assert not contains_plaintext_ai_data(packet)
        assert packet.is_encrypted()
```
##
 Security Considerations

### Network Security

#### Defense in Depth
- **Layer 1**: VPC isolation with no internet gateways
- **Layer 2**: Private subnets with restrictive route tables
- **Layer 3**: Security groups allowing only necessary traffic
- **Layer 4**: NACLs for additional network-level filtering
- **Layer 5**: VPC endpoints for service-specific access control

#### Encryption Standards
- **VPN Tunnels**: IPSec with AES-256-GCM encryption
- **Data in Transit**: TLS 1.3 for all API communications
- **Data at Rest**: KMS encryption for secrets and logs
- **Key Management**: AWS KMS with customer-managed keys

#### Access Controls
```python
# Security Group Rules (GovCloud Lambda)
LAMBDA_SECURITY_GROUP_RULES = [
    {
        "Type": "Egress",
        "Protocol": "HTTPS",
        "Port": 443,
        "Destination": "VPC_ENDPOINTS_CIDR",  # 10.0.3.0/24
        "Description": "Access to VPC endpoints"
    },
    {
        "Type": "Egress", 
        "Protocol": "ALL",
        "Port": "ALL",
        "Destination": "172.16.0.0/16",  # Commercial VPC
        "Description": "Cross-partition access via VPN"
    }
]

# VPC Endpoint Security Group Rules
VPC_ENDPOINT_SECURITY_GROUP_RULES = [
    {
        "Type": "Ingress",
        "Protocol": "HTTPS", 
        "Port": 443,
        "Source": "LAMBDA_SECURITY_GROUP_ID",
        "Description": "Lambda access to VPC endpoints"
    }
]
```

### Compliance and Auditing

#### Audit Trail Requirements
- **VPC Flow Logs**: All network traffic logged and analyzed
- **CloudTrail**: API calls across both partitions
- **CloudWatch**: Application and infrastructure metrics
- **Custom Logging**: Cross-partition request tracking

#### Compliance Mapping
```python
COMPLIANCE_CONTROLS = {
    "NIST_800_53": {
        "SC-8": "Transmission Confidentiality - VPN encryption",
        "SC-7": "Boundary Protection - VPC isolation", 
        "AU-2": "Audit Events - Comprehensive logging",
        "AC-3": "Access Enforcement - IAM and security groups"
    },
    "FedRAMP": {
        "Encryption": "AES-256 for VPN tunnels",
        "Network_Isolation": "Private subnets with no internet access",
        "Monitoring": "Real-time security event detection"
    }
}
```

## Performance Optimization

### Network Performance

#### Bandwidth Allocation
- **VPN Gateway**: Up to 1.25 Gbps per tunnel (2.5 Gbps total)
- **Lambda Concurrency**: Optimized for VPC cold start times
- **VPC Endpoints**: Interface endpoints for lowest latency

#### Latency Optimization
```python
# Connection pooling for cross-partition requests
class CrossPartitionConnectionPool:
    def __init__(self, max_connections=10):
        self.pool = {}
        self.max_connections = max_connections
    
    def get_connection(self, target_region):
        if target_region not in self.pool:
            self.pool[target_region] = create_bedrock_client(
                region=target_region,
                use_vpc_endpoint=True,
                connection_timeout=5,
                read_timeout=30
            )
        return self.pool[target_region]
```

#### Caching Strategy
```python
# Response caching for frequently requested models
@lru_cache(maxsize=100)
def get_model_info(model_id: str) -> Dict[str, Any]:
    """Cache model information to reduce cross-partition calls"""
    return bedrock_client.get_foundation_model(modelIdentifier=model_id)

# Connection caching for VPC endpoints
@cached_property
def vpc_endpoint_clients(self) -> Dict[str, Any]:
    """Cache VPC endpoint clients to avoid recreation"""
    return {
        'secrets': boto3.client('secretsmanager', endpoint_url=VPC_ENDPOINT_SECRETS),
        'dynamodb': boto3.client('dynamodb', endpoint_url=VPC_ENDPOINT_DYNAMODB),
        'logs': boto3.client('logs', endpoint_url=VPC_ENDPOINT_LOGS)
    }
```

### Cost Optimization

#### VPN Gateway Cost Management
- **Right-sizing**: Use appropriate VPN Gateway size for workload
- **Monitoring**: Track data transfer costs across partitions
- **Optimization**: Compress payloads to reduce transfer costs

#### VPC Endpoint Cost Optimization
```python
# Shared VPC endpoints across multiple Lambda functions
VPC_ENDPOINT_SHARING_STRATEGY = {
    "secrets_manager": {
        "shared_across": ["inference_lambda", "monitoring_lambda"],
        "cost_allocation": "proportional_by_usage"
    },
    "dynamodb": {
        "shared_across": ["inference_lambda", "audit_lambda"],
        "cost_allocation": "proportional_by_usage"  
    }
}
```

## Monitoring and Observability

### Key Metrics

#### VPN Health Metrics
```python
VPN_HEALTH_METRICS = [
    "VPN.TunnelState",           # UP/DOWN status
    "VPN.TunnelIpAddress",       # Tunnel endpoint IPs
    "VPN.PacketDropCount",       # Dropped packets
    "VPN.LatencyMetrics",        # Round-trip time
    "VPN.ThroughputMetrics"      # Data transfer rates
]
```

#### Application Performance Metrics
```python
APPLICATION_METRICS = [
    "CrossPartition.RequestLatency",     # End-to-end latency
    "CrossPartition.RequestCount",       # Total requests
    "CrossPartition.ErrorRate",          # Error percentage
    "CrossPartition.TunnelUtilization",  # Which tunnel used
    "VPCEndpoint.ResponseTime"           # VPC endpoint latency
]
```

### Alerting Strategy

#### Critical Alerts
```python
CRITICAL_ALERTS = {
    "vpn_tunnel_down": {
        "condition": "VPN.TunnelState == DOWN for > 5 minutes",
        "action": "immediate_page",
        "escalation": "network_team"
    },
    "cross_partition_failure": {
        "condition": "CrossPartition.ErrorRate > 10% for > 2 minutes", 
        "action": "immediate_alert",
        "escalation": "platform_team"
    }
}
```

#### Warning Alerts
```python
WARNING_ALERTS = {
    "high_latency": {
        "condition": "CrossPartition.RequestLatency > 2000ms for > 10 minutes",
        "action": "team_notification",
        "escalation": "performance_team"
    },
    "vpc_endpoint_slow": {
        "condition": "VPCEndpoint.ResponseTime > 1000ms for > 5 minutes",
        "action": "team_notification", 
        "escalation": "infrastructure_team"
    }
}
```

### Dashboard Configuration

#### Network Dashboard
```python
NETWORK_DASHBOARD_WIDGETS = [
    {
        "type": "line_chart",
        "title": "VPN Tunnel Status",
        "metrics": ["VPN.TunnelState", "VPN.PacketDropCount"],
        "period": "1_minute"
    },
    {
        "type": "gauge",
        "title": "Cross-Partition Latency", 
        "metric": "CrossPartition.RequestLatency",
        "thresholds": {"warning": 1000, "critical": 2000}
    }
]
```

## Deployment Strategy

### Infrastructure as Code

#### CloudFormation Template Structure
```yaml
# Main template orchestrating all components
AWSTemplateFormatVersion: '2010-09-09'
Description: 'VPN-based Cross-Partition AI Inference'

Parameters:
  GovCloudVPCCIDR:
    Type: String
    Default: '10.0.0.0/16'
  CommercialVPCCIDR:
    Type: String  
    Default: '172.16.0.0/16'

Resources:
  # Import nested stacks
  GovCloudInfrastructure:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: './govcloud-infrastructure.yaml'
      
  CommercialInfrastructure:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: './commercial-infrastructure.yaml'
      
  VPNConnectivity:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: './vpn-connectivity.yaml'
      Parameters:
        GovCloudVPCId: !GetAtt GovCloudInfrastructure.Outputs.VPCId
        CommercialVPCId: !GetAtt CommercialInfrastructure.Outputs.VPCId
```

#### Deployment Phases
1. **Phase 1**: Deploy VPC infrastructure in both partitions
2. **Phase 2**: Create VPN gateways and establish tunnels  
3. **Phase 3**: Deploy VPC endpoints in both partitions
4. **Phase 4**: Deploy Lambda functions with VPC configuration
5. **Phase 5**: Configure routing and test connectivity
6. **Phase 6**: Deploy monitoring and alerting

### Rollback Strategy

#### Automated Rollback Triggers
```python
ROLLBACK_CONDITIONS = [
    "VPN tunnel establishment fails after 30 minutes",
    "Cross-partition connectivity test fails", 
    "VPC endpoint creation fails",
    "Lambda function deployment in VPC fails",
    "Security group configuration errors"
]

def execute_rollback(failure_reason: str):
    logger.error(f"Initiating rollback due to: {failure_reason}")
    
    # Rollback sequence
    steps = [
        "delete_lambda_vpc_configuration",
        "delete_vpc_endpoints", 
        "delete_vpn_connections",
        "restore_internet_based_configuration"
    ]
    
    for step in steps:
        try:
            execute_rollback_step(step)
            logger.info(f"Rollback step completed: {step}")
        except Exception as e:
            logger.error(f"Rollback step failed: {step}, error: {e}")
            # Continue with remaining steps
```

This comprehensive design provides the foundation for implementing secure, high-performance VPN connectivity between AWS partitions while maintaining complete private connectivity through VPC endpoints.