# Logstash output for Apache Pulsar

## Prepare

```bash
./pulsar_test_setup.sh
```

## Test

On jruby:

```bash
bundle install
bundle exec rake vendor
bundle exec rspec
```

## Informations

```bash
jruby -S <command>
```
