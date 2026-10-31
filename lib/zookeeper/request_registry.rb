module Zookeeper
  class RequestRegistry
    include Constants
    include Logger

    # @param [Hash] opts
    # @option opts [String] :chroot_path (nil) if given, will be used to
    #   correct a discrepancy between the C and Java clients when using a
    #   chrooted connection. If given, the chroot path will be stripped from
    #   the string returned by a `create`. It should be an absolute path.
    #
    def initialize(watcher, opts={})
      @mutex = Monitor.new

      @default_watcher  = watcher

      @current_req_id   = 0
      @watcher_reqs     = {}
      @completion_reqs  = {}

      @chroot_path = opts[:chroot_path]
    end

    def default_watcher
      @mutex.synchronize { @default_watcher }
    end

    def default_watcher=(blk)
      @mutex.synchronize { @default_watcher = blk }
    end

    def setup_call(meth_name, opts)
      req_id = nil
      @mutex.synchronize {
        req_id = @current_req_id
        @current_req_id += 1
        setup_completion(req_id, meth_name, opts) if opts[:callback]
        setup_watcher(req_id, opts)               if opts[:watcher]
      }
      req_id
    end

    def get_context_for(hash)
      return nil unless hash

      is_session_event  = (hash[:type] == ZOO_SESSION_EVENT)

      req_id  = hash.fetch(:req_id)

      if hash.has_key?(:rc)
        get_completion(req_id, :keep => is_session_event)
      else
        get_watcher(req_id, :keep => is_session_event)
      end
    end

    def clear_watchers!
      @mutex.synchronize { @watcher_reqs.clear }
    end
    
    # if we're chrooted, this method will strip the chroot prefix from +path+
    def strip_chroot_from(path)
      return path unless (chrooted? and path and path.start_with?(@chroot_path))
      path[@chroot_path.length..-1]
    end

    private
      def get_completion(req_id, opts={})
        @mutex.synchronize do
          if opts[:keep] 
            @completion_reqs[req_id]
          else
            @completion_reqs.delete(req_id)
          end
        end
      end

      # Return the watcher hash associated with the req_id. If the req_id
      # is the ZKRB_GLOBAL_CB_REQ, then does not clear the req from the internal
      # store, otherwise the req_id is removed.
      #
      def get_watcher(req_id, opts={})
        @mutex.synchronize do
          if Constants::ZKRB_GLOBAL_CB_REQ == req_id
            { :watcher => @default_watcher, :watcher_context => nil }
          elsif opts[:keep]
            @watcher_reqs[req_id]
          else
            @watcher_reqs.delete(req_id)
          end
        end
      end


      def setup_watcher(req_id, call_opts)
        @mutex.synchronize do
          @watcher_reqs[req_id] = { 
            :watcher => call_opts[:watcher],
            :context => call_opts[:watcher_context] 
          }
        end
      end

      def setup_completion(req_id, meth_name, call_opts)
        @mutex.synchronize do
          @completion_reqs[req_id] = { 
            # the C client (3.5+) strips the chroot from created paths itself,
            # like the Java one: stripping it again here would cut a path that
            # starts with the chroot's own name
            :callback => call_opts[:callback],
            :context  => call_opts[:callback_context]
          }
        end
      end
      
      def chrooted?
        @chroot_path && !@chroot_path.empty?
      end

      def default_watcher_proc
        Proc.new { |args|
          logger.debug { "Ruby ZK Global CB called type=#{event_by_value(args[:type])} state=#{state_by_value(args[:state])}" }
          true
        }
      end
  end
end

