require 'odata4/service/request'
require 'odata4/service/response'
require 'faraday'

module OData4
  # Encapsulates the basic details and functionality needed to interact with an
  # OData4 service.
  class Service
    # The OData4 Service's URL
    attr_reader :service_url
    #Faraday Connection Object
    attr_reader :connection
    # Options to pass around
    attr_reader :options

    HTTP_TIMEOUT = 20

    METADATA_TIMEOUTS = [20, 60]

    MIME_TYPES = {
      atom:  'application/atom+xml',
      json:  'application/json',
      xml:   'application/xml',
      plain: 'text/plain',
      jsonmin: 'application/json;odata.metadata=minimal'
    }

    # Opens the service based on the requested URL and adds the service to
    # {OData4::Registry}
    #
    # @param service_url [String] the URL to the desired OData4 service
    # @param options [Hash] options to pass to the service
    # @return [OData4::Service] an instance of the service
    def initialize(service_url, options = {})
      @service_url = service_url
      @options = default_options.merge(options)
      @connection = faraday_connection
      OData4::ServiceRegistry.add(self)
      register_custom_types
    end

    # Opens the service based on the requested URL and adds the service to
    # {OData4::Registry}
    #
    # @param service_url [String] the URL to the desired OData4 service
    # @param options [Hash] options to pass to the service
    # @return [OData4::Service] an instance of the service
    def self.open(service_url, options = {})
      Service.new(service_url, options)
    end

    # Returns user supplied name for service, or its URL
    # @return [String]
    def name
      @name ||= options[:name] || service_url
    end

    # Returns the service's metadata URL.
    # @return [String]
    def metadata_url
      "#{service_url}/$metadata"
    end

    # Returns the service's metadata definition.
    # @return [Nokogiri::XML]
    def metadata
      @metadata ||= lambda { read_metadata }.call
    end

    # Returns all of the service's schemas.
    # @return Hash<String, OData4::Schema>
    def schemas
      @schemas ||= metadata.xpath('//Schema').map do |schema_xml|
        [
          schema_xml.attributes['Namespace'].value,
          Schema.new(schema_xml, self)
        ]
      end.to_h
    end

    # Returns the service's EntityContainer (singleton)
    # @return OData4::EntityContainer
    def entity_container
      @entity_container ||= EntityContainer.new(self)
    end

    # Returns a hash of EntitySet names and their respective EntityType names
    # @return Hash<String, String>
    def entity_sets
      entity_container.entity_sets
    end

    # Retrieves the EntitySet associated with a specific EntityType by name
    #
    # @param entity_set_name [to_s] the name of the EntitySet desired
    # @return [OData4::EntitySet] an OData4::EntitySet to query
    def [](entity_set_name)
      entity_container[entity_set_name]
    end

    # Returns the default namespace, that is, the namespace of the schema
    # that contains the service's EntityContainer.
    # @return [String]
    def namespace
      entity_container.namespace
    end

    # Returns a list of `EntityType`s exposed by the service
    # @return Array<String>
    def entity_types
      @entity_types ||= schemas.map do |namespace, schema|
        schema.entity_types.map do |entity_type|
          "#{namespace}.#{entity_type}"
        end
      end.flatten
    end

    # Returns a list of `ComplexType`s used by the service.
    # @return [Hash<String, OData4::Schema::ComplexType>]
    def complex_types
      @complex_types ||= schemas.map do |namespace, schema|
        schema.complex_types.map do |name, complex_type|
          [ "#{namespace}.#{name}", complex_type ]
        end.to_h
      end.reduce({}, :merge)
    end

    # Returns a list of `EnumType`s used by the service
    # @return [Hash<String, OData4::Schema::EnumType>]
    def enum_types
      @enum_types ||= schemas.map do |namespace, schema|
        schema.enum_types.map do |name, enum_type|
          [ "#{namespace}.#{name}", enum_type ]
        end.to_h
      end.reduce({}, :merge)
    end

    # Returns a more compact inspection of the service object
    def inspect
      "#<#{self.class.name}:#{self.object_id} name='#{name}' service_url='#{self.service_url}'>"
    end

    # Execute a request against the service
    #
    # @param url_chunk [to_s] string to append to service URL
    # @param options [Hash] additional request options
    # @return [OData4::Service::Response]
    def execute(url_chunk, options = {})
      Request.new(self, url_chunk, options.merge(@options[:request])).execute
    end

    # Get the property type for an entity from metadata.
    #
    # @param entity_name [to_s] the fully qualified entity name
    # @param property_name [to_s] the property name needed
    # @return [String] the name of the property's type
    def get_property_type(entity_name, property_name)
      namespace, _, entity_name = entity_name.rpartition('.')
      raise ArgumentError, 'Namespace missing' if namespace.nil? || namespace.empty?
      schemas[namespace].get_property_type(entity_name, property_name)
    end

    # Get the primary key for the supplied Entity.
    #
    # @param entity_name [to_s] The fully qualified entity name
    # @return [String]
    def primary_key_for(entity_name)
      namespace, _, entity_name = entity_name.rpartition('.')
      raise ArgumentError, 'Namespace missing' if namespace.nil? || namespace.empty?
      schemas[namespace].primary_key_for(entity_name)
    end

    # Get the compound keys for the supplied Entity.
    #
    # @param entity_name [to_s] the fully qualified entity name
    # @return [Array]
    def compound_keys_for(entity_name)
      namespace, _, entity_name = entity_name.rpartition('.')
      raise ArgumentError, 'Namespace missing' if namespace.nil? || namespace.empty?
      schemas[namespace].compound_keys_for(entity_name)
    end

    # Get the list of properties and their various options for the supplied
    # Entity name.
    # @param entity_name [to_s]
    # @return [Hash]
    # @api private
    def properties_for_entity(entity_name)
      namespace, _, entity_name = entity_name.rpartition('.')
      raise ArgumentError, 'Namespace missing' if namespace.nil? || namespace.empty?
      schemas[namespace].properties_for_entity(entity_name)
    end

    # Returns the log level set via initial options, or the
    # default log level (`Logger::WARN`) if none was specified.
    # @see Logger
    # @return [Fixnum|Symbol]
    def log_level
      options[:log_level] || Logger::WARN
    end

    # Returns the logger instance used by the service.
    # When Ruby on Rails has been detected, the service will
    # use `Rails.logger`. The log level will NOT be changed.
    #
    # When no Rails has been detected, a default logger will
    # be used that logs to STDOUT with the log level supplied
    # via options, or the default log level if none was given.
    # @see #log_level
    # @return [Logger]
    def logger
      @logger ||= lambda do
        if defined?(Rails)
          Rails.logger
        else
          logger = ::Logger.new(STDOUT)
          logger.level = log_level
          logger
        end
      end.call
    end

    # Allows the logger to be set to a custom `Logger` instance.
    # @param custom_logger [Logger]
    def logger=(custom_logger)
      @logger = custom_logger
    end

    private

    def default_options
      {
        faraday: {
          headers: { 'OData-Version' => '4.0' },
          timeout: HTTP_TIMEOUT,
        },
        # This is deprecated
        typhoeus: {
          headers: { 'OData-Version' => '4.0' },
          timeout: HTTP_TIMEOUT
        },
        strict: true, # strict property validation
        request: {
          cross_company: false # return only data belonging to the default company
        }
      }
    end

    def faraday_connection
      @connection = ::Faraday.new(url: service_url) do |faraday|
        faraday.request :url_encoded
        faraday.response :logger
        faraday.adapter ::Faraday.default_adapter
      end
    end

    def read_metadata
      # From file, good for debugging
      if options[:metadata_file]
        data = File.read(options[:metadata_file])
        ::Nokogiri::XML(data).remove_namespaces!
      else # From a URL
        response = nil
        begin
          METADATA_TIMEOUTS.each do |timeout|
            response = execute(metadata_url, timeout: timeout)
          end
        rescue Timeout::Error
          raise "Metadata Timeout"
        end
        ::Nokogiri::XML(response.body).remove_namespaces!
      end
    end

    def register_custom_types
      complex_types.each do |name, type|
        ::OData4::PropertyRegistry.add(name, type.property_class)
      end

      enum_types.each do |name, type|
        ::OData4::PropertyRegistry.add(name, type.property_class)
      end
    end
  end
end
