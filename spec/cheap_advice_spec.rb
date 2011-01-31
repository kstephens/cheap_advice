require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

class CheapAdvice
  module Test

    module M
      attr_accessor :_m
      def m(arg)
        @_m = 1 + arg
      end
      def self.mm(arg)
        3 + arg
      end
    end

    class Foo
      include M
      attr_accessor :foo, :bar
      attr_reader :_baz, :_bar
      (class << self; self; end).instance_eval do 
        attr_accessor :_baz
      end
      
      def self.baz(arg)
        self._baz = 3 + arg
      end

      def baz(arg)
        @_baz = 5 + arg
      end

      def do_it(arg)
        yield(arg + 7) + 2
      end
    end
    
    
    class Bar
      include M
      attr_accessor :bar
      attr_reader :_baz
      
      def baz(arg)
        @_baz = 7 + arg
      end

      def calls_private_method(arg)
        private_method(arg)
      end
                               
      private
      def private_method(arg)
        arg
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
    advised.mod.should == CheapAdvice::Test::Foo
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

  it 'handles applying the same advice only once.' do
    null_advice = CheapAdvice.new(:before) do | ar |
    end
    null_advice.advised.size.should == 0

    advised = null_advice.advise! CheapAdvice::Test::Foo, :do_it
    null_advice.advised.size.should == 1

    advised_again = null_advice.advise! CheapAdvice::Test::Foo, :do_it
    advised_again.object_id.should == advised.object_id

    null_advice.advised.size.should == 1

    advised = null_advice.advise! CheapAdvice::Test::Foo, :baz, :class
    null_advice.advised.size.should == 2

    advised_again = null_advice.advise! CheapAdvice::Test::Foo, :baz, :class
    advised_again.object_id.should == advised.object_id

    null_advice.advised.size.should == 2

    advised.unadvise!
  end

  it 'handles String for class and method names.' do
    advice_called = 0
    null_advice = CheapAdvice.new(:before) do | ar |
      advice_called += 1
    end
    null_advice.advised.size.should == 0


    @f = CheapAdvice::Test::Foo.new

    advice_called.should == 0
    
    advised = null_advice.advise!('CheapAdvice::Test::Foo', 'baz')
    null_advice.advised.size.should == 1

    @f.baz(5).should == 10
    @f._baz.should == 10
    advice_called.should == 1

    advised.unadvise!
  end

  it 'handles Module instance method advice.' do
    advice_called = 0
    null_advice = CheapAdvice.new(:before) do | ar |
      advice_called += 1
    end
    null_advice.advised.size.should == 0


    @f = CheapAdvice::Test::Foo.new
    @b = CheapAdvice::Test::Bar.new

    advice_called.should == 0
    
    advised = null_advice.advise!('CheapAdvice::Test::M', 'm')
    null_advice.advised.size.should == 1

    @f.m(5).should == 6
    @f._m.should == 6

    @b.m(5).should == 6
    @b._m.should == 6

    advice_called.should == 2

    advised.unadvise!
  end

  it 'handles Module singleton method advice.' do
    advice_called = 0
    null_advice = CheapAdvice.new(:before) do | ar |
      advice_called += 1
    end
    null_advice.advised.size.should == 0

    advice_called.should == 0
    
    advised = null_advice.advise!(CheapAdvice::Test::M, :mm, :module)
    null_advice.advised.size.should == 1

    CheapAdvice::Test::M.mm(5).should == 8

    advice_called.should == 1

    advised.unadvise!
  end

  it 'handles Class method advice.' do
    advice_called = 0
    null_advice = CheapAdvice.new(:before) do | ar |
      advice_called += 1
    end
    null_advice.advised.size.should == 0


    @f = CheapAdvice::Test::Foo.new

    advice_called.should == 0
    CheapAdvice::Test::Foo._baz.should == nil
    
    advised = null_advice.advise!(CheapAdvice::Test::Foo, :baz, :class)
    null_advice.advised.size.should == 1

    CheapAdvice::Test::Foo.baz(5).should == 8
    CheapAdvice::Test::Foo._baz.should == 8
    @f.baz(5).should == 10
    @f._baz.should == 10
    advice_called.should == 1

    advised.unadvise!

    CheapAdvice::Test::Foo.baz(7).should == 10
    CheapAdvice::Test::Foo._baz.should == 10
    @f.baz(5).should == 10
    @f._baz.should == 10
    advice_called.should == 1
  end

  it 'handles private method advice.' do
    advice_called = 0
    null_advice = CheapAdvice.new(:before) do | ar |
      advice_called += 1
    end
    null_advice.advised.size.should == 0

    advice_called.should == 0
    
    advised = null_advice.advise!(CheapAdvice::Test::Bar, :private_method)
    advised.scope.should == :private
    null_advice.advised.size.should == 1

    @b = CheapAdvice::Test::Bar.new

    @b.calls_private_method(5).should == 5
    advice_called.should == 1

    advised.unadvise!

    @b.calls_private_method(5).should == 5
    advice_called.should == 1
  end

end


