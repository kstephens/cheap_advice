$: << File.expand_path('../../lib', __FILE__)

require 'cheap_advice'
require 'pp'
require 'time'
 
class MyClass
  def foo
    42
  end
end

class MyOtherClass
  def bar
    43
  end
end

a = MyClass.new
b = MyOtherClass.new

trace_advice = CheapAdvice.new(:around) do | ar, body |
  ar.advice[:log] << "#{Time.now.iso8601(6)} " <<
                     "#{ar.rcvr.class} #{ar.meth} #{ar.rcvr.object_id}\n"
  body.call
  ar.advice[:log] << "#{Time.now.iso8601(6)} " <<
                     "#{ar.rcvr.class} #{ar.meth} #{ar.rcvr.object_id} " <<
                     "=> #{ar.result.inspect}\n"    
end
trace_advice[:log] = $stderr # File.open("trace.log", "a+")
trace_advice.advise!(MyClass, :foo)
trace_advice.advise!(MyOtherClass, :bar)


pp a.foo
pp b.bar

trace_advice.disable!

pp a.foo
pp b.bar


