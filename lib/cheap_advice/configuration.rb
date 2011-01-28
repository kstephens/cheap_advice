require 'cheap_advice'

class CheapAdvice
  # 
  class Configuration
    class Error < ::CheapAdvice::Error; end

    # Configuration input hash.
    attr_accessor :config

    # Hash mapping advice names to CheapAdvice objects.
    attr_accessor :advice

    # Array of CheapAdvice::Advised methods.
    attr_accessor :advised

    # Hash of file names that were explicity required before applying advice.
    attr_accessor :required

    # Flag
    attr_accessor :config_changed
    alias :config_changed? :config_changed

    attr_accessor :verbose

    def initialize opts = nil
      opts ||= EMPTY_Hash
      @verbose = false
      opts.each do | k, v |
        send(:"#{k}=", v)
      end
      @advice ||= { }
      @targets = [ ]
      @advised = [ ]
      @required = { }
    end

    def config_changed!
      @config_changed = true
      self
    end

    def configure_if_changed!
      if config_changed?
        configure!
        @config_changed = false
      end
      self
    end

    def configure!
      disable!

      # First pass: parse target and defaults.
      c = [ ]
      d = { }
      get_config.each do | target_name, target_config |
        annotate_error "target=#{target_name}" do
          t = parse_target(target_name)
          # _log { "#{target_name.inspect} => #{t.inspect}" }
          case target_config
          when true, false
            target_config = { :enabled => target_config }
          end
          t.update(target_config) if target_config
          [ :advice, :require ].each do | k |
            t[k] = as_array(t[k]) if t.key?(k)
          end
          case
          when t[:method].nil? && t[:mod].nil? # global default.
            d[nil] = t
          when t[:method].nil? # module default.
            d[t[:mod]] = t
          else
            c << t # real target
          end
        end
      end
      d[nil] ||= { }

      # Second pass: merge defaults with target.
      @targets = [ ]
      c.each do | t |
        x = merge!(d[nil].dup, d[t[:mod]] || EMPTY_Hash)
        t = merge!(x, t)
        # _log { "target = #{t.inspect}" }
        next if t[:enabled] == false
        @targets << t
      end

      enable!

      self
    end

    def disable!
      @targets.each do | t |
        (t[:advice] || EMPTY_Array).each do | advice_name |
          advice_name = advice_name.to_sym
          if advised = (t[:advised] || EMPTY_Hash)[advice_name]
            advised.disable!
          end
        end
      end
      @advised.clear
      self
    end

    def enable!
      @advised.clear
      @targets.each do | t |
        t_str = target_as_string(t)
        annotate_error "target=#{t_str.inspect}" do
          (t[:require] || EMPTY_Array).each do | r |
            _log { "#{t_str}: require #{r}" }
            unless @required[r]
              require r
              @required[r] = true
            end
          end
        end
            
        (t[:advice] || EMPTY_Array).each do | advice_name |
          advice_name = advice_name.to_sym
          annotate_error "target=#{target_as_string(t)} advice=#{advice_name.inspect}" do
            unless advice = @advice[advice_name]
              raise Error, "no advice by that name"
            end
            options = t[:options][nil]
            options = merge!(options, t[:options][advice_name])
            # _log { "#{t.inspect} options => #{options.inspect}" }
            
            advised = advice.advise!(t[:mod], t[:method], t[:kind], options)

            (t[:advised] ||= { })[advice_name] = advised

            @advised << advised
          end
        end
      end
      self
    end

    def _log msg = nil
      return self unless @verbose
      msg ||= yield if block_given?
      $stderr.puts "#{self.class}: #{msg}"
      self
    end

    def annotate_error x
      yield
    rescue Exception => err
      msg = "in #{x.inspect}: #{err.inspect}"
      _log { "ERROR: #{msg}\n  #{err.backtrace * "\n  "}" }
      raise Error, msg, err.backtrace
    end

    def get_config
      case @config
      when Hash
        @config
      when Proc
        @config.call(self)
      when nil
        raise Error, "no config"
      end
    end

    def as_array x
      x = EMPTY_Array if x == nil
      x = x.split(/\s+|\s*,\s*/) if String === x
      raise "Unexpected Hash" if Hash === x
      x
    end

    def parse_target x
      case x
      when nil
        { }
      when Hash
        x
      when String, Symbol
        if x.to_s =~ /\A([a-z0-9_:]+)(?:([#\.])([a-z0-9_]+[=\!\?]?))?\Z/i
          { :mod => $1,
            :kind => $2 && ($2 == '.' ? :module : :instance),
            :method => $3,
          }
        else
          raise Error, "cannot parse #{x.inspect}"
        end
      end
    end
    def target_as_string t
      "#{t[:mod]}#{t[:kind] == :instance ? '#' : '.'}#{t[:method]}"
    end

    def merge! dst, src
      case dst
      when nil, Hash
        case src
        when Hash
          dst = dst ? dst.dup : { }
          src.each do | k, v |
            dst[k] = merge!(dst[k], v)
          end
        else
          dst = src
        end
      else
        dst = src
      end
      dst
    end

  end
end
