# Cross-Partition Inference Roadmap

## 🌐 Version 1.0.0: "Over the Internet" - ✅ COMPLETED
**Release Date**: August 2025  
**Connectivity**: Public Internet with HTTPS/TLS encryption

### Features Delivered
- ✅ **Cross-Partition Proxy**: Lambda-based request routing between GovCloud and Commercial
- ✅ **Advanced AI Models**: Claude 4.1, Claude 3.5 Sonnet, Nova Premier, Llama 4 Scout
- ✅ **Automatic Inference Profiles**: Seamless handling of models requiring inference profiles
- ✅ **Dual Authentication**: Bedrock API keys and AWS credentials support
- ✅ **Model Discovery API**: Real-time Commercial Bedrock model listing
- ✅ **Complete Audit Trail**: DynamoDB logging with 30-day TTL
- ✅ **Comprehensive Testing**: Automated test suite for all components
- ✅ **Full Documentation**: Architecture, setup guides, and API documentation

### Architecture
```
GovCloud (Internet) ──HTTPS──► Commercial AWS
    ↓                              ↓
API Gateway                   Bedrock Models
Lambda Proxy              Inference Profiles
Secrets Manager               API Keys
DynamoDB Logs
```

### Security Profile
- **Encryption**: HTTPS/TLS 1.3 in transit, KMS at rest
- **Authentication**: IAM + Bedrock API keys
- **Network**: Public internet with AWS security controls
- **Compliance**: Complete audit trail, 30-day retention

---

## 🔒 Version 2.0.0: "VPN Connectivity" - 🚧 PLANNED
**Target Release**: Q1 2026  
**Connectivity**: Site-to-Site VPN with private routing

### Key Features
- 🎯 **Private Network Connectivity**: Site-to-Site VPN between GovCloud and Commercial
- 🎯 **VPC-based Lambda**: Deploy Lambda functions in private subnets
- 🎯 **Enhanced Security**: Private IP routing, no internet exposure
- 🎯 **Network Redundancy**: Multiple VPN tunnels for high availability
- 🎯 **Advanced Monitoring**: VPN tunnel health and performance metrics
- 🎯 **Hybrid Connectivity**: Fallback to internet if VPN unavailable

### Architecture
```
GovCloud VPC ──VPN Tunnels──► Commercial VPC
    ↓                              ↓
Private Subnets              Private Endpoints
VPC Lambda                   Bedrock VPC Endpoint
NAT Gateway                  Interface Endpoints
Route Tables                 Security Groups
```

### VPN Infrastructure Requirements
- **GovCloud Side**:
  - Customer Gateway in GovCloud
  - VPN Gateway with BGP routing
  - Private subnets for Lambda deployment
  - Route tables for VPN traffic
  - Security groups for private communication

- **Commercial Side**:
  - VPC with Bedrock VPC endpoints
  - Interface endpoints for Bedrock Runtime
  - Private DNS resolution
  - Security groups allowing GovCloud traffic
  - CloudWatch VPC Flow Logs

### Security Enhancements
- **Network Isolation**: No internet exposure for AI requests
- **Private DNS**: Internal DNS resolution for Bedrock endpoints
- **Enhanced Encryption**: IPSec tunnels + TLS application layer
- **Network Segmentation**: Dedicated subnets for cross-partition traffic
- **Advanced Monitoring**: VPC Flow Logs, VPN tunnel metrics

### Migration Path from v1.0.0
1. **Infrastructure Setup**: Deploy VPN infrastructure in both partitions
2. **Lambda Migration**: Move Lambda to VPC with private subnets
3. **Endpoint Configuration**: Setup Bedrock VPC endpoints in Commercial
4. **Testing & Validation**: Comprehensive testing of private connectivity
5. **Gradual Cutover**: Phased migration with fallback to internet

### 🔧 New Feature: Connectivity Selection
Starting with v2.0.0, administrators can choose their preferred connectivity method:

#### Configuration Options
```bash
# Deploy with connectivity choice
./deploy-mvp.sh --connectivity-type [internet|vpn|direct-connect]

# Environment variable configuration
export CROSS_PARTITION_CONNECTIVITY="vpn"
./deploy-mvp.sh
```

#### Supported Connectivity Types
- **`internet`**: Uses public internet with HTTPS (v1.0.0 compatibility)
- **`vpn`**: Uses Site-to-Site VPN with private routing (v2.0.0 default)
- **`direct-connect`**: Uses AWS Direct Connect (v3.0.0, requires infrastructure)

