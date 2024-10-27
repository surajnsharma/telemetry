#!/bin/bash

# Enable logging to a file
LOG_FILE="setup_git_repo.log"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

# Configuration files and size threshold for large files
CONFIG_FILE=".git_config"
LARGE_FILE_SIZE=100000000  # 100 MB (GitHub's limit for non-LFS files)

# Ensure Git is installed
if ! command -v git &> /dev/null; then
    echo "Git is not installed. Installing Git..."
    sudo apt-get update
    sudo apt-get install -y git
    if [ $? -ne 0 ]; then
        echo "Failed to install Git. Please check your network connection or permissions."
        exit 1
    fi
    echo "Git installed successfully."
else
    echo "Git is already installed."
fi

# Install Git LFS if not already installed
if ! command -v git-lfs &> /dev/null; then
    echo "Git LFS is not installed. Installing Git LFS..."
    sudo apt-get install -y git-lfs
    git lfs install
    if [ $? -ne 0 ]; then
        echo "Failed to install Git LFS. Please check your network connection or permissions."
        exit 1
    fi
    echo "Git LFS installed successfully."
else
    echo "Git LFS is already installed."
fi

# Load or prompt for GitHub user information
load_or_prompt_user_info() {
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

    # Set global Git configurations if not already set
    git config --global user.name "$GITHUB_USER"
    git config --global user.email "$GITHUB_EMAIL"
}

# Load or prompt for GitHub user information
load_or_prompt_user_info

# Set default pull behavior to merge to prevent divergence issues
git config pull.rebase false

# Function to set the remote URL to HTTPS for pull or SSH for push
set_remote_url() {
    if [ "$1" == "pull" ]; then
        REMOTE_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
    else
        REMOTE_URL="git@github.com:$GITHUB_USER/$REPO_NAME.git"
    fi
    git remote set-url origin "$REMOTE_URL"
}

# Function to manage SSH keys
setup_ssh_key() {
    # Check if SSH key exists; generate if missing
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "Generating SSH key..."
        ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$HOME/.ssh/id_ed25519" -q -N ""
        if [ $? -ne 0 ]; then
            echo "Failed to generate SSH key. Please check your permissions and try again."
            exit 1
        fi
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
    echo "Testing SSH connection to GitHub..."
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1)
    if [[ "$SSH_OUTPUT" == *"You've successfully authenticated"* ]]; then
        echo "SSH connection to GitHub was successful."
    elif [[ "$SSH_OUTPUT" == *"Permission denied (publickey)"* ]]; then
        echo "SSH connection to GitHub failed due to missing public key."
        echo "Please ensure your SSH key is added to your GitHub account under Settings > SSH and GPG keys > New SSH key."
        echo "Copy the SSH key below and add it to your GitHub account:"
        cat "$HOME/.ssh/id_ed25519.pub"
        echo -e "\nAfter adding the SSH key, re-run the script.\n"
        exit 1
    else
        echo "SSH connection to GitHub failed. Ensure the SSH key is added to your GitHub account."
        echo "Output from SSH: $SSH_OUTPUT"
        exit 1
    fi
}

# Ask user if they want to update (pull) or push changes
echo "Choose an action:"
echo "1) Update (pull latest changes)"
echo "2) Push new changes (requires SSH access)"
read -p "Enter your choice (1 for update, 2 for push): " user_action

# Function to track large files with Git LFS
track_large_files_with_lfs() {
    echo "Checking for files larger than $(($LARGE_FILE_SIZE / 1000000)) MB to track with Git LFS..."
    find . -type f -size +${LARGE_FILE_SIZE}c -not -path "./.git/*" | while read -r large_file; do
        echo "Tracking large file with Git LFS: $large_file"
        git lfs track "$large_file"
        git add .gitattributes
        git add "$large_file"
        git commit -m "Track large file $large_file with Git LFS"
    done
}

if [ "$user_action" == "1" ]; then
    # Set remote to HTTPS for pulling
    set_remote_url "pull"
    
    # Check if there are any local changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "Local changes detected. Do you want to keep these local changes and ignore the remote changes?"
        read -p "Enter 'yes' to keep local changes or 'no' to override with remote changes: " keep_local_choice

        if [ "$keep_local_choice" == "yes" ]; then
            echo "Stashing local changes temporarily..."
            git stash push -m "Auto-stash before pull"
            echo "Pulling latest changes from remote..."
            git pull origin main
            echo "Applying stashed changes..."
            git stash pop
            if [ $? -ne 0 ]; then
                echo "Merge conflicts detected. Please resolve conflicts and commit changes manually."
                exit 1
            fi
            echo "Local changes applied on top of remote updates."
        else
            echo "Overriding local changes and pulling the latest updates..."
            git reset --hard
            git pull origin main
            if [ $? -ne 0 ]; then
                echo "Failed to pull changes from the remote repository. Please resolve any conflicts and try again."
                exit 1
            fi
            echo "Local repository successfully updated."
        fi
    else
        # Pull latest changes from the remote repository
        echo "Updating local repository with latest changes from remote..."
        git pull origin main
        if [ $? -ne 0 ]; then
            echo "Failed to pull changes from the remote repository. Please resolve any conflicts and try again."
            exit 1
        fi
        echo "Local repository successfully updated."
    fi
    exit 0  # Exit after updating
fi

# Proceed with SSH setup if the user chose to push changes
if [ "$user_action" == "2" ]; then
    # Set remote to SSH for pushing
    set_remote_url "push"
    
    # SSH setup for pushing (only for admins)
    setup_ssh_key

    # Track large files automatically with Git LFS
    track_large_files_with_lfs

    # Stage and push changes
    echo "Staging and committing changes..."
    git add .
    git commit -m "Auto-commit: updating remote repository"
    git push origin main
    if [ $? -ne 0 ]; then
        echo "Failed to push changes. Please check your SSH key configuration."
        exit 1
    fi
    echo "Changes successfully pushed to the remote repository."
fi

