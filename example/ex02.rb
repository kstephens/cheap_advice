$: << File.expand_path('../../lib', __FILE__)

require 'cheap_advice'
require 'cheap_advice/configuration'
require 'cheap_advice/trace'
require 'yaml'

require 'rubygems'
gem 'ruby-debug'
require 'ruby-debug'

##################################################
# Target

class MyClass
  def foo
    42
  end
  def bar
    24
  end
end

##################################################
# Advice

trace_advice = CheapAdvice::Trace.new 

# Configure Trace loggers by name.
trace_advice.logger[:default] =
  File.open(File.expand_path("../ex02-default.log", __FILE__), "w")

trace_advice.logger[:alternate] = 
  File.open(File.expand_path("../ex02-alternate.log", __FILE__), "w")


##################################################
# Advice Configuration


# Register Trace advice with configuration.
trace_config = CheapAdvice::Configuration.new
trace_config.advice[:trace] = trace_advice

config_yml = File.expand_path("../ex02-trace-*.yml", __FILE__)

Dir[config_yml].sort.each do | config_yml |
  # Configure.
  config_hash = YAML.load_file(config_yml)
  trace_config.config = config_hash[:advice]
  trace_config.configure!

  msg = "Using #{config_yml}"
  puts msg
  trace_advice.log_all(msg)

  ##################################################
  # Target activity
  
  a = MyClass.new
  a.foo
  a.bar
end


