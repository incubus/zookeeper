# tests the CZookeeper, obviously only available when running under MRI

unless defined?(::JRUBY_VERSION)
  require 'spec_helper'
  require 'timeout'

  describe Zookeeper::CZookeeper do
    def pop_all_events
      [].tap do |rv|
        begin
          rv << @event_queue.pop(non_blocking=true)
        rescue ThreadError
        end
      end
    end

    def wait_until_connected(timeout=10)
      wait_until(timeout) { @czk.state == Zookeeper::Constants::ZOO_CONNECTED_STATE }
    end

    describe do
      before do
        @event_queue = Zookeeper::Common::QueueWithPipe.new
        @czk = Zookeeper::CZookeeper.new(Zookeeper.default_cnx_str, @event_queue)
      end

      after do
        @czk.close rescue Exception
        @event_queue.close rescue Exception
      end

      it %[should be in connected state within a reasonable amount of time] do
        expect(wait_until_connected).to be_truthy
      end

      describe :after_connected do
        before do
          expect(wait_until_connected).to be_truthy
        end

        it %[should have a connection event after being connected] do
          event = wait_until(10) { @event_queue.pop }
          expect(event).to be
          expect(event[:req_id]).to eq(Zookeeper::Constants::ZKRB_GLOBAL_CB_REQ)
          expect(event[:type]).to   eq(Zookeeper::Constants::ZOO_SESSION_EVENT)
          expect(event[:state]).to  eq(Zookeeper::Constants::ZOO_CONNECTED_STATE)
        end
      end
    end

    it %[should raise ConnectionFailed when a host of the connect string does not resolve] do
      expect {
        Zookeeper::CZookeeper.new('zkrb-no-such-host.invalid:2181', Zookeeper::Common::QueueWithPipe.new)
      }.to raise_error(Zookeeper::Exceptions::ConnectionFailed, /error connecting to zookeeper/)
    end

    describe 'the session timeout' do
      after do
        @zk.close rescue Exception
      end

      it %[should be the default, not the raw ruby value] do
        @zk = Zookeeper.new(Zookeeper.default_cnx_str)
        expect(@zk.recv_timeout).to eq(Zookeeper::CZookeeper::DEFAULT_RECEIVE_TIMEOUT_MSEC)
      end

      it %[should keep the one asked for across a reopen] do
        @zk = Zookeeper.new(Zookeeper.default_cnx_str, 10, nil, :receive_timeout_msec => 15_000)
        expect(@zk.recv_timeout).to eq(15_000)
        @zk.reopen
        expect(@zk.recv_timeout).to eq(15_000)
      end
    end

    describe 'with a request the C client refuses' do
      before do
        @zk = Zookeeper.new(Zookeeper.default_cnx_str)
      end

      after do
        @zk.close rescue Exception
      end

      it %[should answer it and still close promptly] do
        # the C client rejects a control character in a path before sending anything
        expect(@zk.create(:path => "/zkrb-refused-\u0001")[:rc]).to eq(Zookeeper::Constants::ZBADARGUMENTS)
        expect { Timeout.timeout(10) { @zk.close } }.not_to raise_error
      end
    end
  end
end

