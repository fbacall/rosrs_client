#ao      = "http://purl.org/ao/"
#ore     = "http://www.openarchives.org/ore/terms/"
#ro      = "http://purl.org/wf4ever/ro#"
#roevo   = "http://purl.org/wf4ever/roevo#"
#wfprov  = "http://purl.org/wf4ever/wfprov#"
#wfdesc  = "http://purl.org/wf4ever/wfdesc#"
#roterms = "http://ro.example.org/ro/terms/"

module RDF

  class AO < Vocabulary("http://purl.org/ao/")
    property :Annotation
    property :body
    property :annotatesResource
  end

  class ORE < Vocabulary("http://www.openarchives.org/ore/terms/")
    property :Aggregation
    property :AggregatedResource
    property :Proxy
    property :aggregates
    property :proxyFor
    property :proxyIn
    property :isDescribedBy
  end

  class RO < Vocabulary("http://purl.org/wf4ever/ro#")
    property :ResearchObject
    property :AggregatedAnnotation
    property :annotatesAggregatedResource
    property :FolderEntry
    property :Folder
    property :Resource
    property :entryName
  end

  class ROEVO < Vocabulary("http://purl.org/wf4ever/roevo#")
    property :LiveRO
  end

  class ROTERMS < Vocabulary("http://ro.example.org/ro/terms/")
    property :note
    property :resource
    property :defaultBase
  end
end
