module OData4
  class Service
    class Response
      module JSON
        def parse_entity(entity_json, entity_options)
          OData4::Entity.from_json(entity_json, entity_options)
        end

        def next_page
          result_json['@odata.nextLink']
        end

        def next_page_url
          next_page.gsub(service.service_url, '')
        end

        def error_message
          result_json['error'].andand['innererror']
        end

        def parsed_body
          result_json
        end

        private

        def result_json
          @result_json ||= ::JSON.parse(response.body)
        end

        def single_entity?
          result_json['@odata.context'] =~ /\$entity$/
        end

        def find_entities
          single_entity? ? [result_json] : result_json['value']
        end
      end
    end
  end
end
