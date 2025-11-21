#!/bin/bash

# Apple OAuth Secret Key Generator
# This script generates a JWT token for Apple Sign-In with Supabase

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Apple OAuth Secret Key Generator${NC}"
echo "=========================================="
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
    echo "Please install Python 3 to use this script"
    exit 1
fi

# Check if required Python packages are installed
PYTHON_CMD="python3"
VENV_DIR=""

if ! python3 -c "import jwt" 2>/dev/null; then
    echo -e "${YELLOW}Required Python packages not found. Installing...${NC}"
    
    # Try installing with --user flag first (works with externally-managed environments)
    if pip3 install --user PyJWT cryptography 2>/dev/null; then
        echo -e "${GREEN}✓ Packages installed successfully with --user flag${NC}"
        # Use python3 with user site-packages
        PYTHON_CMD="python3"
    else
        echo -e "${YELLOW}Installation with --user failed. Trying virtual environment...${NC}"
        
        # Create a temporary virtual environment
        VENV_DIR=$(mktemp -d)
        if python3 -m venv "$VENV_DIR" 2>/dev/null; then
            # Activate venv and install packages
            source "$VENV_DIR/bin/activate"
            if pip install PyJWT cryptography 2>/dev/null; then
                echo -e "${GREEN}✓ Packages installed in temporary virtual environment${NC}"
                PYTHON_CMD="$VENV_DIR/bin/python3"
            else
                echo -e "${RED}Error: Failed to install required packages in virtual environment${NC}"
                echo -e "${YELLOW}Please install manually:${NC}"
                echo "  pip3 install --user PyJWT cryptography"
                echo "  or"
                echo "  python3 -m venv venv && source venv/bin/activate && pip install PyJWT cryptography"
                rm -rf "$VENV_DIR"
                exit 1
            fi
        else
            echo -e "${RED}Error: Failed to create virtual environment${NC}"
            echo -e "${YELLOW}Please install packages manually:${NC}"
            echo "  pip3 install --user PyJWT cryptography"
            exit 1
        fi
    fi
    echo ""
fi

# Get inputs
read -p "Enter your Team ID (e.g., ZMR9YNSJN2): " TEAM_ID
read -p "Enter your Key ID (e.g., GP8NFX44F7): " KEY_ID
read -p "Enter your Service ID (e.g., com.semina.unheardpath.supabase): " SERVICE_ID
read -p "Enter path to your .p8 key file: " PRIVATE_KEY_PATH

# Validate inputs
if [ -z "$TEAM_ID" ] || [ -z "$KEY_ID" ] || [ -z "$SERVICE_ID" ] || [ -z "$PRIVATE_KEY_PATH" ]; then
    echo -e "${RED}Error: All fields are required${NC}"
    exit 1
fi

if [ ! -f "$PRIVATE_KEY_PATH" ]; then
    echo -e "${RED}Error: Key file not found: $PRIVATE_KEY_PATH${NC}"
    exit 1
fi

# Generate the secret using Python
echo ""
echo -e "${GREEN}Generating OAuth secret...${NC}"
echo ""

SECRET=$($PYTHON_CMD << EOF
import jwt
import time
import sys

try:
    # Read private key
    with open("$PRIVATE_KEY_PATH", 'r') as f:
        private_key = f.read()
    
    # Create JWT
    headers = {
        "alg": "ES256",
        "kid": "$KEY_ID"
    }
    
    payload = {
        "iss": "$TEAM_ID",
        "iat": int(time.time()),
        "exp": int(time.time()) + 15768000,  # 6 months
        "aud": "https://appleid.apple.com",
        "sub": "$SERVICE_ID"
    }
    
    secret = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    print(secret)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
)

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}YOUR APPLE OAUTH SECRET KEY:${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    echo "$SECRET"
    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Copy this secret key and paste it into Supabase!${NC}"
    echo -e "${YELLOW}⚠️  This secret expires in 6 months - set a reminder!${NC}"
    echo ""
    
    # Try to copy to clipboard if available
    if command -v pbcopy &> /dev/null; then
        echo "$SECRET" | pbcopy
        echo -e "${GREEN}✓ Secret key copied to clipboard!${NC}"
    elif command -v xclip &> /dev/null; then
        echo "$SECRET" | xclip -selection clipboard
        echo -e "${GREEN}✓ Secret key copied to clipboard!${NC}"
    fi
    
    # Clean up virtual environment if we created one
    if [ -n "$VENV_DIR" ] && [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
    fi
else
    echo -e "${RED}Error generating secret key${NC}"
    # Clean up virtual environment if we created one
    if [ -n "$VENV_DIR" ] && [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
    fi
    exit 1
fi

