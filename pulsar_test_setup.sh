#!/bin/bash
# Setup pulsar in standalone

set -ex
if [ -n "${PULSAR_VERSION+1}" ]; then
  echo "PULSAR_VERSION is $PULSAR_VERSION"
else
  PULSAR_VERSION=2.2.1
fi

echo "Downloading pulsar version $PULSAR_VERSION."
curl -s -o pulsar.tgz "https://archive.apache.org/dist/pulsar/pulsar-$PULSAR_VERSION/apache-pulsar-$PULSAR_VERSION-bin.tar.gz"
mkdir pulsar && tar xzf pulsar.tgz -C pulsar --strip-components 1

echo "Starting pulsar standalone"
pulsar/bin/pulsar-daemon start standalone
sleep 10

#echo 'Sending hello-pulsar message to topic: "my-topic"'
#pulsar/bin/pulsar-client produce my-topic --messages "hello-pulsar"