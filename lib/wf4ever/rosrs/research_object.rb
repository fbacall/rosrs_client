module ROSRS

  class ResearchObject

    attr_reader :uri, :session

    def initialize(rosrs_session, uri)
      @session = rosrs_session
      @uri = uri
      @loaded = false
    end

    def self.create(session, name, description, creator, date = Time.now.strftime("%Y-%m-%d"))
      c,r,u,m = session.create_research_object(name, description, creator, date)
      self.new(session, u)
    end

    def loaded?
      @loaded
    end

    def load
      manifest_uri, @manifest = @session.get_manifest(uri)
      @resources = extract_resources
      @annotations = extract_annotations
      @root_folder = extract_root_folder
      @loaded = true
    end

    def manifest
      load unless loaded?
      @manifest
    end

    def annotations(resource_uri = nil)
      load unless loaded?
      if resource_uri.nil?
        @annotations.values
      else
        @annotations[resource_uri] || []
      end
    end

    def resources
      load unless loaded?
      @resources.values
    end

    def root_folder
      load unless loaded?
      @root_folder
    end

    def delete!
      code = @session.delete_research_object(uri)
      @loaded = false
      code == 204
    end

    ##
    # Create an annotation for a given resource_uri, using the supplied annotation body.
    def create_annotation(resource_uri, annotation)
      annotation = ROSRS::Annotation.create(self, resource_uri, annotation)
      annotations << annotation
      annotation
    end

    ##
    # Create a folder in the research object.
    def create_folder(name)
      ROSRS::Folder.create(self, name)
    end

    ##
    # Aggregate a given resource
    def add
      raise("Unimplemented") #TODO: Finish
    end

    ##
    # Remove the chosen resource from the RO
    def remove
      raise("Unimplemented") #TODO: Finish
    end

    private

    def extract_annotations
      annotations = {}
      queries = [RDF::RO.annotatesAggregatedResource, RDF::AO.annotatesResource].collect do |predicate|
        RDF::Query.new do
          pattern [:annotation_uri, RDF.type, RDF::RO.AggregatedAnnotation]
          pattern [:annotation_uri, predicate, :resource_uri]
          pattern [:annotation_uri, RDF::AO.body, :body_uri]
          pattern [:annotation_uri, RDF::DC.creator, :created_by]
          pattern [:annotation_uri, RDF::DC.created, :created_at]
        end
      end

      queries.each do |query|
        @manifest.query(query) do |result|
          annotations[result.resource_uri.to_s] ||= []
          annotations[result.resource_uri.to_s] << ROSRS::Annotation.new(self,
                                                                         result.annotation_uri.to_s,
                                                                         result.body_uri.to_s,
                                                                         result.resource_uri.to_s,
                                                                         :created_at => result.created_at.to_s,
                                                                         :created_by => result.created_by.to_s,
                                                                         :resource => @resources[result.resource_uri.to_s]

          )
        end
      end

      annotations
    end

    def extract_root_folder
      query = RDF::Query.new do
        pattern [:research_object, RDF::RO.rootFolder,  :folder]
        pattern [:folder, RDF::ORE.isDescribedBy, :folder_resource_map]
      end

      result = @manifest.query(query).first
      if result
        folder_uri = result.folder.to_s
        folder_name = folder_uri.to_s.split('/').last
        ROSRS::Folder.new(self, folder_name, folder_uri)
      else
        nil
      end
    end

    def extract_resources
      resources = {}

      query = RDF::Query.new do
        pattern [:research_object, RDF::ORE.aggregates, :resource]
        pattern [:resource, RDF.type, RDF::RO.Resource]
        pattern [:resource, RDF::RO.name, :name]
        pattern [:proxy_uri, RDF::ORE.proxyFor, :resource]
      end

      @manifest.query(query).each do |result|
        resource[result.resource.to_s] = ROSRS::Resource.new(self, result.resource.to_s, result.proxy_uri.to_s)
      end

      resources
    end

  end
end