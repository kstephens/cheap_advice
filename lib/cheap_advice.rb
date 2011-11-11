require 'thread'

# Provides cheap advice mechanism for Ruby.
# kurt dot ruby at kurtstephens dot com
#
class CheapAdvice
  EMPTY_Hash = { }.freeze
  EMPTY_Array = [ ].freeze
  EMPTY_String = ''.freeze

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
      unless @enabled_once
        self.enabled!
        @enabled_once = true
      end

      advised = advised_for mod, method, kind, opts_hash
      
      advised.enable! # Should this really be automatically enabled??
      
      advised
    end
  end

  # Called once the first time this advice is enabled.
  # Instances can override this method.
  def enabled!
    self
  end

  def advised_select mod, meth, kind
    @advised.select do | ad |
      (mod ? mod == ad.mod : true) &&
        (meth ? meth == ad.meth : true) &&
        (kind ? kind == ad.kind : true)
    end
  end

  # Returns the existing Advised binding or creates a new one.
  def advised_for mod, meth, kind, opts
    (@advised_for[[ mod, meth, kind ]] ||=
      construct_advised_for(mod, meth, kind)).set_options!(opts)
  end

  # Constructs an Advised binding from this Advice.
  def construct_advised_for mod, meth, kind
    advice = self
    
    advised = Advised.new(advice, mod, meth, kind)
    
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
    attr_reader :mod, :meth, :kind
    alias :cls :mod # Deprecated.

    # The unique Advised id used to generate unique method names.
    attr_reader :advised_id
    
    # The name of the old and new method being patched in.
    attr_reader :old_meth, :new_meth

    # The name of the before, after and around methods.
    attr_reader :before_meth, :after_meth, :around_meth

    # True if the Advised methods are currently installed.
    attr_reader :enabled

    def initialize *args
      @mutex = Mutex.new
      @advice, @mod, @meth, @kind, @options = *args

      case @kind
      when :instance, :class, :module
      else
        raise ArgumentError, "invalid kind #{kind.inspect}"
      end

      @options ||= { }

      @@mutex.synchronize do
        @advised_id = @@advised_id += 1
      end

      @old_meth = :"__advice_old_#{@@advised_id}_#{@meth}"
      @new_meth = :"__advice_new_#{@@advised_id}_#{@meth}"
    
      @before_meth = :"__advice_before_#{@@advised_id}_#{@meth}"
      @after_meth  = :"__advice_after_#{@@advised_id}_#{@meth}"
      @around_meth = :"__advice_around_#{@@advised_id}_#{@meth}"

      @enabled = 
        @advice_methods_applied = false
    end

    def set_options! options
      @options = options || { }
      self
    end

    INSTANCE_SEP = '#'.freeze
    MODULE_SEP = '.'.freeze

    # The string name for the method.
    # Returns "Foo#bar" for an instance method named :bar on class Foo.
    # Returns "Foo.bar" for a class or module method named .bar on class Foo.
    def meth_to_s
      @meth_to_s ||=
        "#{@mod}#{@kind == :instance ? INSTANCE_SEP : MODULE_SEP}#{@meth}".freeze
    end

     # True if the advice, mod, method and kind are equal.
    def == x
      return false unless self.class === x
      @advice == x.advice && @mod == x.mod && @meth == x.meth && @kind == x.kind
    end

    # Support for Hash.
    def hash
      @advice.hash ^ @mod.hash ^ @meth.hash ^ @kind.hash
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
      scope # force calculation of scope before aliasing methods.
        
      @mutex.synchronize do
        return self if @advice_methods_registered

        this = self
        mod_target.instance_eval do 
          define_method(this.before_meth, &this.advice.before)
          define_method(this.after_meth,  &this.advice.after)
          define_method(this.around_meth, &this.advice.around)  
        end

        @advice_methods_registered = true
      end
      self
    end

    # Defines the new advised method in the target Module.
    def define_new_method!
      advised = self
      
      advised.mod_target.instance_eval do
        define_method advised.new_meth do | *args, &block |
          ar = ActivationRecord.new(advised, self, args, block)
          
          # Proc to invoke the old method with :before and :after advise hooks.
          body = Proc.new do
            self.__send__(advised.before_meth, ar)
            begin
              ar.result = self.__send__(advised.old_meth, *ar.args, &ar.block)
            rescue Exception => err
              ar.error = err
            ensure
              self.__send__(advised.after_meth, ar)
            end
            ar.result
          end
          
          # Invoke the :around advice with the body Proc.
          self.__send__(advised.around_meth, ar, body)
          
          # Reraise Exception, if occured.
          raise ar.error if ar.error
          
          # Return the message result to caller.
          ar.result
        end # define_method
      end # instance_eval

      self
    end

    if RUBY_VERSION =~ /^1\.8/
      def scope
        @scope ||= @mutex.synchronize do
          this = self
          mod_target.instance_eval do 
           case
            when private_instance_methods(false).include?(this.meth.to_s)
              :private
            when protected_instance_methods(false).include?(this.meth.to_s)
              :protected
            else
              :public
            end
          end
          
        end
      end
    else
      def scope
        @scope ||= @mutex.synchronize do
          this = self
          mod_target.instance_eval do 
            case
            when private_instance_methods(false).include?(this.meth)
              :private
            when protected_instance_methods(false).include?(this.meth)
              :protected
            else
              :public
            end
          end
        end
      end     
    end

    # Enables the advice on this method.
    def enable!
      @mutex.synchronize do
        return self if @enabled

        this = self
        mod_target.instance_eval do
          case this.scope
          when :public
          else
            public this.meth
          end

          alias_method this.old_meth, this.meth if 
            ! method_defined? this.old_meth
          
          alias_method this.meth, this.new_meth

          case this.scope
          when :private
            private this.meth
          when :protected
            protected this.meth
          end
            
        end

        enabled!
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
          if method_defined? this.old_meth
            alias_method this.meth, this.old_meth
            
            case this.scope
            when :private
              private this.meth
            when :protected
              protected this.meth
            end
          end
        end

        disabled!
        @enabled = false
      end

      self
    end
    alias :unadvise! :disable!

    # Called when Advised is enabled.
    # Instances can override this method.
    def enabled!
      self
    end

    # Called when Advised is enabled.
    # Instances can override this method.
    def disabled!
      self
    end

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
    alias :exception :error
    alias :exception= :error=

    # Arbitrary data accessed by #[], #[]=.
    # Advice blocks can use this to pass data to other blocks.
    # May be a frozen, empty Hash.
    attr_accessor :data

    def initialize *args
      @advised, @rcvr, @args, @block = *args
    end

    def data
      @data || EMPTY_Hash
    end

    def [] key
      (@data || EMPTY_Hash)[key]
    end

    def []= key, value
      (@data ||= { })[key] = value
    end

    # This methods are delegated to #advised.
    DELEGATE_TO_ADVISED = [ :advice, :mod, :meth, :kind, :meth_to_s ]
    eval(DELEGATE_TO_ADVISED.map{|m| "def #{m}; @advised.#{m}; end; "} * "\n")

    # The call stack with CheapAdvice methods filtered out.
    def caller(offset = 0)
      ::Kernel.caller(offset + 2)
    end
  end

end

