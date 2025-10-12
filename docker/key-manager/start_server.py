#!/usr/bin/env python3
"""
Key Manager Server Startup Script
Modifies the server to run on all interfaces for Docker networking
"""

import sys
import os

# Add the current directory to Python path
sys.path.insert(0, '/app')

# Import the server module
from km.server import app

if __name__ == "__main__":
    # Run on all interfaces (0.0.0.0) for Docker networking
    app.run(host="0.0.0.0", port=2020, debug=False)
