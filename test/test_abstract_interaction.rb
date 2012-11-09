# Test suite for ROSRS_Session
require 'helper'


class TestAbstractInteraction < Test::Unit::TestCase

  API_URI = "http://sandbox.wf4ever-project.org/rodl/ROs/"
  AUTH_TOKEN = "32801fc0-1df1-4e34-b"
  TEST_RO = "TestSessionRO_ruby"

  def setup
    @session = ROSRS::Session.new(API_URI, AUTH_TOKEN)
    @ro = ROSRS::ResearchObject.create(@session, TEST_RO, "Ruby Client Library Test RO", "ruby-client-lib")
  end

  def teardown
    @ro.delete!
    if @session
      @session.close
    end
  end

  def test_get_research_object
    ro = ROSRS::ResearchObject.new(@session, @ro.uri)
    assert(!ro.loaded?)
    ro.load
    assert(ro.loaded?)
    assert_not_nil(ro.manifest)
    assert_empty(ro.annotations)
  end

  def test_create_root_folder
    assert_nil(@ro.root_folder)
    ro.create_folder("test_root")
    ro.load
    assert_equal("test_root", ro.root_folder.name)
  end

  def test_delete_research_object
    assert_nothing_raised { @ro.manifest }
    @ro.delete!
    assert_raise(ROSRS::NotFoundException) { @ro.manifest }
  end

 end
