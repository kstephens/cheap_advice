require 'cheap_advice'

require 'time' # Time#iso8601

class CheapAdvice
  # Sample Tracing Advice factory.
  module Trace
    def self.new opts = nil
      opts ||= { }
      trace = CheapAdvice.new(:around, opts) do | ar, body |
        a = ar.advice
        ad = ar.advised
        logger = ad.logger[:name] || ad.logger_default[:name]
        logger = a.logger[logger] || a.logger_default[logger]

        formatter = nil
        if ad[:log_before] != false
          a.log(logger) do
            formatter = a.new_formatter(logger)
            ar[:time_before] = Time.now
            formatter.record(ar, :before)
          end
        end

        body.call

        if ad[:log_after] != false
          a.log(logger) do
            formatter ||= a.new_formatter(logger)
            ar[:time_after] = Time.now
            if ar.error
              ar[:error] = ar.error   if ad[:log_error] != false
            else
              ar[:result] = ar.result if ad[:log_result] != false
            end
            formatter.record(ar, :after)
          end
        end
      end
      trace.extend(Behavior)
      trace.advised_extend = Behavior
      trace
    end

    module Behavior
      def logger
        # $stderr.puts " #{self.class} @options = #{@options.inspect}"
        @options[:logger] ||= { }
      end
      def logger_default
        logger[nil] ||= { }
      end

      def new_formatter logger
        formatter(logger).new(logger, *formatter_options(logger))
      end

      def formatter logger
        logger[:formatter] ||= 
          logger_default[:formatter] ||= 
          DefaultFormatter
      end

      def formatter_options logger
        logger[:formatter_options] ||=
          logger_default[:formatter_options] ||=
          [ ]
      end

      def log_prefix logger, ar
        pre = 
          logger[:log_prefix] ||= 
          logger_default[:log_prefix] ||= 
          EMPTY_String
        case pre
        when Proc
          pre.call(ar)
        else
          pre
        end
      end

      def log logger, msg = nil
        return msg unless logger
        msg ||= yield if block_given?
        return msg if msg.nil?
        dst = logger[:target]
        case dst
        when nil
          nil
        when IO
          dst.seek(0, IO::SEEK_END)
          dst.puts msg.to_s
          dst.flush
        when Proc
          dst.call(msg)
        else
          dst.send(logger[:method] || :debug, msg)
        end
        msg
      end

      def log_all msg = nil
        logger.values.each do | dst |
          log(dst) { msg ||= yield if block_given?; msg }
        end
        msg
      end

    end

    class BaseFormatter
      attr_reader :logger

      def initialize logger, *args
        @logger = logger
      end

      def format obj, mode
        case mode
        when :rcvr
          obj && obj.to_s
        when :module
          obj && obj.name
        when :time
          obj && obj.iso8601(6)
        when :error
          obj.inspect
        when :result
          obj.inspect
        when :method
          ad = ar.method_to_s
        else
          nil
        end
      end
    end
      
    class DefaultFormatter < BaseFormatter
      def format obj, mode
        case mode
        when :error
          return "ERROR #{obj.inspect}"
        when :result
          return "=> #{obj.inspect}"
        when :time
          return super
        else
          obj = super || obj
        end

        obj = obj.inspect
        if mode == :args
          obj = obj.to_s.gsub(/\A\[|\]\Z/, '')
        end
        obj
      end

      # Formats the ActivationRecord for the logger.
      def record ar, mode
        ad = ar.advised
        msg = nil

        case mode
        when :before, :after
          msg = ad.log_prefix(logger, ar).to_s
          msg = msg.dup if msg.frozen?
          ar[:args] ||= format(ar.args, :args) if ad[:log_args] != false
          ar[:meth] ||= "#{ad.method_to_s} #{ar.rcvr.class}"
          msg << "#{format(ar[:"time_#{mode}"], :time)} #{ar[:meth]}"
          msg << " #{format(ar.rcvr, :rcvr)}" if ad[:log_rcvr]
          msg << " ( #{ar[:args]} )" if ar[:args]
        end

        case mode
        when :before
          msg << " {"
        when :after
          msg << " }"
          if ar.error
            msg << " #{format(ar[:error],  :error )}" if ad[:log_error]  != false
          else
            msg << " #{format(ar[:result], :result)}" if ad[:log_result] != false
          end
        end

        msg
      end
    end # class

    class YamlFormatter < BaseFormatter
      def to_hash ar, mode
        ad = ar.advised
        data = (ar.advised.options[:log_data] || EMPTY_Hash).dup
        # pp [ :'ar.data=', ar.data ]
        data.update(ar.data)
        # pp [ :'data=', data ]
        if x = ad.log_prefix(logger, ar)
          data[:log_prefix] = x
        end
        data[:method] = ar.method
        data[:module] = Module === (x = ar.mod) ? x.name : x
        data[:kind] = ar.kind
        data[:signature] = ar.method_to_s
        data[:rcvr] = format(ar.rcvr, :rcvr) if ad[:log_rcvr]
        data[:rcvr_class] = ar.rcvr.class.name
        if x = data[:time_after] && 
            data[:time_before] && 
            (data[:time_after].to_f - data[:time_before].to_f)
          data[:time_elapsed] = x
        end
        data
      end

      def record ar, mode
        case mode
        when :after
          data = to_hash(ar, mode)
          YAML.dump(data)
        else
          nil
        end
      end
    end
  end
end