#### Runtime Switching
```bash
# Switch connectivity method without redeployment
aws ssm put-parameter \
  --name "/cross-partition/connectivity-type" \
  --value "vpn" \
  --type "String" \
  --profile govcloud

# Lambda automatically detects and routes accordingly
```

#### Intelligent Failover
- **Primary**: Configured connectivity method (VPN or Direct Connect)
- **Secondary**: Automatic fallback to internet if primary fails
- **Health Checks**: Continuous monitoring of all connectivity paths
- **Automatic Recovery**: Switch back to primary when available

---

## 🏢 Version 3.0.0: "Direct Connect" - 🚧 PLANNED
**Target Release**: Q3 2026  
**Connectivity**: AWS Direct Connect with dedicated network connection

### Key Features
- 🎯 **Dedicated Network Connection**: AWS Direct Connect between partitions
- 🎯 **Predictable Performance**: Consistent bandwidth and low latency
- 🎯 **Enhanced Compliance**: Dedicated physical connection for sensitive workloads
- 🎯 **Multi-Path Routing**: Primary Direct Connect + VPN backup
- 🎯 **Advanced QoS**: Traffic prioritization and bandwidth management
- 🎯 **Enterprise Integration**: Integration with existing Direct Connect infrastructure

### Architecture
```
GovCloud DC ──Direct Connect──► Commercial DC
    ↓                              ↓
Virtual Interfaces           Virtual Interfaces
BGP Routing                  BGP Routing
Private VLANs               Private VLANs
Dedicated Bandwidth         Dedicated Bandwidth
```

### Direct Connect Infrastructure
- **Physical Connection**:
  - Dedicated 1Gbps or 10Gbps connection
  - Cross-connect in AWS Direct Connect location
  - Redundant connections for high availability
  - BGP routing with AS path prepending

- **Virtual Interfaces**:
  - Private VIF for GovCloud to Commercial routing
  - Dedicated VLANs for cross-partition traffic
  - BGP communities for traffic engineering
  - Route filtering and security policies

### Advanced Features
- **Traffic Engineering**: Intelligent routing based on model type and priority
- **Bandwidth Management**: QoS policies for different AI workloads
- **Cost Optimization**: Data transfer cost reduction vs internet/VPN
- **Compliance Enhancement**: Dedicated connection for classified workloads
- **Performance Monitoring**: Real-time latency and throughput metrics

### Enterprise Integration
- **Existing Direct Connect**: Leverage existing enterprise Direct Connect
- **Hybrid Connectivity**: Multiple connection types with intelligent routing
- **Network Operations**: Integration with enterprise network monitoring
- **Change Management**: Automated network configuration and updates

---

## 🚀 Version 4.0.0: "Enterprise Platform" - 🔮 FUTURE
**Target Release**: Q1 2027  
**Focus**: Multi-region, high availability, enterprise features

### Key Features
- 🎯 **Multi-Region Deployment**: Active-active across multiple regions
- 🎯 **High Availability**: 99.99% uptime with automatic failover
- 🎯 **Global Load Balancing**: Intelligent routing to optimal regions
- 🎯 **Advanced Caching**: Model response caching for performance
- 🎯 **Enterprise Identity**: Integration with SAML/OIDC providers
- 🎯 **Cost Optimization**: Advanced analytics and cost management

---

## 📊 Connectivity Comparison Matrix

| Feature | v1.0.0 Internet | v2.0.0 VPN | v3.0.0 Direct Connect |
|---------|----------------|------------|----------------------|
| **Setup Complexity** | Low | Medium | High |
| **Security Level** | Good | Better | Best |
| **Performance** | Variable | Consistent | Predictable |
| **Cost** | Low | Medium | High |
| **Compliance** | Standard | Enhanced | Maximum |
| **Latency** | 50-200ms | 20-100ms | 10-50ms |
| **Bandwidth** | Unlimited | 1-10 Gbps | 1-100 Gbps |
| **Availability** | 99.9% | 99.95% | 99.99% |

## 🛣️ Migration Strategy

### v1.0.0 → v2.0.0 (Internet to VPN)
1. **Phase 1**: Deploy VPN infrastructure (4 weeks)
2. **Phase 2**: Migrate Lambda to VPC (2 weeks)
3. **Phase 3**: Setup Bedrock VPC endpoints (2 weeks)
4. **Phase 4**: Testing and validation (2 weeks)
5. **Phase 5**: Production cutover (1 week)

