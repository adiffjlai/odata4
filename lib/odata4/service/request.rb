module OData4
  class Service
    # Encapsulates a single request to an OData service.
    class Request
      # The OData service against which the request is performed
      attr_reader :service
      # The OData4::Query that generated this request (optional)
      attr_reader :query
      # The HTTP method for this request
      attr_accessor :method
      # The request body (optional)
      attr_accessor :body
      # The request format (`:atom`, `:json`, or `:auto`)
      attr_accessor :format
      # crossCompany option for request
      attr_accessor :cross_company

      # Create a new request
      # @param service [OData4::Service] Where the request will be sent
      # @param url_chunk [String] Request path, relative to the service URL, including query params
      # @param options [Hash] Additional request options
      def initialize(service, url_chunk, options = {})
        @service = service
        @url_chunk = url_chunk
        @method = options[:method]  || :get
        @format = options[:format]  || :auto
        @query  = options[:query]
        @body   = options[:body]    || nil
        @cross_company = options[:cross_company] || false
        puts options
      end

      # Return the full request URL (including service base)
      # @return [String]
      def url
        append_query(
          ::URI.join("#{service.service_url}/", ::URI.escape(url_chunk))
        )
      end

      # The content type for this request. Depends on format.
      # @return [String]
      def content_type
        if format == :auto
          MIME_TYPES.values.join(',')
        elsif MIME_TYPES.has_key? format
          MIME_TYPES[format]
        else
          raise ArgumentError, "Unknown format '#{format}'"
        end
      end

      # Execute the request
      #
      # @param additional_options [Hash] options to pass to Faraday
      # @return [OData4::Service::Response]
      def execute(additional_options = {})
        options = request_options(additional_options)

        logger.info "Requesting #{method.to_s.upcase} #{url} #{body}..."

        response = service.connection.send(method) do |request|
          request.url url
          request.body = body
          options[:headers].each do |key,value|
            request.headers[key] = value
          end
        end

        Response.new(service, response, query)
      end

      private

      attr_reader :url_chunk

      def logger
        service.logger
      end

      def request_options(additional_options = {})
        options = service.options[:faraday]
          .merge({ method: method })
          .merge(additional_options)

        # Don't overwrite Accept header if already present
        unless options[:headers]['Accept']
          options[:headers] = options[:headers].merge({
            'Accept' => content_type,
          })
          unless options[:headers]['Content-Type']
            options[:headers] = options[:headers].merge({
              'Content-Type' => content_type,
            })
          end
        end

        options
      end

      def append_query uri
        new_query_arr = URI.decode_www_form(
          String(uri.query)
        ) << ["crossCompany", @cross_company]
        puts new_query_arr
        uri.query = URI.encode_www_form(new_query_arr)
        uri.to_s
      end
    end
  end
end
