#!/usr/bin/env bash
set -e
echo "Destroying lab..."
containerlab destroy -t topology.yaml