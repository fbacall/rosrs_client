require 'net/http'
require 'logger'

require 'rubygems'
require 'json'
require 'rdf'
require 'rdf/raptor'

require File.expand_path(File.join(File.dirname(__FILE__), 'namespaces'))
require File.expand_path(File.join(File.dirname(__FILE__), 'rdf_graph'))
require File.expand_path(File.join(File.dirname(__FILE__), 'rosrs_session'))
require File.expand_path(File.join(File.dirname(__FILE__), 'annotation'))
require File.expand_path(File.join(File.dirname(__FILE__), 'folder'))
require File.expand_path(File.join(File.dirname(__FILE__), 'folder_entry'))
require File.expand_path(File.join(File.dirname(__FILE__), 'research_object'))
