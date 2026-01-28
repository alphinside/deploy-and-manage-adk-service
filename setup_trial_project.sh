#!/bin/bash
#
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ============================================================
# Google Cloud Workshop - Project Setup Script
# ============================================================
# This script helps workshop participants:
# 1. Verify trial billing account exists first
# 2. Check if a project already exists in .env (safeguard)
# 3. Validate existing project has trial billing linked
# 4. Create a new GCP project if needed
# 5. Link trial billing account automatically
# 6. Save the project ID to .env file
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Google Cloud Workshop - Project Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# ============================================================
# Step 0: Check if gcloud is authenticated
# ============================================================
echo -e "${YELLOW}Step 0: Checking gcloud authentication${NC}"
echo -e "Verifying you are logged in to Google Cloud...\n"

# Check if user is authenticated by trying to get the active account
ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null)

if [ -z "$ACTIVE_ACCOUNT" ]; then
    echo -e "${RED}ERROR: You are not authenticated with Google Cloud!${NC}"
    echo ""
    echo "Please authenticate first by running one of the following commands:"
    echo ""
    echo -e "  ${YELLOW}Option 1 - If using Cloud Shell:${NC}"
    echo -e "    gcloud auth login --no-launch-browser"
    echo ""
    echo -e "  ${YELLOW}Option 2 - For local development:${NC}"
    echo -e "    gcloud auth login"
    echo ""
    echo "After authenticating, run this script again."
    exit 1
fi

echo -e "${GREEN}✓ Authenticated as: ${ACTIVE_ACCOUNT}${NC}"
echo ""

# ============================================================
# Step 1: Check for Trial Billing Account FIRST
# ============================================================
echo -e "${YELLOW}Step 1: Checking for Trial Billing Account${NC}"
echo -e "Searching for trial billing accounts...\n"

# Get all billing accounts
BILLING_ACCOUNTS=$(gcloud billing accounts list --format="csv[no-heading](ACCOUNT_ID,NAME,OPEN)" 2>/dev/null)

if [ -z "$BILLING_ACCOUNTS" ]; then
    echo -e "${RED}ERROR: No billing accounts found!${NC}"
    echo ""
    echo "This workshop requires a Google Cloud trial billing account."
    echo "Please ensure you have claimed your trial credit first."
    exit 1
fi

# Filter for trial billing accounts only (accounts with "Trial" in the name)
# Store the last one found (most recently added)
SELECTED_ACCOUNT=""
SELECTED_NAME=""
TRIAL_COUNT=0

echo -e "Found trial billing accounts:"
echo "-------------------------------------------"
while IFS=',' read -r account_id name open; do
    # Check if it's a trial account (contains "Trial" in name) and is open
    if [[ "$name" == *"Trial"* ]] && [ "$open" = "True" ]; then
        TRIAL_COUNT=$((TRIAL_COUNT + 1))
        # Keep updating to get the last (latest) one
        SELECTED_ACCOUNT="$account_id"
        SELECTED_NAME="$name"
        echo -e "  ${GREEN}[$TRIAL_COUNT]${NC} $name"
        echo "       ID: $account_id"
    fi
done <<< "$BILLING_ACCOUNTS"
echo "-------------------------------------------"

# Error if no trial billing account found - EXIT EARLY before anything else
if [ $TRIAL_COUNT -eq 0 ]; then
    echo -e "${RED}ERROR: No active trial billing account found!${NC}"
    echo ""
    echo "This workshop requires an active Google Cloud trial billing account."
    echo ""
    echo "Possible reasons:"
    echo "  - You haven't claimed your free trial credit yet"
    echo "  - Your trial billing account is closed/expired (OPEN: False)"
    echo ""
    echo "Your current billing accounts:"
    gcloud billing accounts list
    echo ""
    echo -e "${YELLOW}Note: Trial accounts with OPEN: False are expired and cannot be used.${NC}"
    exit 1
fi

