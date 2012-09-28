
# @@TODO: move tests to separae module
# @@TODO: create separate module for test configuration (RODL, etc)

require "./http_session"

require "test/unit"

class TestROSRS_Session < Test::Unit::TestCase

  Test_rodl = "http://sandbox.wf4ever-project.org/rodl/ROs/"
  Test_ro   = Test_rodl+"workflow2470/"

  def test_Namespace_ORE
    assert_equal(URI("http://www.openarchives.org/ore/terms/Aggregation"),
                 ORE[:Aggregation]
                 )
    assert_equal(URI("http://www.openarchives.org/ore/terms/Aggregation"),
                 ORE.Aggregation
                 )
  end

  def testSplitValues
    s = HTTP_Session.new(Test_rodl)
    assert_equal(['a','b','c'],
                 s.splitValues("a,b,c"))
    assert_equal(['a','"b,c"','d'],
                 s.splitValues('a,"b,c",d'))
    assert_equal(['a',' "b, c\\", c1"',' d'],
                 s.splitValues('a, "b, c\\", c1", d'))
    assert_equal(['a,"b,c",d'],
                 s.splitValues('a,"b,c",d', ";"))
    assert_equal(['a','"b;c"','d'],
                 s.splitValues('a;"b;c";d', ";"))
    assert_equal(['a','<b;c>','d'],
                 s.splitValues('a;<b;c>;d', ";"))
    assert_equal(['"a;b"','(c;d)','e'],
                 s.splitValues('"a;b";(c;d);e', ";", '"(', '")'))
  end

  def test_ParseLinks
    s = HTTP_Session.new(Test_rodl)
    links = [ ['Link', '<http://example.org/foo>; rel=foo'],
              ['Link', ' <http://example.org/bar> ; rel = bar '],
              ['Link', '<http://example.org/bas>; rel=bas; par = zzz , <http://example.org/bat>; rel = bat'],
              ['Link', ' <http://example.org/fie> ; par = fie '],
              ['Link', ' <http://example.org/fum> ; rel = "http://example.org/rel/fum" '],
              ['Link', ' <http://example.org/fas;far> ; rel = "http://example.org/rel/fas" '],
            ]
    assert_equal(URI('http://example.org/foo'), s.parseLinks(links)['foo'])
    assert_equal(URI('http://example.org/bar'), s.parseLinks(links)['bar'])
    assert_equal(URI('http://example.org/bas'), s.parseLinks(links)['bas'])
    assert_equal(URI('http://example.org/bat'), s.parseLinks(links)['bat'])
    assert_equal(URI('http://example.org/fum'), s.parseLinks(links)['http://example.org/rel/fum'])
    assert_equal(URI('http://example.org/fas;far'), s.parseLinks(links)['http://example.org/rel/fas'])
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
    #~ <http:/example.com/res/1> <http://example.org/foo> <http://example.com/res/1> .
    #~ <http:/example.com/res/1> <http://example.org/bar> "Literal property" .
    r1 = %r{<http:/example\.com/res/1> <http://example\.org/foo> <http://example\.com/res/1> \.}
    r2 = %r{<http:/example\.com/res/1> <http://example\.org/bar> "Literal property" \.}
    [r1,r2].each do |r|
      assert(b1 =~ r, "Not matched: #{r}")
    end
  end

  def test_HTTP_Simple_Get
    s = HTTP_Session.new(Test_rodl)
    c,r,h,b = s.doRequest("GET", Test_ro,
      {:accept => "application/rdf+xml"})
    assert_equal(303, c)
    assert_equal("See Other", r)
    assert_equal("application/rdf+xml", h["content-type"])
    assert_equal("", b)
  end

  def test_HTTP_Redirected_Get
    s = HTTP_Session.new(Test_rodl)
    c,r,h,u,b = s.doRequestFollowRedirect("GET", Test_ro,
      {:accept => "application/rdf+xml"})
    assert_equal(200, c)
    assert_equal("OK", r)
    assert_equal("application/rdf+xml", h["content-type"])
    assert_equal(Test_ro+".ro/manifest.rdf", u.to_s)
    #assert_match(???, b)
  end

  def test_aggregateResourceInt
    s = HTTP_Session.new(Test_rodl)
    body    = "test_aggregateResourceInt resource body\n"
    options = { :body => body, :ctype => "text/plain" }
    c, r, puri, ruri = s.aggregateResourceInt(Test_ro, "test_aggregateResourceInt", options)
    assert_equal(200, c)
    assert_equal("OK", r)
    puri_exp = Test_ro+".ro/proxies/"
    puri_act = puri.to_s.slice(0...puri_exp.length)
    assert_equal(puri_exp, puri_act)
    assert_equal(Test_ro+"test_aggregateResourceInt", ruri.to_s)
  end

  def test_createROAnnotationBody
    s = HTTP_Session.new(Test_rodl)
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
    c,r,u = s.createROAnnotationBody(URI("http:/example.com/res/1"), g)
    assert_equal(200, c)
    assert_equal("OK", r)
    assert_equal(nil, u)
  end

 end
