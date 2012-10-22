# ROSRS session class

class ROSRSSession
  # Exception class used to signal HTTP Session errors
  class ROSRSSession::Exception < Exception; end

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
    # Force string or URI to be a URI - tried coerce, didn't work
    @uri = URI(uri.to_s)
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

  def split_values(txt, sep=",", lq=%q('"<), rq=%q('">))
    # Helper function returns list of delimited values in a string,
    # where delimiters in quotes are protected.
    #
    # sep is string of separator
    # lq is string of opening quotes for strings within which separators are not recognized
    # rq is string of corresponding closing quotes
    result = []
    cursor = 0
    begseg = cursor
    while cursor < txt.length do
      if lq.include?(txt[cursor])
        # Skip quoted or bracketed string
        eq = rq[lq.index(txt[cursor])]  # End quote/bracket character
        cursor += 1
        while cursor < txt.length and txt[cursor] != eq do
          if txt[cursor].chr == '\\'
            cursor += 1 # skip '\' quoted-pair
          end
          cursor += 1
        end
        if cursor < txt.length
          cursor += 1 # Skip closing quote/bracket
        end
      elsif sep.include?(txt[cursor])
        result << txt.slice(begseg...cursor)
        cursor += 1
        begseg = cursor
      else
        cursor += 1
      end
    end
    # append final segment
    result << txt.slice(begseg...cursor)
    result
  end

  def parse_links(headerlist)
    # Parse links from headers; returns a hash indexed by link relation
    # Headerlist is a hash indexed by header field name (see HTTP:Response)
    links = {}
    headerlist.each do |h,v|
      #puts "h #{h} = #{v}"
      if h.downcase == "link"
        #puts "v #{v}"
        split_values(v, ",").each do |linkval|
          #puts "linkval #{linkval}"
          linkparts = split_values(linkval, ";")
          linkmatch = /\s*<([^>]*)>\s*/.match(linkparts[0])
          if linkmatch
            linkuri = linkmatch[1]
            #puts "linkuri #{linkuri}"
            linkparts.slice(1..-1).each do |linkparam|
              #puts "linkparam #{linkparam}"
              parammatch = /\s*rel\s*=\s*"?(.*?)"?\s*$/.match(linkparam)
              if parammatch
                linkrel = parammatch[1]
                #puts "linkrel #{linkrel}"
                links[linkrel] = URI(linkuri)
              end
            end
          end
        end
      end
    end
    links
  end

  def get_request_path(uripath)
    # Extract path (incl query) for HTTP request
    # Should accept URI, RDF::URI or string values
    # Must be same host and port as session URI
    # Relative values are based on session URI
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

  def do_request(method, uripath, options = {})
    # Perform HTTP request
    #
    # method        HTTP method name
    # uripath       is reference or URI of resource (see get_request_path)
    # options: {
    #   body    => body to accompany request
    #   ctype   => content type of supplied body
    #   accept  => accept co ntent types for response
    #   headers => additional headers for request
    #   }
    # Return [code, reason(text), response headers, response body]
    #
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

  def do_request_follow_redirect(method, uripath, options = {})
    # Perform HTTP request, following 302, 303 307 redirects
    # Return [code, reason(text), response headers, final uri, response body]
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

  def do_request_rdf(method, uripath, options = {})
    # Perform HTTP request expecting an RDF/XML response
    # Return [code, reason(text), response headers, manifest graph]
    # Returns the manifest as a graph if the request is successful
    # otherwise returns the raw response data.
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

  def create_research_object(name, title, creator, date)
    # Returns [copde, reason, uri, manifest]
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
      error("Error creating RO: : #{code} #{reason}")
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

  def aggregate_internal_resource(ro_uri, respath=nil, options={})
    # Aggregate internal resource
    #
    # options: {
    #   body    => body to accompany request
    #   ctype   => content type of supplied body
    #   accept  => accept content types for response
    #   headers => additional headers for request
    #   }
    # Returns: [code, reason, proxyuri, resource_uri], where code is 200 or 201
    #
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
    resource_uri = links[ORE[:proxyFor].to_s]
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

  def get_resource(resuriref, ro_uri=nil, options={})
    # Retrieve resource from RO
    #
    # resuriref     is relative reference or URI of resource
    # ro_uri         is URI of RO, used as base for relative reference
    # options:
    #   accept  => (content type)
    #   headers => (request headers)
    #
    # Returns:
    #   [code, reason, headers, data], where code is 200 or 404
    if ro_uri
      resuriref = URI.join(ro_uri.to_s, resuriref.to_s)
    end
    code, reason, headers, uri, data = do_request_follow_redirect("GET", resuriref, options)
    unless [200,404].include?(code)
      error("Error retrieving RO resource: #{code}, #{reason}, #{resuriref}")
    end
    [code, reason, headers, uri, data]
  end

  def get_resource_rdf(resource_uri, ro_uri=nil, options={})
    # Retrieve RDF resource from RO
    #
    # resource_uri    is relative reference or URI of resource
    # ro_uri     is URI of RO, used as base for relative reference
    # options:
    #   headers => (request headers)
    #
    # Returns:
    #   [code, reason, headers, uri, data], where code is 200 or 404
    #
    # If code isreturned as 200, data is returned as an RDFGraph value
    #
    if ro_uri
      resource_uri = URI.join(ro_uri.to_s, resource_uri.to_s)
    end
    code, reason, headers, uri, data = do_request_rdf("GET", resource_uri, options)
    unless [200,404].include?(code)
      error("Error retrieving RO resource: #{code}, #{reason}, #{resource_uri}")
    end
    [code, reason, headers, uri, data]
  end

  #~ def getROResourceProxy(self, resuriref, ro_uri):
      #~ """
      #~ Retrieve proxy description for resource.
      #~ Return (proxyuri, manifest)
      #~ """
      #~ (code, reason, headers, manifesturi, manifest) = get_ro_manifest(ro_uri)
      #~ if code not in [200,404]:
          #~ raise self.error("Error retrieving RO manifest", "%03d %s"%
                           #~ (code, reason))
      #~ proxyuri = None
      #~ if code == 200:
          #~ resource_uri = rdflib.URIRef(urlparse.urljoin(str(ro_uri), str(resuriref)))
          #~ proxyterms = list(manifest.subjects(predicate=ORE.proxyFor, object=resource_uri))
          #~ log.debug("getROResourceProxy proxyterms: %s"%(repr(proxyterms)))
          #~ if len(proxyterms) == 1:
              #~ proxyuri = proxyterms[0]
      #~ return (proxyuri, manifest)

  def get_manifest(ro_uri)
    # Retrieve an RO manifest
    # Returns [manifesturi, manifest]
    code, reason, headers, uri, data = do_request_rdf("GET", ro_uri)
    if code != 200
      error("Error retrieving RO manifest: #{code} #{reason}")
    end
    [uri, data]
  end

  #~ def getROLandingPage(self, ro_uri):
      #~ """
      #~ Retrieve an RO landing page
      #~ Return (code, reason, headers, uri, data), where code is 200 or 404
      #~ """
      #~ (code, reason, headers, uri, data) = self.do_request_follow_redirect(ro_uri,
          #~ method="GET", accept="text/html")
      #~ if code in [200, 404]:
          #~ return (code, reason, headers, uri, data)
      #~ raise self.error("Error retrieving RO landing page",
          #~ "%03d %s"%(code, reason))

  #~ def getROZip(self, ro_uri):
      #~ """
      #~ Retrieve an RO as ZIP file
      #~ Return (code, reason, headers, data), where code is 200 or 404
      #~ """
      #~ (code, reason, headers, uri, data) = self.do_request_follow_redirect(ro_uri,
          #~ method="GET", accept="application/zip")
      #~ if code in [200, 404]:
          #~ return (code, reason, headers, uri, data)
      #~ raise self.error("Error retrieving RO as ZIP file",
          #~ "%03d %s"%(code, reason))

  # -----------------------
  # Annotation manipulation
  # -----------------------

  def create_annotation_body(ro_uri, annotation_graph)
    # Create an annotation body from a supplied annnotation graph.
    #
    # Returns: [code, reason, body_uri]
    code, reason, bodyproxyuri, body_uri = aggregate_internal_resource(ro_uri, nil,
      :ctype => "application/rdf+xml",
      :body  => annotation_graph.serialize(format=:xml))
    if code != 201
      error("Error creating annotation body resource",
            "#{code}, #{reason}, #{ro_uri}")
    end
    [code, reason, body_uri]
  end

  def create_annotation_stub_rdf(ro_uri, resource_uri, body_uri)
    # Create entity body for annotation stub
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

  def create_annotation_stub(ro_uri, resource_uri, body_uri)
    # Create an annotation stub for supplied resource using indicated body
    #
    # Returns: [code, reason, stuburi]
    annotation = create_annotation_stub_rdf(ro_uri, resource_uri, body_uri)
    code, reason, headers, data = do_request("POST", ro_uri,
        :ctype => "application/vnd.wf4ever.annotation",
        :body  => annotation)
    if code != 201
        error("Error creating annotation #{code}, #{reason}, #{resource_uri}")
    end
    [code, reason, URI(headers["location"])]
  end

  def create_internal_annotation(ro_uri, resource_uri, annotation_graph)
    # Create internal annotation
    #
    # Returns: [code, reason, annotation_uri, body_uri]
    code, reason, body_uri = create_annotation_body(ro_uri, annotation_graph)
    if code == 201
      code, reason, annotation_uri = create_annotation_stub(ro_uri, resource_uri, body_uri)
    end
    [code, reason, annotation_uri, body_uri]
  end

  def create_external_annotation(ro_uri, resource_uri, body_uri)
    # Create a resource annotation using an existing (possibly external) annotation body
    #
    # Returns: (code, reason, annotation_uri)
    error("Unimplemented")
  end

  def update_annotation_stub(ro_uri, stuburi, resource_uri, body_uri)
    # Update an indicated annotation for supplied resource using indicated body
    #
    # Returns: [code, reason]
    annotation = create_annotation_stub_rdf(ro_uri, resource_uri, body_uri)
    code, reason, headers, data = do_request("PUT", stuburi,
        :ctype => "application/vnd.wf4ever.annotation",
        :body  => annotation)
    if code != 200
        error("Error updating annotation #{code}, #{reason}, #{resource_uri}")
    end
    [code, reason]
  end

  def update_internal_annotation(ro_uri, stuburi, resource_uri, annotation_graph)
    # Update an annotation with a new internal annotation body
    #
    # returns: [code, reason, body_uri]
    code, reason, body_uri = create_annotation_body(ro_uri, annotation_graph)
    if code != 201
        error("Error creating annotation #{code}, #{reason}, #{resource_uri}")
    end
    code, reason = update_annotation_stub(ro_uri, stuburi, resource_uri, body_uri)
    [code, reason, body_uri]
  end

  def update_external_annotation(ro_uri, annotation_uri, body_uri)
    # Update an annotation with an existing (possibly external) annotation body
    #
    # returns: (code, reason)
    error("Unimplemented")
  end

  def get_annotation_stub_uris(ro_uri, resource_uri=nil)
    # Enumerate annnotation URIs associated with a resource
    # (or all annotations for an RO)
    #
    # Returns an array of annotation URIs
    manifesturi, manifest = get_manifest(ro_uri)
    stuburis = []
    manifest.query(:object => RDF::URI(resource_uri)) do |stmt|
      if [AO.annotatesResource,RO.annotatesAggregatedResource].include?(stmt.predicate)
        stuburis << stmt.subject
      end
    end
    stuburis
  end

  def get_annotation_body_uris(ro_uri, resource_uri=nil)
    # Enumerate annnotation body URIs associated with a resource
    # (or all annotations for an RO)
    #
    # Returns an array of annotation body URIs
    body_uris = []
    get_annotation_stub_uris(ro_uri, resource_uri).each do |stuburi|
      body_uris << get_annotation_body_uri(stuburi)
    end
    body_uris
  end

  def get_annotation_body_uri(stuburi)
    # Retrieve annotation body URI for given annotation stub URI
    code, reason, headers  = do_request("GET", stuburi, {})
    if code != 303
      error("No redirect from annnotation stub URI: #{code} #{reason}, #{stuburi}")
    end
    if [nil,""].include?(headers['location'])
      error("No location for redirect from annnotation stub URI: #{code} #{reason}, #{stuburi}")
    end
    RDF::URI(headers['location'])
  end

  def get_annotation_graph(ro_uri, resource_uri=nil)
    # Build RDF graph of all annnotations associated with a resource
    # (or all annotations for an RO)
    #
    # Returns graph of merged annotations
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

  def get_annotation_body(annotation_uri)
    # Retrieve annotation for given annotation URI
    #
    # Returns: [code, reason, body_uri, annotation_graph]
    code, reason, headers, uri, annotation_graph = get_resource_rdf(annotation_uri)
    [code, reason, uri, annotation_graph]
  end

  def remove_annotation(ro_uri, annotation_uri)
    # Remove annotation at given annotation URI
    #
    # Returns: (code, reason)
    #~ (status, reason, headers, data) = self.do_request(annotation_uri,
        #~ method="DELETE")
    #~ return (status, reason)
    error("Unimplemented")
  end

  def get_root_folder(ro_uri)
    Folder.new
  end

  def get_folder(folder_description_uri)




    Folder.new
  end

  def get_folder_hierarchy(ro_uri)

  end


end
