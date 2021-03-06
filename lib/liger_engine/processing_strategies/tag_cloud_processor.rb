require 'occurrence_summer'
require 'mesh_keyword_lookup'
require 'mesh_score_lookup'
require 'redis'

# A LigerEngine Processing Strategy is responsible for taking 
# an array of Pubmed IDs
#
# It must implement the instance method +process+, which accepts a
# query String and returns an array of Integer Pubmed IDs

module LigerEngine
  module ProcessingStrategies
    # The TagCloudProcessor takes a list of PMIDs, and builds a tag cloud
    # from the MeSH terms of all those PMIDs
    class TagCloudProcessor < Base
      attr_accessor :occurrence_summer
      attr_accessor :e_value_threshold # This is the e_value above which we'll consider a MeSH Term
      attr_accessor :max_mesh_terms    # Maximum MeSH terms to return
      attr_accessor :redis
      
      def initialize
        @occurrence_summer = OccurrenceSummer.new(:to_i)
        @e_value_threshold = 0.01
        @max_mesh_terms    = 75
        @redis             = RedisFactory.gimme('mesh')
      end
      
      # Looks up the MeSH keywords for each PMID.
      # If they exist, it adds them into the occurrence summer,
      # If none exist, it returns nil
      def each_id(pmid)
        mesh_keywords = @redis.smembers(pmid)
        unless mesh_keywords.empty?
          @occurrence_summer.sum(mesh_keywords)
        end
      rescue SystemCallError => e
        raise "Could not connect to Redis!"
      end
      
      # Gets a Nokogiri::XML::Element object, rips out the MeSH terms, looks
      # and looks up the corresponding MeshKeywords in our database.
      #
      # It takes that list of MeshKeywords, adds them to the 
      # +occurrence_summer+, and then bulk inserts them into the local cache
      def each_nonlocal(pubmed_article_xml)
        mesh_term_elements = pubmed_article_xml.xpath('./MedlineCitation/MeshHeadingList/MeshHeading/DescriptorName')
        
        unless mesh_term_elements.empty?
          mesh_terms = mesh_term_elements.map{|node| node.text}
          
          # This maps a text mesh descriptor into the mesh id. Done with an in-memory hash
          # instead of the database to speed things up
          mesh_ids = mesh_terms.map{|term| MeshKeywordLookup[term] }
          
          pmid = pubmed_article_xml.xpath('./MedlineCitation/PMID').first.text
          
          
          # If we detect a MeSH term that we don't know about (ie it maps to nil in MeshKeywordLookup)
          # then we send an email notification to the LigerCat administrators suggesting they update
          # LigerCat's MeSH term database.
          #
          # We also do not add this PMID's mesh ids to Redis, because we know that list is incomplete.
          # Presumably, after the admins update LigerCat's MeSH database, the same PMID will show up
          # in a different search, the MeSH id list will then be complete, and it will be added to Redis 
          if i = mesh_ids.index(nil)
            term = mesh_terms[i] # TODO: this only pulls out the first unknown MESH term. It'd be better to pull all of them out if possible
            # Temporarily commenting out update message, because MLB
            # haven't yet provided the freq count file for 2013 
            # Feedback.update_mesh(term, pmid).deliver
          else 
            
            # Cache the PMIDs that we've retrieved into Redis
            mesh_ids.each do |mesh_id|
              @redis.sadd(pmid, mesh_id)
            end
            
          end
             
          @occurrence_summer.sum(mesh_ids.compact)
        end
      rescue SystemCallError => e
        raise "Could not connect to Redis!"
      end

      # Takes the occurrence_summer, calculates the e-value for each one
      # and returns an array of the +max_mesh_terms+ most relevant MeSH terms
      # 
      # Each element in the array is returned as an OpenStruct. It has the accessors +mesh_keyword_id+, 
      # +frequency+, and +e_value+
      #
      # === Returns
      # * An array of OpenStructs, +max_mesh_terms+ long, of the most relevant MeshKeywords
      #
      def return_results
        weighted_frequencies = {}
        @occurrence_summer.occurrences.each do |mesh_id, frequency|
          score = MeshScoreLookup[mesh_id]
          score = 0 if score.nil? # If we've not computed a score for this mesh_id, just fail gracefully 
                    
          weighted_frequency = (frequency * (1-score)).ceil
    
          weighted_frequencies[mesh_id] = weighted_frequency
        end
        
        e_value_calc = EValueCalculator.new(weighted_frequencies, @e_value_threshold)
        
        hashes = []
        e_value_calc.each do |mesh_keyword_id, weighted_frequency, e_value|
          hashes << {:mesh_keyword_id => mesh_keyword_id, :frequency => @occurrence_summer.occurrences[mesh_keyword_id], :weighted_frequency => weighted_frequency}
        end
        
        hashes.sort_by{|h| h[:weighted_frequency] }.last(@max_mesh_terms)
      end
    end
  end
end