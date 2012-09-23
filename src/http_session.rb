# HTTP session class

require 'net/httplib'

class HTTPSessionError < Exception
  # Exception class used to signal HTTP Session errors
end

class http_session

  def initialize(uri, accesskey=nil)
    @uri = uri
    @key = accesskey
    @http = Net::HTTP::new(uri.host, uri.port)
  end

  def close
    if @http
      @http.finish
      @http = nil
    end
  end

  def doRequest(uripath, method='GET', body=nil, ctype=nil, accept=nil, reqheaders=nil)
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    if method == 'GET'
      self.doRequestGet(accept, reqheaders)
    elsif method == 'PUT'
      self.doRequestPut(body, ctype, accept, reqheaders)
    elsif method == 'POST'
      self.DoRequesPost(body, ctype, accept, reqheaders)
    elsif method == 'DELETE'
      self.doRequestDelete(accept, reqheaders)
    else
      raise HTTPSessionError, "Unrecognized method #{method}"
  end

  def getRequestPath(uripath)
    # Extract path (incl query) for HTTP request
    if (uripath.scheme != @uri.scheme)
      raise HTTPSessionError, "Request URI scheme does not match session: #{uripath}"
    end
    if (uripath.host != @uri.host) or
       (uripath.port != @uri.port)
      raise HTTPSessionError, "Request URI host or path does not match session: #{uripath}"
    end
    return uripath.request_uri()
  end

  def getRequestheaders(headers)
    if headers
      reqheaders = headers.clone
    else
      reqheaders = {}
    if @key
      reqheaders["authorization"] = "Bearer "+@key
    end
    if ctype
      reqheaders["content-type"] = ctype
    end
    if accept
      reqheaders['accept'] = accept
    end
    return reqheaders
  end

  def doRequestGet(uripath, accept=nil, headers=nil)
    # Perform HTTP request
    # Return [status, reason(text), response headers, response body]
    path = self.getRequestPath(uripath)
    reqh = self.getRequestHeaders(headers)
    resp = self.get(path, reqh)
    return [resp.code, resp.message, resp, resp.body]
  end

end