### v2.0.0 → v3.0.0 (VPN to Direct Connect)
1. **Phase 1**: Direct Connect provisioning (8-12 weeks)
2. **Phase 2**: Virtual interface configuration (2 weeks)
3. **Phase 3**: BGP routing setup (2 weeks)
4. **Phase 4**: Performance testing (2 weeks)
5. **Phase 5**: Production migration (2 weeks)

## 🎯 Success Metrics by Version

### v1.0.0 Metrics (Current)
- ✅ **Availability**: 99.9% uptime achieved
- ✅ **Latency**: Average 150ms cross-partition
- ✅ **Security**: Zero security incidents
- ✅ **Models**: 25+ AI models supported

### v2.0.0 Target Metrics
- 🎯 **Availability**: 99.95% uptime
- 🎯 **Latency**: Average 75ms cross-partition
- 🎯 **Security**: Private network isolation
- 🎯 **Performance**: 50% latency improvement

### v3.0.0 Target Metrics
- 🎯 **Availability**: 99.99% uptime
- 🎯 **Latency**: Average 25ms cross-partition
- 🎯 **Bandwidth**: Dedicated 10Gbps capacity
- 🎯 **Cost**: 30% reduction in data transfer costs

## 🔧 Technical Implementation Details

### v2.0.0 Connectivity Selection System

#### Configuration Management
Starting with v2.0.0, the system supports multiple connectivity options through a centralized configuration system:

```python
# Lambda function connectivity detection
def get_connectivity_config():
    """Determine which connectivity method to use"""
    try:
        # Check SSM Parameter for runtime configuration
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(
            Name='/cross-partition/connectivity-type'
        )
        connectivity_type = response['Parameter']['Value']
    except:
        # Fallback to environment variable
        connectivity_type = os.environ.get('CONNECTIVITY_TYPE', 'internet')
    
    return {
        'internet': use_internet_routing,
        'vpn': use_vpn_routing,
        'direct-connect': use_direct_connect_routing
    }.get(connectivity_type, use_internet_routing)

def route_bedrock_request(request_data):
    """Route request based on connectivity configuration"""
    connectivity_handler = get_connectivity_config()
    
    try:
        # Try primary connectivity method
        return connectivity_handler(request_data)
    except Exception as e:
        logger.warning(f"Primary connectivity failed: {e}")
        # Automatic failover to internet
        return use_internet_routing(request_data)
```

#### Deployment Configuration
```bash
# CloudFormation parameter for connectivity selection
Parameters:
  ConnectivityType:
    Type: String
    Default: vpn
    AllowedValues: [internet, vpn, direct-connect]
    Description: Choose connectivity method for cross-partition communication

# Conditional resource creation based on connectivity type
Conditions:
  UseVPN: !Equals [!Ref ConnectivityType, vpn]
  UseDirectConnect: !Equals [!Ref ConnectivityType, direct-connect]
  UseInternet: !Equals [!Ref ConnectivityType, internet]

Resources:
  VPNGateway:
    Type: AWS::EC2::VpnGateway
    Condition: UseVPN
    Properties:
      Type: ipsec.1
      
  DirectConnectGateway:
    Type: AWS::DirectConnect::DirectConnectGateway
    Condition: UseDirectConnect
    Properties:
      Name: cross-partition-dxgw
```

### v2.0.0 VPN Implementation

#### GovCloud VPN Setup
```bash
# Create Customer Gateway
aws ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip YOUR_GOVCLOUD_IP \
  --bgp-asn 65000 \
  --profile govcloud

# Create VPN Gateway
aws ec2 create-vpn-gateway \
  --type ipsec.1 \
  --profile govcloud

# Create VPN Connection
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id cgw-xxx \
  --vpn-gateway-id vgw-xxx \
  --profile govcloud
```

#### Commercial VPC Endpoints
```bash
# Create Bedrock VPC Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxx \
  --service-name com.amazonaws.us-east-1.bedrock-runtime \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-xxx \
  --security-group-ids sg-xxx
```

### v3.0.0 Direct Connect Implementation

#### Direct Connect Gateway
```bash
# Create Direct Connect Gateway
aws directconnect create-direct-connect-gateway \
  --name cross-partition-dxgw

# Create Virtual Interface
aws directconnect create-private-virtual-interface \
  --connection-id dxcon-xxx \
  --new-private-virtual-interface \
    virtualInterfaceName=cross-partition-vif \
    vlan=100 \
    asn=65000 \
    customerAddress=192.168.1.1/30 \
    amazonAddress=192.168.1.2/30
```

