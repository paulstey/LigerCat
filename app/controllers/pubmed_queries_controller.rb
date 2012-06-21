class PubmedQueriesController < ApplicationController
  helper_method  :query
  caches_page :index
    
  # GET /articles
  def index
    render :layout => 'home'
  end
  
  # GET /articles/search
  # This is essentially a create method on a GET method
  def search
    redirect_to(pubmed_queries_path) and return if params[:q].blank?
    
    @query = PubmedQuery.find_or_create_by_query(params[:q])
    redirect_to slug_pubmed_query_path(@query, @query.slug)
  end
  
  # GET /articles/:id
  def show
    @query = PubmedQuery.find(params[:id])
    if @query.done?
      @mesh_frequencies = @query.pubmed_mesh_frequencies.find(:all, :include => :mesh_keyword, :order => 'mesh_keywords.name asc')      
      respond_to do |format|
        format.html do
          @publication_histogram = @query.publication_dates.to_histohash # Keeps histogram out of the cloud iframe thingy. TODO refactor the views so this hack isn't needed
          render :action => 'show'; cache_page
        end
        format.cloud { render :action => 'embedded_cloud', :layout => 'iframe'; cache_page }
      end
    else
      redirect_to status_pubmed_query_path(@query)
    end
  end
  
  # GET /articles/:id/status
  # This is technically another resource, so probably some Rails Nazi would
  # tell me that it should be in another controller. But I just don't see the point.
  def status
    @query = PubmedQuery.find(params[:id])

    if @query.done?
      if request.xhr?
        render :text => 'done'
      else
        redirect_to slug_pubmed_query_path(@query, @query.slug)
      end
    else
      @status = @query.humanized_state

      respond_to do |format|
        format.html #status.haml
        format.js   { render :text => @status.titleize }
        format.json { render :json => {:status => @status}.to_json }
        format.xml  { render :xml => "<status>#{@status}</status>" }
      end
    end
  end
  
  # DELETE /articles/:id/cache
  def cache
    query = PubmedQuery.find(params[:id])
    expire_page :action => :show
    expire_page :action => :show, :slug => query.slug
    render :nothing => true, :status => :no_content
  end
  
  
  private
  def set_context
    @context = 'pubmed_queries' # 'articles'
  end
  
  def query
    @query.query rescue nil
  end
end