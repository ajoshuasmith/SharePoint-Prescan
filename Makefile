.PHONY: all build clean test install cross-compile help

VERSION := 2.0.0
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
LDFLAGS := -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)

# Default target
all: build

# Build for current platform
build:
	@echo "Building spready..."
	@go build -ldflags="$(LDFLAGS)" -o spready ./cmd/spready
	@echo "✓ Build complete: ./spready"

# Build with optimization
build-optimized:
	@echo "Building optimized spready..."
	@go build -ldflags="$(LDFLAGS)" -trimpath -o spready ./cmd/spready
	@echo "✓ Optimized build complete: ./spready"

# Build for all platforms
cross-compile:
	@./build.sh

# Run tests
test:
	@echo "Running tests..."
	@go test -v ./...

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	@go test -v -coverprofile=coverage.out ./...
	@go tool cover -html=coverage.out -o coverage.html
	@echo "✓ Coverage report: coverage.html"

# Install to $GOPATH/bin
install:
	@echo "Installing spready..."
	@go install -ldflags="$(LDFLAGS)" ./cmd/spready
	@echo "✓ Installed to $(shell go env GOPATH)/bin/spready"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -f spready
	@rm -rf dist/
	@rm -f coverage.out coverage.html
	@echo "✓ Clean complete"

# Run the scanner on a test path
run:
	@go run ./cmd/spready --path=.

# Show help
help:
	@echo "SharePoint Prescan - Makefile targets:"
	@echo ""
	@echo "  make build           - Build for current platform"
	@echo "  make build-optimized - Build with optimizations"
	@echo "  make cross-compile   - Build for all platforms (Linux, macOS, Windows)"
	@echo "  make test            - Run unit tests"
	@echo "  make test-coverage   - Run tests with coverage report"
	@echo "  make install         - Install to GOPATH/bin"
	@echo "  make clean           - Remove build artifacts"
	@echo "  make run             - Run scanner on current directory"
	@echo "  make help            - Show this help"
	@echo ""
	@echo "Version: $(VERSION)"
	@echo "Commit:  $(COMMIT)"