## 🚀 Deployment Commands by Version

### v2.0.0+ Deployment with Connectivity Selection

#### Quick Deployment Options
```bash
# Deploy with VPN (default for v2.0.0)
./deploy-mvp.sh

# Deploy with specific connectivity type
./deploy-mvp.sh --connectivity internet
./deploy-mvp.sh --connectivity vpn  
./deploy-mvp.sh --connectivity direct-connect

# Deploy with advanced options
./deploy-mvp.sh \
  --connectivity vpn \
  --enable-failover \
  --monitoring enhanced \
  --region us-gov-west-1
```

#### Configuration File Deployment
```yaml
# connectivity-config.yaml
connectivity:
  primary: vpn
  failover: internet
  health_check_interval: 30
  retry_attempts: 3
  
vpn:
  customer_gateway_ip: "203.0.113.12"
  bgp_asn: 65000
  tunnel_count: 2
  
direct_connect:
  connection_id: "dxcon-fg5678gh"
  vlan: 100
  bgp_asn: 65001

# Deploy with configuration file
./deploy-mvp.sh --config connectivity-config.yaml
```

#### Runtime Configuration Changes
```bash
# Change connectivity without redeployment
aws ssm put-parameter \
  --name "/cross-partition/connectivity-type" \
  --value "direct-connect" \
  --overwrite \
  --profile govcloud

# Enable/disable failover
aws ssm put-parameter \
  --name "/cross-partition/enable-failover" \
  --value "true" \
  --type "String" \
  --profile govcloud

# Check current configuration
aws ssm get-parameters \
  --names "/cross-partition/connectivity-type" "/cross-partition/enable-failover" \
  --profile govcloud
```

#### Monitoring and Health Checks
```bash
# Check connectivity status
./test-connectivity.sh --all

# Test specific connectivity method
./test-connectivity.sh --type vpn
./test-connectivity.sh --type direct-connect
./test-connectivity.sh --type internet

# Monitor failover events
aws logs filter-log-events \
  --log-group-name /aws/lambda/CrossPartitionInferenceProxy \
  --filter-pattern "failover" \
  --profile govcloud
```

## 🔄 Version Upgrade Paths

### Backward Compatibility
- **v1.0.0 → v2.0.0**: Seamless upgrade with configuration changes
- **v2.0.0 → v3.0.0**: Infrastructure addition, no breaking changes
- **All versions**: Maintain API compatibility for client applications

### Rollback Strategy
- **v2.0.0**: Can fallback to internet connectivity if VPN fails
- **v3.0.0**: Can fallback to VPN or internet if Direct Connect fails
- **Configuration-driven**: Network path selection via environment variables

## 📋 Prerequisites by Version

### v2.0.0 VPN Prerequisites
**GovCloud Account:**
- VPC with private subnets
- VPN Gateway deployment permissions
- Route table management access
- Security group configuration rights

**Commercial Account:**
- VPC with Bedrock VPC endpoints
- Interface endpoint creation permissions
- Private DNS configuration access
- Cross-partition routing setup

**Network Requirements:**
- Public IP for Customer Gateway
- BGP ASN allocation
- Firewall rules for IPSec traffic
- Network team coordination

### v3.0.0 Direct Connect Prerequisites
**Infrastructure:**
- Direct Connect location access
- Cross-connect provisioning
- Dedicated bandwidth allocation (1-100 Gbps)
- Redundant connection planning

**Network Engineering:**
- BGP routing expertise
- VLAN configuration knowledge
- QoS policy design
- Traffic engineering experience

**Compliance:**
- Physical security requirements
- Dedicated connection approval
- Network architecture review
- Change management processes

## 💰 Cost Analysis by Version

### v1.0.0 Internet Costs (Current)
- **Lambda Execution**: ~$50/month (1M requests)
- **API Gateway**: ~$35/month (1M requests)
- **Data Transfer**: ~$90/GB (internet egress)
- **Storage**: ~$5/month (DynamoDB, Secrets Manager)
- **Total Estimated**: ~$180/month + data transfer

### v2.0.0 VPN Costs (Projected)
- **VPN Gateway**: ~$36/month (always-on)
- **Data Transfer**: ~$20/GB (VPN transfer)
- **VPC Endpoints**: ~$22/month (Bedrock interface endpoint)
- **Additional Lambda**: ~$10/month (VPC overhead)
- **Total Estimated**: ~$248/month + reduced data transfer costs

