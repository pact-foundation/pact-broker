require 'pact_broker/logging'
require 'pact_broker/repositories'
require 'pact_broker/matrix/row'
require 'pact_broker/matrix/deployment_status_summary'
require 'pact_broker/messages'
require 'pact_broker/string_refinements'

module PactBroker
  module Matrix
    module Service

      extend self
      extend PactBroker::Repositories
      extend PactBroker::Services
      include PactBroker::Logging
      extend PactBroker::Messages
      using PactBroker::StringRefinements

      def find selectors, options = {}
        logger.info "Querying matrix", selectors: selectors, options: options
        query_results = matrix_repository.find selectors, options
        deployment_status_summary = DeploymentStatusSummary.new(query_results.rows, query_results.resolved_selectors, query_results.integrations)
        QueryResultsWithDeploymentStatusSummary.new(query_results, deployment_status_summary)
      end

      def find_for_consumer_and_provider params, options = {}
        selectors = [ UnresolvedSelector.new(pacticipant_name: params[:consumer_name]), UnresolvedSelector.new(pacticipant_name: params[:provider_name]) ]
        find(selectors, options)
      end

      def find_for_consumer_and_provider_with_tags params
        consumer_selector = UnresolvedSelector.new(
          pacticipant_name: params[:consumer_name],
          tag: params[:tag],
          latest: true
        )
        provider_selector = UnresolvedSelector.new(
          pacticipant_name: params[:provider_name],
          tag: params[:provider_tag],
          latest: true
        )
        selectors = [consumer_selector, provider_selector]
        options = { latestby: 'cvpv' }
        if validate_selectors(selectors).empty?
          matrix_repository.find(selectors, options).first
        else
          nil
        end
      end

      def find_compatible_pacticipant_versions criteria
        matrix_repository.find_compatible_pacticipant_versions criteria
      end

      def validate_selectors selectors, options = {}
        error_messages = []

        selectors.each do | s |
          if s[:pacticipant_name].nil?
            error_messages << "Please specify the pacticipant name"
          else
            if s.key?(:pacticipant_version_number) && s.key?(:latest)
              error_messages << "A version number and latest flag cannot both be specified for #{s[:pacticipant_name]}"
            end
          end
        end

        selectors.collect{ |selector| selector[:pacticipant_name] }.compact.each do | pacticipant_name |
          unless pacticipant_service.find_pacticipant_by_name(pacticipant_name)
            error_messages << "Pacticipant #{pacticipant_name} not found"
          end
        end

        if selectors.size == 0
          error_messages << "Please provide 1 or more version selectors."
        end

        if options[:tag]&.not_blank? && options[:environment_name]&.not_blank?
          error_messages << message("errors.validation.cannot_specify_tag_and_environment")
        end

        if options[:latest] && options[:environment_name]&.not_blank?
          error_messages << message("errors.validation.cannot_specify_latest_and_environment")
        end

        if options[:environment_name]&.not_blank? && environment_service.find_by_name(options[:environment_name]).nil?
          error_messages << message("errors.validation.environment_with_name_not_found", name: options[:environment_name])
        end

        error_messages
      end
    end
  end
end
