# This is an experimental module for testing Ruby RDF parsing functions, 
# and is not part of the package-provided functionality.  In due course, it should
# be deleted.

require 'rubygems'
require 'rdf'
require 'rdf/raptor'
require 'rdf/ntriples'

samplerdftxt = %q(
      <rdf:RDF
        xmlns:ore="http://www.openarchives.org/ore/terms/"
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" >
        <ore:Proxy rdf:about="http:/eample.com/base">
          <ore:foo rdf:resource="http://example.org.bar" />
        </ore:Proxy>
      </rdf:RDF>
      )

samplerdf = StringIO.new(samplerdftxt)

rdfreader = RDF::Reader.for(:rdfxml).new(samplerdf)

#~ rdfgr = RDF::Graph.new
#~ graph.rewind
#~ graph.each_statement do |statement|
  #~ rdfgr << statement
#~ end

#rdfgr << rdfreader

rdfgr = RDF::Graph.new << RDF::Reader.for(:rdfxml).new(samplerdftxt)

#~ puts "<<<<"
#~ rdfstr = RDF::Writer.for(:rdfxml).buffer do |writer|
  #~ rdfgr.each_statement do |statement|
    #~ writer << statement
  #~ end
#~ end
#~ puts rdfstr
#~ puts "<<<<"

puts "<<<<"
rdfstr = RDF::Writer.for(:rdfxml).buffer do |writer|
    writer << rdfgr
end
puts rdfstr
puts "<<<<"

# RDF::Writer.for(:ntriples).buffer do |writer|
#   graph.each_statement do |statement|
#     writer << statement
#   end
# end

# format = RDF::Format.for(:rdfxml)
# writer = format.writer

# graph.rewind
# puts "<<<<"
# sio = StringIO.new(mode="w")
# rdf = RDF::NTriples::Writer.new(sio) {|writer| writer << stmts[0] }
# puts "<<<<"
# puts rdf
# puts "<<<<"

# sio = StringIO.new(mode="w")
# writer = RDF::Writer.for(:rdfxml).new(sio)
# graph.rewind
# graph.each_statement do |statement|
#   writer.insert_statement(statement)
# end
# puts "<<<<"
# puts sio.string

#writer = RDF::Writer.for(:rdfxml).buffer

# graph.each_statement do |statement|
#   writer << statement
# end

# puts writer.methods - Object.methods
#
# puts writer.serializer
