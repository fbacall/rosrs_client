# HTTP session class

require 'net/http'

require 'rubygems'
require 'rdf'
require 'rdf/raptor'

require './Namespaces'

# ----------

class HTTPSessionError < Exception
  # Exception class used to signal HTTP Session errors
end

class HTTP_Session

  def initialize(uri, accesskey=nil)
    # Force string or URI to be a URI - tried coerce, didn't work
    @uri = URI(uri.to_s)
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
    # Raise exception with supplied message and optional value
    if value
      msg += " (#{value})"
    end
    raise HTTPSessionError.new("HTTPSessionError on #{@uri} #{msg}")
  end

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
    return result
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
    return links
  end

  def getRequestPath(uripath)
    # Extract path (incl query) for HTTP request
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
    #reqheaders.each { |k,v| puts "- reqheader[#{k}] = #{v}" }
    return reqheaders
  end

  def doRequestGet(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    #resp = @http.get(getRequestPath(uripath), getRequestHeaders(options))
    req = Net::HTTP::Get.new(getRequestPath(uripath))
    getRequestHeaders(options).each { |h,v| req.add_field(h, v) }
    resp = @http.request(req)
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestPut(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    #resp = @http.put(getRequestPath(uripath), getRequestHeaders(options))
    req = Net::HTTP::Put.new(getRequestPath(uripath))
    getRequestHeaders(options).each { |h,v| req.add_field(h, v) }
    resp = @http.request(req)
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestPost(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    req = Net::HTTP::Post.new(getRequestPath(uripath))
    getRequestHeaders(options).each { |h,v| req.add_field(h, v) }
    resp = @http.request(req)
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequestDelete(uripath, options={})
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    #resp = @http.delete(getRequestPath(uripath), getRequestHeaders(options))
    req = Net::HTTP::Delete.new(getRequestPath(uripath))
    getRequestHeaders(options).each { |h,v| req.add_field(h, v) }
    resp = @http.request(req)
    return [Integer(resp.code), resp.message, resp, resp.body]
  end

  def doRequest(method, uripath, options)
    # Perform HTTP request
    #
    # options: {
    #   body    => body to accompany request
    #   ctype   => content type of supplied body
    #   accept  => accept co ntent types for response
    #   headers => additional headers for request
    #   }
    # Return [status, reason(text), response headers, response body]
    #
    # @@TODO - refactor so that request objects are built separately,
    #          and request headers added by common code
    debug = true
    if debug
      puts "doRequest #{method} #{uripath}"
      options.each { |k,v| puts "- option[#{k}] = #{v}" }
      if options[:headers]
        options[:headers].each { |k,v| puts "- request header[#{k}] = #{v}", v }
      end
    end
    if method == 'GET'
      c,r,h,b = doRequestGet(uripath, options)
    elsif method == 'PUT'
      c,r,h,b = doRequestPut(uripath, options)
    elsif method == 'POST'
      c,r,h,b = doRequestPost(uripath, options)
    elsif method == 'DELETE'
      c,r,h,b = doRequestDelete(uripath, options)
    else
      error("Unrecognized method #{method}")
    end
    if debug
      puts "doRequest #{c} #{r}"
      h.each { |k,v| puts "- response header[#{k}] = #{v}" }
      puts "- response body"
      puts b
      puts "----"
    end
    return [c,r,h,b]
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
    return [status, reason, headers, URI(uripath), data]
  end

  def aggregateResourceInt(rouri, respath=nil, options={})
    # Aggegate internal resource
    #
    # options: {
    #   body    => body to accompany request
    #   ctype   => content type of supplied body
    #   accept  => accept co ntent types for response
    #   headers => additional headers for request
    #   }
    # Return (status, reason, proxyuri, resuri), where status is 200 or 201
    #
    # POST (empty) proxy value to RO ...
    reqheaders = options[:headers]
    if not reqheaders
      reqheaders = {}
    end
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
    status, reason, headers, data = doRequest("POST", rouri,
      :ctype    => "application/vnd.wf4ever.proxy",
      :headers  => reqheaders,
      :body     => proxydata)
    if status != 201
      error("Error creating aggregation proxy",
            "#{status} #{reason} #{respath}")
    end
    proxyuri = URI(headers["location"])
    # headers.each {|h,v| puts "h #{h} = #{v}"}
    links    = parseLinks(headers)
    # links.each {|r,u| puts "r #{r} -> u #{u.to_s}"}
    resuri = links[ORE[:proxyFor].to_s]
    if not resuri
      error("No ore:proxyFor link in create proxy response",
            "Proxy URI #{proxyuri}")
    end
    # PUT resource content to indicated URI
    status, reason, headers, data = doRequest("PUT", resuri, options)
    if not [200,201].include?(status)
        error("Error creating aggregated resource content",
              "#{status}, #{reason}, #{respath}")
    end
    return [status, reason, proxyuri, resuri]
  end

  def createROAnnotationBody(rouri, anngr)
    # Create an annotation body from a supplied annnotation graph.
    #
    # Returns: (status, reason, bodyuri)
    (status, reason, bodyproxyuri, bodyuri) = aggregateResourceInt(rouri, nil,
      :ctype => "application/rdf+xml",
      :body  => anngr.serialize(format=:xml))
    if status != 201
      error("Error creating annotation body resource",
            "#{status}, #{reason}, #{str(resuri)}")
    end
    return [status, reason, bodyuri]
  end

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

