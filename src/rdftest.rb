require 'rubygems'
require 'rdf'
require 'rdf/raptor'
require 'rdf/ntriples'

samplerdf = StringIO.new(%q(
      <rdf:RDF
        xmlns:ore="http://www.openarchives.org/ore/terms/"
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" >
        <ore:Proxy rdf:about="http:/eample.com/base">
          <ore:foo rdf:resource="http://example.org.bar" />
        </ore:Proxy>
      </rdf:RDF>
      ))

# graph = RDF::Reader.new(samplerdf) do |graph|
#   graph.each_statement { |stmt| puts statement }
# end

stmts = []
graph = RDF::Reader.for(:rdfxml).new(samplerdf)
puts graph.inspect
graph.each_statement { |stmt| puts "---" ; puts stmt; stmts << stmt }
puts "---"

puts stmts.inspect

#graph.rewind

puts "<<<<"
RDF::Writer.for(:rdfxml).buffer do |writer|
  stmts.each do |statement|
    #writer << statement
    puts statement.to_triple
  end
end
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
