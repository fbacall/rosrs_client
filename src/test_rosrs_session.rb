# @@TODO: create separate module for test configuration (RODL, etc)

require "test/unit"
require "logger"

# Set up logger for this module
# @@TODO connect to multi-module logging framework (log4r?)
if not defined?($log)
  loglevel = nil
  loglevel = Logger::DEBUG
  #loglevel = Logger::INFO
  #loglevel = Logger::WARN
  #loglevel = Logger::ERROR
  #$log = Logger.new(STDOUT)
  $log = Logger.new(__FILE__+".log")
  $log.progname = "test_rosrs_session"
  $log.level = Logger::ERROR
  $log.formatter = proc { |sev, dat, prg, msg|
      "#{prg}: #{msg}\n"
    }
  if loglevel
    $log.level = loglevel
  end
end

require "./rosrs_session"
require "./namespaces"

# Test configuration values - may be imported later
class TestConfig
  attr_accessor :rosrs_api_uri, :authorization
  attr_accessor :test_ro_name, :test_ro_path
  attr_accessor :test_ro_uri
  attr_accessor :test_res1_rel, :test_res2_rel
  attr_accessor :test_res1_uri, :test_res2_uri

  def initialize
    @rosrs_api_uri  = "http://sandbox.wf4ever-project.org/rodl/ROs/"
    @authorization  = "47d5423c-b507-4e1c-8"
    @test_ro_name   = "TestSessionRO_ruby"
    @test_ro_path   = test_ro_name+"/"
    @test_ro_uri    = rosrs_api_uri+test_ro_path
    @test_res1_rel  = "subdir/res1.txt"
    @test_res2_rel  = "subdir/res2.rdf"
    @test_res1_uri  = test_ro_uri+test_res1_rel
    @test_res2_uri  = test_ro_uri+test_res2_rel
  end

end

