require 'cheap_advice'

class CheapAdvice
  # 
  class Configuration
    class Error < ::CheapAdvice::Error; end

    attr_accessor :config, :advice

    def initialize opts = nil
      opts ||= EMPTY_Hash
      opts.each do | k, v |
        send(:"#{k}=", v)
      end
      @advice ||= { }
      @targets = [ ]
    end

    def configure!
      disable!

      # First pass: parse target and defaults.
      c = [ ]
      d = { }
      get_config.each do | target_name, target_config |
        t = parse_target(target_name)
        # puts "#{target_name.inspect} => #{t.inspect}"
        case target_config
        when true, false
          target_config = { :enabled => target_config }
        end
        t.update(target_config) if target_config
        t[:advice] = t[:advice].split(/\s+|\s*,\s*/) if String === t[:advice]
        t[:advice] = t[:advice].inject({}) { | h, k | h[k] = true; h } if Array === t[:advice] 
        t[:advice] ||= { }
        case
        when t[:method].nil? && t[:mod].nil? # global default.
          d[nil] = t
        when t[:method].nil? # module default.
          d[t[:mod]] = t
        else
          c << t # real target
        end
      end
      d[nil] ||= { }

      # Second pass: merge defaults with target.
      @targets = [ ]
      c.each do | t |
        x = merge!(d[nil].dup, d[t[:mod]] || EMPTY_Hash)
        t = merge!(x, t)
        # $stderr.puts "target = #{t.inspect}"
        next if t[:enabled] == false
        @targets << t
      end

      enable!

      self
    end

    def disable!
      @targets.each do | t |
        (t[:advice] || EMPTY_Hash).each do | advice_name, enabled |
          advice_name = advice_name.to_sym
          if advised = (t[:advised] || EMPTY_Hash)[advice_name]
            advised.disable!
          end
        end
      end
      self
    end

    def enable!
      @targets.each do | t |
        (t[:advice] || EMPTY_Hash).each do | advice_name, enabled |
          next unless enabled
          advice_name = advice_name.to_sym
          if advice = @advice[advice_name]
            options = t[:options][nil]
            options = merge!(options, t[:options][advice_name])
            # puts "#{t.inspect} options => #{options.inspect}"
            (t[:advised] ||= { })[advice_name] = advice.advise!(t[:mod], t[:method], t[:kind], options)
          else
            raise Error, "no advice #{advice_name.inspect} for #{t.inspect}"
          end
        end
      end
      self
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

    def parse_target x
      case x
      when nil
        { }
      when Hash
        x
      when String, Symbol
        if x.to_s =~ /\A([a-z0-9_:]+)(?:([#\.])([a-z0-9_]+[!?]?))?\Z/i
          { :mod => $1,
            :kind => $2 == '.' ? :module : :instance,
            :method => $3,
          }
        else
          raise Error, "cannot parse #{x.inspect}"
        end
      end
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
