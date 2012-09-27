# This example taken from 
# http://blog.datagraph.org/2010/04/parsing-rdf-with-ruby
#
# When run, results in:
# 
#   /Library/Ruby/Gems/1.8/gems/ffi-1.1.5/lib/ffi/pointer.rb:40: [BUG] Segmentation fault
#   ruby 1.8.6 (2009-06-08) [universal-darwin9.0]
# 
#   Abort trap
#

require 'rubygems'
require 'rdf'
require 'rdf/ntriples'
require 'rdf/raptor'

# The following works with :ntriples, but crashes with :rdfxml

output = RDF::Writer.for(:rdfxml).buffer do |writer|
  subject = RDF::Node.new
  writer << [subject, RDF.type, RDF::FOAF.Person]
  writer << [subject, RDF::FOAF.name, "J. Random Hacker"]
  writer << [subject, RDF::FOAF.mbox, RDF::URI("mailto:jhacker@example.org")]
  writer << [subject, RDF::FOAF.nick, "jhacker"]
end

puts output