class TestROSRS_Session < Test::Unit::TestCase

  attr :log

  Config = TestConfig.new

  def setup
    @log   = $log
    @rouri = nil
    @rosrs = ROSRS_Session.new(Config.rosrs_api_uri, Config.authorization)
  end

  def teardown
    if @rosrs
      @rosrs.close
    end
  end

  def uri(str)
    return RDF::URI(str)
  end

  def lit(str)
    return RDF::Literal(str)
  end

  def stmt(triple)
    s,p,o = triple
    return RDF::Statement(:subject=>s,:predicate=>p,:object=>o)
  end

  def assert_contains(triple, graph)
    #~ log.debug("assert_contains #{triple}")
    #~ graph.each_statement { |stmt| log.debug("- #{stmt}") }
    assert(graph.has_statement?(stmt(triple)), "Expected triple #{triple}")
  end

  def createTestRo
    c, r = @rosrs.deleteRO(Config.test_ro_uri)
    c,r,u,m = @rosrs.createRO(Config.test_ro_name,
        "Test RO for ROSRS_Session", "TestROSRS_Session.py", "2012-09-28")
    assert_equal(c, 201)
    @rouri = u
    return [c,r,u,m]
  end

  def populateTestRo
    # Add plain text resource
    res1_body = %q(#{test_res1_uri}
        resource body line 2
        resource body line 3
        end
        )
    options = { :body => res1_body, :ctype => "text/plain" }
    c, r, puri, ruri = @rosrs.aggregateResourceInt(
        @rouri, Config.test_res1_rel, options)
    assert_equal(201, c)
    assert_equal("Created", r)
    assert_equal(Config.test_res1_uri, ruri.to_s)
    # Add RDF resource
    res2_body = %q(
        <rdf:RDF
          xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          xmlns:ex="http://example.org/" >
          <ex:Resource rdf:about="http:/example.com/res/1">
            <ex:foo rdf:resource="http://example.com/res/1" />
            <ex:bar>Literal property</ex:bar>
          </ex:Resource>
        </rdf:RDF>
        )
    options = { :body => res2_body, :ctype => "application/rdf+xml" }
    c, r, puri, ruri = @rosrs.aggregateResourceInt(
        @rouri, Config.test_res2_rel, options)
    assert_equal(201, c)
    assert_equal("Created", r)
    assert_equal(Config.test_res2_uri, ruri.to_s)
    # @@TODO Add external resource
  end

  def deleteTestRo
    c, r = @rosrs.deleteRO(@rouri)
    return [c, r]
  end

  def test_Namespace_ORE
    assert_equal(RDF::URI("http://www.openarchives.org/ore/terms/Aggregation"),
                 ORE.Aggregation
                 )
    assert_equal(RDF::URI("http://www.openarchives.org/ore/terms/Aggregation"),
                 ORE.Aggregation
                 )
  end

  # ----------
  # Test cases
  # ----------

  def test_SplitValues
    assert_equal(['a','b','c'],
                 @rosrs.splitValues("a,b,c"))
    assert_equal(['a','"b,c"','d'],
                 @rosrs.splitValues('a,"b,c",d'))
    assert_equal(['a',' "b, c\\", c1"',' d'],
                 @rosrs.splitValues('a, "b, c\\", c1", d'))
    assert_equal(['a,"b,c",d'],
                 @rosrs.splitValues('a,"b,c",d', ";"))
    assert_equal(['a','"b;c"','d'],
                 @rosrs.splitValues('a;"b;c";d', ";"))
    assert_equal(['a','<b;c>','d'],
                 @rosrs.splitValues('a;<b;c>;d', ";"))
    assert_equal(['"a;b"','(c;d)','e'],
                 @rosrs.splitValues('"a;b";(c;d);e', ";", '"(', '")'))
  end

  def test_ParseLinks
    links = [ ['Link', '<http://example.org/foo>; rel=foo'],
              ['Link', ' <http://example.org/bar> ; rel = bar '],
              ['Link', '<http://example.org/bas>; rel=bas; par = zzz , <http://example.org/bat>; rel = bat'],
              ['Link', ' <http://example.org/fie> ; par = fie '],
              ['Link', ' <http://example.org/fum> ; rel = "http://example.org/rel/fum" '],
              ['Link', ' <http://example.org/fas;far> ; rel = "http://example.org/rel/fas" '],
            ]
    assert_equal(URI('http://example.org/foo'), @rosrs.parseLinks(links)['foo'])
    assert_equal(URI('http://example.org/bar'), @rosrs.parseLinks(links)['bar'])
    assert_equal(URI('http://example.org/bas'), @rosrs.parseLinks(links)['bas'])
    assert_equal(URI('http://example.org/bat'), @rosrs.parseLinks(links)['bat'])
    assert_equal(URI('http://example.org/fum'), @rosrs.parseLinks(links)['http://example.org/rel/fum'])
    assert_equal(URI('http://example.org/fas;far'), @rosrs.parseLinks(links)['http://example.org/rel/fas'])
  end

  def test_createSerializeGraph
    b = %q(
        <rdf:RDF
          xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          xmlns:ex="http://example.org/" >
          <ex:Resource rdf:about="http:/example.com/res/1">
            <ex:foo rdf:resource="http://example.com/res/1" />
            <ex:bar>Literal property</ex:bar>
          </ex:Resource>
        </rdf:RDF>
        )
    g  = RDF_Graph.new(:data => b)
    b1 = g.serialize(format=:ntriples)
    r1 = %r{<http:/example\.com/res/1> <http://example\.org/foo> <http://example\.com/res/1> \.}
    r2 = %r{<http:/example\.com/res/1> <http://example\.org/bar> "Literal property" \.}
    [r1,r2].each do |r|
      assert(b1 =~ r, "Not matched: #{r}")
    end
  end

  def test_HTTP_Simple_Get
    c,r,u,m = createTestRo
    assert_equal(201, c)
    c,r,h,b = @rosrs.doRequest("GET", @rouri,
      {:accept => "application/rdf+xml"})
    assert_equal(303, c)
    assert_equal("See Other", r)
    assert_equal("application/rdf+xml", h["content-type"])
    assert_equal("", b)
    c,r = deleteTestRo
  end

  def test_HTTP_Redirected_Get
    c,r,u,m = createTestRo
    assert_equal(201, c)
    c,r,h,u,b = @rosrs.doRequestFollowRedirect("GET", @rouri,
        {:accept => "application/rdf+xml"})
    assert_equal(200, c)
    assert_equal("OK", r)
    assert_equal("application/rdf+xml", h["content-type"])
    assert_equal(Config.test_ro_uri+".ro/manifest.rdf", u.to_s)
    #assert_match(???, b)
    c,r = deleteTestRo
  end

  def test_createTestRo
    c,r,u,m = createTestRo
    assert_equal(201, c)
    assert_equal("Created", r)
    assert_equal(Config.test_ro_uri, u)
    s = stmt([uri(Config.test_ro_uri), RDF.type, RO.ResearchObject])
    assert_contains(s, m)
    c,r = deleteTestRo
    assert_equal(204, c)
    assert_equal("No Content", r)
  end

  def test_aggregateResourceInt
    c,r,u,m = createTestRo
    assert_equal(201, c)
    body    = "test_aggregateResourceInt resource body\n"
    options = { :body => body, :ctype => "text/plain" }
    c, r, puri, ruri = @rosrs.aggregateResourceInt(
        @rouri, "test_aggregateResourceInt", options)
    assert_equal(201, c)
    assert_equal("Created", r)
    puri_exp = Config.test_ro_uri+".ro/proxies/"
    puri_act = puri.to_s.slice(0...puri_exp.length)
    assert_equal(puri_exp, puri_act)
    assert_equal(Config.test_ro_uri+"test_aggregateResourceInt", ruri.to_s)
    c,r = deleteTestRo
  end

  def test_createROAnnotationBody
    c,r,u,m = createTestRo
    assert_equal(201, c)
    b = %q(
        <rdf:RDF
          xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          xmlns:ex="http://example.org" >
          <ex:Resource rdf:about="http:/example.com/res/1">
            <ex:foo rdf:resource="http://example..com/res/1" />
            <ex:bar>Literal property</ex:bar>
          </ex:Resource>
        </rdf:RDF>
        )
    g = RDF_Graph.new(:data => b)
    # Create an annotation body from a supplied annnotation graph.
    # Params:  (rouri, anngr)
    # Returns: (status, reason, bodyuri)
    c,r,u = @rosrs.createROAnnotationBody(@rouri, g)
    assert_equal(201, c)
    assert_equal("Created", r)
    assert_match(%r(http://sandbox.wf4ever-project.org/rodl/ROs/TestSessionRO_ruby/), u.to_s)
    #assert_equal(nil, u)
    c,r = deleteTestRo
  end

 end
