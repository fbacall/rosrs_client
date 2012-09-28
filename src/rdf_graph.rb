# Shim class for RDF graph parsing, serialization, access

class RDF_Graph

  def initialize(options)
    # options: :uri =>    (URI to load),
    #          :data =>   (string to load)
    #          :format => (format of data)
    @format = :rdfxml
    @graph = RDF::Graph.new
    if options[:uri]
      load_resource(options[:uri], options[:format])
    end
    if options[:data]
      load_data(options[:data], options[:format])
    end
  end

  def load_data(data, format=nil)
    @graph << RDF::Reader.for(map_format(format)).new(data)
  end

  def load_resource(uri, format=nil)
    raise NotImplementedError.new("Attempt to initialize RDF_Graph from web resource: #{uri}")
  end

  def serialize(format=nil)
    return RDF::Writer.for(map_format(format)).buffer { |w| w << @graph }
  end

  # other methods here

  # Private helpers

  private

  def map_format(format=nil)
    rdf_format = :rdfxml  # default
    if format
      if format == :xml
        rdf_format = :rdfxml
      elsif format == :ntriples
        rdf_format = :ntriples
      elsif format == :turtle
        rdf_format = :turtle
      else
        raise ArgumentError.new("Unrecognized RDF format: #{format}")
      end
    end
    return rdf_format
  end

end