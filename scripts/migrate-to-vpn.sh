#!/bin/bash

# Migrate from Internet to VPN Routing
# This script automates the migration from internet-based to VPN-based routing

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"
MIGRATION_STRATEGY="blue-green"  # blue-green, phased, big-bang
DRY_RUN=false
SKIP_VALIDATION=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Migration phases
MIGRATION_PHASES=(
    "assessment:Pre-migration assessment"
    "infrastructure:VPN infrastructure deployment"
    "testing:Parallel deployment testing"
    "migration:Traffic migration"
    "validation:Post-migration validation"
    "cleanup:Cleanup and optimization"
)

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --strategy STRATEGY       Migration strategy (blue-green|phased|big-bang, default: blue-green)"
    echo "  --phase PHASE            Run specific migration phase"
    echo "  --project-name NAME      Project name (default: cross-partition-inference)"
    echo "  --environment ENV        Environment (default: prod)"
    echo "  --govcloud-profile PROF  AWS CLI profile for GovCloud (default: govcloud)"
    echo "  --commercial-profile PROF AWS CLI profile for Commercial (default: commercial)"
    echo "  --dry-run                Show what would be done without executing"
    echo "  --skip-validation        Skip validation steps (not recommended)"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Migration Strategies:"
    echo "  blue-green    Deploy VPN alongside internet, then switch (recommended)"
    echo "  phased        Gradually migrate traffic percentage by percentage"
    echo "  big-bang      Complete cutover in single maintenance window"
    echo ""
    echo "Migration Phases:"
    for phase_info in "${MIGRATION_PHASES[@]}"; do
        IFS=':' read -r phase desc <<< "$phase_info"
        echo "  $phase: $desc"
    done
    echo ""
    echo "Examples:"
    echo "  $0                                    # Full blue-green migration"
    echo "  $0 --strategy phased                  # Phased migration"
    echo "  $0 --phase assessment                 # Run assessment only"
    echo "  $0 --dry-run                          # Show what would be done"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strategy)
            MIGRATION_STRATEGY="$2"
            shift 2
            ;;
        --phase)
            MIGRATION_PHASE="$2"
            shift 2
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --govcloud-profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --commercial-profile)
            COMMERCIAL_PROFILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🚀 Cross-Partition Routing Migration${NC}"
echo -e "${BLUE}Strategy: ${MIGRATION_STRATEGY}${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Dry Run: ${DRY_RUN}${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Migration state file
MIGRATION_STATE_FILE="./migration-state-${PROJECT_NAME}-${ENVIRONMENT}.json"

# Function to execute command with dry-run support
execute_command() {
    local command="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would execute: $description${NC}"
        echo -e "${YELLOW}[DRY RUN] Command: $command${NC}"
    else
        echo -e "${BLUE}Executing: $description${NC}"
        eval "$command"
    fi
}

# Function to save migration state
save_migration_state() {
    local phase="$1"
    local status="$2"
    local details="$3"
    
    local state_data="{
        \"migration_id\": \"$(date +%Y%m%d-%H%M%S)\",
        \"project_name\": \"$PROJECT_NAME\",
        \"environment\": \"$ENVIRONMENT\",
        \"strategy\": \"$MIGRATION_STRATEGY\",
        \"current_phase\": \"$phase\",
        \"status\": \"$status\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
        \"details\": \"$details\"
    }"
    
    echo "$state_data" > "$MIGRATION_STATE_FILE"
}

# Function to load migration state
load_migration_state() {
    if [ -f "$MIGRATION_STATE_FILE" ]; then
        cat "$MIGRATION_STATE_FILE"
    else
        echo "{}"
    fi
}

