require 'uri'

class Namespace
  def initialize(prefix, base, memberlist)
    @prefix   = prefix
    @base_uri = URI(base)
    @members  = {}
    memberlist.each do |m|
      @members[m.to_sym] = URI(@base_uri.to_s+m)
      Namespace.send(:define_method, m) do
        return @members[m.to_sym]
      end
    end
  end

  def [](name)
    return @members[name]
  end

end

ao      = "http://purl.org/ao/"
ore     = "http://www.openarchives.org/ore/terms/"
foaf    = "http://xmlns.com/foaf/0.1/"
ro      = "http://purl.org/wf4ever/ro#"
roevo   = "http://purl.org/wf4ever/roevo#"
wfprov  = "http://purl.org/wf4ever/wfprov#"
wfdesc  = "http://purl.org/wf4ever/wfdesc#"
dcterms = "http://purl.org/dc/terms/"
roterms = "http://ro.example.org/ro/terms/"

ORE     = Namespace.new("ORE", ore,
            [ "Aggregation", "AggregatedResource", "Proxy",
              "aggregates", "proxyFor", "proxyIn",
              "isDescribedBy"
            ])
AO      = Namespace.new("AO", ao,
            [ "Annotation",
              "body", "annotatesResource"
            ])
RO      = Namespace.new("RO", ro,
            [ "ResearchObject", "AggregatedAnnotation",
              "annotatesAggregatedResource" # @@TODO: deprecated
            ])
ROEVO   = Namespace.new("ROEVO",  roevo,
            [ "LiveRO"
            ])
DCTERMS = Namespace.new("DCTERMS", dcterms,
            [ "identifier", "description", "title",
              "creator", "created", "subject",
              "format", "type"
            ])
ROTERMS = Namespace.new("ROTERMS", roterms,
            [ "note", "resource", "defaultBase"
            ])

RDF__   = Namespace.new("RDF", "...",
            [ "Seq", "Bag", "Alt", "Statement", "Property",
              "XMLLiteral", "List", "PlainLiteral",
              "subject", "predicate", "object",
              "type", "value", "first", "rest", "nil"
            ])
RDFS__  = Namespace.new("RDFS", "...",
            [ "Resource", "Class", "Literal", "Datatype",
              "subClassOf", "subPropertyOf",
              "comment", "label", "domain", "range", "seeAlso", "isDefinedBy",
              "Container", "ContainerMembershipProperty",
              "member",
            ])
