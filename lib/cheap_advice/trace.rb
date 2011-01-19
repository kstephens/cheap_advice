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

        if ad[:log_before] != false
          a.log(log_dst) do 
            msg = "#{ar.rcvr.class} #{ar.method}"
            msg = "#{msg} ( #{ar.args.inspect.gsub(/\A\[|\]\Z/, '')} )" if ad[:log_args] != false
            "#{ad.log_prefix}#{Time.now.iso8601(6)} #{msg} {"
          end
        end

        body.call

        if ad[:log_after] != false
          a.log(log_dst) do
            unless msg
              msg = "#{ar.rcvr.class} #{ar.method}"
              msg = "#{msg} ( #{ar.args.inspect.gsub(/\A\[|\]\Z/, '')} )" if ad[:log_args] != false
            end
            msg = "#{ad.log_prefix}#{Time.now.iso8601(6)} #{msg} }"
            msg = "#{msg} => #{ar.result.inspect}" if ad[:log_result] != false
            msg
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
  end
end
