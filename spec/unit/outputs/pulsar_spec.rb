# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require 'logstash/outputs/pulsar'
require 'json'

describe "outputs/pulsar" do
  let (:simple_pulsar_config) {{'topic_id' => "my-topic"}}
  let (:event) { LogStash::Event.new({
    'message' => 'hello',
    'host' => '172.0.0.1',
    '@timestamp' => LogStash::Timestamp.now
  }) }

  context 'when initializing' do
    it "should register" do
      output = LogStash::Plugin.lookup("output", "pulsar").new(simple_pulsar_config)
      expect {output.register}.to_not raise_error
    end
    it 'should populate pulsar config with default values' do
      pulsar = LogStash::Outputs::Pulsar.new(simple_pulsar_config)
      insist {pulsar.bootstrap_servers} == 'pulsar://localhost:6650'
      insist {pulsar.topic_id} == "my-topic"
    end
  end

  context 'when outputting messages' do
    it 'should send logstash event to pulsar broker' do
        pulsar = LogStash::Outputs::Pulsar.new(simple_pulsar_config)
        pulsar.register
        expect {pulsar.multi_receive([event])}.to_not raise_error
    end
  end
end
