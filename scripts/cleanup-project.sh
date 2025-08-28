#!/bin/bash

# Project Cleanup Script
# Removes temporary files, old test results, and build artifacts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Starting project cleanup...${NC}"

# Function to safely remove files/directories
safe_remove() {
    local target="$1"
    local description="$2"
    
    if [ -e "$target" ]; then
        echo -e "${YELLOW}Removing $description: $target${NC}"
        rm -rf "$target"
        echo -e "${GREEN}✅ Removed $target${NC}"
    else
        echo -e "${BLUE}ℹ️  $target not found (already clean)${NC}"
    fi
}

# Function to clean files by pattern
clean_pattern() {
    local pattern="$1"
    local description="$2"
    
    echo -e "${YELLOW}Cleaning $description...${NC}"
    find . -name "$pattern" -type f -delete 2>/dev/null || true
    echo -e "${GREEN}✅ Cleaned $description${NC}"
}

echo -e "${BLUE}📁 Cleaning temporary files...${NC}"

# Remove temporary test files
clean_pattern "*.tmp" "temporary files"
clean_pattern "test_*.json" "test JSON files"
clean_pattern "*_test.json" "test result files"
clean_pattern "response*.json" "response files"

# Remove build artifacts
echo -e "${BLUE}🔨 Cleaning build artifacts...${NC}"
safe_remove "build/" "build directory"
safe_remove ".coverage" "coverage file"
safe_remove "*.zip" "zip files in root"

# Clean lambda deployment artifacts
echo -e "${BLUE}⚡ Cleaning lambda artifacts...${NC}"
find lambda/ -name "*.zip" -type f -delete 2>/dev/null || true
find lambda/ -name "*deployment*" -type f -delete 2>/dev/null || true

# Clean old test results (keep recent ones)
echo -e "${BLUE}📊 Cleaning old test results...${NC}"
find outputs/ -name "*.txt" -type f -mtime +7 -delete 2>/dev/null || true
find . -name "test-results-*.json" -type f -delete 2>/dev/null || true

# Clean Python cache
echo -e "${BLUE}🐍 Cleaning Python cache...${NC}"
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true

# Clean macOS files
echo -e "${BLUE}🍎 Cleaning macOS files...${NC}"
find . -name ".DS_Store" -delete 2>/dev/null || true

# Clean editor files
echo -e "${BLUE}📝 Cleaning editor files...${NC}"
find . -name "*.swp" -delete 2>/dev/null || true
find . -name "*.swo" -delete 2>/dev/null || true
find . -name "*~" -delete 2>/dev/null || true

# Clean log files
echo -e "${BLUE}📋 Cleaning log files...${NC}"
find . -name "*.log" -delete 2>/dev/null || true

echo -e "${GREEN}✅ Project cleanup completed!${NC}"
echo -e "${BLUE}ℹ️  To run this cleanup regularly, add to your workflow:${NC}"
echo -e "${YELLOW}   ./scripts/cleanup-project.sh${NC}"