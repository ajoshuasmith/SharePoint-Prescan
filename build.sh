#!/bin/bash
# Cross-platform build script for spready

set -e

VERSION="2.0.0"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
LDFLAGS="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}"

echo "Building spready v${VERSION} (${COMMIT})"
echo "================================================"

# Create dist directory
mkdir -p dist

# Build for different platforms
platforms=(
    "linux/amd64"
    "linux/arm64"
    "darwin/amd64"
    "darwin/arm64"
    "windows/amd64"
)

for platform in "${platforms[@]}"; do
    platform_split=(${platform//\// })
    GOOS=${platform_split[0]}
    GOARCH=${platform_split[1]}

    output_name="spready-${GOOS}-${GOARCH}"
    if [ "$GOOS" = "windows" ]; then
        output_name="${output_name}.exe"
    fi

    echo "Building for $GOOS/$GOARCH..."
    GOOS=$GOOS GOARCH=$GOARCH go build -ldflags="${LDFLAGS}" -o "dist/${output_name}" ./cmd/spready

    if [ $? -eq 0 ]; then
        echo "✓ Successfully built dist/${output_name}"
    else
        echo "✗ Failed to build for $GOOS/$GOARCH"
        exit 1
    fi
done

echo ""
echo "================================================"
echo "✓ All builds completed successfully!"
echo ""
echo "Binaries available in ./dist/"
ls -lh dist/

# Create checksums
echo ""
echo "Generating checksums..."
cd dist
sha256sum * > checksums.txt
cd ..

echo "✓ Checksums saved to dist/checksums.txt"