# Phase 1: Pre-migration Assessment
run_assessment() {
    echo -e "${YELLOW}📊 Phase 1: Pre-migration Assessment${NC}"
    save_migration_state "assessment" "in_progress" "Running pre-migration assessment"
    
    # Check current internet routing
    echo -e "${BLUE}Assessing current internet routing...${NC}"
    execute_command \
        "python3 tests/test_internet_routing.py" \
        "Test current internet routing functionality"
    
    # Check AWS resources
    echo -e "${BLUE}Checking AWS resources...${NC}"
    execute_command \
        "aws lambda get-function --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Verify Lambda function exists"
    
    # Check API Gateway
    execute_command \
        "aws apigateway get-rest-apis --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Check API Gateway configuration"
    
    # Performance baseline
    echo -e "${BLUE}Establishing performance baseline...${NC}"
    execute_command \
        "./runbooks/performance-monitoring.sh baseline" \
        "Establish performance baseline"
    
    save_migration_state "assessment" "completed" "Pre-migration assessment completed successfully"
    echo -e "${GREEN}✅ Assessment phase completed${NC}"
}

# Phase 2: VPN Infrastructure Deployment
run_infrastructure_deployment() {
    echo -e "${YELLOW}🏗️ Phase 2: VPN Infrastructure Deployment${NC}"
    save_migration_state "infrastructure" "in_progress" "Deploying VPN infrastructure"
    
    # Deploy VPN infrastructure
    echo -e "${BLUE}Deploying VPN infrastructure...${NC}"
    execute_command \
        "./scripts/deploy-vpn-with-config.sh --project-name $PROJECT_NAME --environment $ENVIRONMENT --govcloud-profile $GOVCLOUD_PROFILE --commercial-profile $COMMERCIAL_PROFILE" \
        "Deploy complete VPN infrastructure"
    
    # Validate VPN deployment
    if [ "$SKIP_VALIDATION" = false ]; then
        echo -e "${BLUE}Validating VPN deployment...${NC}"
        execute_command \
            "./scripts/validate-vpn-connectivity.sh --verbose" \
            "Validate VPN connectivity"
        
        execute_command \
            "./scripts/get-vpn-status.sh summary" \
            "Check VPN tunnel status"
    fi
    
    save_migration_state "infrastructure" "completed" "VPN infrastructure deployed and validated"
    echo -e "${GREEN}✅ Infrastructure deployment phase completed${NC}"
}

# Phase 3: Parallel Deployment Testing
run_parallel_testing() {
    echo -e "${YELLOW}🧪 Phase 3: Parallel Deployment Testing${NC}"
    save_migration_state "testing" "in_progress" "Running parallel deployment tests"
    
    # Test VPN routing
    echo -e "${BLUE}Testing VPN routing...${NC}"
    execute_command \
        "python3 tests/test_vpn_routing.py" \
        "Test VPN routing functionality"
    
    # Run comparison tests
    echo -e "${BLUE}Running routing comparison...${NC}"
    execute_command \
        "python3 tests/test_routing_comparison.py" \
        "Compare internet and VPN routing performance"
    
    # Load testing
    echo -e "${BLUE}Running load tests...${NC}"
    execute_command \
        "./scripts/run-vpn-tests.sh --test-type both" \
        "Run comprehensive routing tests"
    
    save_migration_state "testing" "completed" "Parallel testing completed successfully"
    echo -e "${GREEN}✅ Parallel testing phase completed${NC}"
}

# Phase 4: Traffic Migration
run_traffic_migration() {
    echo -e "${YELLOW}🔄 Phase 4: Traffic Migration${NC}"
    save_migration_state "migration" "in_progress" "Migrating traffic to VPN routing"
    
    case "$MIGRATION_STRATEGY" in
        "blue-green")
            run_blue_green_migration
            ;;
        "phased")
            run_phased_migration
            ;;
        "big-bang")
            run_big_bang_migration
            ;;
        *)
            echo -e "${RED}❌ Unknown migration strategy: $MIGRATION_STRATEGY${NC}"
            exit 1
            ;;
    esac
    
    save_migration_state "migration" "completed" "Traffic migration completed"
    echo -e "${GREEN}✅ Traffic migration phase completed${NC}"
}

