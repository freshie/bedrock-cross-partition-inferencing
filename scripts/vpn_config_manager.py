#!/usr/bin/env python3
"""
VPN Configuration Manager

This module extracts CloudFormation outputs and real-time VPN status
to generate configuration files for the VPN connectivity solution.
"""

import json
import boto3
import os
import sys
from typing import Dict, Any, List, Optional
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class VPNConfigManager:
    """Manages VPN configuration extraction and generation"""
    
    def __init__(self, project_name: str = "cross-partition-inference", environment: str = "dev"):
        self.project_name = project_name
        self.environment = environment
        self.govcloud_profile = "govcloud"
        self.commercial_profile = "commercial"
        
        # Initialize AWS clients
        self.govcloud_session = None
        self.commercial_session = None
        self._initialize_sessions()
    
    def _initialize_sessions(self):
        """Initialize AWS sessions for both partitions"""
        try:
            # GovCloud session
            self.govcloud_session = boto3.Session(profile_name=self.govcloud_profile)
            logger.info(f"Initialized GovCloud session with profile: {self.govcloud_profile}")
            
            # Commercial session
            self.commercial_session = boto3.Session(profile_name=self.commercial_profile)
            logger.info(f"Initialized Commercial session with profile: {self.commercial_profile}")
            
        except Exception as e:
            logger.error(f"Failed to initialize AWS sessions: {str(e)}")
            raise
    
    def extract_cloudformation_outputs(self) -> Dict[str, Any]:
        """Extract outputs from all CloudFormation stacks"""
        
        config = {
            'govcloud': {},
            'commercial': {},
            'extraction_timestamp': datetime.utcnow().isoformat()
        }
        
        # Stack names to extract
        stacks = {
            'govcloud': [
                f"{self.project_name}-govcloud-vpc-{self.environment}",
                f"{self.project_name}-govcloud-vpc-endpoints-{self.environment}",
                f"{self.project_name}-govcloud-vpn-gateway-{self.environment}",
                f"{self.project_name}-govcloud-lambda-{self.environment}",
                f"{self.project_name}-govcloud-monitoring-{self.environment}"
            ],
            'commercial': [
                f"{self.project_name}-commercial-vpc-{self.environment}",
                f"{self.project_name}-commercial-vpc-endpoints-{self.environment}",
                f"{self.project_name}-commercial-vpn-gateway-{self.environment}",
                f"{self.project_name}-commercial-monitoring-{self.environment}"
            ]
        }
        
        # Extract GovCloud outputs
        logger.info("Extracting GovCloud CloudFormation outputs...")
        config['govcloud'] = self._extract_partition_outputs(
            self.govcloud_session, stacks['govcloud'], 'us-gov-west-1'
        )
        
        # Extract Commercial outputs
        logger.info("Extracting Commercial CloudFormation outputs...")
        config['commercial'] = self._extract_partition_outputs(
            self.commercial_session, stacks['commercial'], 'us-east-1'
        )
        
        return config
    
    def _extract_partition_outputs(self, session: boto3.Session, stack_names: List[str], region: str) -> Dict[str, Any]:
        """Extract outputs from CloudFormation stacks in a partition"""
        
        partition_config = {}
        cf_client = session.client('cloudformation', region_name=region)
        
        for stack_name in stack_names:
            try:
                logger.info(f"Extracting outputs from stack: {stack_name}")
                
                response = cf_client.describe_stacks(StackName=stack_name)
                
                if response['Stacks']:
                    stack = response['Stacks'][0]
                    stack_outputs = {}
                    
                    # Extract outputs
                    if 'Outputs' in stack:
                        for output in stack['Outputs']:
                            stack_outputs[output['OutputKey']] = {
                                'value': output['OutputValue'],
                                'description': output.get('Description', ''),
                                'export_name': output.get('ExportName', '')
                            }
                    
                    # Extract parameters
                    stack_parameters = {}
                    if 'Parameters' in stack:
                        for param in stack['Parameters']:
                            stack_parameters[param['ParameterKey']] = param['ParameterValue']
                    
                    partition_config[stack_name] = {
                        'stack_status': stack['StackStatus'],
                        'creation_time': stack['CreationTime'].isoformat(),
                        'last_updated_time': stack.get('LastUpdatedTime', stack['CreationTime']).isoformat(),
                        'outputs': stack_outputs,
                        'parameters': stack_parameters
                    }
                    
                    logger.info(f"Extracted {len(stack_outputs)} outputs from {stack_name}")
                
            except cf_client.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'ValidationError':
                    logger.warning(f"Stack {stack_name} not found, skipping...")
                    partition_config[stack_name] = {'status': 'not_found'}
                else:
                    logger.error(f"Error extracting outputs from {stack_name}: {str(e)}")
                    partition_config[stack_name] = {'status': 'error', 'error': str(e)}
            
            except Exception as e:
                logger.error(f"Unexpected error extracting outputs from {stack_name}: {str(e)}")
                partition_config[stack_name] = {'status': 'error', 'error': str(e)}
        
        return partition_config
    
    def get_vpn_tunnel_status(self) -> Dict[str, Any]:
        """Get real-time VPN tunnel status from AWS APIs"""
        
        vpn_status = {
            'govcloud': {},
            'commercial': {},
            'status_timestamp': datetime.utcnow().isoformat()
        }
        
        # Get GovCloud VPN status
        logger.info("Getting GovCloud VPN tunnel status...")
        vpn_status['govcloud'] = self._get_partition_vpn_status(
            self.govcloud_session, 'us-gov-west-1'
        )
        
        # Get Commercial VPN status
        logger.info("Getting Commercial VPN tunnel status...")
        vpn_status['commercial'] = self._get_partition_vpn_status(
            self.commercial_session, 'us-east-1'
        )
        
        return vpn_status
    
    def _get_partition_vpn_status(self, session: boto3.Session, region: str) -> Dict[str, Any]:
        """Get VPN status for a specific partition"""
        
        partition_status = {
            'vpn_connections': [],
            'vpn_gateways': [],
            'customer_gateways': []
        }
        
        ec2_client = session.client('ec2', region_name=region)
        
        try:
            # Get VPN connections
            vpn_connections = ec2_client.describe_vpn_connections(
                Filters=[
                    {'Name': 'tag:Project', 'Values': [self.project_name]}
                ]
            )
            
            for vpn_conn in vpn_connections['VpnConnections']:
                connection_info = {
                    'vpn_connection_id': vpn_conn['VpnConnectionId'],
                    'state': vpn_conn['State'],
                    'type': vpn_conn['Type'],
                    'customer_gateway_id': vpn_conn['CustomerGatewayId'],
                    'vpn_gateway_id': vpn_conn.get('VpnGatewayId'),
                    'transit_gateway_id': vpn_conn.get('TransitGatewayId'),
                    'tunnels': []
                }
                
                # Get tunnel details
                if 'VgwTelemetry' in vpn_conn:
                    for tunnel in vpn_conn['VgwTelemetry']:
                        tunnel_info = {
                            'outside_ip_address': tunnel['OutsideIpAddress'],
                            'status': tunnel['Status'],
                            'last_status_change': tunnel['LastStatusChange'].isoformat() if tunnel.get('LastStatusChange') else None,
                            'status_message': tunnel.get('StatusMessage', ''),
                            'accepted_route_count': tunnel.get('AcceptedRouteCount', 0)
                        }
                        connection_info['tunnels'].append(tunnel_info)
                
                partition_status['vpn_connections'].append(connection_info)
            
            # Get VPN gateways
            vpn_gateways = ec2_client.describe_vpn_gateways(
                Filters=[
                    {'Name': 'tag:Project', 'Values': [self.project_name]}
                ]
            )
            
            for vpn_gw in vpn_gateways['VpnGateways']:
                gateway_info = {
                    'vpn_gateway_id': vpn_gw['VpnGatewayId'],
                    'state': vpn_gw['State'],
                    'type': vpn_gw['Type'],
                    'availability_zone': vpn_gw.get('AvailabilityZone'),
                    'vpc_attachments': []
                }
                
                if 'VpcAttachments' in vpn_gw:
                    for attachment in vpn_gw['VpcAttachments']:
                        gateway_info['vpc_attachments'].append({
                            'vpc_id': attachment['VpcId'],
                            'state': attachment['State']
                        })
                
                partition_status['vpn_gateways'].append(gateway_info)
            
            # Get customer gateways
            customer_gateways = ec2_client.describe_customer_gateways(
                Filters=[
                    {'Name': 'tag:Project', 'Values': [self.project_name]}
                ]
            )
            
            for cust_gw in customer_gateways['CustomerGateways']:
                partition_status['customer_gateways'].append({
                    'customer_gateway_id': cust_gw['CustomerGatewayId'],
                    'state': cust_gw['State'],
                    'type': cust_gw['Type'],
                    'ip_address': cust_gw['IpAddress'],
                    'bgp_asn': cust_gw['BgpAsn']
                })
            
            logger.info(f"Found {len(partition_status['vpn_connections'])} VPN connections, "
                       f"{len(partition_status['vpn_gateways'])} VPN gateways, "
                       f"{len(partition_status['customer_gateways'])} customer gateways")
        
        except Exception as e:
            logger.error(f"Error getting VPN status: {str(e)}")
            partition_status['error'] = str(e)
        
        return partition_status
    
    def generate_config_file(self, config_data: Dict[str, Any], vpn_status: Dict[str, Any]) -> str:
        """Generate config-vpn.sh file with all VPN-specific settings"""
        
        logger.info("Generating config-vpn.sh file...")
        
        config_content = self._generate_config_header()
        config_content += self._generate_vpc_config(config_data)
        config_content += self._generate_vpc_endpoint_config(config_data)
        config_content += self._generate_vpn_config(config_data, vpn_status)
        config_content += self._generate_lambda_config(config_data)
        config_content += self._generate_monitoring_config(config_data)
        config_content += self._generate_validation_functions()
        
        return config_content
    
    def _generate_config_header(self) -> str:
        """Generate configuration file header"""
        
        return f'''#!/bin/bash
# VPN Connectivity Configuration
# Generated automatically by VPNConfigManager
# Project: {self.project_name}
# Environment: {self.environment}
# Generated: {datetime.utcnow().isoformat()}

# Color codes for output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

echo -e "${{BLUE}}🔧 Loading VPN Connectivity Configuration${{NC}}"
echo -e "${{BLUE}}Project: {self.project_name}${{NC}}"
echo -e "${{BLUE}}Environment: {self.environment}${{NC}}"
echo ""

# Project Configuration
export PROJECT_NAME="{self.project_name}"
export ENVIRONMENT="{self.environment}"
export ROUTING_METHOD="vpn"

'''
    
    def _generate_vpc_config(self, config_data: Dict[str, Any]) -> str:
        """Generate VPC configuration section"""
        
        config_content = "# VPC Configuration\n"
        
        # GovCloud VPC
        govcloud_vpc_stack = f"{self.project_name}-govcloud-vpc-{self.environment}"
        if govcloud_vpc_stack in config_data.get('govcloud', {}):
            vpc_outputs = config_data['govcloud'][govcloud_vpc_stack].get('outputs', {})
            
            config_content += f"export GOVCLOUD_VPC_ID=\"{vpc_outputs.get('VPCId', {}).get('value', '')}\"\n"
            config_content += f"export GOVCLOUD_VPC_CIDR=\"{vpc_outputs.get('VPCCidr', {}).get('value', '10.0.0.0/16')}\"\n"
            config_content += f"export GOVCLOUD_PRIVATE_SUBNET_ID=\"{vpc_outputs.get('PrivateSubnetId', {}).get('value', '')}\"\n"
            config_content += f"export GOVCLOUD_VPN_SUBNET_ID=\"{vpc_outputs.get('VPNSubnetId', {}).get('value', '')}\"\n"
            config_content += f"export GOVCLOUD_LAMBDA_SG_ID=\"{vpc_outputs.get('LambdaSecurityGroupId', {}).get('value', '')}\"\n"
        
        # Commercial VPC
        commercial_vpc_stack = f"{self.project_name}-commercial-vpc-{self.environment}"
        if commercial_vpc_stack in config_data.get('commercial', {}):
            vpc_outputs = config_data['commercial'][commercial_vpc_stack].get('outputs', {})
            
            config_content += f"export COMMERCIAL_VPC_ID=\"{vpc_outputs.get('VPCId', {}).get('value', '')}\"\n"
            config_content += f"export COMMERCIAL_VPC_CIDR=\"{vpc_outputs.get('VPCCidr', {}).get('value', '172.16.0.0/16')}\"\n"
            config_content += f"export COMMERCIAL_PRIVATE_SUBNET_ID=\"{vpc_outputs.get('PrivateSubnetId', {}).get('value', '')}\"\n"
            config_content += f"export COMMERCIAL_VPN_SUBNET_ID=\"{vpc_outputs.get('VPNSubnetId', {}).get('value', '')}\"\n"
        
        config_content += "\n"
        return config_content
    
    def _generate_vpc_endpoint_config(self, config_data: Dict[str, Any]) -> str:
        """Generate VPC endpoint configuration section"""
        
        config_content = "# VPC Endpoint Configuration\n"
        
        # GovCloud VPC Endpoints
        govcloud_endpoints_stack = f"{self.project_name}-govcloud-vpc-endpoints-{self.environment}"
        if govcloud_endpoints_stack in config_data.get('govcloud', {}):
            endpoint_outputs = config_data['govcloud'][govcloud_endpoints_stack].get('outputs', {})
            
            config_content += f"export VPC_ENDPOINT_SECRETS=\"{endpoint_outputs.get('SecretsManagerEndpointDNS', {}).get('value', '')}\"\n"
            config_content += f"export VPC_ENDPOINT_DYNAMODB=\"{endpoint_outputs.get('DynamoDBEndpointDNS', {}).get('value', '')}\"\n"
            config_content += f"export VPC_ENDPOINT_LOGS=\"{endpoint_outputs.get('CloudWatchLogsEndpointDNS', {}).get('value', '')}\"\n"
            config_content += f"export VPC_ENDPOINT_MONITORING=\"{endpoint_outputs.get('CloudWatchEndpointDNS', {}).get('value', '')}\"\n"
        
        # Commercial VPC Endpoints
        commercial_endpoints_stack = f"{self.project_name}-commercial-vpc-endpoints-{self.environment}"
        if commercial_endpoints_stack in config_data.get('commercial', {}):
            endpoint_outputs = config_data['commercial'][commercial_endpoints_stack].get('outputs', {})
            
            config_content += f"export COMMERCIAL_BEDROCK_ENDPOINT=\"{endpoint_outputs.get('BedrockEndpointDNS', {}).get('value', '')}\"\n"
            config_content += f"export COMMERCIAL_LOGS_ENDPOINT=\"{endpoint_outputs.get('CloudWatchLogsEndpointDNS', {}).get('value', '')}\"\n"
            config_content += f"export COMMERCIAL_MONITORING_ENDPOINT=\"{endpoint_outputs.get('CloudWatchEndpointDNS', {}).get('value', '')}\"\n"
        
        config_content += "\n"
        return config_content
    
    def _generate_vpn_config(self, config_data: Dict[str, Any], vpn_status: Dict[str, Any]) -> str:
        """Generate VPN configuration section"""
        
        config_content = "# VPN Configuration\n"
        
        # Extract VPN connection details from status
        govcloud_vpn_status = vpn_status.get('govcloud', {})
        commercial_vpn_status = vpn_status.get('commercial', {})
        
        # GovCloud VPN
        if govcloud_vpn_status.get('vpn_connections'):
            vpn_conn = govcloud_vpn_status['vpn_connections'][0]  # First connection
            config_content += f"export GOVCLOUD_VPN_CONNECTION_ID=\"{vpn_conn.get('vpn_connection_id', '')}\"\n"
            config_content += f"export GOVCLOUD_VPN_STATE=\"{vpn_conn.get('state', '')}\"\n"
            
            if vpn_conn.get('tunnels'):
                for i, tunnel in enumerate(vpn_conn['tunnels']):
                    config_content += f"export GOVCLOUD_VPN_TUNNEL_{i+1}_IP=\"{tunnel.get('outside_ip_address', '')}\"\n"
                    config_content += f"export GOVCLOUD_VPN_TUNNEL_{i+1}_STATUS=\"{tunnel.get('status', '')}\"\n"
        
        # Commercial VPN
        if commercial_vpn_status.get('vpn_connections'):
            vpn_conn = commercial_vpn_status['vpn_connections'][0]  # First connection
            config_content += f"export COMMERCIAL_VPN_CONNECTION_ID=\"{vpn_conn.get('vpn_connection_id', '')}\"\n"
            config_content += f"export COMMERCIAL_VPN_STATE=\"{vpn_conn.get('state', '')}\"\n"
            
            if vpn_conn.get('tunnels'):
                for i, tunnel in enumerate(vpn_conn['tunnels']):
                    config_content += f"export COMMERCIAL_VPN_TUNNEL_{i+1}_IP=\"{tunnel.get('outside_ip_address', '')}\"\n"
                    config_content += f"export COMMERCIAL_VPN_TUNNEL_{i+1}_STATUS=\"{tunnel.get('status', '')}\"\n"
        
        config_content += "\n"
        return config_content
    
    def _generate_lambda_config(self, config_data: Dict[str, Any]) -> str:
        """Generate Lambda configuration section"""
        
        config_content = "# Lambda Configuration\n"
        
        # GovCloud Lambda
        govcloud_lambda_stack = f"{self.project_name}-govcloud-lambda-{self.environment}"
        if govcloud_lambda_stack in config_data.get('govcloud', {}):
            lambda_outputs = config_data['govcloud'][govcloud_lambda_stack].get('outputs', {})
            
            config_content += f"export LAMBDA_FUNCTION_NAME=\"{lambda_outputs.get('LambdaFunctionName', {}).get('value', '')}\"\n"
            config_content += f"export LAMBDA_FUNCTION_ARN=\"{lambda_outputs.get('LambdaFunctionArn', {}).get('value', '')}\"\n"
            config_content += f"export LAMBDA_ROLE_ARN=\"{lambda_outputs.get('LambdaRoleArn', {}).get('value', '')}\"\n"
        
        # Secrets configuration
        config_content += f"export COMMERCIAL_CREDENTIALS_SECRET=\"{self.project_name}-commercial-credentials-{self.environment}\"\n"
        config_content += f"export REQUEST_LOG_TABLE=\"{self.project_name}-request-log-{self.environment}\"\n"
        
        config_content += "\n"
        return config_content
    
    def _generate_monitoring_config(self, config_data: Dict[str, Any]) -> str:
        """Generate monitoring configuration section"""
        
        config_content = "# Monitoring Configuration\n"
        
        # CloudWatch configuration
        config_content += f"export CLOUDWATCH_LOG_GROUP=\"/aws/lambda/{self.project_name}-cross-partition-inference\"\n"
        config_content += f"export CLOUDWATCH_NAMESPACE=\"{self.project_name}/VPN\"\n"
        
        # Monitoring stack outputs
        govcloud_monitoring_stack = f"{self.project_name}-govcloud-monitoring-{self.environment}"
        if govcloud_monitoring_stack in config_data.get('govcloud', {}):
            monitoring_outputs = config_data['govcloud'][govcloud_monitoring_stack].get('outputs', {})
            
            config_content += f"export MONITORING_DASHBOARD_URL=\"{monitoring_outputs.get('DashboardURL', {}).get('value', '')}\"\n"
            config_content += f"export ALARM_TOPIC_ARN=\"{monitoring_outputs.get('AlarmTopicArn', {}).get('value', '')}\"\n"
        
        config_content += "\n"
        return config_content
    
    def _generate_validation_functions(self) -> str:
        """Generate validation functions for the configuration"""
        
        return '''# Configuration Validation Functions

validate_vpn_config() {
    echo -e "${YELLOW}🔍 Validating VPN Configuration...${NC}"
    
    local errors=0
    
    # Check required variables
    required_vars=(
        "PROJECT_NAME"
        "ENVIRONMENT"
        "GOVCLOUD_VPC_ID"
        "COMMERCIAL_VPC_ID"
        "VPC_ENDPOINT_SECRETS"
        "COMMERCIAL_BEDROCK_ENDPOINT"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}❌ Missing required variable: $var${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✅ $var is set${NC}"
        fi
    done
    
    # Check VPN tunnel status
    if [ -n "$GOVCLOUD_VPN_TUNNEL_1_STATUS" ]; then
        if [ "$GOVCLOUD_VPN_TUNNEL_1_STATUS" = "UP" ]; then
            echo -e "${GREEN}✅ GovCloud VPN Tunnel 1 is UP${NC}"
        else
            echo -e "${YELLOW}⚠️ GovCloud VPN Tunnel 1 status: $GOVCLOUD_VPN_TUNNEL_1_STATUS${NC}"
        fi
    fi
    
    if [ -n "$COMMERCIAL_VPN_TUNNEL_1_STATUS" ]; then
        if [ "$COMMERCIAL_VPN_TUNNEL_1_STATUS" = "UP" ]; then
            echo -e "${GREEN}✅ Commercial VPN Tunnel 1 is UP${NC}"
        else
            echo -e "${YELLOW}⚠️ Commercial VPN Tunnel 1 status: $COMMERCIAL_VPN_TUNNEL_1_STATUS${NC}"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}🎉 VPN configuration validation passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ VPN configuration validation failed with $errors error(s)${NC}"
        return 1
    fi
}

test_vpn_connectivity() {
    echo -e "${YELLOW}🔗 Testing VPN Connectivity...${NC}"
    
    # Test VPC endpoint connectivity
    if [ -n "$VPC_ENDPOINT_SECRETS" ]; then
        echo -e "${BLUE}Testing Secrets Manager VPC endpoint...${NC}"
        if timeout 10 nc -z $(echo $VPC_ENDPOINT_SECRETS | cut -d'.' -f1) 443 2>/dev/null; then
            echo -e "${GREEN}✅ Secrets Manager VPC endpoint is reachable${NC}"
        else
            echo -e "${RED}❌ Secrets Manager VPC endpoint is not reachable${NC}"
        fi
    fi
    
    # Test cross-partition connectivity (if VPN is up)
    if [ "$GOVCLOUD_VPN_TUNNEL_1_STATUS" = "UP" ] && [ "$COMMERCIAL_VPN_TUNNEL_1_STATUS" = "UP" ]; then
        echo -e "${GREEN}✅ VPN tunnels are up - cross-partition connectivity should be available${NC}"
    else
        echo -e "${YELLOW}⚠️ VPN tunnels are not fully up - cross-partition connectivity may be limited${NC}"
    fi
}

show_vpn_status() {
    echo -e "${BLUE}📊 VPN Status Summary${NC}"
    echo "=================================="
    echo "Project: $PROJECT_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Routing Method: $ROUTING_METHOD"
    echo ""
    
    echo -e "${BLUE}GovCloud VPC:${NC}"
    echo "  VPC ID: $GOVCLOUD_VPC_ID"
    echo "  CIDR: $GOVCLOUD_VPC_CIDR"
    echo "  VPN Connection: $GOVCLOUD_VPN_CONNECTION_ID"
    echo "  VPN State: $GOVCLOUD_VPN_STATE"
    echo "  Tunnel 1 Status: $GOVCLOUD_VPN_TUNNEL_1_STATUS"
    echo "  Tunnel 2 Status: $GOVCLOUD_VPN_TUNNEL_2_STATUS"
    echo ""
    
    echo -e "${BLUE}Commercial VPC:${NC}"
    echo "  VPC ID: $COMMERCIAL_VPC_ID"
    echo "  CIDR: $COMMERCIAL_VPC_CIDR"
    echo "  VPN Connection: $COMMERCIAL_VPN_CONNECTION_ID"
    echo "  VPN State: $COMMERCIAL_VPN_STATE"
    echo "  Tunnel 1 Status: $COMMERCIAL_VPN_TUNNEL_1_STATUS"
    echo "  Tunnel 2 Status: $COMMERCIAL_VPN_TUNNEL_2_STATUS"
    echo ""
    
    echo -e "${BLUE}VPC Endpoints:${NC}"
    echo "  Secrets Manager: $VPC_ENDPOINT_SECRETS"
    echo "  DynamoDB: $VPC_ENDPOINT_DYNAMODB"
    echo "  CloudWatch Logs: $VPC_ENDPOINT_LOGS"
    echo "  Commercial Bedrock: $COMMERCIAL_BEDROCK_ENDPOINT"
    echo ""
}

# Auto-run validation if script is sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being executed directly
    validate_vpn_config
    test_vpn_connectivity
    show_vpn_status
else
    # Script is being sourced
    echo -e "${GREEN}✅ VPN configuration loaded successfully${NC}"
    echo -e "${BLUE}Available functions: validate_vpn_config, test_vpn_connectivity, show_vpn_status${NC}"
fi
'''
    
    def validate_configuration(self, config_data: Dict[str, Any], vpn_status: Dict[str, Any]) -> Dict[str, Any]:
        """Validate the extracted configuration"""
        
        validation_results = {
            'is_valid': True,
            'errors': [],
            'warnings': [],
            'summary': {}
        }
        
        # Check required CloudFormation stacks
        required_stacks = {
            'govcloud': [
                f"{self.project_name}-govcloud-vpc-{self.environment}",
                f"{self.project_name}-govcloud-vpc-endpoints-{self.environment}"
            ],
            'commercial': [
                f"{self.project_name}-commercial-vpc-{self.environment}",
                f"{self.project_name}-commercial-vpc-endpoints-{self.environment}"
            ]
        }
        
        for partition, stacks in required_stacks.items():
            for stack_name in stacks:
                if stack_name not in config_data.get(partition, {}):
                    validation_results['errors'].append(f"Missing required stack: {stack_name}")
                    validation_results['is_valid'] = False
                elif config_data[partition][stack_name].get('status') == 'not_found':
                    validation_results['errors'].append(f"Stack not found: {stack_name}")
                    validation_results['is_valid'] = False
                elif config_data[partition][stack_name].get('status') == 'error':
                    validation_results['errors'].append(f"Error accessing stack: {stack_name}")
                    validation_results['is_valid'] = False
        
        # Check VPN tunnel status
        for partition in ['govcloud', 'commercial']:
            vpn_connections = vpn_status.get(partition, {}).get('vpn_connections', [])
            if not vpn_connections:
                validation_results['warnings'].append(f"No VPN connections found in {partition}")
            else:
                for vpn_conn in vpn_connections:
                    if vpn_conn.get('state') != 'available':
                        validation_results['warnings'].append(
                            f"VPN connection {vpn_conn.get('vpn_connection_id')} in {partition} is not available"
                        )
                    
                    # Check tunnel status
                    for tunnel in vpn_conn.get('tunnels', []):
                        if tunnel.get('status') != 'UP':
                            validation_results['warnings'].append(
                                f"VPN tunnel {tunnel.get('outside_ip_address')} in {partition} is {tunnel.get('status')}"
                            )
        
        # Generate summary
        validation_results['summary'] = {
            'total_errors': len(validation_results['errors']),
            'total_warnings': len(validation_results['warnings']),
            'govcloud_stacks': len([s for s in config_data.get('govcloud', {}) if 'error' not in config_data['govcloud'][s]]),
            'commercial_stacks': len([s for s in config_data.get('commercial', {}) if 'error' not in config_data['commercial'][s]]),
            'govcloud_vpn_connections': len(vpn_status.get('govcloud', {}).get('vpn_connections', [])),
            'commercial_vpn_connections': len(vpn_status.get('commercial', {}).get('vpn_connections', []))
        }
        
        return validation_results
    
    def save_configuration_files(self, config_data: Dict[str, Any], vpn_status: Dict[str, Any], output_dir: str = "."):
        """Save configuration files to disk"""
        
        logger.info(f"Saving configuration files to {output_dir}")
        
        # Ensure output directory exists
        os.makedirs(output_dir, exist_ok=True)
        
        # Save raw configuration data
        config_file_path = os.path.join(output_dir, "vpn-config-data.json")
        with open(config_file_path, 'w') as f:
            json.dump({
                'cloudformation_outputs': config_data,
                'vpn_status': vpn_status
            }, f, indent=2, default=str)
        
        logger.info(f"Saved raw configuration data to {config_file_path}")
        
        # Generate and save config-vpn.sh
        config_script = self.generate_config_file(config_data, vpn_status)
        config_script_path = os.path.join(output_dir, "config-vpn.sh")
        
        with open(config_script_path, 'w') as f:
            f.write(config_script)
        
        # Make script executable
        os.chmod(config_script_path, 0o755)
        
        logger.info(f"Generated config-vpn.sh at {config_script_path}")
        
        # Validate and save validation results
        validation_results = self.validate_configuration(config_data, vpn_status)
        validation_file_path = os.path.join(output_dir, "vpn-config-validation.json")
        
        with open(validation_file_path, 'w') as f:
            json.dump(validation_results, f, indent=2)
        
        logger.info(f"Saved validation results to {validation_file_path}")
        
        return {
            'config_data_file': config_file_path,
            'config_script_file': config_script_path,
            'validation_file': validation_file_path,
            'validation_results': validation_results
        }

