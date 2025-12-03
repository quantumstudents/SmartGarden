#!/bin/bash

# Show Git version
git --version

# Add all files
git add .

# Commit with message
git commit -m "initial commit"

# Push to main branch
git push origin main

# === Tagging for GitHub Actions Release Build ===
#git tag v1.0
#git push origin v1.0

echo "Done."