# Blue-Green Migration
run_blue_green_migration() {
    echo -e "${BLUE}Running Blue-Green migration...${NC}"
    
    # Enable dual routing
    echo -e "${BLUE}Enabling dual routing support...${NC}"
    execute_command \
        "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"internet\",\"ENABLE_DUAL_ROUTING\":\"true\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Enable dual routing in Lambda function"
    
    # Test dual routing
    echo -e "${BLUE}Testing dual routing...${NC}"
    execute_command \
        "aws lambda invoke --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --payload '{\"routing_method\":\"vpn\",\"model_id\":\"anthropic.claude-3-sonnet-20240229-v1:0\",\"prompt\":\"Blue-green test\"}' test-vpn.json --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Test VPN routing via dual routing"
    
    # Switch to VPN routing
    echo -e "${BLUE}Switching to VPN routing...${NC}"
    execute_command \
        "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"vpn\",\"ENABLE_DUAL_ROUTING\":\"false\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Switch Lambda function to VPN routing"
    
    # Immediate validation
    echo -e "${BLUE}Validating cutover...${NC}"
    execute_command \
        "python3 tests/test_vpn_routing.py" \
        "Validate VPN routing after cutover"
}

# Phased Migration
run_phased_migration() {
    echo -e "${BLUE}Running Phased migration...${NC}"
    
    local phases=(5 25 50 75 100)
    
    for percentage in "${phases[@]}"; do
        echo -e "${BLUE}Migrating ${percentage}% of traffic to VPN...${NC}"
        
        execute_command \
            "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"internet\",\"ENABLE_DUAL_ROUTING\":\"true\",\"VPN_TRAFFIC_PERCENTAGE\":\"$percentage\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
            "Set VPN traffic percentage to $percentage%"
        
        # Monitor for issues
        echo -e "${BLUE}Monitoring for 5 minutes...${NC}"
        if [ "$DRY_RUN" = false ]; then
            sleep 300  # 5 minutes
            
            # Check for errors
            execute_command \
                "./scripts/validate-vpn-connectivity.sh" \
                "Validate connectivity at $percentage% migration"
        fi
    done
    
    # Final switch to 100% VPN
    echo -e "${BLUE}Completing migration to 100% VPN...${NC}"
    execute_command \
        "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"vpn\",\"ENABLE_DUAL_ROUTING\":\"false\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Complete migration to VPN routing"
}

# Big Bang Migration
run_big_bang_migration() {
    echo -e "${BLUE}Running Big Bang migration...${NC}"
    
    # Direct switch to VPN routing
    execute_command \
        "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"vpn\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Switch directly to VPN routing"
    
    # Immediate validation
    execute_command \
        "python3 tests/test_vpn_routing.py" \
        "Validate VPN routing after big bang cutover"
}

# Phase 5: Post-Migration Validation
run_post_migration_validation() {
    echo -e "${YELLOW}✅ Phase 5: Post-Migration Validation${NC}"
    save_migration_state "validation" "in_progress" "Running post-migration validation"
    
    # Comprehensive validation
    echo -e "${BLUE}Running comprehensive validation...${NC}"
    execute_command \
        "./scripts/validate-vpn-connectivity.sh --verbose" \
        "Comprehensive VPN connectivity validation"
    
    # Performance validation
    echo -e "${BLUE}Validating performance...${NC}"
    execute_command \
        "./runbooks/performance-monitoring.sh report --period 1" \
        "Generate post-migration performance report"
    
    # Security validation
    echo -e "${BLUE}Validating security...${NC}"
    execute_command \
        "./scripts/get-vpn-status.sh" \
        "Validate VPN tunnel security"
    
    # Generate migration report
    echo -e "${BLUE}Generating migration report...${NC}"
    execute_command \
        "python3 tests/test_routing_comparison.py" \
        "Generate final migration comparison report"
    
    save_migration_state "validation" "completed" "Post-migration validation completed successfully"
    echo -e "${GREEN}✅ Post-migration validation phase completed${NC}"
}

