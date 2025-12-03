#!/bin/bash

echo "--------------------------------------"
echo "  DELETE ALL COMMITS — FULL RESET"
echo "--------------------------------------"
echo "This will erase ALL git history."
echo "Files will be kept. Repo will be reinitialized."
echo "--------------------------------------"

read -p "Are you sure? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "Canceled."
    exit 1
fi

# Store current remote
REMOTE_URL=$(git remote get-url origin 2>/dev/null)

echo "→ Removing .git folder..."
rm -rf .git

echo "→ Reinitializing repository..."
git init

if [ -n "$REMOTE_URL" ]; then
    echo "→ Restoring remote: $REMOTE_URL"
    git remote add origin "$REMOTE_URL"
fi

echo "→ Creating fresh commit..."
git add .
git commit -m "Initial clean commit (all previous history deleted)"

# Detect branch (main or master)
BRANCH=main
git branch -M $BRANCH

echo "→ Pushing to GitHub (force overwrite)..."
git push -u origin $BRANCH --force

echo "--------------------------------------"
echo "  COMPLETED: All commit history erased."
echo "--------------------------------------"
