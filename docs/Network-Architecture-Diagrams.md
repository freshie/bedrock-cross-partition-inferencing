# Network Architecture Diagrams and Flow Documentation

This document provides detailed network architecture diagrams and traffic flow documentation for the VPN connectivity solution.

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Detailed Network Topology](#detailed-network-topology)
3. [Traffic Flow Diagrams](#traffic-flow-diagrams)
4. [Security Architecture](#security-architecture)
5. [Routing Configuration](#routing-configuration)
6. [Failure Scenarios](#failure-scenarios)

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            AWS GovCloud Partition                               │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        VPC (10.0.0.0/16)                               │    │
│  │                                                                         │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │    │
│  │  │  Lambda Subnet  │    │  VPC Endpoints  │    │   VPN Subnet    │     │    │
│  │  │  (10.0.1.0/24)  │    │  (10.0.3.0/24)  │    │  (10.0.2.0/24)  │     │    │
│  │  │                 │    │                 │    │                 │     │    │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │     │    │
│  │  │  │  Lambda   │  │    │  │ Secrets   │  │    │  │    VPN    │  │     │    │
│  │  │  │ Function  │◄─┼────┼─►│ DynamoDB  │  │    │  │  Gateway  │  │     │    │
│  │  │  │           │  │    │  │CloudWatch │  │    │  │           │  │     │    │
│  │  │  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │     │    │
│  │  └─────────────────┘    └─────────────────┘    └─────────┬───────┘     │    │
│  └─────────────────────────────────────────────────────────┼─────────────┘    │
└─────────────────────────────────────────────────────────────┼─────────────────┘
                                                              │
                                                         VPN Tunnel
                                                        (IPSec Encrypted)
                                                              │
┌─────────────────────────────────────────────────────────────┼─────────────────┐
│                          AWS Commercial Partition          │                 │
│                                                             │                 │
│  ┌─────────────────────────────────────────────────────────┼─────────────┐    │
│  │                      VPC (172.16.0.0/16)               │             │    │
│  │                                                         │             │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌───────▼─────────┐   │    │
│  │  │   VPN Subnet    │    │  VPC Endpoints  │    │  Private Subnet │   │    │
│  │  │ (172.16.2.0/24) │    │ (172.16.3.0/24) │    │ (172.16.1.0/24) │   │    │
│  │  │                 │    │                 │    │   (Reserved)    │   │    │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │    │                 │   │    │
│  │  │  │    VPN    │  │    │  │  Bedrock  │  │    │                 │   │    │
│  │  │  │  Gateway  │  │    │  │CloudWatch │  │    │                 │   │    │
│  │  │  │           │  │    │  └───────────┘  │    │                 │   │    │
│  │  │  └───────────┘  │    └─────────────────┘    └─────────────────┘   │    │
│  │  └─────────────────┘                                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Detailed Network Topology

### GovCloud VPC Components

**VPC Configuration:**
- **CIDR Block**: 10.0.0.0/16
- **DNS Hostnames**: Enabled
- **DNS Resolution**: Enabled
- **Tenancy**: Default

**Subnets:**
1. **Lambda Subnet (10.0.1.0/24)**
   - **Purpose**: Lambda function deployment
   - **Type**: Private (no internet gateway)
   - **Availability Zone**: us-gov-west-1a

2. **VPN Subnet (10.0.2.0/24)**
   - **Purpose**: VPN Gateway deployment
   - **Type**: Private (no internet gateway)
   - **Availability Zone**: us-gov-west-1b

3. **VPC Endpoint Subnet (10.0.3.0/24)**
   - **Purpose**: VPC endpoint network interfaces
   - **Type**: Private (no internet gateway)
   - **Availability Zone**: us-gov-west-1a

### Commercial VPC Components

**VPC Configuration:**
- **CIDR Block**: 172.16.0.0/16
- **DNS Hostnames**: Enabled
- **DNS Resolution**: Enabled
- **Tenancy**: Default

**Subnets:**
1. **Private Subnet (172.16.1.0/24)**
   - **Purpose**: Reserved for future use
   - **Type**: Private (no internet gateway)
   - **Availability Zone**: us-east-1a

2. **VPN Subnet (172.16.2.0/24)**
   - **Purpose**: VPN Gateway deployment
   - **Type**: Private (no internet gateway)
   - **Availability Zone**: us-east-1b

3. **VPC Endpoint Subnet (172.16.3.0/24)**
   - **Purpose**: VPC endpoint network interfaces
   - **Type**: Private (no internet gateway)
   - **Availability Zone**: us-east-1a

## Traffic Flow Diagrams

### Normal Request Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   API       │    │   Lambda    │    │     VPN     │    │   Bedrock   │
│  Gateway    │    │  Function   │    │   Tunnel    │    │   Service   │
│ (External)  │    │ (GovCloud)  │    │(Encrypted)  │    │(Commercial) │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │                  │
       │ 1. HTTP Request  │                  │                  │
       ├─────────────────►│                  │                  │
       │                  │                  │                  │
       │                  │ 2. Get Secrets   │                  │
       │                  ├─────────────────►│                  │
       │                  │    (VPC Endpoint)│                  │
       │                  │                  │                  │
       │                  │ 3. Cross-Partition│                 │
       │                  │    Bedrock Call  │                  │
       │                  ├─────────────────►├─────────────────►│
       │                  │                  │                  │
       │                  │                  │ 4. AI Response   │
       │                  │◄─────────────────┼─────────────────◄│
       │                  │                  │                  │
       │                  │ 5. Log Request   │                  │
       │                  ├─────────────────►│                  │
       │                  │   (DynamoDB)     │                  │
       │                  │                  │                  │
       │ 6. HTTP Response │                  │                  │
       │◄─────────────────┤                  │                  │
       │                  │                  │                  │
```

### Detailed Packet Flow

1. **Request Initiation**
   - External client sends HTTPS request to API Gateway
   - API Gateway triggers Lambda function in GovCloud VPC

2. **Credential Retrieval**
   - Lambda function queries Secrets Manager via VPC endpoint
   - DNS resolves to VPC endpoint private IP (10.0.3.x)
   - Traffic stays within GovCloud VPC

3. **Cross-Partition Request**
   - Lambda function initiates Bedrock API call
   - Traffic routes through VPN tunnel to Commercial VPC
   - Packet flow: 10.0.1.x → VPN Gateway → IPSec Tunnel → Commercial VPC

4. **Bedrock Processing**
   - Commercial VPC receives encrypted traffic
   - VPN Gateway decrypts and forwards to Bedrock VPC endpoint
   - Bedrock processes AI inference request

5. **Response Return**
   - Bedrock response follows reverse path
   - Commercial VPC → VPN Tunnel → GovCloud VPC → Lambda

6. **Audit Logging**
   - Lambda logs request/response to DynamoDB via VPC endpoint
   - CloudWatch logs capture all function activity

## Security Architecture

### Network Security Layers

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Security Layers                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Layer 1: VPC Isolation                                                         │
│ ├─ No Internet Gateways                                                        │
│ ├─ Private Subnets Only                                                        │
│ └─ VPC Peering Disabled                                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Layer 2: Network ACLs                                                          │
│ ├─ Subnet-level Traffic Filtering                                              │
│ ├─ Stateless Packet Inspection                                                 │
│ └─ Default Deny All                                                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Layer 3: Security Groups                                                       │
│ ├─ Instance-level Firewalls                                                    │
│ ├─ Stateful Connection Tracking                                                │
│ └─ Least Privilege Rules                                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Layer 4: VPN Encryption                                                        │
│ ├─ IPSec Tunnel Encryption                                                     │
│ ├─ AES-256 Encryption                                                          │
│ └─ Perfect Forward Secrecy                                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Layer 5: Application Security                                                  │
│ ├─ IAM Role-based Access                                                       │
│ ├─ VPC Endpoint Policies                                                       │
│ └─ API Authentication                                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Security Group Rules

**Lambda Security Group (GovCloud)**
```
Inbound Rules: None (Lambda doesn't accept inbound connections)

Outbound Rules:
├─ HTTPS (443) → VPC Endpoint Security Group (AWS Services)
├─ All Traffic → 172.16.0.0/16 (Commercial VPC via VPN)
└─ DNS (53) → VPC DNS (10.0.0.2)
```

**VPC Endpoint Security Group (GovCloud)**
```
Inbound Rules:
├─ HTTPS (443) ← Lambda Security Group
└─ HTTPS (443) ← 172.16.0.0/16 (Commercial VPC via VPN)

Outbound Rules:
└─ All Traffic → 0.0.0.0/0 (AWS Service Communication)
```

**VPN Security Group (Both Partitions)**
```
Inbound Rules:
├─ UDP 500 ← 0.0.0.0/0 (IKE)
├─ UDP 4500 ← 0.0.0.0/0 (IPSec NAT-T)
└─ ESP (50) ← 0.0.0.0/0 (IPSec)

Outbound Rules:
└─ All Traffic → 0.0.0.0/0
```

## Routing Configuration

### GovCloud Route Tables

**Private Subnet Route Table**
```
Destination         Target              Status
10.0.0.0/16        Local               Active
172.16.0.0/16      VPN Gateway         Active
0.0.0.0/0          -                   (No default route)
```

**VPC Endpoint Route Table**
```
Destination         Target              Status
10.0.0.0/16        Local               Active
172.16.0.0/16      VPN Gateway         Active
```

**VPN Subnet Route Table**
```
Destination         Target              Status
10.0.0.0/16        Local               Active
172.16.0.0/16      VPN Gateway         Active
```

### Commercial Route Tables

**Private Subnet Route Table**
```
Destination         Target              Status
172.16.0.0/16      Local               Active
10.0.0.0/16        VPN Gateway         Active
0.0.0.0/0          -                   (No default route)
```

**VPC Endpoint Route Table**
```
Destination         Target              Status
172.16.0.0/16      Local               Active
10.0.0.0/16        VPN Gateway         Active
```

### BGP Configuration

**GovCloud BGP Settings**
- **Local ASN**: 65000
- **Remote ASN**: 65001
- **Advertised Routes**: 10.0.0.0/16
- **Received Routes**: 172.16.0.0/16

**Commercial BGP Settings**
- **Local ASN**: 65001
- **Remote ASN**: 65000
- **Advertised Routes**: 172.16.0.0/16
- **Received Routes**: 10.0.0.0/16

## Failure Scenarios

### Scenario 1: Primary VPN Tunnel Failure

```
Normal State:
Tunnel 1: UP (Primary)
Tunnel 2: UP (Secondary)

Failure State:
Tunnel 1: DOWN
Tunnel 2: UP (Now Primary)

Recovery:
├─ BGP automatically fails over to Tunnel 2
├─ Traffic continues with minimal interruption
├─ CloudWatch alarms trigger notifications
└─ Tunnel 1 attempts automatic recovery
```

### Scenario 2: Complete VPN Failure

```
Failure State:
Tunnel 1: DOWN
Tunnel 2: DOWN

Impact:
├─ Cross-partition requests fail
├─ Lambda functions timeout
├─ Critical alarms trigger
└─ Incident response procedures activate

Recovery Steps:
1. Check AWS Service Health
2. Verify customer-side connectivity
3. Review VPN configuration
4. Contact AWS Support if needed
5. Implement emergency procedures
```

### Scenario 3: VPC Endpoint Failure

```
Failure State:
VPC Endpoint: Unavailable

Impact:
├─ Cannot access AWS services
├─ Lambda functions fail
├─ DNS resolution issues
└─ Service degradation

Fallback:
├─ VPC endpoints automatically fail to public endpoints (if configured)
├─ Traffic routes through internet (if NAT gateway available)
└─ Manual intervention required for private-only setup
```

## Network Performance Considerations

### Latency Optimization

**Expected Latencies:**
- **Intra-VPC**: < 1ms
- **VPC Endpoint**: 2-5ms
- **Cross-Partition (VPN)**: 10-50ms
- **Bedrock API**: 100-500ms

**Optimization Strategies:**
1. **Connection Pooling**: Reuse connections to reduce setup time
2. **Response Caching**: Cache frequently requested data
3. **Payload Compression**: Reduce data transfer time
4. **Parallel Processing**: Process multiple requests concurrently

### Bandwidth Considerations

**VPN Tunnel Capacity:**
- **Maximum Bandwidth**: 1.25 Gbps per tunnel
- **Aggregate Bandwidth**: 2.5 Gbps (both tunnels)
- **Typical Usage**: < 100 Mbps for AI inference

**Monitoring Points:**
- VPN tunnel utilization
- VPC endpoint data processing
- Lambda function duration
- Cross-partition request volume

This architecture provides a secure, scalable, and resilient foundation for cross-partition AI inference while maintaining complete network isolation and compliance requirements.