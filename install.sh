#!/bin/bash
# SharePoint-Prescan Go Edition - Quick Install & Run Script
# Usage: curl -sSL https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/install.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Detect platform and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
    linux*) OS="linux" ;;
    darwin*) OS="darwin" ;;
    *) echo -e "${RED}Unsupported OS: $OS${NC}"; exit 1 ;;
esac

case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

BINARY_NAME="spready-$OS-$ARCH"
DOWNLOAD_URL="https://github.com/ajoshuasmith/SharePoint-Prescan/releases/latest/download/$BINARY_NAME"
LOCAL_PATH="/tmp/$BINARY_NAME"

echo ""
echo -e "${CYAN}SharePoint-Prescan Go Edition - Quick Install${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""
echo -e "${GRAY}Platform: $OS-$ARCH${NC}"
echo -e "${GRAY}Binary:   $BINARY_NAME${NC}"
echo ""

# Download if not present
if [ ! -f "$LOCAL_PATH" ] || [ ! -s "$LOCAL_PATH" ]; then
    echo -e "${YELLOW}Downloading binary...${NC}"
    if command -v curl &> /dev/null; then
        curl -fsSL "$DOWNLOAD_URL" -o "$LOCAL_PATH" || {
            echo -e "${RED}Failed to download from: $DOWNLOAD_URL${NC}"
            echo ""
            echo -e "${YELLOW}To build from source instead:${NC}"
            echo -e "${GRAY}  git clone https://github.com/ajoshuasmith/SharePoint-Prescan.git${NC}"
            echo -e "${GRAY}  cd SharePoint-Prescan${NC}"
            echo -e "${GRAY}  go build -o spready ./cmd/spready${NC}"
            exit 1
        }
    elif command -v wget &> /dev/null; then
        wget -q "$DOWNLOAD_URL" -O "$LOCAL_PATH" || {
            echo -e "${RED}Failed to download from: $DOWNLOAD_URL${NC}"
            exit 1
        }
    else
        echo -e "${RED}Neither curl nor wget found. Please install one of them.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Downloaded successfully${NC}"
fi

# Make executable
chmod +x "$LOCAL_PATH"

echo ""

# If no arguments, show usage
if [ $# -eq 0 ]; then
    echo -e "${CYAN}Usage Examples:${NC}"
    echo ""
    echo -e "${GRAY}  # Interactive download and run:${NC}"
    echo -e "  curl -sSL https://raw.githubusercontent.com/.../install.sh | bash"
    echo ""
    echo -e "${GRAY}  # With parameters:${NC}"
    echo -e "  curl -sSL https://raw.githubusercontent.com/.../install.sh | bash -s -- --path /data"
    echo ""
    echo -e "${GRAY}  # Download once, run multiple times:${NC}"
    echo -e "  curl -sSL https://raw.githubusercontent.com/.../install.sh -o install.sh"
    echo -e "  chmod +x install.sh"
    echo -e "  ./install.sh --path /data --destination https://contoso.sharepoint.com/..."
    echo ""
    echo -e "${GREEN}Binary downloaded to: $LOCAL_PATH${NC}"
    echo -e "${GRAY}You can run it directly:${NC}"
    echo -e "  $LOCAL_PATH --path /data"
    echo ""
    exit 0
fi

# Run the scanner with provided arguments
echo -e "${GREEN}Running scan...${NC}"
echo ""

"$LOCAL_PATH" "$@"

EXIT_CODE=$?
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}Scan completed successfully!${NC}"
elif [ $EXIT_CODE -eq 1 ]; then
    echo -e "${YELLOW}Scan completed with warnings${NC}"
elif [ $EXIT_CODE -eq 2 ]; then
    echo -e "${RED}Scan completed with critical issues${NC}"
fi

echo ""
echo -e "${GRAY}Binary location: $LOCAL_PATH${NC}"
echo -e "${GRAY}To run again: $LOCAL_PATH --path <path>${NC}"
echo ""

exit $EXIT_CODE
