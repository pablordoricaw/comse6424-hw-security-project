#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0"
    echo ""
    echo "Description:"
    echo "  Opens a new Firefox window with job hunt workspace tabs."
    echo ""
    echo "Options:"
    echo "  -h, --help  Show this help message"
    exit 1
}

# Check if help flag is passed
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# Fill URLS with the websites most used while working on this project
URLS=(
    "https://www.google.com"
    "https://www.github.com"
)

# Open first URL in a new window
/Applications/Firefox.app/Contents/MacOS/firefox -new-window "${URLS[0]}" &

# Brief wait for the window to open
sleep 1

# Open remaining URLs as new tabs in that window
for i in "${!URLS[@]}"; do
    if [ $i -eq 0 ]; then continue; fi
    /Applications/Firefox.app/Contents/MacOS/firefox -new-tab "${URLS[$i]}" &
    sleep 0.3
done