# Phase 6: Cleanup and Optimization
run_cleanup() {
    echo -e "${YELLOW}🧹 Phase 6: Cleanup and Optimization${NC}"
    save_migration_state "cleanup" "in_progress" "Running cleanup and optimization"
    
    # Remove dual routing code (if applicable)
    echo -e "${BLUE}Cleaning up dual routing configuration...${NC}"
    execute_command \
        "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"vpn\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Clean up Lambda environment variables"
    
    # Optimize VPN configuration
    echo -e "${BLUE}Optimizing VPN configuration...${NC}"
    execute_command \
        "./runbooks/performance-monitoring.sh optimize" \
        "Run VPN performance optimization"
    
    # Generate cost analysis
    echo -e "${BLUE}Analyzing cost impact...${NC}"
    execute_command \
        "aws cloudwatch get-metric-statistics --namespace AWS/VPN --metric-name TunnelState --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 3600 --statistics Average --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Analyze VPN usage metrics"
    
    save_migration_state "cleanup" "completed" "Cleanup and optimization completed"
    echo -e "${GREEN}✅ Cleanup phase completed${NC}"
}

# Rollback function
run_rollback() {
    echo -e "${RED}🔄 Rolling back to internet routing...${NC}"
    save_migration_state "rollback" "in_progress" "Rolling back to internet routing"
    
    # Switch back to internet routing
    execute_command \
        "aws lambda update-function-configuration --function-name ${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT} --environment Variables='{\"ROUTING_METHOD\":\"internet\",\"ENABLE_DUAL_ROUTING\":\"false\"}' --profile $GOVCLOUD_PROFILE --region us-gov-west-1" \
        "Rollback to internet routing"
    
    # Validate rollback
    execute_command \
        "python3 tests/test_internet_routing.py" \
        "Validate internet routing after rollback"
    
    save_migration_state "rollback" "completed" "Rollback completed successfully"
    echo -e "${GREEN}✅ Rollback completed${NC}"
}

# Main execution
main() {
    # Load previous migration state
    local previous_state
    previous_state=$(load_migration_state)
    
    if [ "$previous_state" != "{}" ]; then
        echo -e "${YELLOW}📋 Previous migration state found:${NC}"
        echo "$previous_state" | jq '.'
        echo ""
    fi
    
    # Run specific phase if requested
    if [ -n "$MIGRATION_PHASE" ]; then
        case "$MIGRATION_PHASE" in
            "assessment")
                run_assessment
                ;;
            "infrastructure")
                run_infrastructure_deployment
                ;;
            "testing")
                run_parallel_testing
                ;;
            "migration")
                run_traffic_migration
                ;;
            "validation")
                run_post_migration_validation
                ;;
            "cleanup")
                run_cleanup
                ;;
            "rollback")
                run_rollback
                ;;
            *)
                echo -e "${RED}❌ Unknown migration phase: $MIGRATION_PHASE${NC}"
                exit 1
                ;;
        esac
        return
    fi
    
    # Run complete migration
    echo -e "${BLUE}🚀 Starting complete migration process...${NC}"
    
    run_assessment
    run_infrastructure_deployment
    run_parallel_testing
    run_traffic_migration
    run_post_migration_validation
    run_cleanup
    
    # Final summary
    echo ""
    echo -e "${GREEN}🎉 Migration completed successfully!${NC}"
    echo -e "${BLUE}📊 Migration Summary:${NC}"
    echo "  Strategy: $MIGRATION_STRATEGY"
    echo "  Project: $PROJECT_NAME"
    echo "  Environment: $ENVIRONMENT"
    echo "  Completed: $(date)"
    echo ""
    echo -e "${BLUE}📋 Next Steps:${NC}"
    echo "  1. Monitor VPN performance for 24-48 hours"
    echo "  2. Update documentation and runbooks"
    echo "  3. Train team on VPN-specific procedures"
    echo "  4. Schedule API Gateway cleanup (if applicable)"
    echo ""
    
    # Save final state
    save_migration_state "completed" "success" "Full migration completed successfully"
}

# Handle interrupts for rollback
trap 'echo -e "\n${YELLOW}Migration interrupted. Run with --phase rollback to revert changes.${NC}"; exit 1' INT TERM

# Run main function
main "$@"