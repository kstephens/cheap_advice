require 'thread'

# Provides cheap advice mechanism for Ruby.
# kurt dot ruby at kurtstephens dot com
#
class CheapAdvice
  module Options
    def initialize
      @mutex = Mutex.new
      @options = { }
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
  end
  include Options

  attr_accessor :before, :after, :around, :advised, :options

  NULL_PROC = lambda { | ar | }
  NULL_AROUND_PROC = lambda { | ar, result | result.call }
  EMPTY_HASH = { }.freeze

  # options:
  #   :before
  #   :after
  #   :around
  def initialize opts, &blk
    super()

    @advised = [ ]
    @advised_for = { }

    opts_hash = EMPTY_HASH
    opts_key = nil
    
    case opts
    when Hash # advice :before => lambda ...
      opts_hash = opts
    when Symbol # advice :method, :before do ... end
      opts_key = opts
    end
    @options = opts_hash.dup

    @before = (opts_key == :before ? blk : opts_hash[:before]) || 
      NULL_PROC
    @after  = (opts_key == :after  ? blk : opts_hash[:after])  || 
      NULL_PROC
    @around = (opts_key == :around ? blk : opts_hash[:around]) || 
      NULL_AROUND_PROC

    @blk = blk
  end


  # Apply advice to class and method.
  # 
  def advise! cls, method, *opts
    return cls.map { | x | advise! x, method, *opts } if 
      Array === cls
    return method.map { | x | advise! cls, x, *opts } if 
      Array === method

    opts_hash = Hash === opts[-1] ? opts.pop : nil
    kind = opts.shift
    kind ||= :instance

    method = method.to_sym

    @mutex.synchronize do
      advised = advised_for cls, method, kind, opts_hash
      
      advised.enable! # Should this really be automatically enabled??
      
      advised
    end
  end

  def advised_for cls, method, kind, opts
    @advised_for[[ cls, method, kind ]] ||=
      construct_advised_for cls, method, kind, opts
  end

  def construct_advised_for cls, method, kind, opts
    advice = self
    
    advised = Advised.new(advice, cls, method, kind, opts)
    
    advised.register_advice_methods!
    
    advised.cls_target.instance_eval do
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

    @advised << advised
      
    advised
  end


  def disable!
    @mutex.synchronize do
      @advised.each { | x | x.disable! }
    end
    self
  end
  alias :unadvise! :disable!


  def enable!
    @mutex.synchronize do
      @advised.each { | x | x.enable! }
    end
    self
  end
  alias :readvise! :enable!


  # Represents the application of advice to a class and method.
  class Advised
    include Options

    @@advice_id ||= 0

    attr_reader :advice, :cls, :method, :kind, :options
    attr_reader :advice_id
    attr_reader :old_method, :new_method
    attr_reader :before_method, :after_method, :around_method
    attr_reader :enabled

    def initialize *args
      @mutex = Mutex.new
      @advice, @cls, @method, @kind, @options = *args

      case @kind
      when :instance, :class, :method
      else
        raise ArgumentError, "invalid kind #{kind.inspect}"
      end

      @options ||= { }

      @advice_id = @@advice_id += 1
      
      @old_method = "__advice_old_#{@@advice_id}_#{@method}"
      @new_method = "__advice_new_#{@@advice_id}_#{@method}"
    
      @before_method = "__advice_before_#{@@advice_id}_#{@method}"
      @after_method  = "__advice_after_#{@@advice_id}_#{@method}"
      @around_method = "__advice_around_#{@@advice_id}_#{@method}"

      @enabled = 
        @advice_methods_applied = false
    end

    def == x
      return false unless self.class === x
      @advice == x.advice && @cls == x.cls && @method == x.method && @kind == x.kind
    end

    def hash
      @advice.hash ^ @cls.hash ^ @method.hash ^ @kind.hash
    end


    def cls_target
      case @kind
      when :instance
        @cls
      when :class, :module
        (class << @cls; self; end)
      else
        raise ArgumentError, "invalid kind #{kind.inspect}"
      end
    end

    def register_advice_methods!
      @mutex.synchronize do
        return self if @advice_methods_registered

        this = self
        cls_target.instance_eval do 
          define_method(this.before_method, &this.advice.before)
          define_method(this.after_method,  &this.advice.after)
          define_method(this.around_method, &this.advice.around)  
        end

        @advice_methods_registered = true
      end
      self
    end


    def enable!
      @mutex.synchronize do
        return self if @enabled

        this = self
        cls_target.instance_eval do
          alias_method this.old_method, this.method if 
            method_defined? this.method and 
            ! method_defined? this.old_method
          
          alias_method this.method, this.new_method
        end

        @enabled = true
      end
      self
    end
    alias :advise! :enable!

    def disable!
      @mutex.synchronize do
        return self if ! @enabled

        this = self
        cls_target.instance_eval do
          alias_method this.method, this.old_method if 
            method_defined? this.old_method
        end

        @enabled = false
      end

      self
    end
    alias :unadvise! :disable!

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

