module MultiDb
  module ActiveRecordRuntimeExtensions
    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods
      # handle subclasses which were defined by the framework or plugins
      base.send(:descendants).each do |child|
        child.hijack_connection
      end
    end

    module InstanceMethods
      def connection_proxy
        self.class.connection_proxy
      end

      def reload(options = nil)
        connection_proxy.with_master { super }
      end
    end

    module ClassMethods
      def connection_proxy
        @connection_proxy
      end

      def connection_proxy=(proxy)
        @connection_proxy = proxy
      end

      # Make sure transactions always switch to the master
      def transaction(options = {}, &block)
        if self.connection.kind_of?(ConnectionProxy)
          super
        else
          @connection_proxy.with_master { super }
        end
      end

      # make caching always use the ConnectionProxy
      def cache(&block)
        if ActiveRecord::Base.configurations.blank?
          yield
        else
          @connection_proxy.cache(&block)
        end
      end

      def inherited(child)
        super
        child.hijack_connection
      end

      def hijack_connection
        return if ConnectionProxy.master_models.include?(self.to_s) || ConnectionProxy.master_models.include?(self)
        logger.info "[MULTIDB] hijacking connection for #{self.to_s}"
        class << self
          def connection
            @connection_proxy
          end
        end
      end
    end
  end
end

ActiveRecord::Base.class_eval do
  class << self
    def proxy_spec
      @proxy_spec
    end

    def establish_multi_db_connection(spec = nil)
      @proxy_spec = (spec.is_a?(String) || spec.is_a?(Symbol)) ? spec.to_s : nil
      establish_base_connection spec
    end

    alias_method :establish_base_connection, :establish_connection
    alias_method :establish_connection,      :establish_multi_db_connection
  end
end
