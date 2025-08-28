# Implementation Plan

- [x] 1. Create VPN Lambda function with VPC configuration
  - Implement new Lambda function specifically for VPN routing in VPC
  - Configure VPC settings, security groups, and subnet assignments
  - Set up environment variables for VPN-specific configuration
  - _Requirements: 2.1, 2.2, 3.1_

- [x] 2. Implement VPN routing logic in Lambda function
  - Write VPN Lambda handler that uses VPC endpoints for AWS service calls
  - Implement Bedrock client that routes through VPN tunnel to Commercial AWS
  - Add proper error handling for VPN-specific failures (tunnel down, VPC endpoint issues)
  - _Requirements: 2.1, 2.2, 6.1_

- [x] 3. Enhance existing internet Lambda function for dual routing support
  - Modify existing Lambda to detect routing method from API Gateway path
  - Add routing_method field to response payload
  - Ensure backward compatibility with existing response format
  - _Requirements: 1.1, 1.3, 4.3_

- [x] 4. Create API Gateway resource structure for VPN paths
  - Add new `/v1/vpn/bedrock/invoke-model` resource to existing API Gateway
  - Configure POST method integration with VPN Lambda function
  - Set up proper request/response mapping templates
  - _Requirements: 4.1, 4.2, 4.3_

- [x] 5. Implement authentication and authorization for both paths
  - Configure API key authentication for VPN endpoints
  - Set up IAM roles and policies for VPN Lambda VPC execution
  - Ensure consistent authentication behavior across both routing methods
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 6. Create comprehensive error handling for both routing methods
  - Implement standardized error response format for both Lambda functions
  - Add specific error codes for VPN-related failures
  - Create error logging with appropriate context and routing method identification
  - _Requirements: 6.1, 6.2, 6.4_

- [x] 7. Set up monitoring and logging for dual routing
  - Create separate CloudWatch log groups for internet and VPN Lambda functions
  - Implement custom metrics for each routing method
  - Add X-Routing-Method header to all responses for tracking
  - _Requirements: 6.2, 6.3, 3.3_

- [x] 8. Write unit tests for VPN Lambda function
  - Create test cases for successful VPN routing scenarios
  - Test VPN-specific error conditions (tunnel failures, VPC endpoint issues)
  - Validate request parsing and response formatting for VPN Lambda
  - _Requirements: 8.1, 8.2_

- [x] 9. Write unit tests for enhanced internet Lambda function
  - Test routing method detection from API Gateway event
  - Validate backward compatibility with existing functionality
  - Test error handling and response formatting
  - _Requirements: 8.1, 1.1, 1.3_

- [x] 10. Create integration tests for API Gateway paths
  - Test `/v1/bedrock/invoke-model` path routes to internet Lambda correctly
  - Test `/v1/vpn/bedrock/invoke-model` path routes to VPN Lambda correctly
  - Validate authentication works consistently across both paths
  - _Requirements: 8.1, 4.1, 4.2, 5.1_

- [x] 11. Implement end-to-end testing for both routing methods
  - Create test that validates complete internet routing flow from API Gateway to Bedrock
  - Create test that validates complete VPN routing flow from API Gateway to Bedrock
  - Implement comparison test that verifies functional equivalence between routing methods
  - _Requirements: 8.2, 8.3_

- [x] 12. Create deployment scripts for VPN infrastructure
  - Write script to deploy VPC, subnets, and VPN gateway for VPN Lambda
  - Create script to deploy VPC endpoints required for VPN Lambda operation
  - Implement validation script to verify VPN connectivity before Lambda deployment
  - _Requirements: 2.2, 2.3_

- [x] 13. Create deployment script for VPN Lambda function
  - Write script to package and deploy VPN Lambda function with VPC configuration
  - Configure Lambda environment variables for VPN routing
  - Set up IAM roles and policies for VPN Lambda execution
  - _Requirements: 3.1, 5.2_

- [x] 14. Update API Gateway deployment with VPN paths
  - Modify existing API Gateway CloudFormation/deployment scripts to add VPN resources
  - Configure integration between VPN path and VPN Lambda function
  - Deploy and validate new API Gateway configuration
  - _Requirements: 4.1, 4.2_

- [x] 15. Create monitoring dashboard for dual routing
  - Build CloudWatch dashboard showing metrics for both internet and VPN routing
  - Add alerts for VPN-specific failures (tunnel down, high error rates)
  - Implement performance comparison charts between routing methods
  - _Requirements: 6.2, 6.3, 7.3_

- [x] 16. Write comprehensive validation tests
  - Create automated test suite that validates both routing methods are functional
  - Implement performance comparison tests between internet and VPN routing
  - Add load testing capabilities for both routing paths
  - _Requirements: 8.3, 8.4, 7.1, 7.2_