#!/bin/bash

# Simple auto-commit + push script

# Get the current branch name
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "--------------------------------------"
echo " Auto Commit & Push Script"
echo " Branch: $BRANCH"
echo "--------------------------------------"

# Stage all changes
git add .

# Commit with a default message (allow override)
MESSAGE=${1:-"Auto-commit from Raspberry Pi"}
git commit -m "$MESSAGE"

# Push to the current branch
git push origin "$BRANCH"

echo "--------------------------------------"
echo " Commit and push completed!"
echo "--------------------------------------"

