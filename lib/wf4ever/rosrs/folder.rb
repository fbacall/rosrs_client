module ROSRS

  # A representation of a folder in a Research Object.

  class Folder

    attr_reader :research_object, :name, :uri

    ##
    # +research_object+:: The Wf4Ever::ResearchObject that aggregates this folder.
    # +name+::            The display name of the Folder.
    # +uri+::             The URI for the resource referred to by the Folder.
    # +options+::         A hash of options:
    # [:eager_load]       Whether or not to eagerly load the entire Folder hierarchy within in this Folder.
    def initialize(research_object, name, uri, options = {})
      @name = name
      @uri = uri
      @research_object = research_object
      @session = research_object.session
      @loaded = false
      if options[:contents_graph]
        @contents = parse_folder_description(options[:contents_graph])
        @loaded = true
      end
      @root_folder = options[:root_folder] || false
      load if (@eager_load = options[:eager_load])
    end

    ##
    # Fetch the entry with name +child_name+ from the Folder's contents
    def child(child_name)
      contents.select {|child| child.name == child_name}.first
    end

    ##
    # Returns boolean stating whether or not a description of this Folder's contents has been fetched and loaded.
    def loaded?
      @loaded
    end

    ##
    # Returns whether or not this folder is the root folder of the RO
    def root?
      @root_folder
    end

    ##
    # Returns an array of FolderEntry objects
    def contents
      load unless loaded?
      @contents
    end

    ##
    # Fetch and parse the Folder's description to get the Folder's contents.
    def load
      @contents = fetch_folder_contents
      @loaded = true
    end

    ##
    # Delete this folder from the RO. Contents will be preserved.
    # Also deletes any entries in other folders pointing to this one.
    def delete
      code = @session.delete_folder(@uri)
      @loaded = false
      code == 204
    end

    ##
    # Add a resource to this folder. The resource must already be present in the RO.
    def add(resource_uri, entry_name = nil)
      contents << ROSRS::FolderEntry.create(self, entry_name, resource_uri)
    end

    def remove(entry)

    end

    ##
    # Create a folder in the RO and add it to this folder as a subfolder
    def create_folder(name)
      folder = @research_object.create_folder(name)
      add(folder.uri, name)
      folder
    end

    def self.create(ro, name, contents = [])
      code, reason, uri, folder_description = ro.session.create_folder(ro.uri, name, contents)
      self.new(ro, name, uri, :contents => folder_description)
    end

    private

    # Get folder contents from remote resource map file
    def fetch_folder_contents
      code, reason, headers, uripath, graph = @session.do_request_rdf("GET", uri,
                                                                      :accept => 'application/vnd.wf4ever.folder')
      parse_folder_description(graph)
    end

    def parse_folder_description(graph)
      contents = []

      query = RDF::Query.new do
        pattern [:folder_entry, RDF.type,  RDF::RO.FolderEntry]
        pattern [:folder_entry, RDF::RO.entryName, :name]
        pattern [:folder_entry, RDF::ORE.proxyFor, :target]
        # pattern [:target, RDF.type, RDF::RO.Resource]
        # The pattern below is treated as mandatory - Bug in RDF library! :( Maybe not needed?
        # pattern [:target, RDF::ORE.isDescribedBy, :target_resource_map], :optional => true
      end

      # Create instances for each item.
      graph.query(query).each do |result|
      #  if result.respond_to? :target_resource_map
      #    contents << ROSRS::Folder.new(@research_object, result.name.to_s, result.target.to_s, :eager_load => @eager_load)
      #  else
          contents << ROSRS::FolderEntry.new(self, result.name.to_s, result.folder_entry.to_s, result.target.to_s)
      #  end
      end
    end

  end
end