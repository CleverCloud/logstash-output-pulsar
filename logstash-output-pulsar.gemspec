Gem::Specification.new do |s|
  s.name            = 'logstash-output-pulsar'
  s.version         = '1.0.1'
  s.licenses        = ['MIT']
  s.summary         = "Writes events to a pulsar topic"
  s.description     = "This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program"
  s.authors         = ['Clever Cloud']
  s.email           = 'devs@clever-cloud.com'
  s.homepage        = "https://www.clever-cloud.com"
  s.require_paths = ['lib', 'vendor/jar-dependencies']

  # Files
  s.files = Dir["lib/**/*","spec/**/*","*.gemspec","*.md","CONTRIBUTORS","Gemfile","LICENSE","NOTICE.TXT", "vendor/jar-dependencies/**/*.jar", "vendor/jar-dependencies/**/*.rb", "VERSION", "docs/**/*"]

  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { 'logstash_plugin' => 'true', 'group' => 'output'}

  s.add_development_dependency 'jar-dependencies'

  # Gem dependenciesw
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency 'logstash-codec-plain'
  s.add_runtime_dependency 'logstash-codec-json'

  s.add_development_dependency 'logstash-devutils'
  s.add_development_dependency 'poseidon'
  s.add_development_dependency 'snappy'
end