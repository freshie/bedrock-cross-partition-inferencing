# Branching Strategy

## Overview
This repository follows a Git Flow-inspired branching strategy to maintain stability while enabling continuous development.

## Branch Structure

### `main` - Production/Stable Branch
- **Purpose**: Contains stable, production-ready code
- **Protection**: Only accepts merges from `develop` via pull requests
- **Releases**: All releases are tagged from this branch
- **Direct commits**: Not allowed (except for hotfixes)

### `develop` - Integration Branch  
- **Purpose**: Integration branch for ongoing development
- **Source**: Branched from `main`
- **Merges into**: `main` (for releases)
- **Receives**: Feature branches, bug fixes

### Feature Branches - `feature/feature-name`
- **Purpose**: Development of new features
- **Naming**: `feature/descriptive-name` (e.g., `feature/nova-premier-support`)
- **Source**: Branched from `develop`
- **Merges into**: `develop`
- **Lifecycle**: Created → Developed → Merged → Deleted

### Hotfix Branches - `hotfix/issue-name`
- **Purpose**: Critical fixes for production issues
- **Naming**: `hotfix/descriptive-name` (e.g., `hotfix/api-timeout-fix`)
- **Source**: Branched from `main`
- **Merges into**: Both `main` and `develop`
- **Lifecycle**: Created → Fixed → Merged → Deleted

## Workflow

### New Feature Development
```bash
# Start from develop
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feature/your-feature-name

# Develop your feature
# ... make commits ...

# Push feature branch
git push origin feature/your-feature-name

# Create pull request: feature/your-feature-name → develop
```

### Release Process
```bash
# From develop branch
git checkout develop
git pull origin develop

# Merge to main
git checkout main
git pull origin main
git merge develop

# Tag the release
git tag -a v1.3.0 -m "Release v1.3.0: Description"
git push origin main --tags
```

### Hotfix Process
```bash
# Create hotfix from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-fix

# Fix the issue
# ... make commits ...

# Merge to main
git checkout main
git merge hotfix/critical-fix
git tag -a v1.2.1 -m "Hotfix v1.2.1: Critical fix"

# Merge to develop
git checkout develop
git merge hotfix/critical-fix

# Push everything
git push origin main develop --tags

# Clean up
git branch -d hotfix/critical-fix
```

## Branch Protection Rules (GitHub)

When repository approval comes through, configure these protection rules:

### `main` branch:
- Require pull request reviews before merging
- Require status checks to pass before merging
- Require branches to be up to date before merging
- Restrict pushes that create files larger than 100MB
- Require signed commits (optional)

### `develop` branch:
- Require pull request reviews before merging (optional)
- Allow force pushes (for rebasing)

## Current Status

- ✅ `main` branch: Stable v1.2.0 release
- ✅ `develop` branch: Created for ongoing development
- 🔄 Ready for feature branch workflow

## Examples

### Feature Branch Names
- `feature/nova-premier-support`
- `feature/enhanced-error-handling`
- `feature/cost-optimization`
- `feature/monitoring-dashboard`

### Release Tags
- `v1.2.0` - Current stable release
- `v1.3.0` - Next planned release
- `v1.2.1` - Hotfix release (if needed)

## Benefits

1. **Stability**: `main` always contains working code
2. **Parallel Development**: Multiple features can be developed simultaneously
3. **Code Review**: All changes go through pull requests
4. **Release Management**: Clear release process with tagging
5. **Hotfix Support**: Quick fixes without disrupting development
6. **History**: Clean, readable git history