module ROSRS

  class Resource
    attr_reader :uri, :proxy_uri, :name

    def initialize(research_object, uri, proxy_uri = nil, external = nil)
      @research_object = research_object
      @uri = uri
      @proxy_uri = proxy_uri
      @session = @research_object.session
      if external.nil?
        @external = !@uri.include?(research_object.uri)
      else
        @external = external
      end
    end

    ##
    # Get all the annotations on this resource
    def annotations
      @research_object.annotations(@uri)
    end

    ##
    # Add an annotation to this resource
    def annotate(annotation)
      @research_object.create_annotation(@uri, annotation)
    end

    ##
    # Removes this resource from the Research Object.
    def delete
      code = @session.delete_resource(@proxy_uri)[0]
      @loaded = false
      code == 204
    end

    def internal?
      !@external
    end

    def external?
      @external
    end

    def self.create_internal(research_object, name, body, content_type = 'text/plain')
      code, reason, proxy_uri, resource_uri = research_object.session.aggregate_internal_resource(research_object.uri,
                                                                                                 name,
                                                                                                 :body => body,
                                                                                                 :ctype => content_type)
      self.new(research_object, resource_uri, proxy_uri, false)
    end

    def self.create_external(research_object, uri)
      code, reason, proxy_uri, resource_uri = research_object.session.aggregate_external_resource(research_object.uri, uri)
      self.new(research_object, resource_uri, proxy_uri, true)
    end

  end
end