def main():
    """Main function for command-line usage"""
    
    import argparse
    
    parser = argparse.ArgumentParser(description='Extract VPN configuration from AWS infrastructure')
    parser.add_argument('--project-name', default='cross-partition-inference', help='Project name')
    parser.add_argument('--environment', default='dev', help='Environment name')
    parser.add_argument('--output-dir', default='.', help='Output directory for configuration files')
    parser.add_argument('--govcloud-profile', default='govcloud', help='AWS CLI profile for GovCloud')
    parser.add_argument('--commercial-profile', default='commercial', help='AWS CLI profile for Commercial')
    parser.add_argument('--validate-only', action='store_true', help='Only validate existing configuration')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    try:
        # Initialize config manager
        config_manager = VPNConfigManager(
            project_name=args.project_name,
            environment=args.environment
        )
        
        config_manager.govcloud_profile = args.govcloud_profile
        config_manager.commercial_profile = args.commercial_profile
        
        if args.validate_only:
            # Load existing configuration and validate
            config_file = os.path.join(args.output_dir, "vpn-config-data.json")
            if os.path.exists(config_file):
                with open(config_file, 'r') as f:
                    existing_config = json.load(f)
                
                validation_results = config_manager.validate_configuration(
                    existing_config.get('cloudformation_outputs', {}),
                    existing_config.get('vpn_status', {})
                )
                
                print(json.dumps(validation_results, indent=2))
                
                if validation_results['is_valid']:
                    logger.info("✅ Configuration validation passed")
                    sys.exit(0)
                else:
                    logger.error("❌ Configuration validation failed")
                    sys.exit(1)
            else:
                logger.error(f"Configuration file not found: {config_file}")
                sys.exit(1)
        
        else:
            # Extract fresh configuration
            logger.info("🔄 Extracting CloudFormation outputs...")
            config_data = config_manager.extract_cloudformation_outputs()
            
            logger.info("🔄 Getting VPN tunnel status...")
            vpn_status = config_manager.get_vpn_tunnel_status()
            
            logger.info("💾 Saving configuration files...")
            result = config_manager.save_configuration_files(config_data, vpn_status, args.output_dir)
            
            # Print summary
            validation_results = result['validation_results']
            
            print(f"\n🎉 Configuration extraction completed!")
            print(f"📁 Files saved to: {args.output_dir}")
            print(f"📋 Configuration script: {result['config_script_file']}")
            print(f"📊 Validation results: {validation_results['summary']}")
            
            if validation_results['is_valid']:
                print("✅ Configuration is valid and ready to use")
                print(f"\nTo use the configuration, run:")
                print(f"  source {result['config_script_file']}")
                sys.exit(0)
            else:
                print("❌ Configuration validation failed")
                print("Errors:")
                for error in validation_results['errors']:
                    print(f"  - {error}")
                if validation_results['warnings']:
                    print("Warnings:")
                    for warning in validation_results['warnings']:
                        print(f"  - {warning}")
                sys.exit(1)
    
    except Exception as e:
        logger.error(f"❌ Configuration extraction failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()