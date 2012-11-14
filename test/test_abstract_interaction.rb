# Test suite for ROSRS_Session
require 'helper'


class TestAbstractInteraction < Test::Unit::TestCase

  API_URI = "http://sandbox.wf4ever-project.org/rodl/ROs/"
  AUTH_TOKEN = "32801fc0-1df1-4e34-b"
  TEST_RO = "TestSessionRO_ruby"

  def setup
    @session = ROSRS::Session.new(API_URI, AUTH_TOKEN)
    @ro = ROSRS::ResearchObject.create(@session, TEST_RO)
  end

  def teardown
    @ro.delete
    if @session
      @session.close
    end
  end

  def test_get_research_object
    ro = ROSRS::ResearchObject.new(@session, @ro.uri)
    assert(!ro.loaded?)
    ro.load # Fetch and parse the manifest
    assert(ro.loaded?)
    assert_not_nil(ro.manifest)
    #assert_empty(ro.annotations)
  end

  def test_create_root_folder
    assert_nil(@ro.root_folder)
    @ro.create_folder("test_root")
    @ro.load
    assert_not_nil(@ro.root_folder)
    assert_equal("test_root", @ro.root_folder.name)
  end

  def test_delete_research_object
    assert_nothing_raised { @ro.manifest }
    @ro.delete
    assert_raise(ROSRS::NotFoundException) { @ro.manifest }
  end

  def test_aggregating_resources
    # Check can add resources
    assert_equal(0, @ro.resources.size)
    external = @ro.aggregate_external("http://www.google.com")
    assert_equal(1, @ro.resources.size)
    internal = @ro.aggregate_internal('text_example.txt', "Hello world", 'text/plain')
    assert_equal(2, @ro.resources.size)

    # Check still there after reloading and parsing manifest
    @ro.load
    assert_equal(2, @ro.resources.size)

    # Check URI of aggregated resources
    resource_uris = @ro.resources.collect {|r| r.uri}
    assert_include(resource_uris, internal.uri)
    assert_include(resource_uris, external.uri)

    # Check proxy URI of aggregated resources
    proxy_uris = @ro.resources.collect {|r| r.proxy_uri}
    assert_include(proxy_uris, internal.proxy_uri)
    assert_include(proxy_uris, external.proxy_uri)

    # Check resources are flagged as internal/external correctly
    internal_resource = @ro.resources.select {|r| r.uri == internal.uri}.first
    assert(internal_resource.internal?)
    external_resource = @ro.resources.select {|r| r.uri == external.uri}.first
    assert(external_resource.external?)

    # Check deaggregating resources
    @ro.remove(external_resource)
    assert_equal(1, @ro.resources.size)
    resource_uris = @ro.resources.collect {|r| r.uri}
    assert_not_include(resource_uris, external_resource.uri)
    assert_include(resource_uris, internal_resource.uri)

    # And check after reloading manifest
    @ro.load
    assert_equal(1, @ro.resources.size)
    resource_uris = @ro.resources.collect {|r| r.uri}
    assert_not_include(resource_uris, external_resource.uri)
    assert_include(resource_uris, internal_resource.uri)
  end

  def test_annotating_resources
    # Check can add annotations
    external = @ro.aggregate_external("http://www.google.com")
    internal = @ro.aggregate_internal('text_example.txt', "Hello world", 'text/plain')
    assert_equal(0, external.annotations.size)
    assert_equal(0, internal.annotations.size)
    # Create some annotations
    remote_annotation = internal.annotate("http://www.example.com/annotation")
    body = create_annotation_body(@ro.uri, external.uri)
    local_annotation = external.annotate(body)
    # Check added to local object
    assert_equal(1, external.annotations.size)
    assert_equal(1, internal.annotations.size)
    # Reload RO by fetching and parsing manifest
    @ro.load
    # Check annotations still there
    external = @ro.resources.select {|r| r.uri == external.uri}.first
    internal = @ro.resources.select {|r| r.uri == internal.uri}.first
    assert_equal(1, external.annotations.size)
    assert_equal(1, internal.annotations.size)
    # Check annotations content is the same
    assert_equal(remote_annotation.uri, internal.annotations.first.uri)
    assert_equal(remote_annotation.body_uri, internal.annotations.first.body_uri)
    assert_equal(local_annotation.uri, external.annotations.first.uri)
    assert_equal(local_annotation.body_uri, external.annotations.first.body_uri)
  end

  private

  def create_annotation_body(ro_uri, resource_uri)
    body = %(<?xml version="1.0" encoding="UTF-8"?>
      <rdf:RDF
         xmlns:dct="http://purl.org/dc/terms/"
         xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
         xml:base="#{ro_uri}"
      >
        <rdf:Description rdf:about="#{resource_uri}">
        <dct:title>Title 1</dct:title>
        <rdfs:seeAlso rdf:resource="http://example.org/test1" />
        </rdf:Description>
      </rdf:RDF>
      )

    ROSRS::RDFGraph.new(:data => body, :format => :xml)
  end

 end
