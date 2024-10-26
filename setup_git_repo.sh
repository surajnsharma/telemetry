#!/bin/bash

# Ensure Git is installed
if ! command -v git &> /dev/null; then
    echo "Git is not installed. Installing Git..."
    sudo apt-get update
    sudo apt-get install -y git
    echo "Git installed successfully."
else
    echo "Git is already installed."
fi

# Configuration file for storing GitHub info
CONFIG_FILE=".git_config"
LARGE_FILE_SIZE=100000000  # Set the size threshold to 100 MB (GitHub's limit)

# Load or prompt for GitHub user information
load_or_prompt_user_info() {
    # Check if .git_config exists and load existing configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Current Git configuration:"
        echo "GitHub Username: $GITHUB_USER"
        echo "GitHub Email: $GITHUB_EMAIL"
        echo "Repository Name: $REPO_NAME"
        echo "Remote URL: git@github.com:$GITHUB_USER/$REPO_NAME.git"
        echo -e "\nPress Enter to keep this configuration or type 'change' to update."
        read -p "" choice
    else
        choice="change"
    fi

    # If user wants to change or no config exists, prompt for new information
    if [ "$choice" == "change" ] || [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_EMAIL" ] || [ -z "$REPO_NAME" ]; then
        while [[ -z "$GITHUB_USER" ]]; do
            read -p "Enter your GitHub username (e.g., surajnsharma): " GITHUB_USER
        done
        while [[ -z "$GITHUB_EMAIL" ]]; do
            read -p "Enter your GitHub email (e.g., surajshamra@juniper.net): " GITHUB_EMAIL
        done
        while [[ -z "$REPO_NAME" ]]; do
            read -p "Enter the name of the repository (e.g., telemetry): " REPO_NAME
        done

        # Save new configuration to .git_config file
        echo "GITHUB_USER=\"$GITHUB_USER\"" > "$CONFIG_FILE"
        echo "GITHUB_EMAIL=\"$GITHUB_EMAIL\"" >> "$CONFIG_FILE"
        echo "REPO_NAME=\"$REPO_NAME\"" >> "$CONFIG_FILE"
        echo "Configuration saved to $CONFIG_FILE"
    fi
}

# Load or prompt for GitHub user information
load_or_prompt_user_info

# Check if SSH key exists; generate if missing
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$HOME/.ssh/id_ed25519" -q -N ""
    echo "SSH key generated."
else
    echo "SSH key already exists. Key location: $HOME/.ssh/id_ed25519"
fi

# Display SSH key and prompt to add to GitHub if not added
echo "Copy the SSH key below and add it to your GitHub account under Settings > SSH and GPG keys > New SSH key:"
cat "$HOME/.ssh/id_ed25519.pub"
echo -e "\nPress Enter after adding the SSH key to GitHub..."
read -p ""

# Test SSH connection to GitHub
ssh -T git@github.com

# Initialize Git repository if not already initialized
if [ ! -d ".git" ]; then
    echo "Initializing Git repository..."
    git init
fi

# Set remote URL to use SSH, or update it if it already exists
REMOTE_URL="git@github.com:$GITHUB_USER/$REPO_NAME.git"
if git remote get-url origin &> /dev/null; then
    echo "Updating existing remote URL to $REMOTE_URL"
    git remote set-url origin "$REMOTE_URL"
else
    echo "Setting remote URL to $REMOTE_URL"
    git remote add origin "$REMOTE_URL"
fi
git remote -v

# Check branch and set to main
echo "Setting branch to 'main'..."
git branch -M main

# Stage and commit files if there are changes
if [ -n "$(git status --porcelain)" ]; then
    echo "Staging and committing changes..."
    git add .
    git commit -m "Auto-commit: updates to repository"
else
    echo "No new changes to commit."
fi

# Install Git Large File Storage (LFS) if not already installed
if ! command -v git-lfs &> /dev/null; then
    echo "Installing Git LFS..."
    sudo apt-get install -y git-lfs
    git lfs install
fi

# Automatically detect large files and track them with Git LFS
echo "Detecting files larger than $(($LARGE_FILE_SIZE / 1000000)) MB..."
find . -type f -size +${LARGE_FILE_SIZE}c -not -path "./.git/*" | while read -r large_file; do
    echo "Tracking large file with Git LFS: $large_file"
    git lfs track "$large_file"
    git add .gitattributes
    git add "$large_file"
    git commit -m "Add large file $large_file with Git LFS"
done

# Push to GitHub
echo "Pushing to GitHub..."
git push -u origin main

echo "Repository setup and push complete. Any new changes have been committed and pushed."
