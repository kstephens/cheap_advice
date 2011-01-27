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
        log_dst = a.logger[ad.logger] || a.logger[nil]

        msg = nil
        formatter = nil
        if ad[:log_before] != false
          a.log(log_dst) do
            formatter = a.new_formatter
            ar[:before_time] = Time.now
            formatter.record(ar, :before)
          end
        end

        body.call

        if ad[:log_after] != false
          a.log(log_dst) do
            formatter ||= a.new_formatter
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
      def new_formatter
        formatter.new(*formatter_options)
      end
      def formatter
        @options[:formatter] ||= DefaultFormatter
      end
      def formatter_options
        @options[:formatter_options] ||= [ ]
      end

      def logger
        @options[:logger] ||= { }
      end
      def logger_method
        @options[:logger_method]
      end
      def log_prefix
        case pre = @options[:log_prefix]
        when Proc
          pre.call
        else
          pre
        end
      end

      def log dst, msg = nil
        return msg unless dst
        msg ||= yield if block_given?
        return msg if msg.nil?
        case dst
        when IO
          dst.seek(0, IO::SEEK_END)
          dst.puts msg.to_s
          dst.flush
        when Proc
          dst.call(msg)
        else
          dst.send(logger_method || :debug, msg)
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

    class DefaultFormatter
      def initialize *args
      end

      def format obj, mode
        case mode
        when :module
          return obj && obj.name
        when :time
          return obj && obj.iso8601(6)
        when :error
          return "ERROR #{obj.inspect}"
        when :result
          return "=> #{obj.inspect}"
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
          ar[:args] ||= format(ar.args, :args) if ad[:log_args] != false
          ar[:meth_class] ||= "#{ar.rcvr.class} #{ar.method}"
          msg = "#{msg}#{format(ar[:before_time], :time)} #{ar[:meth_class]}"
          msg = "#{msg} ( #{ar[:args]} )" if ar[:args]
          msg = "#{msg} {"
        when :after
          ar[:args] ||= format(ar.args, :args) if ad[:log_args] != false
          ar[:meth_class] ||= "#{ar.rcvr.class} #{ar.method}"
          msg = "#{msg}#{format(ar[:after_time],  :time)} #{ar[:meth_class]}"
          msg = "#{msg} ( #{ar[:args]} )" if ar[:args]
          msg = "#{msg} }"
          if ar.error
            msg = "#{msg} #{format(ar[:error],  :error)}"  if ad[:log_error] != false
          else
            msg = "#{msg} #{format(ar[:result], :result)}" if ad[:log_result] != false
          end
        end
        msg = "#{ad.log_prefix}#{msg}" if msg
        msg
      end
    end
  end
end
