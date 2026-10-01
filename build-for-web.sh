#!/bin/bash

set -e

flutter build web

cd build/web
python3 -m http.server 3000 --bind 0.0.0.0

cd ../../

echo "-----------------------------"
echo ""
echo "Web build ended successfully!"
echo ""
echo "-----------------------------"
