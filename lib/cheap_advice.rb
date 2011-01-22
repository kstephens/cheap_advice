require 'thread'

# Provides cheap advice mechanism for Ruby.
# kurt dot ruby at kurtstephens dot com
#
class CheapAdvice
  EMPTY_Hash = { }.freeze
  EMPTY_Array = [ ].freeze

  class Error < ::Exception; end

  module Options
    # Hash accesible by #[] and #[]=.
    attr_accessor :options
    def initialize
      @mutex = Mutex.new
      @options = { }
    end

    def [](k)
      # @mutex.synchronize do
        @options[k]
      # end
    end


    def []=(k, v)
      # @mutex.synchronize do
        @options[k] = v
      # end
    end
  end
  include Options

  # Procs called before, after, and around the original method.
  attr_accessor :before, :after, :around

  # Collection of Advised method bindings.
  attr_accessor :advised

  # Module or Array of Modules to extend new Advised objects with.
  attr_accessor :advised_extend

  NULL_PROC = lambda { | ar | }
  NULL_AROUND_PROC = lambda { | ar, body | body.call }

  # options:
  #   :before
  #   :after
  #   :around
  def initialize *opts, &blk
    super()

    @advised = [ ]
    @advised_for = { }

    opts_hash = Hash === opts[-1] ? opts.pop : { }
    opts_key = opts.shift
    @options = opts_hash

    @before = (opts_key == :before ? blk : opts_hash[:before]) || 
      NULL_PROC
    @after  = (opts_key == :after  ? blk : opts_hash[:after])  || 
      NULL_PROC
    @around = (opts_key == :around ? blk : opts_hash[:around]) || 
      NULL_AROUND_PROC

    @blk = blk
  end


  # Apply advice a method on a Module (or Class).
  #
  # The advised method is enabled immediately (this may change in a future release).
  #
  # Returns an Advised object that describes what method was advised.
  #
  # mod can be a String, a Module or an Array of either.
  # method can be a String, a Symbol or an Array of either.
  # if either are Arrays the result will be an Array of Advised objects.
  # 
  # The type of method scope can be specified by:
  # * :instance (default)
  # * :class 
  # * :module 
  #
  # Any additional Hash options are propagated to the Advised binding object, which
  # can be accessed from the ActivationRecord passed to the Advice block(s).
  #
  # Examples:
  #   advice = CheapAdvice(:around) { | ar, body | ...; body.call; ... }
  #   advice.advise! MyClass, :instance_method, options_hash
  #   advice.advise! MyClass, :class_method, :class
  #
  # Each Advised object is extended with #advised_extend.
  # The #advised Array lists all Advised object.
  #
  def advise! mod, method, *opts
    return mod.map { | x | advise! x, method, *opts } if 
      Array === mod
    return method.map { | x | advise! mod, x, *opts } if 
      Array === method

    opts_hash = Hash === opts[-1] ? opts.pop : { }
    kind = opts.shift
    kind ||= :instance

    method = method.to_sym

    @mutex.synchronize do
      advised = advised_for mod, method, kind, opts_hash
      
      advised.enable! # Should this really be automatically enabled??
      
      advised
    end
  end

  def advised_select mod, method, kind
    @advised.select do | ad |
      (mod ? mod == ad.mod : true) &&
        (method ? method == ad.method : true) &&
        (kind ? kind == ad.kind : true)
    end
  end

  # Returns the existing Advised binding or creates a new one.
  def advised_for mod, method, kind, opts
    (@advised_for[[ mod, method, kind ]] ||=
      construct_advised_for(mod, method, kind)).set_options!(opts)
  end

  # Constructs an Advised binding from this Advice.
  def construct_advised_for mod, method, kind
    advice = self
    
    advised = Advised.new(advice, mod, method, kind)
    
    case @advised_extend
    when nil
    when Module
      advised.extend(@advised_extend)
    when Array
      @advised_extend.each { | m | advised.extend(m) }
    else
      raise TypeError, "advised_extend: expected nil, Module or Array of Modules, given #{@advised_extend.class}"
    end

    advised.register_advice_methods!
    
    advised.define_new_method!

    @advised << advised
      
    advised
  end


  # Disables all currently Advised methods.
  def disable!
    @mutex.synchronize do
      @advised.each { | x | x.disable! }
    end
    self
  end
  alias :unadvise! :disable!


  # Enables all currently Advised methods.
  def enable!
    @mutex.synchronize do
      @advised.each { | x | x.enable! }
    end
    self
  end
  alias :readvise! :enable!


  # Represents the application/binding of advice to a class and method.
  class Advised
    include Options

    @@mutex = Mutex.new
    @@advised_id ||= 0
    
    # The Advice being applied to the Module and method.
    attr_reader :advice
    # The Module, method and kind (instance, class or module method)
    attr_reader :mod, :method, :kind
    alias :cls :mod # Deprecated.

    # The unique Advised id used to generate unique method names.
    attr_reader :advised_id
    
    # The name of the old and new method being patched in.
    attr_reader :old_method, :new_method

    # The name of the before, after and around methods.
    attr_reader :before_method, :after_method, :around_method

    # True if the Advised methods are currently installed.
    attr_reader :enabled

    def initialize *args
      @mutex = Mutex.new
      @advice, @mod, @method, @kind, @options = *args

      case @kind
      when :instance, :class, :module
      else
        raise ArgumentError, "invalid kind #{kind.inspect}"
      end

      @options ||= { }

      @@mutex.synchronize do
        @advised_id = @@advised_id += 1
      end

      @old_method = :"__advice_old_#{@@advised_id}_#{@method}"
      @new_method = :"__advice_new_#{@@advised_id}_#{@method}"
    
      @before_method = :"__advice_before_#{@@advised_id}_#{@method}"
      @after_method  = :"__advice_after_#{@@advised_id}_#{@method}"
      @around_method = :"__advice_around_#{@@advised_id}_#{@method}"

      @enabled = 
        @advice_methods_applied = false
    end

    def set_options! options
      @options = options || { }
      self
    end

