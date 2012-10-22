class FolderEntry

  attr_reader :name, :path, :parent

  def initialize(name, path, parent)
    @name = name
    @path = path
    @parent = parent
  end

end

class Folder < FolderEntry

  def initialize(name, path, parent, resource_map_uri, eager_load = false)
    super(name, path, parent)
    @resource_map_uri = resource_map_uri
    @loaded = false
    load! if (@eager_load = eager_load)
  end

  def eager_load?
    @eager_load
  end

  def loaded?
    @loaded
  end

  def contents
    load! unless loaded?
    @contents
  end

  def size
    contents.size
  end

  # Get folder contents from resource map
  def load!
    @contents = []
    # Load folder contents
    graph = RDF::Graph.load(resource_map_uri)

    query = RDF::Query.new do
      pattern [:folder_entry, RDF.type,  RDF::RO.FolderEntry]
      pattern [:folder_entry, RDF::RO.entryName, :name]
      pattern [:folder_entry, RDF::ORE.proxy_for, :target]
      pattern [:target, RDF.type, RDF::RO.Resource]
      # The pattern below is treated as mandatory - Bug in RDF library! :(
      pattern [:target, RDF::ORE.isDescribedBy, :target_resource_map], :optional => true
    end

    query.execute(graph).each do |result|
      if result.respond_to? :target_resource_map
        @contents << Folder.new(result.name.to_s, result.target.to_s, self, result.target_resource_map.to_s)
      else
        @contents << FolderEntry.new(result.name.to_s, result.target.to_s, self)
      end
    end

    #   Create instances for each item. Pass along eager_load setting to child folders.
    @loaded = true
  end

end