class FolderEntry

  attr_reader :name, :uri, :parent

  def initialize(name, uri, parent)
    @name = name
    @uri = uri
    @parent = parent
  end

  def folder?
    false
  end

end

class Folder < FolderEntry

  def initialize(name, uri, parent, rosrs_session, eager_load = false)
    super(name, uri, parent)
    @loaded = false
    @session = rosrs_session
    load! if (@eager_load = eager_load)
  end

  def child(child_name)
    contents.select {|child| child.name == child_name}.first
  end

  def folder?
    true
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

  def load!
    unless loaded?
      fetch_folder_contents!
      @loaded = true
    end
    @loaded
  end

  def refresh!
    fetch_folder_contents!
    @loaded = true
  end

  private

  # Get folder contents from resource map
  def fetch_folder_contents!
    @contents = []

    # Load folder contents
    code, reason, headers, uripath, graph = @session.do_request_rdf("GET", uri)

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
        @contents << Folder.new(result.name.to_s, result.target.to_s, self, result.target_resource_map.to_s, eager_load?)
      else
        @contents << FolderEntry.new(result.name.to_s, result.target.to_s, self)
      end
    end
  end

end
