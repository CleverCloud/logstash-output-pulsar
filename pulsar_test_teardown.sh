#!/bin/bash
# Kill pulsar

set -ex

echo "Stopping Pulsar standalone"
pulsar/bin/pulsar-daemon stop standalone
