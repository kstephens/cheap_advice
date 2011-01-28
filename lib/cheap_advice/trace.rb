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
        ar[:logger] = logger = a.logger[ad.logger] || a.logger_default

        msg = nil
        formatter = nil
        if ad[:log_before] != false
          a.log(logger) do
            formatter = a.new_formatter(logger)
            ar[:before_time] = Time.now
            formatter.record(ar, :before)
          end
        end

        body.call

        if ad[:log_after] != false
          a.log(logger) do
            formatter ||= a.new_formatter(logger)
            ar[:after_time] = Time.now
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
        @options[:logger] ||= { }
      end
      def logger_default
        logger[nil] ||= { }
      end

      def new_formatter logger
        formatter(logger).new(*formatter_options(logger))
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

      def log_prefix logger
        pre = 
          logger[:log_prefix] ||= 
          logger_default[:log_prefix] ||= 
          EMPTY_String
        case pre
        when Proc
          pre.call
        else
          pre
        end
      end

      def log logger, msg = nil
        return msg unless logger
        msg ||= yield if block_given?
        return msg if msg.nil?
        dst = logger[:stream]
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
      def initialize *args
      end

      def format obj, mode
        case mode
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
      def initialize *args
      end

      def format obj, mode
        case mode
        when :error
          return "ERROR #{obj.inspect}"
        when :result
          return "=> #{obj.inspect}"
        else
          obj = super || obj
        end

        obj = obj.inspect
        if mode == :args
          obj = obj.to_s.gsub(/\A\[|\]\Z/, '')
        end
        obj
      end

      # Formats the ActivationRecord for the log.
      def record ar, mode
        ad = ar.advised
        msg = nil
        case mode
        when :before
          msg = ad.log_prefix(ar[:logger]).to_s.dup
          ar[:args] ||= format(ar.args, :args) if ad[:log_args] != false
          ar[:meth] ||= "#{ad.method_to_s} #{ar.rcvr.class}"
          msg << "#{format(ar[:before_time], :time)} #{ar[:meth]}"
          msg << "#{msg} ( #{ar[:args]} )" if ar[:args]
          msg << " {"
        when :after
          msg = ad.log_prefix(ar[:logger]).to_s.dup
          ar[:args] ||= format(ar.args, :args) if ad[:log_args] != false
          ar[:meth] ||= "#{ad.method_to_s} #{ar.rcvr.class}"
          msg << "#{format(ar[:after_time],  :time)} #{ar[:meth]}"
          msg << "( #{ar[:args]} )" if ar[:args]
          msg << " }"
          if ar.error
            msg << "#{format(ar[:error],  :error )}" if ad[:log_error]  != false
          else
            msg << "#{format(ar[:result], :result)}" if ad[:log_result] != false
          end
        end
        msg
      end
    end # class

    class YamlFormatter < BaseFormatter
      def to_hash ar, mode
        data = ar.data.merge(ar[:record_data])
        data[:method] = ar.method
        data[:module] = ar.mod.name
        data[:kind] = ar.kind
        data[:signature] = ar.method_to_s
        data[:rcvr_class] = ar.rcvr.class.name
        data[:time_elapsed] = data[:time_after] && data[:time_before] && data[:time_after].to_f - data[:time_before].to_f
        data
      end

      def record ar, mode
        case mode
        when :before
          to_hash(ar, mode)
          nil
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
