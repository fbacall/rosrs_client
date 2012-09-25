# HTTP session class

require 'net/http'

class HTTPSessionError < Exception
  # Exception class used to signal HTTP Session errors
end

class HTTP_Session

  SOMEURI = URI("")

  def initialize(uri, accesskey=nil)
    @uri = SOMEURI.coerce(uri)[0]
    @key = accesskey
    @http = Net::HTTP.new(@uri.host, @uri.port)
  end

  def close
    if @http
      @http.finish
      @http = nil
    end
  end

  def error(msg, value=Nil)
    if value
      msg += " (#{value})"
      raise HTTPSessionError msg=msg, value=value, @uri)
  end

  def doRequestGet(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    resp = @http.get(getRequestPath(uripath), getRequestHeaders(options))
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestPut(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    resp = @http.put(getRequestPath(uripath), getRequestHeaders(options))
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestPost(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    resp = @http.post(getRequestPath(uripath), getRequestHeaders(options))
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestDelete(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    resp = @http.delete(getRequestPath(uripath), getRequestHeaders(options))
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequest(method, uripath, options)
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    if method == 'GET'
      return self.doRequestGet(uripath, options)
    elsif method == 'PUT'
      return self.doRequestPut(uripath, options)
    elsif method == 'POST'
      return self.doRequesPost(uripath, options)
    elsif method == 'DELETE'
      return self.doRequestDelete(uripath, options)
    else
      raise HTTPSessionError, "Unrecognized method #{method}"
    end
  end

  def doRequestFollowRedirect(method, uripath, options)
    # Perform HTTP request, following 302, 303 307 redirects
    # Return [status, reason(text), response headers, final uri, response body]
    status, reason, headers, data = doRequest(method, uripath, options)
    if [302,303,307].include?(status)
      uripath = headers["location"]
      status, reason, headers, data = doRequest(method, uripath, options)
    end
    if [302,307].include?(status)
      # Allow second temporary redirect
      uripath = headers["location"]
      status, reason, headers, data = doRequest(method, uripath, options)
    end
    puts "Data "+data
    puts "Status "+status.to_s+", Path "+uripath
    return [status, reason, headers, URI(uripath), data]
  end

  def getRequestPath(uripath)
    # Extract path (incl query) for HTTP request
    uripath = SOMEURI.coerce(uripath)[0]
    if uripath.scheme and (uripath.scheme != @uri.scheme)
      raise HTTPSessionError, "Request URI scheme does not match session: #{uripath}"
    end
    if (uripath.host and uripath.host != @uri.host) or
       (uripath.port and uripath.port != @uri.port)
      raise HTTPSessionError, "Request URI host or port does not match session: #{uripath}"
    end
    requri = URI.join(@uri.to_s, uripath.path).path
    if uripath.query
      requri += "?"+uripath.query
    end
    return requri
  end

  def getRequestHeaders(options)
    if options[:headers]
      reqheaders = options[:headers].clone
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
    return reqheaders
  end

  def aggregateResourceInt(rouri, respath=nil, options)
    # Aggegate internal resource
    # Return (status, reason, proxyuri, resuri), where status is 200 or 201
    #
    # POST (empty) proxy value to RO ...
    reqheaders = respath and { "slug": respath }
    proxydata = %q(
      <rdf:RDF
        xmlns:ore="http://www.openarchives.org/ore/terms/"
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" >
        <ore:Proxy>
        </ore:Proxy>
      </rdf:RDF>
      )
    status, reason, headers, data = doRequest("POST", rouri,
      ctype=>"application/vnd.wf4ever.proxy",
      reqheaders=>reqheaders, 
      body=>proxydata)
    if status != 201
      raise self.error("Error creating aggregation proxy",
                      "#{status} #{reason} #{respath}")
    end
    proxyuri = rdflib.URIRef(headers["location"])
    links    = self.parseLinks(headers)
    log.debug("- links: "+repr(links))
    log.debug("- ORE.proxyFor: "+str(ORE.proxyFor))
    if str(ORE.proxyFor) not in links:
        raise self.error("No ore:proxyFor link in create proxy response",
                        "Proxy URI %s"%str(proxyuri))
    resuri   = rdflib.URIRef(links[str(ORE.proxyFor)])
    # PUT resource content to indicated URI
    (status, reason, headers, data) = self.doRequest(resuri,
        method="PUT", ctype=ctype, body=body)
    if status not in [200,201]:
        raise self.error("Error creating aggregated resource content",
            "%03d %s (%s)"%(status, reason, respath))
    return (status, reason, proxyuri, resuri)
  end

  def createROAnnotationBody(rouri, anngr)
    # Create an annotation body from a supplied annnotation graph.
    # 
    # Returns: (status, reason, bodyuri)
    (status, reason, bodyproxyuri, bodyuri) = self.aggregateResourceInt(rouri,
        ctype="application/rdf+xml",
        body=anngr.serialize(format="xml"))
    if status != 201:
        raise self.error("Error creating annotation body resource",
            "%03d %s (%s)"%(status, reason, str(resuri)))
    return (status, reason, bodyuri)

  # def createROAnnotationStub(self, rouri, resuri, bodyuri):
  #     """
  #     Create an annotation stub for supplied resource using indicated body
  #     
  #     Returns: (status, reason, annuri)
  #     """
  #     annotation = self.createAnnotationRDF(rouri, resuri, bodyuri)
  #     (status, reason, headers, data) = self.doRequest(rouri,
  #         method="POST",
  #         ctype="application/vnd.wf4ever.annotation",
  #         body=annotation)
  #     if status != 201:
  #         raise self.error("Error creating annotation",
  #             "%03d %s (%s)"%(status, reason, str(resuri)))
  #     annuri   = rdflib.URIRef(headers["location"])
  #     return (status, reason, annuri)

  # def createROAnnotationInt(rouri, resuri, anngr)
  #   # Create internal annotation
  #   # 
  #   # Return (status, reason, annuri, bodyuri)
  #   status, reason, bodyuri = self.createROAnnotationBody(rouri, anngr)
  #   if status == 201:
  #       status, reason, annuri = self.createROAnnotationStub(rouri, resuri, bodyuri)
  #   return [status, reason, annuri, bodyuri]
  # end

  def createROAnnotationExt(rouri, resuri, bodyuri)
    # Creeate a resource annotation using an existing (possibly external) annotation body
    # 
    # Returns: (status, reason, annuri)
  end

  def updateROAnnotationInt(rouri, annuri, resuri, anngr)
    # Update an annotation with a new internal annotation body
    # 
    # returns: (status, reason, bodyuri)
  end

  def updateROAnnotationExt(rouri, annuri, bodyuri)
    # Update an annotation with an existing (possibly external) annotation body
    # 
    # returns: (status, reason)
  end

  def getROAnnotationUris(rouri, resuri=None)
    # Enumerate annnotation URIs associated with a resource
    # (or all annotations for an RO) 
    # 
    # Returns an iterator over annotation URIs
  end

  def getROAnnotationBodyUris(rouri, resuri=None)
    # Enumerate annnotation body URIs associated with a resource
    # (or all annotations for an RO) 
    # 
    # Returns an iterator over annotation URIs
  end

  def getROAnnotationBodyUri(annuri)
    # Retrieve annotation for given annotation URI
  end

  def getROAnnotationGraph(rouri, resuri=None)
    # Build RDF graph of annnotations associated with a resource
    # (or all annotations for an RO) 
    # 
    # Returns graph of merged annotations
  end

  def getROAnnotation(annuri)
    # Retrieve annotation for given annotation URI
    # 
    # Returns: (status, reason, bodyuri, anngr)
  end

  def removeROAnnotation(rouri, annuri)
    # Remove annotation at given annotation URI
    # 
    # Returns: (status, reason)
  end

end


s = HTTP_Session.new("http://sandbox.wf4ever-project.org/rodl/ROs/")
c,r,h,u,b = s.doRequestFollowRedirect("GET", 
  "http://sandbox.wf4ever-project.org/rodl/ROs/InterProScan_RO2/", 
  {:accept => "application/rdf+xml"})
puts c
puts r
h.each { |hdr,val| puts hdr+"="+val }
puts u
puts '---'
puts b
puts '---'


