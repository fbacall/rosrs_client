module ROSRS

  class ResearchObject

    attr_reader :uri, :session

    def initialize(rosrs_session, uri)
      @session = rosrs_session
      if URI(uri).relative?
        uri = (rosrs_session.uri + URI(uri)).to_s
      end
      @uri = uri
      @uri << '/' unless uri[-1] == '/'
      @loaded = false
    end

    def self.create(session, name)
      c,r,u,m = session.create_research_object(name)
      self.new(session, u)
    end

    ##
    # Has this RO's manifest been fetched and parsed?
    def loaded?
      @loaded
    end

    ##
    # Fetch and parse the RO manifest
    def load
      manifest_uri, @manifest = @session.get_manifest(uri)
      @resources = extract_resources
      @annotations = extract_annotations
      @root_folder = extract_root_folder
      @folders = extract_folders
      @loaded = true
    end

    def manifest
      load unless loaded?
      @manifest
    end

    ##
    # Get Annotations in this RO for the given resource_uri.
    # If resource_uri is nil, get the Annotations on the RO itself.
    def annotations(resource_uri = nil)
      load unless loaded?
      if resource_uri.nil?
        @annotations[@uri]
      else
        @annotations[resource_uri] || []
      end
    end

    ##
    # Return the Resource object for the given resource_uri, if it exists.
    # If resource_uri is nil, return all Resources in the RO.
    def resources(resource_uri = nil)
      load unless loaded?
      if resource_uri.nil?
        @resources.values
      else
        @resources[resource_uri]
      end
    end

    ##
    # Return the Folder object for the given resource_uri, if it exists.
    # If resource_uri is nil, return all Folder in the RO.
    def folders(resource_uri = nil)
      load unless loaded?
      if resource_uri.nil?
        @folders.values
      else
        @folders[resource_uri]
      end
    end

    ##
    # Return the root folder of the RO.
    def root_folder
      load unless loaded?
      @root_folder
    end

    ##
    # Delete this RO from the repository
    def delete
      code = @session.delete_research_object(@uri)[0]
      @loaded = false
      code == 204
    end

    ##
    # Create an annotation for a given resource_uri, using the supplied annotation body.
    def create_annotation(resource_uri, annotation)
      annotation = ROSRS::Annotation.create(self, resource_uri, annotation)
      @annotations[resource_uri] ||= []
      @annotations[resource_uri] << annotation
      annotation
    end

    ##
    # Create a folder in the research object.
    def create_folder(name)
      ROSRS::Folder.create(self, name)
    end

    ##
    # Aggregate an internal resource
    def aggregate_internal(name, body, content_type = 'text/plain')
      resource = ROSRS::Resource.create_internal(self, name, body, content_type)
      load unless loaded?
      @resources[resource.uri] = resource
    end

    ##
    # Aggregate an internal resource
    def aggregate_external(uri)
      resource = ROSRS::Resource.create_external(self, uri)
      load unless loaded?
      @resources[resource.uri] = resource
    end

    ##
    # Remove the chosen resource from the RO
    def remove(resource)
      resource.delete
      @resources.delete(resource.uri)
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

    def extract_folders
      folders = {}

      query = RDF::Query.new do
        pattern [:research_object, RDF::ORE.aggregates, :folder]
        pattern [:folder, RDF.type, RDF::RO.Folder]
      end

      result = @manifest.query(query).first
      if result
        folder_uri = result.folder.to_s
        folder_name = folder_uri.to_s.split('/').last
        folders[folder_uri] = ROSRS::Folder.new(self, folder_name, folder_uri)
      else
        nil
      end
      folders.delete(@root_folder)
      folders
    end

    def extract_root_folder
      query = RDF::Query.new do
        pattern [:research_object, RDF::ORE.aggregates, :folder]
        pattern [:research_object, RDF::RO.rootFolder, :folder]
        pattern [:folder, RDF.type, RDF::RO.Folder]
      end

      result = @manifest.query(query).first
      if result
        folder_uri = result.folder.to_s
        folder_name = folder_uri.to_s.split('/').last
        ROSRS::Folder.new(self, folder_name, folder_uri, :root_folder => true)
      else
        nil
      end
    end

    def extract_resources
      resources = {}

      query = RDF::Query.new do
        pattern [:research_object, RDF::ORE.aggregates, :resource]
        pattern [:resource, RDF.type, RDF::RO.Resource]
        #pattern [:resource, RDF::RO.name, :name]
        pattern [:proxy_uri, RDF::ORE.proxyFor, :resource]
      end

      @manifest.query(query).each do |result|
        resources[result.resource.to_s] = ROSRS::Resource.new(self, result.resource.to_s, result.proxy_uri.to_s)
      end

      resources
    end

  end
end