.PHONY: build clean install

# Build the Go binary
build:
	@echo "Building tmux-styler..."
	@mkdir -p bin
	@go build -o bin/tmux-styler main.go

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf bin/

# Install dependencies
deps:
	@echo "Installing Go dependencies..."
	@go mod tidy

# Install the binary to local bin (for development)
install: build
	@echo "Installing tmux-styler to ~/.local/bin..."
	@mkdir -p ~/.local/bin
	@cp bin/tmux-styler ~/.local/bin/

# Development build with verbose output
dev: deps build
	@echo "Development build complete!"
	@echo "Binary location: $(PWD)/bin/tmux-styler"

all: deps build