# Auto-select the latest (last) trial billing account
echo -e "\n${GREEN}✓ Trial billing account found!${NC}"
echo -e "  Name: ${GREEN}${SELECTED_NAME}${NC}"
echo -e "  ID:   ${GREEN}${SELECTED_ACCOUNT}${NC}"
echo ""

# ============================================================
# SAFEGUARD: Check if project already exists in .env
# ============================================================
ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
    # Check if GCLOUD_PROJECT_ID is set in .env
    EXISTING_PROJECT=$(grep "^GCLOUD_PROJECT_ID=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
    
    if [ -n "$EXISTING_PROJECT" ]; then
        echo -e "${YELLOW}Safeguard: Found existing project in .env${NC}"
        echo -e "Project ID: ${GREEN}${EXISTING_PROJECT}${NC}"
        echo -e "Validating project setup...\n"
        
        # Check if project exists in GCP
        if gcloud projects describe "$EXISTING_PROJECT" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Project exists in Google Cloud"
            
            # Check if project has billing linked
            BILLING_INFO=$(gcloud billing projects describe "$EXISTING_PROJECT" --format="value(billingAccountName)" 2>/dev/null)
            
            if [ -n "$BILLING_INFO" ]; then
                # Extract billing account ID
                BILLING_ACCOUNT_ID=$(echo "$BILLING_INFO" | sed 's|billingAccounts/||')
                
                # Check if it's a trial billing account
                BILLING_NAME=$(gcloud billing accounts describe "$BILLING_ACCOUNT_ID" --format="value(displayName)" 2>/dev/null)
                
                if [[ "$BILLING_NAME" == *"Trial"* ]]; then
                    echo -e "  ${GREEN}✓${NC} Linked to trial billing account: ${BILLING_NAME}"
                    echo ""
                    echo -e "${BLUE}============================================${NC}"
                    echo -e "${GREEN}  Project Already Set Up! ✓${NC}"
                    echo -e "${BLUE}============================================${NC}"
                    echo -e "  Project ID:      ${GREEN}${EXISTING_PROJECT}${NC}"
                    echo -e "  Billing Account: ${GREEN}${BILLING_ACCOUNT_ID}${NC}"
                    echo -e "${BLUE}============================================${NC}"
                    echo ""
                    echo -e "Your environment is ready. No action needed!"
                    echo -e "To use a different project, remove GCLOUD_PROJECT_ID from .env and re-run this script."
                    echo ""
                    
                    # Activate the project
                    echo -e "Activating project..."
                    gcloud config set project "$EXISTING_PROJECT"
                    echo -e "${GREEN}✓ Project activated: ${EXISTING_PROJECT}${NC}"
                    exit 0
                else
                    echo -e "  ${YELLOW}⚠${NC} Project is linked to non-trial billing: ${BILLING_NAME}"
                    echo -e "  This workshop requires a trial billing account."
                    echo -e "  Creating a new project with trial billing...\n"
                fi
            else
                echo -e "  ${YELLOW}⚠${NC} Project exists but has no billing account linked"
                echo -e "  Linking trial billing account to this project...\n"
                # Skip project creation, just link billing
                PROJECT_ID="$EXISTING_PROJECT"
                SKIP_PROJECT_CREATION=true
            fi
        else
            echo -e "  ${RED}✗${NC} Project does not exist in Google Cloud"
            echo -e "  The project ID in .env is invalid or has been deleted."
            echo -e "  Creating a new project...\n"
        fi
        echo ""
    fi
fi

# ============================================================
# Step 2: Create a new GCP Project (skip if linking billing to existing project)
# ============================================================
if [ "$SKIP_PROJECT_CREATION" != "true" ]; then
    DEFAULT_PROJECT_ID="workshop-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    echo -e "${YELLOW}Step 2: Create a new GCP Project${NC}"
    echo -e "Suggested project ID: ${GREEN}${DEFAULT_PROJECT_ID}${NC}"
    read -p "Enter project ID (press Enter for suggested): " PROJECT_ID
    PROJECT_ID=${PROJECT_ID:-$DEFAULT_PROJECT_ID}

    # Validate project ID format (lowercase letters, digits, hyphens only)
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        echo -e "${RED}Error: Project ID must:${NC}"
        echo "  - Be 6 to 30 characters"
        echo "  - Start with a lowercase letter"
        echo "  - Contain only lowercase letters, digits, and hyphens"
        echo "  - Not end with a hyphen"
        exit 1
    fi

    echo -e "\nCreating project: ${GREEN}${PROJECT_ID}${NC}..."
    gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create project. The ID might already be taken.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Project created successfully!${NC}"
    echo ""
else
    echo -e "${YELLOW}Step 2: Using existing project${NC}"
    echo -e "Project ID: ${GREEN}${PROJECT_ID}${NC}"
    echo -e "${GREEN}✓ Skipping project creation${NC}"
    echo ""
fi

# ============================================================
# Step 3: Link Trial Billing Account to Project
# ============================================================
echo -e "${YELLOW}Step 3: Link Trial Billing Account${NC}"
echo -e "Linking billing account to project..."
gcloud billing projects link "$PROJECT_ID" --billing-account="$SELECTED_ACCOUNT"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to link billing account.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Billing account linked successfully!${NC}"
echo ""

# ============================================================
# Step 4: Set as default project
# ============================================================
echo -e "${YELLOW}Step 4: Setting as Default Project${NC}"
gcloud config set project "$PROJECT_ID"
echo -e "${GREEN}✓ Default project set to: ${PROJECT_ID}${NC}"
echo ""

# ============================================================
# Step 5: Write to .env file
# ============================================================
echo -e "${YELLOW}Step 5: Saving to .env file${NC}"
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

# Check if .env exists
if [ -f "$ENV_FILE" ]; then
    # .env exists - update or append GOOGLE_CLOUD_PROJECT
    if grep -q "^GOOGLE_CLOUD_PROJECT=" "$ENV_FILE"; then
        # Update existing value
        sed -i "s/^GOOGLE_CLOUD_PROJECT=.*/GOOGLE_CLOUD_PROJECT=${PROJECT_ID}/" "$ENV_FILE"
        echo -e "Updated GOOGLE_CLOUD_PROJECT in existing ${ENV_FILE}"
    else
        # Append to existing file
        echo "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" >> "$ENV_FILE"
        echo -e "Appended GOOGLE_CLOUD_PROJECT to existing ${ENV_FILE}"
    fi
elif [ -f "$ENV_EXAMPLE" ]; then
    # .env doesn't exist but .env.example does - use it as template
    echo -e "Using ${ENV_EXAMPLE} as template..."
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    # Update the project ID in the copied file
    if grep -q "^GOOGLE_CLOUD_PROJECT=" "$ENV_FILE"; then
        sed -i "s/^GOOGLE_CLOUD_PROJECT=.*/GOOGLE_CLOUD_PROJECT=${PROJECT_ID}/" "$ENV_FILE"
    else
        echo "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" >> "$ENV_FILE"
    fi
    echo -e "Created ${ENV_FILE} from ${ENV_EXAMPLE} template"
else
    # Neither .env nor .env.example exists - create new .env file
    echo "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" > "$ENV_FILE"
    echo -e "Created new ${ENV_FILE}"
fi

echo -e "${GREEN}✓ Project ID saved to .env file!${NC}"
echo ""

# ============================================================
# Summary
# ============================================================
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  Setup Complete! 🎉${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "  Project ID:      ${GREEN}${PROJECT_ID}${NC}"
echo -e "  Billing Account: ${GREEN}${SELECTED_ACCOUNT}${NC}"
echo -e "  Environment:     ${GREEN}.env${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "You can now proceed with the workshop!"
echo -e "To verify, run: ${YELLOW}gcloud config get-value project${NC}"
