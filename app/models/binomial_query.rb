require 'pubmed_search'

class BinomialQuery < PubmedQuery
  has_many :eol_taxon_concepts, :dependent => :destroy, :foreign_key => 'query_id'
  
  # Sets the queue that Resque should use
  def self.queue
    :eol_taxa
  end
  
  def search_strategy
    @search_strategy ||= LigerEngine::SearchStrategies::BinomialPubmedSearchStrategy.new
  end

  # This is the verbatim string that gets sent out to PubMed in the Search Strategy. We
  # need this accessor method, because the "Selected Terms" panel and the Publication
  # Histogram both need this information to perform their respective AJAX calls.
  def actual_pubmed_query
    LigerEngine::SearchStrategies::BinomialPubmedSearchStrategy::species_specific_query(query)
  end
  
  def cache_webhook_uri
    url_for(:controller => 'pubmed_queries',
            :action     => :cache,
            :id         => self.id)
  end
  
end
