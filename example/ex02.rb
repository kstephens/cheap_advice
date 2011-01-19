$: << File.expand_path('../../lib', __FILE__)

require 'cheap_advice'
require 'cheap_advice/configuration'
require 'cheap_advice/trace'
require 'yaml'
require 'benchmark'

require 'rubygems'
gem 'ruby-debug'
require 'ruby-debug'

##################################################
# Target

class MyClass
  def foo(arg)
    42 + arg
  end
  def bar(arg)
    24 + arg
  end
end

trace_advice = nil
trace_config = nil

Benchmark.bm(40) do | bm |

##################################################
# Advice

  bm.report("trace_advice setup") do
    trace_advice = CheapAdvice::Trace.new 
    
    # Configure Trace loggers by name.
    trace_advice.logger[:default] =
      File.open(File.expand_path("../ex02-default.log", __FILE__), "w")
    
    trace_advice.logger[:alternate] = 
      File.open(File.expand_path("../ex02-alternate.log", __FILE__), "w")
  end

##################################################
# Advice Configuration


  bm.report("trace_config setup") do
    # Register Trace advice with configuration.
    trace_config = CheapAdvice::Configuration.new
    trace_config.advice[:trace] = trace_advice
  end

  config_yml = File.expand_path("../ex02-trace-*.yml", __FILE__)
  
  Dir[config_yml].sort.each do | config_yml |
    # Configure.
    config_hash = YAML.load_file(config_yml)
    trace_config.config = config_hash[:advice]

    bm.report("configure! using #{File.basename(config_yml)}") do
      trace_config.configure!
    end

    msg = "Using #{config_yml}"
    # puts msg
    trace_advice.log_all(msg)
    
    ##################################################
    # Target activity
    
    bm.report("Target activity") do
      a = MyClass.new
      a.foo(123)
      a.bar(456)
    end
  end
end



