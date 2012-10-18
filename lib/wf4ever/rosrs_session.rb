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

  def splitValues(txt, sep=",", lq=%q('"<), rq=%q('">))
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

  def parseLinks(headerlist)
    # Parse links from headers; returns a hash indexed by link relation
    # Headerlist is a hash indexed by header field name (see HTTP:Response)
    links = {}
    headerlist.each do |h,v|
      #puts "h #{h} = #{v}"
      if h.downcase == "link"
        #puts "v #{v}"
        splitValues(v, ",").each do |linkval|
          #puts "linkval #{linkval}"
          linkparts = splitValues(linkval, ";")
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

  def getRequestPath(uripath)
    # Extract path (incl query) for HTTP request
    # Should accept URI, RDF::URI or string values
    # Must be same host and port as session URI
    # Relative values are based on session URI
    uripath = URI(uripath.to_s)
    if uripath.scheme and (uripath.scheme != @uri.scheme)
      error("Request URI scheme does not match session: #{uripath}")
    end
    if (uripath.host and uripath.host != @uri.host) or
       (uripath.port and uripath.port != @uri.port)
      error("Request URI host or port does not match session: #{uripath}")
    end
    requri = URI.join(@uri.to_s, uripath.path).path
    if uripath.query
      requri += "?"+uripath.query
    end
    requri
  end

  def getRequestHeaders(options = {})
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

  def doRequest(method, uripath, options = {})
    # Perform HTTP request
    #
    # method        HTTP method name
    # uripath       is reference or URI of resource (see getRequestPath)
    # options: {
    #   body    => body to accompany request
    #   ctype   => content type of supplied body
    #   accept  => accept co ntent types for response
    #   headers => additional headers for request
    #   }
    # Return [code, reason(text), response headers, response body]
    #
    if method == 'GET'
      req = Net::HTTP::Get.new(getRequestPath(uripath))
    elsif method == 'PUT'
      req = Net::HTTP::Put.new(getRequestPath(uripath))
    elsif method == 'POST'
      req = Net::HTTP::Post.new(getRequestPath(uripath))
    elsif method == 'DELETE'
      req = Net::HTTP::Delete.new(getRequestPath(uripath))
    else
      error("Unrecognized HTTP method #{method}")
    end
    if options[:body]
      req.body = options[:body]
    end
    getRequestHeaders(options).each { |h,v| req.add_field(h, v) }
    resp = @http.request(req)
    [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestFollowRedirect(method, uripath, options = {})
    # Perform HTTP request, following 302, 303 307 redirects
    # Return [code, reason(text), response headers, final uri, response body]
    code, reason, headers, data = doRequest(method, uripath, options)
    if [302,303,307].include?(code)
      uripath = headers["location"]
      code, reason, headers, data = doRequest(method, uripath, options)
    end
    if [302,307].include?(code)
      # Allow second temporary redirect
      uripath = headers["location"]
      code, reason, headers, data = doRequest(method, uripath, options)
    end
    [code, reason, headers, uripath, data]
  end

  def doRequestRDF(method, uripath, options = {})
    # Perform HTTP request expecting an RDF/XML response
    # Return [code, reason(text), response headers, manifest graph]
    # Returns the manifest as a graph if the request is successful
    # otherwise returns the raw response data.
    options[:accept] = "application/rdf+xml"
    code, reason, headers, uripath, data = doRequestFollowRedirect(method, uripath, options)
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

  def createRO(name, title, creator, date)
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
    code, reason, headers, uripath, data = doRequestRDF("POST", "",
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

  def deleteRO(rouri)
    #  code, reason = deleteRO(rouri)
    code, reason = doRequest("DELETE", rouri,
        :accept => "application/rdf+xml")
    if [204, 404].include?(code)
      [code, reason]
    else
      error("Error deleting RO #{rouri}: #{code} #{reason}")
    end
  end

  # ---------------------
  # Resource manipulation
  # ---------------------

  def aggregateResourceInt(rouri, respath=nil, options={})
    # Aggegate internal resource
    #
    # options: {
    #   body    => body to accompany request
    #   ctype   => content type of supplied body
    #   accept  => accept co ntent types for response
    #   headers => additional headers for request
    #   }
    # Returns: [code, reason, proxyuri, resuri], where code is 200 or 201
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
    code, reason, headers = doRequest("POST", rouri,
      :ctype    => "application/vnd.wf4ever.proxy",
      :headers  => reqheaders,
      :body     => proxydata)
    if code != 201
      error("Error creating aggregation proxy",
            "#{code} #{reason} #{respath}")
    end
    proxyuri = URI(headers["location"])
    links    = parseLinks(headers)
    resuri = links[ORE[:proxyFor].to_s]
    unless resuri
      error("No ore:proxyFor link in create proxy response",
            "Proxy URI #{proxyuri}")
    end
    # PUT resource content to indicated URI
    code, reason, headers, data = doRequest("PUT", resuri, options)
    unless [200,201].include?(code)
        error("Error creating aggregated resource content",
              "#{code}, #{reason}, #{respath}")
    end
    [code, reason, proxyuri, resuri]
  end

  # -----------------------
  # Resource access
  # -----------------------

  def getROResource(resuriref, rouri=nil, options={})
    # Retrieve resource from RO
    #
    # resuriref     is relative reference or URI of resource
    # rouri         is URI of RO, used as base for relative reference
    # options:
    #   accept  => (content type)
    #   headers => (request headers)
    #
    # Returns:
    #   [code, reason, headers, data], where code is 200 or 404
    if rouri
      resuriref = URI.join(rouri.to_s, resuriref.to_s)
    end
    code, reason, headers, uri, data = doRequestFollowRedirect("GET", resuriref, options)
    unless [200,404].include?(code)
      error("Error retrieving RO resource: #{code}, #{reason}, #{resuriref}")
    end
    [code, reason, headers, uri, data]
  end

  def getROResourceRDF(resuri, rouri=nil, options={})
    # Retrieve RDF resource from RO
    #
    # resuri    is relative reference or URI of resource
    # rouri     is URI of RO, used as base for relative reference
    # options:
    #   headers => (request headers)
    #
    # Returns:
    #   [code, reason, headers, uri, data], where code is 200 or 404
    #
    # If code isreturned as 200, data is returned as an RDFGraph value
    #
    if rouri
      resuri = URI.join(rouri.to_s, resuri.to_s)
    end
    code, reason, headers, uri, data = doRequestRDF("GET", resuri, options)
    unless [200,404].include?(code)
      error("Error retrieving RO resource: #{code}, #{reason}, #{resuri}")
    end
    return [code, reason, headers, uri, data]
  end

  #~ def getROResourceProxy(self, resuriref, rouri):
      #~ """
      #~ Retrieve proxy description for resource.
      #~ Return (proxyuri, manifest)
      #~ """
      #~ (code, reason, headers, manifesturi, manifest) = getROManifest(rouri)
      #~ if code not in [200,404]:
          #~ raise self.error("Error retrieving RO manifest", "%03d %s"%
                           #~ (code, reason))
      #~ proxyuri = None
      #~ if code == 200:
          #~ resuri = rdflib.URIRef(urlparse.urljoin(str(rouri), str(resuriref)))
          #~ proxyterms = list(manifest.subjects(predicate=ORE.proxyFor, object=resuri))
          #~ log.debug("getROResourceProxy proxyterms: %s"%(repr(proxyterms)))
          #~ if len(proxyterms) == 1:
              #~ proxyuri = proxyterms[0]
      #~ return (proxyuri, manifest)

  def getROManifest(rouri)
    # Retrieve an RO manifest
    # Returns [manifesturi, manifest]
    code, reason, headers, uri, data = doRequestRDF("GET", rouri)
    if code != 200
      error("Error retrieving RO manifest: #{code} #{reason}")
    end
    [uri, data]
  end

  #~ def getROLandingPage(self, rouri):
      #~ """
      #~ Retrieve an RO landing page
      #~ Return (code, reason, headers, uri, data), where code is 200 or 404
      #~ """
      #~ (code, reason, headers, uri, data) = self.doRequestFollowRedirect(rouri,
          #~ method="GET", accept="text/html")
      #~ if code in [200, 404]:
          #~ return (code, reason, headers, uri, data)
      #~ raise self.error("Error retrieving RO landing page",
          #~ "%03d %s"%(code, reason))

  #~ def getROZip(self, rouri):
      #~ """
      #~ Retrieve an RO as ZIP file
      #~ Return (code, reason, headers, data), where code is 200 or 404
      #~ """
      #~ (code, reason, headers, uri, data) = self.doRequestFollowRedirect(rouri,
          #~ method="GET", accept="application/zip")
      #~ if code in [200, 404]:
          #~ return (code, reason, headers, uri, data)
      #~ raise self.error("Error retrieving RO as ZIP file",
          #~ "%03d %s"%(code, reason))

  # -----------------------
  # Annotation manipulation
  # -----------------------

  def createROAnnotationBody(rouri, anngr)
    # Create an annotation body from a supplied annnotation graph.
    #
    # Returns: [code, reason, bodyuri]
    code, reason, bodyproxyuri, bodyuri = aggregateResourceInt(rouri, nil,
      :ctype => "application/rdf+xml",
      :body  => anngr.serialize(format=:xml))
    if code != 201
      error("Error creating annotation body resource",
            "#{code}, #{reason}, #{str(resuri)}")
    end
    [code, reason, bodyuri]
  end

  def createAnnotationStubRDF(rouri, resuri, bodyuri)
    # Create entity body for annotation stub
    v = { :xmlbase => rouri.to_s,
          :resuri  => resuri.to_s,
          :bodyuri => bodyuri.to_s
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
            <ao:annotatesResource rdf:resource="#{v[:resuri]}" />
            <ao:body rdf:resource="#{v[:bodyuri]}" />
          </ro:AggregatedAnnotation>
        </rdf:RDF>
        )
    annotation_stub
  end

  def createROAnnotationStub(rouri, resuri, bodyuri)
    # Create an annotation stub for supplied resource using indicated body
    #
    # Returns: [code, reason, stuburi]
    annotation = createAnnotationStubRDF(rouri, resuri, bodyuri)
    code, reason, headers, data = doRequest("POST", rouri,
        :ctype => "application/vnd.wf4ever.annotation",
        :body  => annotation)
    if code != 201
        error("Error creating annotation #{code}, #{reason}, #{resuri}")
    end
    return [code, reason, URI(headers["location"])]
  end

  def createROAnnotationInt(rouri, resuri, anngr)
    # Create internal annotation
    #
    # Returns: [code, reason, annuri, bodyuri]
    code, reason, bodyuri = createROAnnotationBody(rouri, anngr)
    if code == 201
      code, reason, annuri = createROAnnotationStub(rouri, resuri, bodyuri)
    end
    [code, reason, annuri, bodyuri]
  end

  def createROAnnotationExt(rouri, resuri, bodyuri)
    # Create a resource annotation using an existing (possibly external) annotation body
    #
    # Returns: (code, reason, annuri)
    error("Unimplemented")
  end

  def updateROAnnotationStub(rouri, stuburi, resuri, bodyuri)
    # Update an indicated annotation for supplied resource using indicated body
    #
    # Returns: [code, reason]
    annotation = createAnnotationStubRDF(rouri, resuri, bodyuri)
    code, reason, headers, data = doRequest("PUT", stuburi,
        :ctype => "application/vnd.wf4ever.annotation",
        :body  => annotation)
    if code != 200
        error("Error updating annotation #{code}, #{reason}, #{resuri}")
    end
    [code, reason]
  end

  def updateROAnnotationInt(rouri, stuburi, resuri, anngr)
    # Update an annotation with a new internal annotation body
    #
    # returns: [code, reason, bodyuri]
    code, reason, bodyuri = createROAnnotationBody(rouri, anngr)
    if code != 201
        error("Error creating annotation #{code}, #{reason}, #{resuri}")
    end
    code, reason = updateROAnnotationStub(rouri, stuburi, resuri, bodyuri)
    [code, reason, bodyuri]
  end

  def updateROAnnotationExt(rouri, annuri, bodyuri)
    # Update an annotation with an existing (possibly external) annotation body
    #
    # returns: (code, reason)
    error("Unimplemented")
  end

  def getROAnnotationStubUris(rouri, resuri=nil)
    # Enumerate annnotation URIs associated with a resource
    # (or all annotations for an RO)
    #
    # Returns an array of annotation URIs
    manifesturi, manifest = getROManifest(rouri)
    stuburis = []
    manifest.query(:object => RDF::URI(resuri)) do |stmt|
      if [AO.annotatesResource,RO.annotatesAggregatedResource].include?(stmt.predicate)
        stuburis << stmt.subject
      end
    end
    stuburis
  end

  def getROAnnotationBodyUris(rouri, resuri=nil)
    # Enumerate annnotation body URIs associated with a resource
    # (or all annotations for an RO)
    #
    # Returns an array of annotation body URIs
    bodyuris = []
    getROAnnotationStubUris(rouri, resuri).each do |stuburi|
      bodyuris << getROAnnotationBodyUri(stuburi)
    end
    bodyuris
  end

  def getROAnnotationBodyUri(stuburi)
    # Retrieve annotation body URI for given annotation stub URI
    code, reason, headers  = doRequest("GET", stuburi, {})
    if code != 303
      error("No redirect from annnotation stub URI: #{code} #{reason}, #{stuburi}")
    end
    if [nil,""].include?(headers['location'])
      error("No location for redirect from annnotation stub URI: #{code} #{reason}, #{stuburi}")
    end
    RDF::URI(headers['location'])
  end

  def getROAnnotationGraph(rouri, resuri=nil)
    # Build RDF graph of all annnotations associated with a resource
    # (or all annotations for an RO)
    #
    # Returns graph of merged annotations
    agraph = RDFGraph.new
    getROAnnotationStubUris(rouri, resuri).each do |auri|
      code, reason, headers, buri, bodytext = doRequestFollowRedirect("GET", auri, {})
      if code == 200
        content_type = headers['content-type'].split(';', 2)[0].strip.downcase
        if ANNOTATION_CONTENT_TYPES.include?(content_type)
          bodyformat = ANNOTATION_CONTENT_TYPES[content_type]
          agraph.load_data(bodytext, bodyformat)
        else
          warn "Warning: #{buri} has unrecognized content-type: #{content_type}"
        end
      else
        error("Failed to GET #{buri}: #{code} #{reason}")
      end
    end
    agraph
  end

  def getROAnnotationBody(annuri)
    # Retrieve annotation for given annotation URI
    #
    # Returns: [code, reason, bodyuri, anngr]
    code, reason, headers, uri, anngr = getROResourceRDF(annuri)
    [code, reason, uri, anngr]
  end

  def removeROAnnotation(rouri, annuri)
    # Remove annotation at given annotation URI
    #
    # Returns: (code, reason)
    #~ (status, reason, headers, data) = self.doRequest(annuri,
        #~ method="DELETE")
    #~ return (status, reason)
    error("Unimplemented")
  end

end
