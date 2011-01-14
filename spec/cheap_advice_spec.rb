require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

class CheapAdvice
  module Test

    class Foo
      attr_accessor :foo
      attr_reader :_baz
      
      def baz(arg)
        @_baz = 5 + arg
      end

      def do_it(arg)
        yield(arg + 7) + 2
      end
    end
    
    
    class Bar
      attr_accessor :bar
      attr_reader :_baz
      
      def baz(arg)
        @_baz = 7 + arg
      end
    end
  end
end


describe "CheapAdvice" do
  attr_reader :tracing_advice
  attr_reader :f, :b

  before(:each) do
    @tracing_advice = CheapAdvice.new(:around) do | ar, body |
      ar.advice.log "  TRACE: before #{ar.rcvr.class}\##{ar.method}(#{ar.args.join(", ")})"
      ar.advice.log "         foo = #{@foo.inspect}"
      ar.advice.log "         bar = #{@bar.inspect}"
      result = body.call
      ar.advice.log "  TRACE: after  #{ar.rcvr.class}\##{ar.method}(#{ar.args.join(", ")}) => #{result.inspect}"
      ar.result = "yo!"
      ar.advice.log "  TRACE: return #{ar.result.inspect}"
      "oy!" # Not relevant.
    end
    @tracing_advice.instance_eval do
      def log msg = nil
        return @log unless msg
        (@log ||= [ ]) << msg.dup
      end
    end
  end

  it "handles simple tracing_advice example." do
    @f = CheapAdvice::Test::Foo.new
    @b = CheapAdvice::Test::Bar.new

    assert_without_advice
    tracing_advice.log.should == nil

    tracing_advice.advise!( [CheapAdvice::Test::Foo, CheapAdvice::Test::Bar], [ :bar, :bar=, :baz ])
    f.foo = 10
    f.foo.should == 10
    f.baz(10).should == "yo!"
    b.bar = 101
    b.bar.should == "yo!"
    b.baz(10).should == "yo!"
    tracing_advice.log.should_not == nil
    tracing_advice.log.size.should == 20
    
    tracing_advice.unadvise!
    assert_without_advice
  end

  def assert_without_advice
    f.foo = 10
    f.foo.should == 10
    f.baz(10).should == 15
    f._baz.should == 15
    
    b.bar = 101
    b.bar.should == 101
    b.baz(10).should == 17
    b._baz.should == 17
  end

  it 'handles methods with blocks.' do
    ars = [ ]
    basic_advice = CheapAdvice.new(:before) do | ar |
      ars << ar
    end
    basic_advice.advised.size.should == 0

    @f = CheapAdvice::Test::Foo.new

    assert_do_it f
    ars.size.should == 0

    basic_advice.advise! CheapAdvice::Test::Foo, 'do_it'

    basic_advice.advised.size.should == 1
    advised = basic_advice.advised.first
    advised.cls.should == CheapAdvice::Test::Foo
    advised.method.should == :do_it
    advised.enabled.should == true
    
    assert_do_it f
    ars.size.should == 1

    advised.unadvise!
    advised.enabled.should == false

    assert_do_it f
    ars.size.should == 1
  end

  def assert_do_it f
    arg = nil
    result = f.do_it(10) do | _arg |
      _arg.should == 17
      arg = _arg
    end
    arg.should == 17
    result.should == 19
  end

end


