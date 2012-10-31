module RO

  # A representation of a folder in a Research Object.

  class Folder

    attr_reader :name, :uri

    ##
    # +rosrs_session+:: A ROSRSSession object, needed to fetch the Folder contents.
    # +name+::          The display name of the Folder.
    # +uri+::           The URI for the resource referred to by the Folder.
    # +options+::       A hash of options:
    # [:eager_load]     Whether or not to eagerly load the entire Folder hierarchy within in this Folder.
    def initialize(rosrs_session, name, uri, options = {})
      @name = name
      @uri = uri
      @session = rosrs_session

      @loaded = false
      @contents = []
      load! if (@eager_load = options[:eager_load])
    end

    ##
    # Fetch the entry with name +child_name+ from the Folder's contents
    def child(child_name)
      contents.select {|child| child.name == child_name}.first
    end

    ##
    # Returns boolean stating whether or not this is a folder. Useful when examining Folder#contents.
    def folder?
      true
    end

    ##
    # Returns boolean stating whether or not a description of this Folder's contents has been fetched and loaded.
    def loaded?
      @loaded
    end

    ##
    # Returns an array of FolderEntry and Folder objects.
    def contents
      load! unless loaded?
      @contents
    end

    ##
    # Returns the number of entries within the folder.
    def size
      contents.size
    end

    ##
    # Fetch and parse the Folder's description to get the Folder's contents.
    def load!
      fetch_folder_contents!
      @loaded = true
    end

    ##
    # Manually set the Folder's contents.
    #
    # Saves making an HTTP request if you already have the folder description.
    def set_contents!(contents)
      @contents = contents
      @loaded = true
    end

    ##
    # Delete this folder from the RO. Contents will be preserved.
    # Also deletes any entries in other folders pointing to this one.
    def delete!
      @session.delete_folder(@uri)
    end

    ##
    # Add a resource to this folder. The resource must already be present in the RO.
    def add_resource(resource_uri, resource_name = nil)
      @session.add_folder_entry(@uri, resource_uri, resource_name, :parent => self)
    end

    private

    # Get folder contents from resource map
    def fetch_folder_contents!
      code, reason, headers, uripath, graph = @session.do_request_rdf("GET", uri,
                                                                      :accept => 'application/vnd.wf4ever.folder')
      set_contents!(graph)
    end

    def parse_folder_description(graph)
      contents = []

      query = RDF::Query.new do
        pattern [:folder_entry, RDF.type,  RDF::RO.FolderEntry]
        pattern [:folder_entry, RDF::RO.entryName, :name]
        pattern [:folder_entry, RDF::ORE.proxyFor, :target]
        pattern [:target, RDF.type, RDF::RO.Resource]
        # The pattern below is treated as mandatory - Bug in RDF library! :( Maybe not needed?
        # pattern [:target, RDF::ORE.isDescribedBy, :target_resource_map], :optional => true
      end

      # Create instances for each item.
      graph.query(query).each do |result|
        if result.respond_to? :target_resource_map
          contents << RO::Folder.new(@session, result.name.to_s, result.target.to_s, :eager_load => @eager_load)
        else
          contents << RO::FolderEntry.new(@session, result.name.to_s, result.target.to_s, result.entry_uri.to_s, self)
        end
      end
    end

  end

  # An item within a folder.

  class FolderEntry

    attr_reader :name, :uri, :parent, :entry_uri

    ##
    # +rosrs_session+:: A ROSRSSession object.
    # +name+:: The display name of the FolderEntry.
    # +uri+:: The URI for the resource referred to by the FolderEntry.
    # +entry_uri+:: The URI of the folder entry.
    # +parent+:: The parent Folder in which this FolderEntry resides.
    def initialize(rosrs_session, name, uri, entry_uri, parent)
      @name = name
      @uri = uri
      @entry_uri = entry_uri
      @parent = parent
      @session = rosrs_session
    end

    ##
    # Returns boolean stating whether or not this is a folder. Useful when examining RO::Folder#contents.
    def folder?
      false
    end

    ##
    # Removes this entry from the folder. The resource it refers to will still exists, however.
    def delete!
      @session.remove_folder_entry(@entry_uri)
    end

  end

end