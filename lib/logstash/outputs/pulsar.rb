require 'logstash/namespace'
require 'logstash/outputs/base'
require 'java'
require 'logstash-output-pulsar_jars.rb'

java_import org.apache.pulsar.client.api.PulsarClient
java_import org.apache.pulsar.client.api.CompressionType
java_import org.apache.pulsar.client.impl.auth.AuthenticationBasic
java_import java.util.concurrent.TimeUnit

class LogStash::Outputs::Pulsar < LogStash::Outputs::Base
  declare_threadsafe!

  config_name 'pulsar'

  default :codec, 'plain'

  # pulsar client configuration
  config :allow_tls_insecure_connection, :validate => :boolean, :default => false
  config :auth_plugin_class_name, :validate => :string, :default => ""
  config :auth_params_string, :validate => :string, :default => ""
  config :bootstrap_servers, :validate => :string, :default => 'pulsar://localhost:6650' # use pulsar+ssl to enable TLS
  config :connections_per_broker, :validate => :number, :default => 1
  config :enable_tcp_no_delay, :validate => :boolean, :default => true
  config :enable_tls_hostname_verification, :validate => :boolean, :default => false
  config :keep_alive_interval, :validate => :number, :default => 30 # milliseconds
  config :num_io_threads, :validate => :number, :default => 1
  config :num_listener_threads, :validate => :number, :default => 1
  config :operation_timeout, :validate => :number, :default => 30 # seconds
  config :tls_trust_certs_file_path, :validate => :string

  # pulsar producer configuration
  config :batch_max_publish_delay, :validate => :number, :default => 10 # milliseconds
  config :batch_max_size, :validate => :number, :default => 16384
  config :block_if_queue_full, :validate => :boolean, :default => true
  config :compression_type, :validate => ["none", "lz4", "zlib"], :default => "none"
  config :public_encryption_key, :validate => :string, :default => ""
  config :producer_properties, :validate => :hash, :default => {}
  config :send_timeout, :validate => :number, :default => 10 # milliseconds
  config :topic_id, :validate => :string, :required => true

  # pulsar message configuration
  config :message_key, :validate => :string
  config :message_properties, :validate => :hash, :default => {}

  # pulsar plugin configuration
  config :retries, :validate => :number
  config :retry_backoff_ms, :validate => :number, :default => 100 # milliseconds

  public
  def register
    @thread_batch_map = Concurrent::Hash.new

    if !@retries.nil?
      if @retries < 0
        raise ConfigurationError, "A negative retry count (#{@retries}) is not valid. Must be a value >= 0"
      end

      @logger.warn("Pulsar output is configured with finite retry. This instructs Logstash to LOSE DATA after a set number of send attempts fails. If you do not want to lose data if Pulsar is down, then you must remove the retry setting.", :retries => @retries)
    end

    @producer = create_producer

    @codec.on_event do |event, data|
      write_to_pulsar(event, data.to_java.getBytes(), java.util.HashMap.new(@message_properties))
    end
  end

  def prepare(record)
    # This output is threadsafe, so we need to keep a batch per thread.
    @thread_batch_map[Thread.current].add(record)
  end

  def multi_receive(events)
    t = Thread.current
    if !@thread_batch_map.include?(t)
      @thread_batch_map[t] = java.util.ArrayList.new(events.size)
    end

    events.each do |event|
      break if event == LogStash::SHUTDOWN
      @codec.encode(event)
    end

    batch = @thread_batch_map[t]

    if batch.any?
      retrying_send(batch)
      batch.clear
    end
  end

  def retrying_send(batch)
    remaining = @retries

    while batch.any?
      if !remaining.nil?
        if remaining < 0
          logger.info("Exhausted user-configured retry count when sending to Pulsar. Dropping these events.",
                      :max_retries => @retries, :drop_count => batch.count)
          break
        end

        remaining -= 1
      end

      failures = []

      futures = batch.collect do |record|
        begin
          record.sendAsync()
        rescue org.apache.pulsar.client.api.PulsarClientException => e
          failures << record
          nil
        end
      end.compact

      futures.each_with_index do |future, i|
        begin
          future.get()
        rescue => e
          logger.warn("PulsarProducer.send() failed: #{e}", :exception => e)
          failures << batch[i]
        end
      end

      # No failures? Cool. Let's move on.
      break if failures.empty?

      # Otherwise, retry with any failed transmissions
      if remaining.nil? || remaining >= 0
        delay = @retry_backoff_ms / 1000.0
        logger.info("Sending batch to Pulsar failed. Will retry after a delay.", :batch_size => batch.size,
                                                                                :failures => failures.size,
                                                                                :sleep => delay)
        batch = failures
        sleep(delay)
      end
    end
  end

  def close
    @producer.close
  end

  private
  def write_to_pulsar(event, serialized_data, serialized_properties)
    if @message_key.nil?
      record = @producer.newMessage()
        .value(serialized_data)
        .properties(serialized_properties)
    else
      record = @producer.newMessage()
        .key(event.sprintf(@message_key))
        .value(serialized_data)
        .properties(serialized_properties)
    end

    prepare(record)
  rescue LogStash::ShutdownSignal
    @logger.debug('Pulsar producer got shutdown signal')
  rescue => e
    @logger.warn('Pulsar producer threw exception, restarting', :exception => e)
  end

  def create_producer
    begin
      pulsar_client = PulsarClient.builder()
        .allowTlsInsecureConnection(@allow_tls_insecure_connection)
        .authentication(@auth_plugin_class_name, @auth_params_string)
        .connectionsPerBroker(@connections_per_broker)
        .enableTcpNoDelay(@enable_tcp_no_delay)
        .enableTlsHostnameVerification(@enable_tls_hostname_verification)
        .ioThreads(@num_io_threads)
        .keepAliveInterval(@keep_alive_interval, TimeUnit::MILLISECONDS)
        .listenerThreads(@num_listener_threads)
        .operationTimeout(@operation_timeout, TimeUnit::SECONDS)
        .serviceUrl(@bootstrap_servers)
        .tlsTrustCertsFilePath(@tls_trust_certs_file_path)
        .build();

      pulsar_producer = pulsar_client.newProducer()
        .batchingMaxMessages(@batch_max_size)
        .batchingMaxPublishDelay(@batch_max_publish_delay, TimeUnit::MILLISECONDS)
        .blockIfQueueFull(@block_if_queue_full)
        .compressionType(CompressionType::valueOf(@compression_type.upcase))
        .topic(@topic_id)
        .sendTimeout(@send_timeout, TimeUnit::SECONDS)
        .create();

      if (@public_encryption_key.size > 0)
        pulsar_producer.addEncryptionKey(@public_encryption_key)
      end
      if (@producer_properties.keys.size > 0)
        pulsar_producer.properties(java.util.HashMap.new(@producer_properties))
      end
    rescue => e
      logger.error("Unable to create Pulsar producer from given configuration",
                   :pulsar_error_message => e,
                   :cause => e.respond_to?(:getCause) ? e.getCause() : nil)
      raise e
    end
  end
end #class LogStash::Outputs::Pulsar
