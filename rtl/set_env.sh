#!/bin/bash
# Project Environment Setup Script
# Source this file to set up PROJECT_PATH environment variable

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set PROJECT_PATH to the project root directory
export PROJECT_PATH="${SCRIPT_DIR}"
