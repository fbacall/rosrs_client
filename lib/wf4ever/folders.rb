module RO
  class FolderEntry

    attr_reader :name, :uri, :parent

    ##
    # +name+:: The display name of the FolderEntry.
    # +uri+:: The URI for the resource referred to by the FolderEntry.
    # +parent+:: The parent Folder in which this FolderEntry resides.
    def initialize(name, uri, parent)
      @name = name
      @uri = uri
      @parent = parent
    end

    ##
    # Returns boolean stating whether or not this is a folder. Useful when examining Folder#contents.
    #
    def folder?
      false
    end

  end


  # A representation of a folder in a Research Object.

  class Folder < FolderEntry

    ##
    # +name+::          The display name of the Folder.
    # +uri+::           The URI for the resource referred to by the Folder.
    # +parent+::        The parent Folder in which this Folder resides.
    # +rosrs_session+:: A ROSRSSession object, needed to fetch the Folder contents.
    # +options+::       A hash of options:
    # [:eager_load]     Whether or not to eagerly load the entire Folder hierarchy within in this Folder.
    def initialize(name, uri, parent, rosrs_session, options = {})
      super(name, uri, parent)
      @loaded = false
      @session = rosrs_session
      @contents = []
      load! if (@eager_load = options[:eager_load])
    end

    ##
    # Fetch the entry with name +child_name+ from the Folder's contents
    #
    def child(child_name)
      contents.select {|child| child.name == child_name}.first
    end

    ##
    # Returns boolean stating whether or not this is a folder. Useful when examining Folder#contents.
    #
    def folder?
      true
    end

    ##
    # Returns boolean stating whether or not a description of this Folder's contents has been fetched and loaded.
    #
    def loaded?
      @loaded
    end

    ##
    # Returns an array of FolderEntry and Folder objects.
    #
    def contents
      load!
      @contents
    end

    ##
    # Returns the number of entries within the folder.
    #
    def size
      contents.size
    end

    ##
    # Fetch and parse the Folder's description to get the Folder's contents, if not already loaded.
    #
    # See also: refresh!
    #
    def load!
      unless loaded?
        fetch_folder_contents!
        @loaded = true
      end
      @loaded
    end

    ##
    # Fetch and parse the Folder's description to get the Folder's contents, regardless if already loaded.
    #
    def refresh!
      fetch_folder_contents!
      @loaded = true
    end

    ##
    # Manually set the Folder's contents.
    #
    # Saves making an HTTP request if you already have the folder description.
    #
    def set_contents!(contents)
      @contents = contents
      @loaded = true
    end

    private

    # Get folder contents from resource map
    def fetch_folder_contents!
      code, reason, headers, uripath, graph = @session.do_request_rdf("GET", uri)
      set_contents!(graph)
    end

    def parse_folder_description(graph)
      contents = []

      query = RDF::Query.new do
        pattern [:folder_entry, RDF.type,  RDF::RO.FolderEntry]
        pattern [:folder_entry, RDF::RO.entryName, :name]
        pattern [:folder_entry, RDF::ORE.proxyFor, :target]
        pattern [:target, RDF.type, RDF::RO.Resource]
        # The pattern below is treated as mandatory - Bug in RDF library! :(
        pattern [:target, RDF::ORE.isDescribedBy, :target_resource_map], :optional => true
      end

      # Create instances for each item.
      graph.query(query).each do |result|
        if result.respond_to? :target_resource_map
          contents << Folder.new(result.name.to_s, result.target.to_s, self,
                                 result.target_resource_map.to_s, :eager_load => @eager_load)
        else
          contents << FolderEntry.new(result.name.to_s, result.target.to_s, self)
        end
      end
    end

  end
end