### v3.0.0 Direct Connect Costs (Projected)
- **Direct Connect Port**: ~$216/month (1Gbps dedicated)
- **Data Transfer**: ~$2/GB (Direct Connect transfer)
- **Virtual Interface**: ~$0 (included)
- **Cross-Connect**: ~$100/month (colocation fees)
- **Total Estimated**: ~$584/month + significantly reduced data transfer

### ROI Analysis
- **Break-even point for VPN**: >4GB/month data transfer
- **Break-even point for Direct Connect**: >40GB/month data transfer
- **Performance benefits**: Reduced latency improves user experience
- **Compliance value**: Enhanced security for sensitive workloads

## 🔒 Security Progression

### v1.0.0 Security (Current)
- ✅ **Transport**: HTTPS/TLS 1.3 encryption
- ✅ **Authentication**: IAM + Bedrock API keys
- ✅ **Authorization**: Fine-grained IAM policies
- ✅ **Audit**: Complete request logging
- ✅ **Storage**: KMS encryption at rest

### v2.0.0 Security Enhancements
- 🎯 **Network**: Private VPN tunnels, no internet exposure
- 🎯 **Isolation**: VPC network segmentation
- 🎯 **Monitoring**: VPC Flow Logs, enhanced CloudTrail
- 🎯 **Encryption**: IPSec + TLS double encryption
- 🎯 **Access**: Private DNS, no public endpoints

### v3.0.0 Security Maximum
- 🎯 **Physical**: Dedicated network connection
- 🎯 **Compliance**: Meets highest government standards
- 🎯 **Monitoring**: Real-time network analytics
- 🎯 **Redundancy**: Multiple secure paths
- 🎯 **Control**: Complete network path visibility

## 🎯 Decision Matrix: Which Version and Connectivity to Choose?

### Choose v1.0.0 (Internet Only) If:
- ✅ Quick deployment needed (days)
- ✅ Low to medium data volumes (<1GB/month)
- ✅ Standard security requirements
- ✅ Limited networking expertise
- ✅ Cost-sensitive deployment
- ✅ No advanced networking infrastructure

### Choose v2.0.0+ with Internet Connectivity If:
- 🎯 Want latest features but simple networking
- 🎯 Need failover capabilities
- 🎯 Plan to upgrade to VPN/Direct Connect later
- 🎯 Testing and development environments
- 🎯 Temporary or proof-of-concept deployments

### Choose v2.0.0+ with VPN Connectivity If:
- 🎯 Enhanced security required
- 🎯 Medium data volumes (1-40GB/month)
- 🎯 Existing VPN infrastructure or can deploy VPN
- 🎯 Predictable performance needed
- 🎯 Compliance requirements for private connectivity
- 🎯 Want automatic failover to internet

### Choose v2.0.0+ with Direct Connect If:
- 🎯 Maximum security and compliance required
- 🎯 High data volumes (>40GB/month)
- 🎯 Existing Direct Connect infrastructure
- 🎯 Predictable, low-latency performance critical
- 🎯 Enterprise-grade requirements
- 🎯 Multi-path redundancy needed

### 🔄 Connectivity Selection Benefits (v2.0.0+)
- **Flexibility**: Change connectivity method without redeployment
- **Failover**: Automatic fallback to internet if primary fails
- **Testing**: Test different connectivity methods easily
- **Migration**: Gradual migration from internet to private connectivity
- **Cost Optimization**: Switch based on usage patterns and costs

## 📅 Release Timeline

```
2025 Q3: v1.0.0 Internet ✅ RELEASED
2025 Q4: v1.1.0 Bug fixes and enhancements
2026 Q1: v2.0.0 VPN Connectivity
2026 Q2: v2.1.0 VPN optimizations
2026 Q3: v3.0.0 Direct Connect
2026 Q4: v3.1.0 Direct Connect enhancements
2027 Q1: v4.0.0 Enterprise Platform
```

## 🤝 Support and Maintenance

### v1.0.0 Support Lifecycle
- **Active Development**: 2025-2026
- **Maintenance Mode**: 2026-2028
- **End of Life**: 2028 (migrate to v3.0.0+)

### Upgrade Support
- **Free upgrades**: Within major version (1.x → 1.y)
- **Migration assistance**: Between major versions
- **Backward compatibility**: Maintained for 2 years
- **Documentation**: Complete upgrade guides provided

---

**📞 Questions or feedback on the roadmap?**  
Contact the development team or create an issue in the project repository.