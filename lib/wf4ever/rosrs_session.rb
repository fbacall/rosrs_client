# ROSRS session class

class ROSRSSession
  # Exception class used to signal HTTP Session errors
  class Exception < Exception; end

  ANNOTATION_CONTENT_TYPES =
    { "application/rdf+xml" => :xml,
      "text/turtle"         => :turtle,
      #"text/n3"             => :n3,
      "text/nt"             => :ntriples,
      #"application/json"    => :jsonld,
      #"application/xhtml"   => :rdfa,
    }

  # -------------
  # General setup
  # -------------

  def initialize(uri, accesskey=nil)
    @uri = URI(uri.to_s) # Force string or URI to be a URI - tried coerce, didn't work
    @key = accesskey
    @http = Net::HTTP.new(@uri.host, @uri.port)
  end

  def close
    if @http and @http.started?
      @http.finish
      @http = nil
    end
  end

  def error(msg, value=nil)
    # Raise exception with supplied message and optional value
    if value
      msg += " (#{value})"
    end
    raise ROSRSSession::Exception.new("ROSRSSession::Exception on #@uri #{msg}")
  end

  # -------
  # Helpers
  # -------

  ##
  # Parse links from headers; returns a hash indexed by link relation
  # Headerlist is a hash indexed by header field name (see HTTP:Response)
  def parse_links(headers)
    links = {}
    link_header = headers["link"] || headers["Link"]
    link_header.split(",").each do |link|
      matches = link.strip.match(/<([^>]*)>\s*;.*rel\s*=\s*"?([^;"]*)"?/)
      links[matches[2]] = URI(matches[1]) if matches
    end
    links
  end

  ##
  # Extract path (incl query) for HTTP request
  # Should accept URI, RDF::URI or string values
  # Must be same host and port as session URI
  # Relative values are based on session URI
  def get_request_path(uripath)
    uripath = URI(uripath.to_s)
    if uripath.scheme && (uripath.scheme != @uri.scheme)
      error("Request URI scheme does not match session: #{uripath}")
    end
    if (uripath.host && uripath.host != @uri.host) ||
       (uripath.port && uripath.port != @uri.port)
      error("Request URI host or port does not match session: #{uripath}")
    end
    requri = URI.join(@uri.to_s, uripath.path).path
    if uripath.query
      requri += "?"+uripath.query
    end
    requri
  end

  def get_request_headers(options = {})
    if options[:headers]
      # Convert symbol keys to strings
      reqheaders = options[:headers].inject({}) do |headers, (header, value)|
        headers[header.to_s] = value
        headers
      end
    else
      reqheaders = {}
    end
    if @key
      reqheaders["authorization"] = "Bearer "+@key
    end
    if options[:ctype]
      reqheaders["content-type"] = options[:ctype]
    end
    if options[:accept]
      reqheaders['accept'] = options[:accept]
    end
    reqheaders
  end

  ##
  # Perform HTTP request
  #
  # method        HTTP method name
  # uripath       is reference or URI of resource (see get_request_path)
  # options:
  # [:body]    body to accompany request
  # [:ctype]   content type of supplied body
  # [:accept]  accept content types for response
  # [:headers] additional headers for request
  # Return [code, reason(text), response headers, response body]
  #
  def do_request(method, uripath, options = {})

    req = nil

    case method
    when 'GET'
      req = Net::HTTP::Get.new(get_request_path(uripath))
    when 'PUT'
      req = Net::HTTP::Put.new(get_request_path(uripath))
    when 'POST'
      req = Net::HTTP::Post.new(get_request_path(uripath))
    when 'DELETE'
      req = Net::HTTP::Delete.new(get_request_path(uripath))
    else
      error("Unrecognized HTTP method #{method}")
    end

    if options[:body]
      req.body = options[:body]
    end

    get_request_headers(options).each { |h,v| req.add_field(h, v) }
    resp = @http.request(req)
    [Integer(resp.code), resp.message, resp, resp.body]
  end

  ##
  # Perform HTTP request, following 302, 303 307 redirects
  # Return [code, reason(text), response headers, final uri, response body]
  def do_request_follow_redirect(method, uripath, options = {})
    code, reason, headers, data = do_request(method, uripath, options)
    if [302,303,307].include?(code)
      uripath = headers["location"]
      code, reason, headers, data = do_request(method, uripath, options)
    end
    if [302,307].include?(code)
      # Allow second temporary redirect
      uripath = headers["location"]
      code, reason, headers, data = do_request(method, uripath, options)
    end
    [code, reason, headers, uripath, data]
  end

  ##
  # Perform HTTP request expecting an RDF/XML response
  # Return [code, reason(text), response headers, manifest graph]
  # Returns the manifest as a graph if the request is successful
  # otherwise returns the raw response data.
  def do_request_rdf(method, uripath, options = {})
    options[:accept] = "application/rdf+xml"
    code, reason, headers, uripath, data = do_request_follow_redirect(method, uripath, options)
    if code >= 200 and code < 300
      if headers["content-type"].downcase == "application/rdf+xml"
        begin
          data = RDFGraph.new(:data => data, :format => :xml)
        rescue Exception => e
          code = 902
          reason = "RDF parse failure (#{e.message})"
        end
      else
        code = 901
        reason = "Non-RDF content-type returned (#{h["content-type"]})"
      end
    end
    [code, reason, headers, uripath, data]
  end

  # ---------------
  # RO manipulation
  # ---------------

  ##
  # Returns [copde, reason, uri, manifest]
  def create_research_object(name, title, creator, date)
    reqheaders   = {
        "slug"    => name
        }
    roinfo = {
        "id"      => name,
        "title"   => title,
        "creator" => creator,
        "date"    => date
        }
    roinfotext = roinfo.to_json
    code, reason, headers, uripath, data = do_request_rdf("POST", "",
        :body       => roinfotext,
        :headers    => reqheaders)
    if code == 201
      [code, reason, headers["location"], data]
    elsif code == 409
      [code, reason, nil, data]
    else
      error("Error creating RO: #{code} #{reason}")
    end
  end

  def delete_research_object(ro_uri)
    #  code, reason = delete_research_object(ro_uri)
    code, reason = do_request("DELETE", ro_uri,
        :accept => "application/rdf+xml")
    if [204, 404].include?(code)
      [code, reason]
    else
      error("Error deleting RO #{ro_uri}: #{code} #{reason}")
    end
  end

  # ---------------------
  # Resource manipulation
  # ---------------------

  ##
  # Aggregate internal resource
  #
  # options:
  # [:body]    body to accompany request
  # [:ctype]   content type of supplied body
  # [:accept]  accept content types for response
  # [:headers] additional headers for request
  #
  # Returns: [code, reason, proxyuri, resource_uri], where code is 200 or 201

  def aggregate_internal_resource(ro_uri, respath=nil, options={})
      # POST (empty) proxy value to RO ...
    reqheaders = options[:headers] || {}
    if respath
      reqheaders['slug'] = respath
    end
    proxydata = %q(
      <rdf:RDF
        xmlns:ore="http://www.openarchives.org/ore/terms/"
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" >
        <ore:Proxy>
        </ore:Proxy>
      </rdf:RDF>
      )
    code, reason, headers = do_request("POST", ro_uri,
      :ctype    => "application/vnd.wf4ever.proxy",
      :headers  => reqheaders,
      :body     => proxydata)
    if code != 201
      error("Error creating aggregation proxy",
            "#{code} #{reason} #{respath}")
    end
    proxyuri = URI(headers["location"])
    links    = parse_links(headers)
    resource_uri = links[RDF::ORE.proxyFor.to_s]
    unless resource_uri
      error("No ore:proxyFor link in create proxy response",
            "Proxy URI #{proxyuri}")
    end
    # PUT resource content to indicated URI
    code, reason = do_request("PUT", resource_uri, options)
    unless [200,201].include?(code)
        error("Error creating aggregated resource content",
              "#{code}, #{reason}, #{respath}")
    end
    [code, reason, proxyuri, resource_uri]
  end

  # -----------------------
  # Resource access
  # -----------------------

  ##
  # Retrieve resource from RO
  #
  # resuriref    is relative reference or URI of resource
  # ro_uri       is URI of RO, used as base for relative reference
  # options:
  # [:accept]    content type
  # [:headers]   additional headers for request
  # Returns:
  # [code, reason, headers, data], where code is 200 or 404
  def get_resource(resuriref, ro_uri=nil, options={})
    if ro_uri
      resuriref = URI.join(ro_uri.to_s, resuriref.to_s)
    end
    code, reason, headers, uri, data = do_request_follow_redirect("GET", resuriref, options)
    unless [200,404].include?(code)
      error("Error retrieving RO resource: #{code}, #{reason}, #{resuriref}")
    end
    [code, reason, headers, uri, data]
  end

  ##
  # Retrieve RDF resource from RO
  #
  # resource_uri    is relative reference or URI of resource
  # ro_uri     is URI of RO, used as base for relative reference
  # options:
  # [:headers]   additional headers for request
  #
  # Returns:
  # [code, reason, headers, uri, data], where code is 200 or 404
  #
  # If code isreturned as 200, data is returned as an RDFGraph value
  def get_resource_rdf(resource_uri, ro_uri=nil, options={})
    if ro_uri
      resource_uri = URI.join(ro_uri.to_s, resource_uri.to_s)
    end
    code, reason, headers, uri, data = do_request_rdf("GET", resource_uri, options)
    unless [200,404].include?(code)
      error("Error retrieving RO resource: #{code}, #{reason}, #{resource_uri}")
    end
    [code, reason, headers, uri, data]
  end

  ##
  # Retrieve an RO manifest
  #
  # Returns [manifesturi, manifest]
  def get_manifest(ro_uri)
    code, reason, headers, uri, data = do_request_rdf("GET", ro_uri)
    if code != 200
      error("Error retrieving RO manifest: #{code} #{reason}")
    end
    [uri, data]
  end

  # -----------------------
  # Annotation manipulation
  # -----------------------

  ##
  # Create an annotation body from a supplied annnotation graph.
  #
  # Returns: [code, reason, body_uri]
  def create_annotation_body(ro_uri, annotation_graph)
    code, reason, bodyproxyuri, body_uri = aggregate_internal_resource(ro_uri, nil,
      :ctype => "application/rdf+xml",
      :body  => annotation_graph.serialize(format=:xml))
    if code != 201
      error("Error creating annotation body resource",
            "#{code}, #{reason}, #{ro_uri}")
    end
    [code, reason, body_uri]
  end

  ##
  # Create entity body for annotation stub
  def create_annotation_stub_rdf(ro_uri, resource_uri, body_uri)
    v = { :xmlbase => ro_uri.to_s,
          :resource_uri  => resource_uri.to_s,
          :body_uri => body_uri.to_s
        }
    annotation_stub = %Q(<?xml version="1.0" encoding="UTF-8"?>
        <rdf:RDF
          xmlns:ro="http://purl.org/wf4ever/ro#"
          xmlns:ao="http://purl.org/ao/"
          xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
          xml:base="#{v[:xmlbase]}"
        >
          <ro:AggregatedAnnotation>
            <ao:annotatesResource rdf:resource="#{v[:resource_uri]}" />
            <ao:body rdf:resource="#{v[:body_uri]}" />
          </ro:AggregatedAnnotation>
        </rdf:RDF>
        )
    annotation_stub
  end

  ##
  # Create an annotation stub for supplied resource using indicated body
  #
  # Returns: [code, reason, stuburi]
  def create_annotation_stub(ro_uri, resource_uri, body_uri)
    annotation = create_annotation_stub_rdf(ro_uri, resource_uri, body_uri)
    code, reason, headers, data = do_request("POST", ro_uri,
        :ctype => "application/vnd.wf4ever.annotation",
        :body  => annotation)
    if code != 201
        error("Error creating annotation #{code}, #{reason}, #{resource_uri}")
    end
    [code, reason, URI(headers["location"])]
  end

  ##
  # Create internal annotation
  #
  # Returns: [code, reason, annotation_uri, body_uri]
  def create_internal_annotation(ro_uri, resource_uri, annotation_graph)
    code, reason, body_uri = create_annotation_body(ro_uri, annotation_graph)
    if code == 201
      code, reason, annotation_uri = create_annotation_stub(ro_uri, resource_uri, body_uri)
    end
    [code, reason, annotation_uri, body_uri]
  end

  ##
  # UNIMPLEMENTED
  # Create a resource annotation using an existing (possibly external) annotation body
  #
  # Returns: (code, reason, annotation_uri)
  def create_external_annotation(ro_uri, resource_uri, body_uri)
    error("Unimplemented")
  end

  ##
  # Update an indicated annotation for supplied resource using indicated body
  #
  # Returns: [code, reason]
  def update_annotation_stub(ro_uri, stuburi, resource_uri, body_uri)
    annotation = create_annotation_stub_rdf(ro_uri, resource_uri, body_uri)
    code, reason, headers, data = do_request("PUT", stuburi,
        :ctype => "application/vnd.wf4ever.annotation",
        :body  => annotation)
    if code != 200
        error("Error updating annotation #{code}, #{reason}, #{resource_uri}")
    end
    [code, reason]
  end

  ##
  # Update an annotation with a new internal annotation body
  #
  # returns: [code, reason, body_uri]
  def update_internal_annotation(ro_uri, stuburi, resource_uri, annotation_graph)
    code, reason, body_uri = create_annotation_body(ro_uri, annotation_graph)
    if code != 201
        error("Error creating annotation #{code}, #{reason}, #{resource_uri}")
    end
    code, reason = update_annotation_stub(ro_uri, stuburi, resource_uri, body_uri)
    [code, reason, body_uri]
  end

  ##
  # Update an annotation with an existing (possibly external) annotation body
  #
  # returns: (code, reason)
  def update_external_annotation(ro_uri, annotation_uri, body_uri)
    error("Unimplemented")
  end

  ##
  # Enumerate annnotation URIs associated with a resource
  # (or all annotations for an RO)
  #
  # Returns an array of annotation URIs
  def get_annotation_stub_uris(ro_uri, resource_uri=nil)
    manifesturi, manifest = get_manifest(ro_uri)
    stuburis = []
    manifest.query(:object => RDF::URI(resource_uri)) do |stmt|
      if [RDF::AO.annotatesResource,RDF::RO.annotatesAggregatedResource].include?(stmt.predicate)
        stuburis << stmt.subject
      end
    end
    stuburis
  end

  ##
  # Enumerate annnotation body URIs associated with a resource
  # (or all annotations for an RO)
  #
  # Returns an array of annotation body URIs
  def get_annotation_body_uris(ro_uri, resource_uri=nil)
    body_uris = []
    get_annotation_stub_uris(ro_uri, resource_uri).each do |stuburi|
      body_uris << get_annotation_body_uri(stuburi)
    end
    body_uris
  end

  ##
  # Retrieve annotation body URI for given annotation stub URI
  def get_annotation_body_uri(stuburi)
    code, reason, headers  = do_request("GET", stuburi, {})
    if code != 303
      error("No redirect from annnotation stub URI: #{code} #{reason}, #{stuburi}")
    end
    if [nil,""].include?(headers['location'])
      error("No location for redirect from annnotation stub URI: #{code} #{reason}, #{stuburi}")
    end
    RDF::URI(headers['location'])
  end

  ##
  # Build RDF graph of all annnotations associated with a resource
  # (or all annotations for an RO)
  #
  # Returns graph of merged annotations
  def get_annotation_graph(ro_uri, resource_uri=nil)
    annotation_graph = RDFGraph.new
    get_annotation_stub_uris(ro_uri, resource_uri).each do |auri|
      code, reason, headers, buri, bodytext = do_request_follow_redirect("GET", auri, {})
      if code == 200
        content_type = headers['content-type'].split(';', 2)[0].strip.downcase
        if ANNOTATION_CONTENT_TYPES.include?(content_type)
          bodyformat = ANNOTATION_CONTENT_TYPES[content_type]
          annotation_graph.load_data(bodytext, bodyformat)
        else
          warn("Warning: #{buri} has unrecognized content-type: #{content_type}")
        end
      else
        error("Failed to GET #{buri}: #{code} #{reason}")
      end
    end
    annotation_graph
  end

  ##
  # Retrieve annotation for given annotation URI
  #
  # Returns: [code, reason, body_uri, annotation_graph]
  def get_annotation_body(annotation_uri)
    code, reason, headers, uri, annotation_graph = get_resource_rdf(annotation_uri)
    [code, reason, uri, annotation_graph]
  end

  ##
  # Remove annotation at given annotation URI
  # UNIMPLEMENTED
  #
  # Returns: (code, reason)
  def remove_annotation(ro_uri, annotation_uri)

    error("Unimplemented")
  end

  # -----------------------
  # Folder manipulation
  # -----------------------

  ##
  # Returns an array of the given research object's root folders, as Folder objects.
  def get_root_folders(ro_uri, options = {})
    uri, data = get_manifest(ro_uri)
    query = RDF::Query.new do
      pattern [:folder, RDF.type,  RDF::RO.RootFolder]
      pattern [:folder, RDF::ORE.isDescribedBy, :folder_resource_map]
    end

    data.query(query).collect do |result|
      get_folder(result.folder_resource_map.to_s, options.merge({:name => result.folder.to_s}))
    end
  end

  ##
  # Returns a Folder object from the given resource map URI.
  def get_folder(folder_resource_map_uri, options = {})
    folder_name = options[:name] || URI(folder_resource_map_uri).path[1..-1].split('.',2)[0]
    Folder.new(folder_name, options[:path], folder_resource_map_uri, options[:parent], options[:eager_load])
  end

  ##
  # Returns an array of the given research object's root folders, as Folder objects.
  # These folders have their contents pre-loaded,
  # and the full hierarchy can be traversed without making further requests
  def get_folder_hierarchy(ro_uri, options = {})
    options[:eager_load] = true
    get_root_folders(ro_uri, options)
  end

  ##
  # +contents+ is an Array containing Hash elements, which must consist of a :uri and an optional :name.
  # Example:
  #   folder_contents = [{:name => 'test_data.txt', :uri => 'http://www.example.com/ro/file1.txt'},
  #                      {:uri => 'http://www.myexperiment.org/workflows/7'}]
  #   create_folder('ros/new_ro/', 'example_data', folder_contents)
  #
  # Returns [uri, folder_contents, folder_description_location]
  #
  # +uri+:: The URI of the created folder
  # +folder_contents+:: A list of the folder's contents. In the same form as +contents+.
  # +folder_description_location+:: The URI of the document which describes the created folder.
  def create_folder(ro_uri, name, contents)
    code, reason, headers, uripath, graph = do_request_rdf("POST", ro_uri,
        :body       => create_folder_description(contents),
        :headers    => {"Slug" => name, "Content-Type" => 'application/vnd.wf4ever.folder'})

    if code == 201
      folder_contents = parse_folder_description(graph)
      folder_description_location = parse_links(headers)[RDF::ORE.isDescribedBy.to_s]
      [headers["location"], folder_contents, folder_description_location]
    else
      error("Error creating folder: #{code} #{reason}")
    end
  end

  private

  ##
  # Takes +contents+ ,an Array containing Hash elements, which must consist of a :uri and an optional :name,
  # and returns an RDF description of the folder contents.
  def create_folder_description(contents)
    body = %(
      <rdf:RDF
        xmlns:ore="#{RDF::ORE.to_uri.to_s}"
        xmlns:rdf="#{RDF.to_uri.to_s}"
        xmlns:ro="#{RDF::RO.to_uri.to_s}" >
        <ro:Folder>
          #{contents.collect {|r| "<ore:aggregates rdf:resource=\"#{r[:uri]}\" />" }.join("\n")}
        </ro:Folder>
    )
    contents.each do |r|
      if r[:name]
        body << %(
          <ro:FolderEntry>
            <ro:entryName>#{r[:name]}</ro:entryName>
            <ore:proxyFor rdf:resource="#{r[:uri]}" />
          </ro:FolderEntry>
        )
      end
    end
    body << %(
      </rdf:RDF>
    )

    body
  end

  ##
  # Takes an ro:Folder RDF description and returns an Array of Hashes, containing the :name and :uri for
  # each FolderEntry.
  def parse_folder_description(folder_description)
    query = RDF::Query.new do
      pattern [:folder_entry, RDF.type, RDF.Description]
      pattern [:folder_entry, RDF::RO.entryName, :name]
      pattern [:folder_entry, RDF::ORE.proxyFor, :target]
    end

    folder_description.query(query).collect {|e| {:name => e.name.to_s, :uri => e.target.to_s}}
  end

  public



end