=begin
    def fromString str
      case str
      when String, Symbol
        str.to_s.
      else
        raise TypeError
      end
    end
=end

    # True if the advice, mod, method and kind are equal.
    def == x
      return false unless self.class === x
      @advice == x.advice && @mod == x.mod && @method == x.method && @kind == x.kind
    end

    # Support for Hash.
    def hash
      @advice.hash ^ @mod.hash ^ @method.hash ^ @kind.hash
    end

    # Returns the target Module for the kind of method.
    def mod_target
      case @kind
      when :instance
        mod_resolve
      when :class, :module
        (class << mod_resolve; self; end)
      else
        raise ArgumentError, "mod_target: invalid kind #{kind.inspect}"
      end
    end

    # Resolves mod Strings to the actual target Module.
    def mod_resolve
      case @mod
      when Module
        @mod
      when String, Symbol
        @mod.to_s.split('::').
          reject { | name | name.empty?}.
          inject(Object) { | namespace, name | namespace.const_get(name) }
      else
        raise TypeError, "mod_resolve: expected Module, String, Symbol, given #{@mod.class}"
      end
    end

    # Registers the before, after and around advice methods.
    def register_advice_methods!
      @mutex.synchronize do
        return self if @advice_methods_registered

        this = self
        mod_target.instance_eval do 
          define_method(this.before_method, &this.advice.before)
          define_method(this.after_method,  &this.advice.after)
          define_method(this.around_method, &this.advice.around)  
        end

        @advice_methods_registered = true
      end
      self
    end

    # Defines the new advised method in the target Module.
    def define_new_method!
      advised = self
      
      advised.mod_target.instance_eval do
        define_method advised.new_method do | *args, &block |
          ar = ActivationRecord.new(advised, self, args, block)
          
          # Proc to invoke the old method with :before and :after advise hooks.
          body = Proc.new do
            self.__send__(advised.before_method, ar)
            begin
              ar.result = self.__send__(advised.old_method, *ar.args, &ar.block)
            rescue Exception => err
              ar.error = err
            ensure
              self.__send__(advised.after_method, ar)
            end
            ar.result
          end
          
          # Invoke the :around advice with the body Proc.
          self.__send__(advised.around_method, ar, body)
          
          # Reraise Exception, if occured.
          raise ar.error if ar.error
          
          # Return the message result to caller.
          ar.result
        end # define_method
      end # instance_eval

      self
    end

    # Enables the advice on this method.
    def enable!
      @mutex.synchronize do
        return self if @enabled

        this = self
        mod_target.instance_eval do
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

    # Disables the advice on this method.
    def disable!
      @mutex.synchronize do
        return self if ! @enabled

        this = self
        mod_target.instance_eval do
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
    # The Advised method binding object.
    attr_reader :advised

    # The original message receiver, arguments and block (if given).
    # Can be modified by the advice blocks.
    attr_accessor :rcvr, :args, :block

    # The original message return result available in the :around or :after advice blocks.
    # Value can be changed in the advice blocks to alter the return result.
    attr_accessor :result

    # Any Exception rescued from the original method.
    # Usually nil if no exception was raised; 
    # if not nil, Exception is reraised after the :around advice block.
    # Can be modified by the :after advice block.
    attr_accessor :error

    def initialize *args
      @advised, @rcvr, @args, @block = *args
    end

    # Returns the Advice of the Advised method.
    def advice
      @advised.advice
    end

    # The Module of the Advised method.
    # This may *not* be the same as #rcvr.class.
    def mod
      @advised.mod
    end

    # The Symbol name of the Advised method.
    def method
      @advised.method
    end

    # The method kind.
    def kind
      @advised.kind
    end

    # The call stack with CheapAdvice methods filtered out.
    def caller(offset = 0)
      ::Kernel.caller(offset + 2)
    end
  end

end

