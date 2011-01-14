require 'thread'

# Provides cheap advice mechanism for Ruby.
# kurt dot ruby at kurtstephens dot com
#
class CheapAdvice
  attr_accessor :before, :after, :around, :advised

  NULL_PROC = lambda { | ar | }
  NULL_AROUND_PROC = lambda { | ar, result | result.call }
  EMPTY_HASH = { }.freeze

  # options:
  #   :before
  #   :after
  #   :around
  def initialize opts, &blk
    @mutex = Mutex.new

    @advised = [ ]

    opts_hash = EMPTY_HASH
    opts_key = nil
    
    case opts
      # advice :before => lambda ...
    when Hash 
      opts_hash = opts
      # advice :method, :before do ... end
    when Symbol 
      opts_key = opts
    end

    @before = (opts_key == :before ? blk : opts_hash[:before]) || 
      NULL_PROC
    @after  = (opts_key == :after  ? blk : opts_hash[:after])  || 
      NULL_PROC
    @around = (opts_key == :around ? blk : opts_hash[:around]) || 
      NULL_AROUND_PROC

    @blk = blk
  end


  # Apply advice to class and method.
  def advise! cls, method, opts = nil
    return cls.map { | x | advise! x, method, opts } if 
      cls.kind_of?(Enumerable)
    return method.map { | x | advise! cls, x, opts } if 
      method.kind_of?(Enumerable)

    @mutex.synchronize do

      advice = self
      
      advised = Advised.new(advice, cls, method, opts)
      
      advised.apply_advice_methods!
      
      cls.class_eval do
        define_method advised.new_method do | *args, &block |
          ar = ActivationRecord.new(advised, self, args, block)
          
          do_result = Proc.new do
            self.send(advised.before_method, ar)
            begin
              ar.result = self.send(advised.old_method, *ar.args, &ar.block)
            rescue Exception => err
              ar.error = err
            ensure
              self.send(advised.after_method, ar)
            end
            
            ar.result
          end
          
          self.send advised.around_method, ar, do_result
          
          raise ar.error if ar.error
          
          ar.result
        end
      end
      
      advised.advise!
      
      @advised << advised
      
      advised
    end
  end


  def unadvise!
    @mutex.synchronize do
      @advised.each { | x | x.unadvise! }
    end
    self
  end


  def readvise!
    @mutex.synchronize do
      @advised.each { | x | x.advise! }
    end
    self
  end


  # Represents the application of advice to a class and method.
  class Advised

    @@advice_id ||= 0

    attr_reader :advice, :cls, :method, :options
    attr_reader :advice_id
    attr_reader :old_method, :new_method
    attr_reader :before_method, :after_method, :around_method

    def initialize *args
      @mutex = Mutex.new
      @advice, @cls, @method, @options = *args

      @options ||= { }

      @advice_id = @@advice_id += 1
      
      @old_method = "__advice_old_#{@@advice_id}_#{@method}"
      @new_method = "__advice_new_#{@@advice_id}_#{@method}"
    
      @before_method = "__advice_before_#{@@advice_id}_#{@method}"
      @after_method  = "__advice_after_#{@@advice_id}_#{@method}"
      @around_method = "__advice_around_#{@@advice_id}_#{@method}"
    end


    def [](k)
      @mutex.synchronize do
        @options[k]
      end
    end


    def []=(k, v)
      @mutex.synchronize do
        @options[k] = v
      end
    end


    def apply_advice_methods!
      this = self
      @mutex.synchronize do
        @cls.instance_eval do 
          define_method(this.before_method, &this.advice.before)
          define_method(this.after_method,  &this.advice.after)
          define_method(this.around_method, &this.advice.around)  
        end
      end
      self
    end


    def advise!
      this = self
      @mutex.synchronize do
        @cls.instance_eval do
          alias_method this.old_method, this.method if 
            method_defined? this.method and 
            ! method_defined? this.old_method
          
          alias_method this.method, this.new_method
        end
      end
      self
    end

    def unadvise!
      this = self
      @mutex.synchronize do
        @cls.instance_eval do
          alias_method this.method, this.old_method if 
            method_defined? this.old_method
        end
      end
      self
    end
  end


  # Represents the activation record of a method invocation.
  class ActivationRecord
    attr_reader :advised, :rcvr, :args, :block
    attr_accessor :result, :error, :body
    
    def initialize *args
      @advised, @rcvr, @args, @block = *args
    end

    def advice
      @advised.advice
    end

    def method
      @advised.method
    end

    def caller(offset = 0)
      ::Kernel.caller(offset + 2)
    end
  end

end

