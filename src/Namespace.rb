require 'uri'

class Namespace
  def initialize(prefix, base, memberlist)
    @prefix   = prefix
    @base_uri = URI(base)
    @members  = {}
    memberlist.each do |m|
      @members[m.to_sym] = URI(@base_uri.to_s+m)
      Namespace.send(:define_method, m) do
        return @members[m.to_sym]
      end
    end
  end
  
  def [](name)
    return @members[name]
  end
    
end

ORE = Namespace.new("ORE", "http://www.openarchives.org/ore/terms/",
        [ "Aggregation", "AggregatedResource", "Proxy", 
          "aggregates", "proxyFor", "proxyIn", "isDescribedBy"
        ])

 