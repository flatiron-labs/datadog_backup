# frozen_string_literal: true

module DatadogBackup
  class Synthetics < Core
    def all_synthetics
      get_all.fetch('tests', []).map do |test|
        @typeMap[test['public_id']] = test['type']
        get_by_id(test['public_id'])
      end
    end

    def api_service
      # The underlying class from Dogapi that talks to datadog
      client.instance_variable_get(:@dashboard_service)
    end

    def api_version
      'v1'
    end

    def api_resource_name
      'synthetics/tests'
    end

    def get(id)
      with_200 do
        url = "/api/#{api_version}/#{api_resource_name}/#{id}"
        unless @typeMap.fetch(id, nil).nil?
          url = "/api/#{api_version}/synthetics/tests/#{@typeMap.fetch(id, nil)}/#{id}"
        end
        api_service.request(Net::HTTP::Get, url, nil, nil, false)
      end
    rescue RuntimeError => e
      return {} if e.message.include?('Request failed with error ["404"')

      raise e.message
    end


    def backup
      logger.info("Starting diffs on #{::DatadogBackup::ThreadPool::TPOOL.max_length} threads")

      futures = all_synthetics.map do |synthetic|
        Concurrent::Promises.future_on(::DatadogBackup::ThreadPool::TPOOL, synthetic) do |synthetic|
          id = synthetic['public_id']
          get_and_write_file(id)
        end
      end

      watcher = ::DatadogBackup::ThreadPool.watcher(logger)
      watcher.join if watcher.status

      Concurrent::Promises.zip(*futures).value!
    end

    def initialize(options)
      super(options)
      @banlist = %w[modified_at url].freeze
      @typeMap = {}
    end
  end
end
